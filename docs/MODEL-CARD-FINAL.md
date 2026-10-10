---
license: other
license_name: qwen-community-1.0
license_link: LICENSE
base_model: trohrbaugh/Qwen3.8-Flash-Next-heretic
base_model_relation: quantized
library_name: gguf
pipeline_tag: image-text-to-text
quantized_by: the-shop
language: [en, zh]
tags: [gguf, qwen, qwen4exp, moe, mtp, heretic, decensored, abliterated, uncensored, quantized, not-for-all-audiences]
---

# Qwen3.8-Flash-Next-Heretic — Hybrid q4lean5 (GGUF)

Mixed-precision GGUF of the Qwen3.8-Flash-Next (`qwen4exp`) sparse MoE, **decensored**.
101,488,511,936 B across 3 shards · **4.59 BPW** · sized for a 128 GB Mac.

**In 30 seconds:** at `-ngl 48` it assigns ~67 GiB of tensors to the GPU (94.5 GiB Metal span). On a 128 GB Apple Silicon Mac it
serves comfortably. On 64 GB it does not run usefully — the weights alone are 94.5 GiB. It will
answer things stock Qwen refuses.

Quantized by **the-shop** from [`trohrbaugh/Qwen3.8-Flash-Next-heretic`](https://huggingface.co/trohrbaugh/Qwen3.8-Flash-Next-heretic)
(Heretic 1.3.0+custom, seed 2185752647), itself an abliteration of
[`Qwen/Qwen3.8-Flash-Next`](https://huggingface.co/Qwen/Qwen3.8-Flash-Next) @ `de4b8e4d43b917e7706784d8bb445c9af86a3540`.

## Build recipe

How this quant was built, what was measured, and which claims survived scrutiny:
**https://github.com/the-shop/qwen38-flashnext-hybrid-recipe**

Includes the exact tensor→type map read from the shipped header, the llama.cpp patch needed to
*rebuild* it (serving needs no patch), a claims audit separating what held from what was retracted,
and the provenance chain verified by sha256.

## Quickstart

Works on **stock upstream llama.cpp** — no fork, no patches. Verified on llama.cpp master @ `bf79dbbc` and `7f2dd88`.

```sh
# 128 GB Apple Silicon: raise the wired cap first
sudo sysctl -w iogpu.wired_limit_mb=122880

llama-cli \
  -m Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5-00001-of-00003.gguf \
  -ngl 48 -c 8192 --flash-attn on \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  -ot "ple_ngram_embd=CPU,per_layer_token_embd=CPU,token_embd=CPU" \
  --jinja --temp 1.0 --top-p 0.95 --top-k 20
```

The `-ot` override keeps the PLE n-gram table and the embeddings in host memory; it is part of the
validated serving config.

Point `-m` at **shard 1 only** — llama.cpp opens `00002` and `00003` from the same directory.
Download all three.

**Never pass `--kv-unified` with `--parallel` > 1.** It is a boolean (there is no `--kv-unified 0`;
you omit it). With it set and more than one slot, QSA is **silently disabled** and the model runs
dense attention — output and throughput both change, with no error. This invalidated an entire
measurement set during development.

### Speculative decoding (MTP)

```sh
  -md mtp-Qwen3.8-Flash-Next-Heretic-BF16.gguf --spec-type draft-mtp --spec-draft-n-max 1
```

Verified loading and generating on stock master.

> **Disclosure:** the MTP draft head is **byte-identical to the base-model head** — all 34 tensors
> hash equal, verified per-tensor. Heretic did not modify the MTP block, so although this file was
> converted from the heretic checkpoint, the draft weights are base weights. Draft and target are
> different weights.

### Vision

```sh
llama-mtmd-cli -m ...-00001-of-00003.gguf --mmproj mmproj-Qwen3.8-Flash-Next-Heretic-F16.gguf --image pic.png -p "Describe this image."
```

Validated: correctly identified shapes, colours and their positions in a synthetic test image
(259 ms encode). The main GGUF carries no vision tensors; the projector is the separate mmproj
(`qwen3vl_merger`, 334 tensors).

## Precision layout

Measured from the shipped GGUF header, not reconstructed from a command line:

| type | tensors | bytes | share | what |
|---|---|---|---|---|
| **Q4_0** | 145 | 96.75 GB | **95.3%** | all routed experts (gate/up/down) **and the PLE n-gram table** |
| Q6_K | 423 | 3.51 GB | 3.5% | dense: attn q/k/v/qkv/output/gate, `ffn_gate_shexp`, `output`, ssm α/β |
| F16 | 169 | 0.67 GB | 0.7% | `hc_ffn_*`, `ple_conv1d` |
| Q8_0 | 99 | 0.29 GB | 0.3% | `ple_key`/`ple_value`, `hc_attn_up`, `output_hc_up` |
| F32 | 388 | 0.26 GB | 0.3% | norms, gate-inp, `ssm_a`, conv1d |

`general.file_type` is set to `MOSTLY_Q4_0` because **Q4_0 is 95.3% of the bytes**. Labelling by
tensor *count* would say Q6_K (423 vs 145) and imply ~6.5 bpw fidelity this file does not have.

**Why not uniform q4_K/q6_K:** MoE down-proj is `ne[0]=640`, the PLE table `ne[0]=160`. Neither
divides 256, so every 256-block format silently falls back to F16 on exactly the tensors that
dominate the file. q4_0-class is the floor, and that constraint is what shapes this recipe.

## Hardware

| setup | expect |
|---|---|
| **128 GB Apple Silicon** (validated on M5 Max) | `-ngl 48` with the `-ot` override above: ~67 GiB of tensors (94.5 GiB Metal span); loads and generates correctly. Backend logs confirming every layer runs on the GPU have not been captured yet. Needs the `iogpu.wired_limit_mb` bump. |
| **64 GB Mac** | **No.** Weights alone are 94.5 GiB. Not a tuning problem. |
| **NVIDIA** | Untested by us. ~95 GiB of weights plus KV, so 2× 80 GB or 4× 48 GB with `--tensor-split`. |

**Tiering, if you can't fit it all:** put a **contiguous block** of layers on the GPU, never
cherry-pick expert tensors. At equal GPU memory, contiguous `-ngl 16` beat scattered per-layer
expert placement by **+28.6%** (20.80 vs 16.18 tok/s, measured on the
[Q8_0 sibling](https://huggingface.co/the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-Q8_0), not on this file) — each CPU↔GPU crossing costs a GPU drain plus
host-side copies, and scattered placement pays two per *layer* instead of two per *token*.

llama.cpp charges the Metal buffer as `max_offset − min_offset` over GPU-assigned tensors **per
file**, so a single GPU-assigned tensor near offset 0 stretches the span across the whole file.

## What has NOT been validated

- **No safety evaluation of any kind by us.** The refusal and KL figures below are
  **trohrbaugh's**, from their abliteration run.
- No needle battery across 64K–128K. `qwen4exp.context_length = 262144` is **metadata**; we claim
  the file declares it, not that it works at that length.
- No agentic/SWE rounds, no uncensored-suite evaluation.
- One sighting of llama.cpp issue #28805 with this serving config (prefill completes, decode returns a single
  EOS, HTTP 200).
- Exactness figures are measured against a **q8_0** reference, and the F16 source is itself a lossy
  re-encode of a natively-bf16 checkpoint — **two removes from BF16**.
- **No like-for-like throughput comparison against any other quant exists.** An earlier comparison
  was measured with QSA disabled and has been retracted.

## Decensoring

This model is abliterated. Per **trohrbaugh's** `reproduce.json` — *their* measurement, not ours —
the abliteration scored **0 refusals of 100** across hacking, deception, drugs, weapons and
self-harm prompts, at **KL 0.1160**.

## Licence

**Qwen Community License 1.0**, inherited unchanged through the whole chain — shipped verbatim as
`LICENSE`, which governs; this summary does not. Not Apache-2.0; an Apache claim on a different
Qwen3.8-Flash-Next lineage does not apply to these weights. We cannot and do not grant any
additional rights.

- **Clause 1:** keep the copyright and permission notice in all copies or substantial portions.
  If the model or any derivative is used in a commercial product or service with more than
  100,000,000 monthly active users or more than US$20,000,000 (or equivalent) in monthly
  revenue, the model name must be prominently displayed in that product's user interface.
- **Clause 2:** if you or any of your affiliates run a Model as a Service or AI Work Assistant
  business, you need a separate licence from Qwen before using the model or its derivatives
  for any commercial purpose. Internal use is exempt only while it does not make the model,
  its outputs or its underlying capabilities available to any third party.

## Related

- Q8_0 GGUF of the same weights:
  [the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-Q8_0](https://huggingface.co/the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-Q8_0)
- MLX 8-bit of the same weights, for TensorFold with SSD expert streaming:
  [the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-MLX-8bit](https://huggingface.co/the-shop/MLXFW-Qwen3.8-Flash-Next-Heretic-MLX-8bit)
- Build recipe: [the-shop/qwen38-flashnext-hybrid-recipe](https://github.com/the-shop/qwen38-flashnext-hybrid-recipe)
- MLX/TensorFold tooling: [the-shop/mlxfw-qwen38-flashnext-q8](https://github.com/the-shop/mlxfw-qwen38-flashnext-q8)

## Credits

| role | who |
|---|---|
| Base model | **Qwen Team, Alibaba** — `Qwen/Qwen3.8-Flash-Next` @ `de4b8e4d43b917e7706784d8bb445c9af86a3540` |
| Decensoring tool | **p-e-w** — [heretic](https://github.com/p-e-w/heretic) |
| Tool fork | **timrohrbaugh** — heretic 1.3.0+custom; listed by the parent as github.com/timrohrbaugh/heretic, which returns 404 as of 2026-10-10 |
| Abliterated weights | **trohrbaugh** — [`trohrbaugh/Qwen3.8-Flash-Next-heretic`](https://huggingface.co/trohrbaugh/Qwen3.8-Flash-Next-heretic), direct parent |
| Runtime | **ggml-org** — llama.cpp |
| Arch support (merged) | **unslothai** — llama.cpp PR **#27742** |
| Arch support (closed) | **JJJYmmm** — llama.cpp PR **#27739**, `add_qwen4exp` @ `dfa0c0f` |

**PR #27739 deserves explicit credit.** It never merged, but it is the branch this model was
converted, quantized and first served on. A closed PR is still someone's work.

Requantized and measured by the-shop (Mladen Lotar).
