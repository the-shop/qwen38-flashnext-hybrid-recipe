# HF model card — draft (superseded)

**Superseded by `MODEL-CARD-FINAL.md`.** Kept as a record of the options considered. The two
open decisions marked **[DECIDE]** were resolved as: ungated, with the `not-for-all-audiences`
tag; and the mmproj shipped after the vision path was validated (`docs/PREFLIGHT.md`). Several
statements below were corrected in the final card (`--kv-unified` is a boolean; the MTP draft
head is byte-identical to the base-model head; only BF16 and Q8_0 MTP heads were published).

## Frontmatter

```yaml
---
license: other
license_name: qwen-community-1.0
license_link: LICENSE
base_model: trohrbaugh/Qwen3.8-Flash-Next-heretic
base_model_relation: quantized
library_name: gguf
pipeline_tag: text-generation      # [DECIDE] image-text-to-text if the mmproj ships
quantized_by: the-shop
language: [en, zh]
tags:
  - gguf
  - qwen
  - qwen4exp
  - moe
  - abliterated
  - uncensored
  - quantized
  - not-for-all-audiences          # resolved: added (docs/RISK.md)
---
```

## Body

```markdown
# Qwen3.8-Flash-Next-Heretic — Hybrid q4lean5 (GGUF)

Mixed-precision GGUF of a 177B-parameter / A10B MoE. 101.5 GB, 4.59 BPW; starts a 262,144-token
server inside a 128 GB unified-memory budget (long-context quality untested).

Quantized by the-shop from [trohrbaugh/Qwen3.8-Flash-Next-heretic], itself a Heretic
decensoring of [Qwen/Qwen3.8-Flash-Next] at commit `de4b8e4d`, produced with
[p-e-w/heretic] via the timrohrbaugh/heretic fork, v1.3.0+custom, seed 2185752647.

## Precision layout

| component | type |
|---|---|
| MoE gate/up experts | q4_0 |
| MoE down experts | q4_0 (ne[0]=640 — see below) |
| dense | q6_K |
| embeddings, lm_head | q8_0 |
| PLE projections | q8_0 |
| PLE n-gram table | q4_0, host-pinned |

Q6_K 423 · F32 388 · F16 169 · Q8_0 99 · Q4_0 145 (q4lean5, read from the shipped header; the pre-Q6_K tier was Q8_0 522 — that is q4lean2's census, not the winner's)

**Why not uniformly q4_K/q6_K:** the MoE down-projection is `ne[0]=640` and the PLE table
is `ne[0]=160`. Neither divides 256, so any 256-block format *silently falls back* for
those tensors. q4_0-class is the floor for them.

## Running it

Works with unmodified llama.cpp from PR #27742 (merged 2026-08-27) onward. No fork needed.

    llama-server --model Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5-00001-of-0000N.gguf \
      --ctx-size 262144 --flash-attn on \
      --cache-type-k q4_0 --cache-type-v q4_0 \
      --load-mode none \
      -ot "ple_ngram_embd=CPU,per_layer_token_embd=CPU,token_embd=CPU"
    # env: LLAMA_MMAP_PREFETCH=0   (Apple Silicon; avoids eager whole-file WILLNEED)

**If you run more than one slot, omit `--kv-unified`** (it is a boolean flag). With `--kv-unified` and slots>1,
QSA is silently disabled and the model falls back to dense attention. This is the single
easiest way to get wrong numbers from this model.

## Measured

M5 Max, 128 GB unified, weights on an external SSD.

| metric | value | conditions |
|---|---|---|
| decode | 49.96 t/s | single stream, MTP Q8_0 draft, acceptance 0.905 |
| batch-4 aggregate | 86.38 t/s | MTP, QSA on, acceptance 0.921 |
| batch-8 | ~69.0 t/s | degrades vs batch-4 |
| wired @262144 | 79.48 GiB | KV q4_0, mmproj off, host-pinned PLE+embeddings |

Throughput figures use the MTP draft head. Exactness figures below are draft-free — the
two were not measured together, and MTP output is not byte-identical to greedy.

## Exactness

Teacher-forced, 1153 positions, against an all-q8_0 reference built from the same F16 source.

| KV (cand/ref) | top-1 |
|---|---|
| F16 / F16 | 95.06% |
| q8_0 / q8_0 | 94.54% |
| q4_0 / q4_0 (served) | 94.62% |

Top-1 only: the stored logits bins keep the argmax plus token ids 0-255 (a top-k heap bug in
`logits-dump.cpp`, since fixed), so KL figures from them are invalid and withdrawn.

**Read these carefully.** The reference is q8_0, not BF16, and the F16 source is itself a
lossy same-size re-encode of a natively-bf16 checkpoint — so these are two removes from
BF16 and are not comparable to published BF16-referenced figures elsewhere.

## Files

| file | size |
|---|---|
| q4lean5 GGUF (3 shards) | 101,488,511,936 B total (unsplit file 101,488,511,616 B) |
| MTP-Q8_0 draft head | 4,143,611,456 B |
| MTP-Q4_K_M draft head | 2,794,430,016 B |
| mmproj F16 | 904,003,936 B |

**The MTP draft heads derive from the base Qwen3.8-Flash-Next, not the heretic checkpoint.**
Draft and target are different weights.

## Decensoring — not our measurement

trohrbaugh reports KL 0.1160 and 0 refusals / 100 prompts across hacking, deception, drugs,
weapons and self-harm categories. **Those are their figures from their run**, recorded in
`reproduce.json`. the-shop requantized the result and ran no safety evaluation of its own.

This model will comply with requests a stock Qwen model refuses. Evaluate it yourself
before deploying it anywhere it can act.

## Not validated

No needle test across 64K–128K. No agentic or SWE rounds. No uncensored-suite evaluation.
One observation of llama.cpp issue 28805 with this serving config (prefill completes, decode returns a
single EOS token, HTTP 200).

## Licence

Qwen Community License 1.0, inherited unchanged through the chain and shipped verbatim.
**Clause 1:** products or services with >100M monthly active users or >US$20M monthly
revenue must prominently display the model name. **Clause 2:** operating a Model-as-a-Service
or AI Work Assistant business requires a separate licence from Qwen before any commercial use;
the internal-use exemption holds only while no third party gets access.
```

## [DECIDE] 1 — gating (resolved: ungated + `not-for-all-audiences`)

trohrbaugh ships **ungated**. orcarouter (a different lineage) ships `gated: auto`.

| option | what a visitor sees | what it blocks | reversible |
|---|---|---|---|
| nothing | normal page | nothing | — |
| `not-for-all-audiences` tag | click-through interstitial over the card | **nothing** — files, API, anonymous download all work | yes, delete the line |
| `gated: auto` | must log in, click "Agree and send request" | **the files**; anonymous download fails | yes |
| `gated: manual` | same, then waits for us | the files, until we approve; rejected users cannot re-request | yes |

Gating gives us a downloadable report of every requester (id, name, email, timestamps) —
which is a data-handling obligation we take on. We can revoke any individual's access at
any time regardless of prior approval. `extra_gated_eu_disallowed` exists but only applies
once gated.

## [DECIDE] 2 — mmproj (resolved: shipped, vision validated)

Shipping it makes the repo `image-text-to-text`. The validated serve config is `MMPROJ=off`,
so the vision path was untested at draft time. It was later validated on stock llama.cpp
(`docs/PREFLIGHT.md`) and shipped.

## Upstream terms — none beyond the licence

The trohrbaugh card adds **no** usage restriction, disclaimer or attribution request — it is
a Heretic auto-generated card plus Qwen's own card pasted verbatim. (orcarouter's card does
carry a research-only restriction; that is a different lineage and does not bind this work.) Only
Qwen Community 1.0 applies. Crediting trohrbaugh and both Heretic repos is courtesy and
accuracy, not obligation.
