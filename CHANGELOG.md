# Changelog

All notable changes to this recipe repository. Versions are annotated git tags on `main`.

## Unreleased

- **Reproduction:** `REPRODUCE.md` gives the exact command chain from the source checkpoint to the
  shipped shards (tool commits, every `--include-weights` / `--exclude-weights` argument, thread
  counts, `LLAMA_MMAP_PREFETCH=0`), with the sha256 and byte size of every surviving
  intermediate and a verified / inferred split. Recovered from the build session's command log.
- **Correction:** v0.1.0 said the literal quantize arguments were never recorded and that
  `scripts/quant-heretic-hybrid.sh` is a different recipe. Both were wrong: the arguments were in
  the session log, and that script is step 3 of the q4lean chain (README, `docs/TYPEMAP.md`,
  repo rules updated). The chain is still not re-run end to end.
- **Attribution:** the F16 conversion on the #27742 tree (`6c84c7d5`) is now recorded, not
  inferred (`docs/ATTRIBUTION.md`).

## v0.1.0 — 2026-10-10

First public release of the build recipe and runtime notes for
`Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5` (101,488,511,616 B unsplit, 4.59 BPW), a mixed-precision
GGUF of the 177B / A10B Qwen3.8-Flash-Next MoE, requantized from
`trohrbaugh/Qwen3.8-Flash-Next-heretic`.

- **Recipe:** reconstructed build chain (README) and measured ground-truth type maps from the
  shipped GGUF headers (`docs/TYPEMAP.md`). The literal quantize arguments were never recorded;
  the type map is the authoritative target.
- **Runtime:** loads and generates on stock upstream llama.cpp (post-#27742), including the
  MTP draft head and the vision projector (`docs/STOCK-LOAD.md`, `docs/PREFLIGHT.md`).
- **Patches:** `patches/qwen4exp-pr27739-local.patch` (7 files against JJJYmmm/llama.cpp
  `add_qwen4exp` @ `dfa0c0f`; patch 7 is required to rebuild the quant) and
  `patches/script-drift.patch`.
- **Scripts:** quantize, serve, bench, byte-identity and logits-exactness tooling.
- **Fix:** `scripts/logits-dump.cpp` kept token ids 0-255 plus the argmax instead of the true
  top-256 (max-heap where a min-heap was needed). Fixed here; the published exactness figures
  are top-1 only, and KL / top-5 / p99 from the earlier bins are withdrawn (`docs/CLAIMS.md`).
- **Claims:** surviving vs retracted figures (`docs/CLAIMS.md`), provenance by sha256
  (`docs/PROVENANCE.md`), span investigation (`docs/SPAN.md`), risk and licence notes
  (`docs/RISK.md`), model card (`docs/MODEL-CARD-FINAL.md`).
- **Attribution:** full upstream chain in `docs/ATTRIBUTION.md`. Licences: weights under the Qwen
  Community License 1.0, shipped verbatim (`LICENSE`); scripts and patches MIT (`LICENSE-CODE`).
