# Qwen3.8-Flash-Next-Heretic — hybrid quantization recipe

Build recipe and runtime notes for `Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5.gguf`
(101,488,511,616 B unsplit · 4.59 BPW), a mixed-precision GGUF of a 177B / A10B MoE that
starts a 262,144-token server inside a 128 GB unified-memory budget; long-context quality untested.

## ▶ The weights

**https://huggingface.co/the-shop/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5** — public, 114.30 GB,
10 files, every GGUF byte-verified (HF stored oid == local sha256).

| file | size |
|---|---|
| `…-q4lean5-0000{1,2,3}-of-00003.gguf` | 101.49 GB total |
| `mtp-…-BF16.gguf` / `mtp-…-Q8_0.gguf` | 7.77 / 4.14 GB — speculative draft head |
| `mmproj-…-F16.gguf` | 0.90 GB — vision projector |

Runs on **stock upstream llama.cpp** — no fork, no patches. Verified by loading on a clean build.

Related releases by the-shop (same parent weights, different formats):

- HF: [`the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-Q8_0`](https://huggingface.co/the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-Q8_0)
- HF: [`the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-MLX-8bit`](https://huggingface.co/the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-MLX-8bit)
- GitHub: [`the-shop/mlxfw-qwen38-flashnext-q8`](https://github.com/the-shop/mlxfw-qwen38-flashnext-q8)

This repository is the *recipe*, not the release: how the quant was built, what was measured, and
which claims survived scrutiny.

Parent: `trohrbaugh/Qwen3.8-Flash-Next-heretic` (sha256-verified) · base `Qwen/Qwen3.8-Flash-Next` @ `de4b8e4d`

## Status of this document

The winner, `q4lean5`, was built in several passes. The exact commands, including every
`--include-weights` / `--exclude-weights` argument, thread count and tool commit, were
recovered from the build session's command log and are in **[`REPRODUCE.md`](REPRODUCE.md)**,
together with the sha256 and byte size of every intermediate that still exists. (v0.1.0 said
these arguments were never recorded; they were in the session log, not in the quantize logs.)
The full chain has **not** been re-run end to end, so it stays unverified until a rebuild
reproduces the byte count.

## Lineage

```
Qwen/Qwen3.8-Flash-Next                       (Alibaba, Qwen Community License 1.0)
  └─ decensored with Heretic v1.3.0+custom    (github.com/p-e-w/heretic,
     KL 0.1160, refusals 0/100 (trohrbaugh's)  fork: timrohrbaugh/heretic)
      └─ bf16 safetensors, 360 GB (335 GiB), 33 weight shards + 1 auxiliary  (trohrbaugh/Qwen3.8-Flash-Next-heretic, sha256-verified — docs/PROVENANCE.md)
          └─ convert_hf_to_gguf               (llama.cpp @ 6c84c7d5, PR #27742)
              └─ F16.gguf  354,029,928,960 B
```

## Build chain to the winner

Exact commands per step: [`REPRODUCE.md`](REPRODUCE.md).

| step | input | output | ftype | bytes |
|---|---|---|---|---|
| 3-pass hybrid (`scripts/quant-heretic-hybrid.sh 12`) | F16.gguf | Hybrid-f16.gguf | — | ~180 GB **(deleted: VOID-ARCH)** |
| PLE table F16→q4_0 (`--include-weights per_layer_token_embd`) | Hybrid-f16.gguf | q4ple.gguf | Q4_0 | 106,754,669,696 |
| pass A: gate/up q4_K→q4_0 | q4ple.gguf | .tA.gguf | Q4_0 | — |
| pass B: dense/emb/lm_head→q8_0, exclude experts+PLE | .tA.gguf | q4lean2.gguf | Q8_0 | 102,523,604,096 |
| dense→q6_K | q4lean2.gguf | **q4lean5.gguf** | Q6_K | **101,488,511,616** |

Q6_K 423 · F32 388 · F16 169 · Q8_0 99 · Q4_0 145 (q4lean5, read from the shipped header; the pre-Q6_K tier was Q8_0 522 — that is q4lean2's census, not the winner's)

**The winner descends from an artifact that was deleted.** Reproducing from source
means rebuilding the 180 GB `Hybrid-f16.gguf` intermediate first.

## Why the format looks like this

Not taste — hard constraints discovered by measurement:

- **Block-size floors.** MoE down-proj is `ne[0]=640` and the PLE table is `ne[0]=160`.
  Neither divides 256, so any 256-block format (q4_K, q6_K) *silently falls back to
  F16/q8_0* for those tensors. q4_0-class is the floor for them. The quantize logs are
  full of `ncols 640 not divisible by 256 ... falling back`.
- **F16 PLE is unservable on Metal in the old fork** — the allocator wires every tensor
  regardless of `-ot` placement; 184 GB total exceeded the working set and produced
  `kIOGPUCommandBufferCallbackErrorOutOfMemory` with garbage output.
- **Wired memory is a placement problem.** On the #27739 fork build, `--load-mode none` plus host-pinned PLE and
  embeddings cut 32 GiB with byte-identical output (sha `2d59e26b0dab9a71`).

## Serving

```sh
MODEL=/path/to/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5-00001-of-00003.gguf \
BIN=/path/to/stock-llama.cpp/build/bin/llama-server \
KVTYPE=q4_0 MMPROJ=off \
OT="ple_ngram_embd=CPU,per_layer_token_embd=CPU,token_embd=CPU" \
KV_UNIFIED=0 \
LLAMA_MMAP_PREFETCH=0 \
scripts/serve-flashnext-hybrid.sh
```

- `MODEL` is shard 1 of the q4lean5 split; llama.cpp opens shards 2 and 3 from the same directory.
- `BIN` points at a stock llama.cpp build (otherwise the script falls back to `$LLAMA_FORK`).
- `KV_UNIFIED` defaults to `1` in the script (passes `--kv-unified`); set `KV_UNIFIED=0` whenever SLOTS>1.
- `LLAMA_MMAP_PREFETCH=0` has no upstream equivalent; master still issues eager WILLNEED.

**`--kv-unified` with SLOTS>1 silently disables QSA** and runs dense attention. This
invalidated an entire earlier measurement set — if your throughput looks wrong, check
this first.

## Runtime requirements

- **Loading:** stock upstream llama.cpp (post-#27742, merged 2026-08-27). The GGUF uses
  upstream-canonical metadata keys and tensor names. The four arch patches in
  `patches/` are backports *into an older fork*, not divergences from master — a third
  party does not need them. See docs/STOCK-LOAD.md for the verification.
- **Rebuilding the quant:** requires patch 7 in `patches/qwen4exp-pr27739-local.patch`.
  Stock `--include-weights` only filters the imatrix; every tensor is otherwise
  quantized with the positional ftype, silently producing a different model.

## Attribution

This repo contains no original weights. Base model by **Qwen**, abliteration by
**trohrbaugh** using **p-e-w/heretic** (timrohrbaugh fork), architecture support by
**unslothai** (merged llama.cpp #27742) and **JJJYmmm** (closed #27739 — the branch this was
actually built on), runtime by **ggml-org**, comparison baseline by **Unsloth**.

**Full chain, licence terms and the rules for publishing from this repo:
[`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).** It is binding — read it before writing
anything public.

## Contents

```
CLAUDE.md (AGENTS.md -> CLAUDE.md)    repo rules: releases, attribution, claims discipline
CHANGELOG.md                           release history
REPRODUCE.md                           exact rebuild chain: commands, tool commits, sha256 per step
docs/ATTRIBUTION.md                    the full chain; BINDING
docs/TYPEMAP.md                        measured type maps = the authoritative recipe
patches/qwen4exp-pr27739-local.patch   7 files, +151/-17 against JJJYmmm/llama.cpp @ dfa0c0f
patches/script-drift.patch             historical diff (bin/ paths) of the serve/logits-dump edits
                                       behind the published numbers; already applied in scripts/
scripts/                               quantize, serve, bench, exactness tooling
LICENSE                                Qwen Community License 1.0 (weights), shipped verbatim
LICENSE-CODE                           MIT, for the scripts and patches in this repo
docs/                                  provenance, claims audit, stock-load and pre-flight
                                       verification, span investigation, risk, model card
```

## Licence

Qwen Community License 1.0 travels with the weights. A downstream card claiming Apache 2.0
is inconsistent with the LICENSE shipped in the checkpoint; follow the Qwen terms.

**Clause 1:** keep the copyright and permission notice in all copies. If a commercial product
or service using the model (or a derivative) has more than 100M monthly active users or more
than US$20M monthly revenue, the model name must be prominently displayed in its user interface.

**Clause 2:** if you or an affiliate run a Model-as-a-Service or AI Work Assistant business,
you need a separate licence from Qwen before any commercial use. The exemption for internal use
holds **only while no third party gets access** to the model, its outputs or its capabilities.

This is a summary, not legal advice; the `LICENSE` text governs.

**This repository's scripts and patches** are MIT-licensed (`LICENSE-CODE`). The **weights** are
under the Qwen Community License 1.0 (`LICENSE`).

## Running these scripts

Paths come from environment variables — copy `.env.example` to `.env` and set them.

```sh
cp .env.example .env && $EDITOR .env && set -a && . ./.env && set +a
```

**Not shipped here:** `bench-model.sh`, `verify-model.sh`, and the campaign log files that some
docs cite as evidence. They were measurement harnesses specific to one machine;
`scripts/bench-hybrid-ladder.sh` runs them only if you point `BENCH_MODEL` / `VERIFY_MODEL` at
your own equivalents. Where a document
cites one, it is naming its evidence, not a file you will find in this repository.

**What runs on stock llama.cpp:** serving, including MTP and vision. Only *rebuilding the quant*
needs the fork patch in `patches/` — upstream's `--include-weights` still does not gate tensor
types.

## Authorship

Built and measured by the-shop (Mladen Lotar). Upstream credits: [`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).
