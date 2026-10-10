# The span trap — investigated, and it is NOT real

**Conclusion: do not pin `output.weight`. Plain `-ngl 48` with only the PLE/token_embd
overrides is correct. The pin is unnecessary AND costs throughput.**

This file exists because a plausible, source-flavoured warning nearly made it into a public
model card. It is kept as a record of how it was knocked down.

## The claim

llama.cpp charges the Metal buffer **span** per file as `(max offset+size) − (min offset)` over
GPU-assigned tensors, not their summed bytes. In q4lean5, `output.weight` sits at offset 0, so
with any `-ngl > 0` the span runs to 94.51 GiB for 67.20 GiB of tensors — 27.31 GiB of waste,
over the 80.64 GiB `maxBufferLength`. Predicted: OOM at any `-ngl`, fixable with `^output=CPU`.

## Why it is wrong

Verified directly in `ggml/src/ggml-metal/ggml-metal-device.m`:

**1. Exceeding `maxBufferLength` is not a failure path — it is the view stride** (`:1753-1780`).
When a span exceeds `max_buffer_size`, ggml splits it into *overlapping views*, up to
`GGML_METAL_MAX_BUFFERS = 64`. The source comment says it outright:

> `// this overlap between the views will guarantee that the tensor with the maximum size will fully fit into one of the views`

`size_step = max_buffer_size - size_ovlp`, looped over the whole span. Real failure happens only
when `newBufferWithBytesNoCopy` returns nil — i.e. the system genuinely cannot back the
allocation. So "largest span > maxBufferLength → FAIL" was simply the wrong rule.

**2. The two limits are different** (`:885-890`). `max_buffer_size = maxBufferLength` (80.64 GiB)
but `max_working_set_size = recommendedMaxWorkingSetSize` (120 GiB) on macOS 10.12+. The
prediction conflated them.

**3. Exceeding the working set is a warning, not an error** (`:1532-1543`) — `GGML_LOG_WARN`,
inside `#ifndef GGML_METAL_NDEBUG`.

Corrected verdict for q4lean5 at ngl 48 with no extra pin: total span 94.51 GiB, under the
120 GiB working set. **SAFE.**

## Measured

Stock llama.cpp `6c84c7d5`, q4lean5, `-ngl 48`, ctx 4096, flash-attn on, KV q4_0:

| config | exit | span warnings | OOM | output | t/s |
|---|---|---|---|---|---|
| with `^output=CPU` | 0 | 0 | 0 | "Canberra" | 34.1 |
| **without the pin** | 0 | 0 | 0 | "Canberra" | **40.4** |

Logs: `span-{withpin,nopin}.log` (campaign logs, not shipped).

**The pin costs 6.3 t/s.** Pinning `output.weight` to CPU moves the lm_head matmul off the GPU.
That is the pin's cost, not noise — so the advice was wrong twice over: unnecessary, and a
regression.

## Where the original OOM came from

A real 39-error OOM storm was observed, but on a different model: **total** span 123.44 GiB,
over the 120 GiB working set. That is a working-set problem, not a per-buffer one, and it does
not generalise to q4lean5 at 94.51 GiB.

## What to take from this

The rule that actually matters is **total span vs `recommendedMaxWorkingSetSize` (120 GiB)**.
`maxBufferLength` is not a cliff.

The prediction had a plausible mechanism and a prior observation behind it, and was still wrong.
Reading the allocator source, then measuring, settled it; the warning was not published.
