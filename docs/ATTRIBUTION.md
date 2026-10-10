# Attribution

Nothing here is original weights. This repository packages a **requantization** of someone
else's decensoring of someone else's model, built on a community runtime, measured against
a third party's quant. Every link gets named.

Where a figure came from someone else's run, it is attributed to them and **not** restated
as ours.

## The chain

| role | who | identifier |
|---|---|---|
| Base model | **Qwen Team, Alibaba** | `Qwen/Qwen3.8-Flash-Next` @ commit `de4b8e4d43b917e7706784d8bb445c9af86a3540` |
| Decensoring tool | **p-e-w** | <https://github.com/p-e-w/heretic> |
| Tool fork used | **timrohrbaugh** | github.com/timrohrbaugh/heretic — v1.3.0+custom (URL as recorded in `reproduce.json`; returns 404 as of 2026-10-10) |
| Abliterated weights (direct parent) | **trohrbaugh** | `trohrbaugh/Qwen3.8-Flash-Next-heretic` |
| Mirror we downloaded from | **ModelScope** | `modelscope.cn/models/trohrbaugh/Qwen3.8-Flash-Next-heretic`, pulled 2026-10-02 14:54–20:44 CEST — evidence below |
| Runtime | **ggml-org** and llama.cpp contributors | <https://github.com/ggml-org/llama.cpp> |
| Architecture support — **merged** | **unslothai** | llama.cpp PR **#27742**, merged 2026-08-27. This is what lets stock llama.cpp load our GGUF. |
| Conversion tooling | **unslothai**, via the #27742 tree | llama.cpp @ `6c84c7d5` (the #27742 merge); the #27739 fork's `convert_hf_to_gguf.py` has no `qwen4exp` support, so conversion must have used this tree (inference from capability) |
| Architecture support — **closed** | **JJJYmmm** | llama.cpp PR **#27739**, branch `add_qwen4exp` @ `dfa0c0f`, 2026-08-26. **Never merged** — and it is the branch we actually built and quantized on. |
| Comparison baseline | **Unsloth** | UD-Q4_K_XL — per the baseline serving script (not shipped): "WEIGHTS: unsloth UD-Q4_K_XL, locally patched and re-split from 4 into 5 shards". **Our copy is re-split, not pristine.** |
| Sibling quants (downloaded, not used in the build) | **groxaxo** | `groxaxo/Qwen3.8-Flash-Next-Heretic-GGUF` (UD-IQ4_XS) |
| This requantization | **the-shop** (Mladen Lotar) | — |

### On PR #27739

Credit it plainly. JJJYmmm's `add_qwen4exp` lost the race to #27742 and was closed unmerged,
but **it is the code that produced these files** — every GGUF in this project was converted,
quantized and first served on that branch. Four of the seven patches in `patches/` are
backports of #27742's merged work *into* #27739, which is why the output is loadable by stock
llama.cpp today.

A closed PR is still someone's work. It got us here.

## Figures that are not ours

- **KL 0.1160, refusals 0/100** across hacking / deception / drugs / weapons / self-harm:
  **trohrbaugh's** measurement from their abliteration run, recorded in `reproduce/reproduce.json`.
  the-shop ran no safety evaluation. Attribute, never restate.
- **UD-Q4_K_XL throughput** used as a baseline: measured by us on our hardware, but the
  artifact is Unsloth's. See `docs/CLAIMS.md` — the published delta against it was **retracted**
  (measured with `--kv-unified`, which silently disables QSA), and no like-for-like QSA
  comparison against it exists.

## Evidence for the download host

The bf16 checkpoint was downloaded from the **ModelScope** mirror:

- the download script fetched from `https://www.modelscope.cn/models/$r/resolve/master/$p`
  with repo id `trohrbaugh/Qwen3.8-Flash-Next-heretic`
- its log ends `ALL DONE Fri Oct 2 20:44:11 CEST 2026`

The job list the script consumed was not preserved. The mirror does not affect identity: the
bytes match the HF repo shard-for-shard (see Verification below).

## Who built it

Built and measured by **the-shop (Mladen Lotar)**: downloads, F16 conversion, the q4lean
quantize passes, all tiering and exactness measurement, provenance resolution, stock-load
verification and packaging. Everything upstream of that is credited in the chain above.

## Licence

**Qwen Community License 1.0**, inherited unchanged through the whole chain. `trohrbaugh`
kept it and shipped the LICENSE file; we ship it verbatim.

Clause 1: the notice travels with every copy, and a commercial product or service using the
model with more than 100M monthly active users or more than US$20M monthly revenue must display
the model name prominently in its user interface.

Clause 2: anyone (or any affiliate) running a Model-as-a-Service or AI Work Assistant business
needs a separate licence from Qwen before any commercial use. The internal-use exemption applies
only while no third party gets access to the model, its outputs or its capabilities.

The `trohrbaugh` card adds **no** terms of its own — it is a Heretic auto-generated card plus
Qwen's card verbatim, with no usage restriction, disclaimer or attribution request. (A
research-only restriction exists on `orcarouter/Qwen3.8-Flash-Next-Uncensored`; that is a
**different lineage** and does not bind this work.)

## Rules for anyone working in this repo

1. **Name every upstream.** Base, abliteration tool and its fork, parent weights, runtime,
   both PRs, the comparison baseline. Including the closed PR.
2. **Never present someone else's measurement as ours.** If we did not run it, say whose it is.
3. **Never drop the closed PR** because it was not merged.
4. **Follow the Qwen licence**, not a downstream card's conflicting claim.
5. **Mark unresolved provenance as unresolved.** Do not infer a parent from a sibling
   directory — that mistake was made once here and was wrong.

## Verification

The parent was established by bytes, not inference. `reproduce/SHA256SUMS` in the bf16
checkpoint records sha256 for all 34 shards; hashing our own files reproduces them
(`model-auxiliary.safetensors` → `f346d471…bc9a8212`). The HF repo matches on shard count,
every byte size, and a README byte-identical at 66203 bytes.

Full detail and the one remaining unknown: `docs/PROVENANCE.md`.
