# Pre-flight

## Closed — verified empirically

| # | item | evidence |
|---|---|---|
| ✅ | **Current master loads it.** Built `ggml-org/llama.cpp` @ `bf79dbbc`, **200 commits** past the merge commit. Loads clean, no unknown-arch, no missing tensor. | `build : b200-bf79dbbc` |
| ✅ | **Output is correct**, not just loading. `-n 600`, temp 0: full thinking block, then `Canberra. 17 × 23 = 391.` Both right. | the earlier `-n 24` truncated inside the thinking block |
| ✅ | **Low-risk by construction.** The `LLM_KV_*` set that `qwen4exp.cpp` reads is **byte-identical** across those 200 commits (file grew 1199→1469 lines, key set unchanged). New `NEXTN_HC_HEAD_*` tensors are gated behind `load_mtp`, default false. | |
| ✅ | **Chat template intact** — byte-identical to source `chat_template.jinja` (8952 B, sha `c3cf9e34abf4f9e3`). Vocab 248320. | |
| ✅ | **Main GGUF sha256** `e84a8f8460c557bdc559be89760c1bc20dcd25fb2dc31e6d6b0022c6fda70d57` | 101,488,511,616 B |

## Blockers found in pre-flight — all resolved before publication

### 1. The MTP sidecar did not load on current master — recovered

`Qwen3.8-Flash-Next-MTP-Q8_0.gguf` carried `blk.48.nextn.{eh_proj,enorm,hnorm}` plus top-level
`output_hc_{norm,down,up}`. Master (`src/models/qwen4exp.cpp`) requires **per-block**
`blk.48.nextn.hc_head_{norm,down,up}` when `load_mtp` is on. Master grew a first-class MTP path
(`--mtp`, `COMMON_SPECULATIVE_TYPE_DRAFT_MTP`) *after* the original conversion, with renamed
tensors. The two namings are different tensors in `llama-arch.cpp`, not aliases.

`qwen4exp.cpp` MTP support, counted per tree:

| tree | nextn | mtp | hc_head | lines |
|---|---|---|---|---|
| fork #27739 | 18 | 17 | 0 | 1442 |
| #27742 merge commit `6c84c7d5` | 0 | 0 | 4 | 1199 |
| master `7f2dd88` | 23 | 17 | 9 | 1469 |

The missing weights were in the heretic checkpoint all along: its index lists 31 MTP tensors
including `mtp.hyper_connection_mixer.{hc_norm,input_mix_weight_down,input_mix_weight_up}`, and
master's converter maps that prefix to `nextn_hc_head` and exports the head on its own with
`--mtp`. The fork's converter never emitted those three.

**Resolution:** the MTP head was reconverted from the heretic checkpoint with master's converter.
It loads and generates on stock master (`RC=0`, answered "Canberra", no assert, no missing tensor).

**Finding:** the reconverted head is **byte-identical to the base-model head** — all 34 tensors
hash equal, checked per tensor name. Heretic never touched the MTP block, so the "draft and target
are different weights" disclosure stays, now on verified evidence. Acceptance can only move because
the target changed, not the draft. The fix was a pure 3-for-3 rename (`output_hc_*` →
`blk.48.nextn.hc_head_*`).

**Method trap:** a byte-aligned comparison of the two files reports DIFFER. That is an artifact —
tensor storage order differs between the files, so equal offsets hold different tensors. Only
per-name hashing is valid.

**Consequence for published numbers:** the 49.96 t/s / 86.38 t/s MTP figures in `CLAIMS.md` were
produced with the original fork sidecar. They have not been re-measured with the master-converted
head and must not be presented as measured on stock llama.cpp. **Unverified on stock.**

### 2. `general.name = "Qwen3.8 Flash Next Heretic Bf16"` — fixed

HF renders this as the model name — "Bf16" on a 4.59 BPW file. Rewritten with
`gguf_new_metadata.py --general-name` to `Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5`
(full 101.5 GB rewrite) and verified in the rewritten header.

### 3. `general.file_type = 18` (`MOSTLY_Q6_K`) — fixed

18 was chosen by tensor **count** (423 Q6_K vs 145 Q4_0). By **bytes**, Q4_0 is 96.75 of
101.48 GB (95.3%), so HF would have badged a ~6.5 bpw expectation on a mostly 4.5 bpw file.
Set to `2` (`MOSTLY_Q4_0`) with `gguf_set_metadata.py general.file_type 2` (in-place scalar edit;
`gguf_new_metadata.py` has no file_type option). Byte breakdown: `MODEL-CARD-FINAL.md`.

### 4. Vision path never executed — validated

The mmproj is a real projector: `general.architecture = clip`, `clip.projector_type =
qwen3vl_merger`, `clip.has_vision_encoder = True`, `image_size 768`, 334 vision tensors.
`qwen3vl_merger` is supported by mtmd, and mtmd validates embedding width against the text model at
runtime, so a mismatch fails cleanly. The main GGUF carries zero vision tensors and reports
`modalities : text`, but sets `qwen4exp.ple.image_token_id = 248056`.

Tested with `llama-mtmd-cli` on a synthetic image (red circle left, blue square right, text
"HELLO 42"), chosen so a wrong answer is unmistakable: `RC=0`, 259 ms encode, both shapes, colours
and positions named correctly.

## Packaging notes

- Split with `llama-gguf-split --split-max-size 45G` into 3 shards (44,846,695,616 /
  44,744,014,016 / 11,897,802,304 B). The split was done believing HF capped files at 50 GB; HF
  actually recommends <200 GB per file with a 500 GB hard limit, so it was optional. Shard 1 plus
  the MTP draft were re-validated on stock master after splitting (`RC=0`, "Canberra", 17×23=391).
- Every GGUF was byte-verified after upload (HF stored oid == local sha256).
- A 101.49 GB model does not fit HF's 100 GB free-tier private quota, and the quota check only
  lands when the atomic Xet commit completes. The repository was therefore published public.
- Harness trap: an upload piped through `tail` reported success on failure because `$?` was
  `tail`'s status. Use `set -o pipefail` or `PIPESTATUS`.

## Desirable, ranked

4. ~~mmproj never tested~~ — resolved above.
5. ~~Not split~~ — split into 3 shards, see packaging notes.
6. ~~Storage quota~~ — see packaging notes.
7. **Context length.** `qwen4exp.context_length = 262144` is metadata only. No needle battery
   64K–128K, and one sighting of llama.cpp #28805. Claim *the file declares* 262144, not that it works.
8. **Rebuild unverified.** `TYPEMAP.md` makes it falsifiable; leave it labelled reconstructed.

## Open — not yet run: proof that `-ngl` actually offloads

**Status: open.** Both span runs passed, but `llama-cli` at default verbosity prints no backend
lines, so neither proved GPU engagement. Until the run below is captured, the model card says the
file loads and generates at `-ngl 48`, and does **not** claim that every layer runs on the GPU.
One load-only run settles it:

```sh
llama-server --model <q4lean5> --port <free> -ngl 48 --ctx-size 512 --no-warmup -lv 8 2>&1 | tee be.log
grep -c "bind\|already in use" be.log      # FIRST - a dead server fakes a clean absence
grep -c "assigned to device MTL0" be.log   # the answer
grep -E "MTL0.*model buffer size" be.log   # GiB actually on GPU
```

`-lv 8`, not `-lv 4` — the `assigned to device` lines are DEBUG level. Expect ~1.4 GiB/layer for
q4lean5, so a healthy full offload reports ~60–67 GiB on MTL0; ~0 means offload silently did not
happen.
