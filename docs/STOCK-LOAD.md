# Stock-runtime verification

**Question:** can someone who downloads this GGUF run it with unmodified llama.cpp,
or do they need our patched fork?

**Answer: unmodified llama.cpp works.** Verified by loading, not by inspection.

## Method

Built `ggml-org/llama.cpp` at `6c84c7d5` — the commit that MERGED Qwen3.8-Flash-Next
support (PR #27742, 2026-08-27). Working tree confirmed clean first:
`git status --porcelain` → 0 modified files. Separate build dir (`build-stock`) so no
artifact from the patched fork could leak in.

```sh
cmake -B build-stock -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DLLAMA_CURL=OFF
cmake --build build-stock --target llama-cli -j 10

LLAMA_MMAP_PREFETCH=0 build-stock/bin/llama-cli \
  --model Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5.gguf \
  --ctx-size 512 --n-gpu-layers 0 --no-warmup --temp 0 --top-k 1 -n 24 --single-turn \
  -p "What is the capital city of Australia? Reply with the city name only."
```

## Result

```
build      : b10660-6c84c7d5
model      : Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5.gguf
ftype      : Q6_K
modalities : text
[ Prompt: 13.0 t/s | Generation: 13.0 t/s ]
```

Loaded cleanly. No unknown-architecture error, no missing tensor, no metadata-key
failure, no assert. Generation proceeded.

`ftype : Q6_K` reflects the header as it was at the time of this run: `general.file_type` was
later changed from 18 (`MOSTLY_Q6_K`) to 2 (`MOSTLY_Q4_0`), see `docs/PREFLIGHT.md` §3. The
tensor data is unchanged by that edit.

## What this does and does not prove

**Proves:** the GGUF's metadata keys and tensor names are upstream-canonical. The four
arch patches in `patches/` are backports of this merged work into the older, never-merged
#27739 branch — not divergences from upstream. A downloader needs none of them.

**Does not prove:** answer correctness. `-n 24` truncated generation inside the model's
thinking block. Correctness evidence is the campaign's verify-model 4/4 and the exactness
matrix in `docs/CLAIMS.md`, not this run.

**Does not cover:** current master. `6c84c7d5` is the merge commit; master has since moved
(a newer `qwen4exp.cpp`, ~1469 lines vs 1199 here). Master (`bf79dbbc`, `7f2dd88`) was verified
separately, including answer correctness, MTP and vision — see `docs/PREFLIGHT.md`.

## Still fork-only

| need | why |
|---|---|
| **Rebuilding the quant** | patch 7 — stock `--include-weights` only filters the imatrix; every tensor is otherwise quantized with the positional ftype, silently producing a different model |
| `LLAMA_MMAP_PREFETCH=0` | no upstream equivalent; master still issues eager WILLNEED (`llama-mmap.cpp:513`). Master's `TENSOR_READ_LAZY` on the PLE table mitigates but does not replace it. |
