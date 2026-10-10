# Repository rules — Qwen3.8-Flash-Next hybrid quant recipe

Recipe repo for a requantization of a 177B/A10B MoE. No weights here — see README.md.
`AGENTS.md` is a symlink to this file.

## Releases

- Releases are **annotated git tags** `vMAJOR.MINOR.PATCH` on `main`. The current release is
  `v0.1.0`.
- Every release has a matching entry in `CHANGELOG.md`, written before the tag.
- Never force-push `main`. Never move or delete a published tag; fix forward with a new
  PATCH release.
- Author for commits and tags: `Mladen Lotar <mladen@the-shop.hr>`.

## No AI attribution

Commits, PRs, tags, docs and release notes carry **no** AI-tool attribution: no AI-tool
attribution trailers or session links, and no narration of how the work was divided between
tools or review passes.
Write in neutral project voice ("we", "the-shop"), never first-person tool voice.

## Credit upstream

**`docs/ATTRIBUTION.md` is binding.** This project contains no original weights: it is a
requantization of someone else's abliteration of someone else's model, built on a community
runtime, measured against a third party's quant.

Before writing anything public — model card, README, commit message, post, issue comment:

1. **Name every upstream.** Qwen (base), p-e-w/heretic and the timrohrbaugh fork (tool),
   trohrbaugh (parent weights), ggml-org (runtime), **both** llama.cpp PRs — merged #27742
   (unslothai) *and* closed #27739 (JJJYmmm) — Unsloth (comparison baseline).
2. **Never drop #27739 because it was closed.** It is the branch everything was built on.
3. **Never present someone else's measurement as ours.** The KL 0.1160 and 0/100 refusal
   figures are trohrbaugh's. We ran no safety evaluation.
4. **Follow the Qwen Community 1.0 licence**, not a downstream card's conflicting claim.
5. **Mark unresolved provenance as unresolved.** Do not infer a parent from a sibling
   directory. That was done once here and the answer was wrong.

## Claims discipline

- Every number must trace to a measurement: a log, a sha256, a commit, or a measured value
  with its configuration. Anything not measured is marked **unverified**.
- **`docs/CLAIMS.md` separates what survived review from what was retracted. Publish only
  from column A.** The original campaign report (not shipped) keeps superseded values inline;
  reading it without CLAIMS.md reproduces withdrawn numbers.
- Never republish:
  - the q4ple vs UD-Q4_K_XL baseline throughput delta (measured with `--kv-unified`, which
    silently disables QSA and falls back to dense attention)
  - any exactness figure without naming the KV type on both sides and the q8_0 reference
  - the external 89.5% anchor comparison — the source report explicitly says not to quote it
- Figures measured on a sibling artifact (e.g. the Q8_0 quant) are labelled as such.

## Reproduction

**`docs/TYPEMAP.md` is the authoritative recipe**, not a command line. The literal
`--include-weights` strings for q4lean2/q4lean5 were never recorded; the type maps were read
out of the shipped GGUF headers. A rebuild that reproduces those tables has reproduced the model.

Do **not** attribute `scripts/quant-heretic-hybrid.sh`'s `--include-weights` strings to
q4lean — that script builds a different artifact and keeps the PLE table at F16, where q4lean
has it at Q4_0.

## Facts that bite

- The winner is **q4lean5**, not q4ple. 101,488,511,616 B.
- `--kv-unified` with slots>1 silently disables QSA. Check this first when throughput looks wrong.
- Stock llama.cpp (post-#27742) **loads** this GGUF — verified by loading, see `docs/STOCK-LOAD.md`.
  **Rebuilding** the quant still needs patch 7; stock `--include-weights` only filters the imatrix.
- The q4lean5 build script does not exist. The chain in README.md is reconstructed from logs
  and is unverified until a rebuild reproduces the byte count. Say so whenever citing it.

## Hygiene

No machine-local paths, hostnames, usernames, private data or internal ticket ids in tracked
files. Scripts read locations from environment variables (`.env.example`).
