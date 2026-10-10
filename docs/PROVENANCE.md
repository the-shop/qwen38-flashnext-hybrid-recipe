# Provenance — what we can and cannot evidence

## Proven from local files

| fact | evidence |
|---|---|
| Base is `Qwen/Qwen3.8-Flash-Next` | heretic README line 14; HF cache stub `models--Qwen--Qwen3.8-Flash-Next` (refs only) |
| Decensored with Heretic v1.3.0+custom | heretic README header; `github.com/p-e-w/heretic`, fork `timrohrbaugh/heretic` (fork URL 404 as of 2026-10-10) |
| Abliteration quality | KL 0.1160, refusals 0/100 (stated in that README) |
| Licence of the weights we hold | `LICENSE` in the bf16 dir = **Qwen Community License 1.0**, "Copyright (c) 2026 Qwen"; frontmatter `license: other / license_name: qwen-community-1.0` |
| Source safetensors integrity | `qwen3.8-flash-next-heretic-bf16/reproduce/SHA256SUMS` |

## Parent — RESOLVED by byte evidence

**`trohrbaugh/Qwen3.8-Flash-Next-heretic`**, proven, not inferred.

The bf16 dir contains a `reproduce/` directory recording the abliteration run:

```
reproduce/reproduce.json
  model        Qwen/Qwen3.8-Flash-Next
  model_commit de4b8e4d43b917e7706784d8bb445c9af86a3540
  fork         https://github.com/timrohrbaugh/heretic
  upstream     https://github.com/p-e-w/heretic
  timestamp    2026-08-27T20:20:38
  seed         2185752647
```

plus `weights_sha256` for all 34 shards, mirrored in `reproduce/SHA256SUMS`.

**Verified by hashing our own files**, independently re-checked:

| shard | sha256 | |
|---|---|---|
| `model-auxiliary.safetensors` | `f346d471…bc9a8212` | matches recorded |
| `model-00006-of-00033.safetensors` | `2d1e8899…6064841b` | matches recorded |

**Matched to the HF repo** (`api/models/trohrbaugh/Qwen3.8-Flash-Next-heretic?blobs=true`):
34 safetensors with byte sizes identical to ours, `README.md` 66203 bytes = ours exactly,
`lastModified 2026-08-27T20:25:21Z` (4 minutes after the reproduce timestamp), repo sha
`0bfdb14f38416fcbddd7ccfafe50c43e8321c0c1`, **not gated**, cardData identical to our local
frontmatter.

### The orcarouter lead was wrong

`orcarouter/Qwen3.8-Flash-Next-Uncensored` is a **different model** — 131 shards, `gated: auto`,
`license: apache-2.0`. It is the parent of the *sibling* `qwen3.8-flash-next-heretic-gguf/`
directory (groxaxo's quants), not of our bf16.

**The Apache-2.0 conflict does not apply to our chain.** `trohrbaugh` kept
`qwen-community-1.0` and shipped the LICENSE. We inherit those terms unchanged.

### Minor

- Mirror: the download script fetched from ModelScope (see `ATTRIBUTION.md`); the job list it
  consumed was not preserved. Irrelevant for identity — the bytes are identified.
- HF reports `LICENSE` at 3235 bytes; our local copy is 3220 — text-identical; line endings differ (CRLF upstream). **Ship the upstream HF LICENSE.**
- Heretic ran against base commit `de4b8e4d…`; the HF cache ref for `Qwen/Qwen3.8-Flash-Next`
  main is `f5d08274…`. Cite the pinned commit; do not imply we tracked main.

## Obligations we take on by redistributing

1. Ship the Qwen LICENSE verbatim (clause 1: notice included in all copies or substantial portions).
2. Derivative works are explicitly permitted — fine-tuning and derivatives are in scope.
3. **Clause 2 — Model-as-a-Service.** Offering third parties inference or fine-tuning access
   via API or hosted endpoint, commercially, requires a separate licence from Qwen first.
   The internal-use exemption holds only while no third party gets access to the model, its
   outputs or its capabilities. *This is a business decision, not a packaging detail.*
4. **Clause 1 — name display.** A commercial product or service using the model (or a
   derivative) with more than 100M monthly active users or more than US$20M monthly revenue must
   prominently display the model name in its UI. It does not apply to the-shop's own scale, but it
   passes to every downstream user.

No naming/"built with" prefix rule and no use-policy propagation clause in this licence text.

## Disclosures the model card must carry

- **Refusals 0/100 and KL 0.1160 are trohrbaugh's measurements, not ours** (`reproduce.json`,
  across hacking/deception/drugs/weapons/self-harm). Attribute them; do not restate as if we
  evaluated. We ran no safety evals of our own — we requantized someone else's abliteration.
- The **MTP draft head is byte-identical to the base-model head** (all 34 tensors hash equal
  per tensor name; Heretic did not modify the MTP block). Draft and target are different weights.
- The F16 conversion is a **lossy same-size re-encode of a natively-bf16 checkpoint**;
  future requants should use `--outtype bf16`. Every exactness figure is therefore two
  removes from BF16, and measured against a q8_0 reference rather than BF16.
- Unvalidated surface: no needle battery across 64K–128K, no agentic/SWE rounds, no
  uncensored-suite evaluation. One observation of llama.cpp issue 28805 with this serving config
  (prefill completes, decode returns a single EOS, HTTP 200).
