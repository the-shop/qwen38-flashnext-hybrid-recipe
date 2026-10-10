# Ground-truth type maps

These tables are read directly out of the shipped GGUF headers: measured ground truth for what
the build produced. The commands that produced it (every `--include-weights` /
`--exclude-weights` argument, per step) are in [`../REPRODUCE.md`](../REPRODUCE.md).
v0.1.0 of this file said those arguments were never recorded; they were in the build
session's command log, not in the quantize logs.

For acceptance this file is the target: it states what a rebuild must produce, whatever route
is taken to it.

## q4lean2 — 102,523,604,096 B (95.5 GiB)

| type | tensors |
|---|---|
| Q8_0 | 522 |
| F32 | 388 |
| F16 | 169 |
| Q4_0 | 145 |

## q4lean5 — 101,488,511,616 B (94.5 GiB) · **the winner**

| type | tensors |
|---|---|
| Q6_K | 423 |
| F32 | 388 |
| F16 | 169 |
| Q8_0 | 99 |
| Q4_0 | 145 |

## The only difference between them

The dense tier moves **Q8_0 → Q6_K**, for exactly these tensors:

```
attn_q  attn_k  attn_v  attn_qkv  attn_output  attn_gate
ffn_gate_shexp
output  output_hc_down
hc_attn_down  hc_attn_inject
ssm_alpha  ssm_beta
```

Everything else is byte-for-byte the same tier. This matches the `dense -> q6_K` pass
header in the q4lean5 quantize log (not shipped).

## Identical in both

| tensors | type |
|---|---|
| experts gate / up / down | Q4_0 |
| `per_layer_token_embd` (the PLE table) | **Q4_0** |
| `ple_key`, `ple_value` | Q8_0 |
| `ple_conv1d` | F16 |
| `hc_attn_up`, `output_hc_up` | Q8_0 |
| `hc_ffn_up` / `hc_ffn_down` / `hc_ffn_inject` | F16 |
| `ffn_gate_inp`, `ffn_gate_inp_shexp` | F32 |
| all norms, `ssm_a`, `ssm_conv1d`, `ssm_dt.bias`, indexer norms | F32 |

## Two traps this exposes

**The PLE table is Q4_0 in q4lean, not F16.** `scripts/quant-heretic-hybrid.sh` keeps it F16
because it is only the **first step** of the q4lean chain: it builds `Hybrid-f16.gguf` (since
deleted as VOID-ARCH), and the next step (q4ple) takes `per_layer_token_embd` to Q4_0. Its
`--include-weights` strings are q4lean's step 3, not the whole recipe; the later passes change
the expert gate/up type and the dense tier. Full chain: [`../REPRODUCE.md`](../REPRODUCE.md).

**Format floors are visible here.** Tensors that stay F16 or fall to Q8_0 under a 256-block
target do so because their `ne[0]` does not divide 256 — MoE down-proj at 640, the PLE table
at 160, `hc_attn_up`/`output_hc_up` at 320. The quantizer falls back silently; the logs record
it as `ncols N not divisible by 256 ... falling back`.

## Status

The chain in `REPRODUCE.md` is the recorded command sequence, but it has not been re-run end to
end, so it is unverified until a rebuild reproduces the byte count. This type map, by contrast,
is measured from the shipped files. A rebuild that reproduces **these tables** has reproduced the
model, whatever arguments get used to reach it.

## Rebuild acceptance bar

A rebuild counts as reproducing q4lean5 if it is **type-map-identical** (the tables above) and
**byte-count-identical** (101,488,511,616 B). Byte-identical output is not required; it is not a
reasonable bar across hosts and thread counts. If a rebuild does not reproduce, do not edit this
file to match: publish the delta as an erratum in `CLAIMS.md` section C. If the difference is
small and quality-neutral, the rebuild ships under a new name (q4lean6) and the published file
stays as it is.
