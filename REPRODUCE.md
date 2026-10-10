# Reproducing q4lean5 from the source weights

The exact command chain that produced `Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5`, step by step,
with every tool commit, thread count, environment variable, intermediate byte size and sha256
that was recorded.

**Credits.** Base model by **Qwen** (`Qwen/Qwen3.8-Flash-Next`), abliteration by **trohrbaugh**
with **p-e-w/heretic** (timrohrbaugh fork), runtime by **ggml-org** and the llama.cpp
contributors, architecture support by **unslothai** (merged llama.cpp PR #27742) and
**JJJYmmm** (closed llama.cpp PR #27739, the branch this was quantized on), comparison baseline
by **Unsloth**. Full chain and licence terms: [`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).

## Status

| | |
|---|---|
| **Recorded** | Every command below was taken from the build session's own command log (the shell commands as executed, with arguments), not reconstructed from quantize log headers. The quantize log files themselves are not shipped. |
| **Verified** | The sha256 and byte size of every intermediate that still exists (table at the end), the source weights against the abliteration run's own `SHA256SUMS`, the shipped shards against the release `SHA256SUMS`, and a byte-identical rebuild of both MTP heads on a second llama.cpp tree and thread count. |
| **Not verified** | The main chain (steps 2–6) has **not** been re-executed end to end. Until a rebuild reproduces `e84a8f84…` / 101,488,511,616 B, the acceptance bar in [`docs/TYPEMAP.md`](docs/TYPEMAP.md) applies. |

## Environment

Paths are placeholders; see `.env.example`.

| variable | meaning |
|---|---|
| `$SRC` | the source checkpoint directory (bf16 safetensors, step 1) |
| `$MODELS_DIR/qwen3.8-flash-next-heretic-f16` (`$D` below) | where every GGUF intermediate is written |
| `$LLAMA_TOOLS` | `ggml-org/llama.cpp` @ `6c84c7d5d8833c6e0df69628f75a0f599797934e` (the #27742 merge, 2026-08-27). Python converter only. |
| `$LLAMA_FORK` | `JJJYmmm/llama.cpp` branch `add_qwen4exp` @ `dfa0c0fee2b704fd2ac228d365d40502c3006c40` + [`patches/qwen4exp-pr27739-local.patch`](patches/qwen4exp-pr27739-local.patch), built. Provides `llama-quantize`. |
| `$LLAMA_MASTER` | `ggml-org/llama.cpp` @ `bf79dbbcd085e151e65bc98951228054a9e297ae` (2026-10-04, build `b200-bf79dbbc`), built. Release metadata, split, MTP head. |

Every `llama-quantize` call ran with **`LLAMA_MMAP_PREFETCH=0`** (a `$LLAMA_FORK` patch; it only
stops the eager whole-file `MADV_WILLNEED` on a 354 GB input and does not change what is written).

**Why the fork is required for steps 3–6.** Patch 7 (`src/llama-quant.cpp`,
`tools/quantize/quantize.cpp`, `include/llama.h`) makes `--include-weights` /
`--exclude-weights` gate *which tensors are quantized*: a tensor whose name contains an
`--include-weights` pattern (and no `--exclude-weights` pattern) gets the positional type,
every other tensor is copied as it is. Stock `llama-quantize` uses those flags only to filter
the imatrix and quantizes every tensor to the positional type, so the same command lines on a
stock build produce a different model.

## Step 1 — source weights

`trohrbaugh/Qwen3.8-Flash-Next-heretic`, HF repo sha `0bfdb14f38416fcbddd7ccfafe50c43e8321c0c1`
(downloaded from the ModelScope mirror; identity established by hash, see
[`docs/PROVENANCE.md`](docs/PROVENANCE.md)).

- 33 weight shards + `model-auxiliary.safetensors`, **360,000,190,352 B** in total.
- All 34 sha256 values match the checkpoint's own `reproduce/SHA256SUMS` (re-hashed 2026-10-10).

## Step 2 — convert to F16 GGUF (`$LLAMA_TOOLS`)

Python environment: the tree's converter requirements plus `pyyaml`, `tqdm`, `transformers`
(versions not recorded).

```sh
cd "$LLAMA_TOOLS"
# vision projector: the first run used --mmproj; its output was renamed to mmproj-…
python convert_hf_to_gguf.py "$SRC" --outtype f16 --mmproj \
  --outfile "$D/Qwen3.8-Flash-Next-Heretic-F16.gguf"
mv "$D/Qwen3.8-Flash-Next-Heretic-F16.gguf" "$D/mmproj-Qwen3.8-Flash-Next-Heretic-F16.gguf"
# text model
python convert_hf_to_gguf.py "$SRC" --outtype f16 \
  --outfile "$D/Qwen3.8-Flash-Next-Heretic-F16.gguf"
```

| output | bytes | sha256 |
|---|---|---|
| `Qwen3.8-Flash-Next-Heretic-F16.gguf` | 354,029,928,960 | `2eace28079a0a97d16468d4becb778131d2574e5f922172913c6da9c8903a185` |
| `mmproj-Qwen3.8-Flash-Next-Heretic-F16.gguf` | 904,003,936 | `85a27e03b7b506cb2be3fe70d6a8559bc660072ac723a68899d4cdeab494d3e2` |

The mmproj is the file shipped in the release (same sha256).

`--outtype f16` is a same-size re-encode of a natively bf16 checkpoint and is lossy for values
outside the f16 range; it is what was used, so a reproduction must use it too.

## Step 3 — Hybrid-f16 (`$LLAMA_FORK`, 12 threads)

This is [`scripts/quant-heretic-hybrid.sh`](scripts/quant-heretic-hybrid.sh), run as
`scripts/quant-heretic-hybrid.sh 12`. The script in this repository differs from the one that ran
only in reading its paths from environment variables. Its three passes:

```sh
export LLAMA_MMAP_PREFETCH=0
Q="$LLAMA_FORK/build/bin/llama-quantize"
"$Q" --include-weights "ffn_gate_exps,ffn_up_exps" \
  --token-embedding-type f16 --output-tensor-type f16 \
  "$D/Qwen3.8-Flash-Next-Heretic-F16.gguf" "$D/.t1-q4k.gguf" q4_K 12
"$Q" --include-weights "ffn_down_exps" \
  --token-embedding-type f16 --output-tensor-type f16 \
  "$D/.t1-q4k.gguf" "$D/.t2-down.gguf" q4_0 12
"$Q" --include-weights "ple_key,ple_value,ple_conv1d,ple_norm_key,ple_norm_query,ple_norm_conv" \
  --token-embedding-type f16 --output-tensor-type f16 \
  "$D/.t2-down.gguf" "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-f16.gguf" q8_0 12
```

Output `Qwen3.8-Flash-Next-Heretic-Hybrid-f16.gguf`: ~180.4 GB, census F16 690 · F32 388 ·
Q4_K 96 · Q4_0 48 · Q8_0 2. **Exact bytes and sha256 not recorded; the file was deleted** (it is
unservable on Metal in that fork, see README). The PLE table (`per_layer_token_embd`) is still
F16 here; step 4 takes it to Q4_0.

## Step 4 — q4ple: PLE table to Q4_0 (`$LLAMA_FORK`, 6 threads)

```sh
LLAMA_MMAP_PREFETCH=0 "$Q" --include-weights "per_layer_token_embd" \
  "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-f16.gguf" \
  "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-q4ple.gguf" q4_0 6
```

| output | bytes | sha256 |
|---|---|---|
| `…-Hybrid-q4ple.gguf` | 106,754,669,696 | `ac7a3c7ca5b97124e5e1c1dfdd48bf27e28109ac2ea2b7631f5826b03d459211` |

A first attempt at 12 threads was stopped for memory pressure and its output deleted; the file
above is the 6-thread run.

## Step 5 — q4lean2 (`$LLAMA_FORK`, 6 threads, two passes)

```sh
export LLAMA_MMAP_PREFETCH=0
# pass A: expert gate/up q4_K -> q4_0
"$Q" --include-weights "ffn_gate_exps,ffn_up_exps" --allow-requantize \
  "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-q4ple.gguf" "$D/.tA.gguf" q4_0 6
# pass B: dense / embeddings / lm_head -> q8_0; experts and PLE untouched
"$Q" --exclude-weights "ffn_gate_exps,ffn_up_exps,ffn_down_exps,per_layer_token_embd,ple_" \
  "$D/.tA.gguf" "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean2.gguf" q8_0 6
rm -f "$D/.tA.gguf"
```

| output | bytes | sha256 |
|---|---|---|
| `.tA.gguf` (temporary) | not recorded | not recorded |
| `…-Hybrid-q4lean2.gguf` | 102,523,604,096 | `a5f626a581e1e16ba17a913ace305bc3b2dd633d928259f699f475a1d041086e` |

## Step 6 — q4lean5: dense tier Q8_0 to Q6_K (`$LLAMA_FORK`, 6 threads)

```sh
LLAMA_MMAP_PREFETCH=0 "$Q" \
  --exclude-weights "ffn_gate_exps,ffn_up_exps,ffn_down_exps,per_layer_token_embd,ple_" \
  --allow-requantize \
  "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean2.gguf" \
  "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5.gguf" q6_K 6
```

| output | bytes | sha256 |
|---|---|---|
| `…-Hybrid-q4lean5.gguf` | **101,488,511,616** | `e84a8f8460c557bdc559be89760c1bc20dcd25fb2dc31e6d6b0022c6fda70d57` |

Tensors whose row length does not divide 256 cannot take Q6_K and fall back (logged as
`ncols N not divisible by 256 ... falling back`); the resulting type map is in
[`docs/TYPEMAP.md`](docs/TYPEMAP.md).

## Step 7 — release metadata and split (`$LLAMA_MASTER`)

```sh
export PYTHONPATH="$LLAMA_MASTER/gguf-py"
python "$LLAMA_MASTER/gguf-py/gguf/scripts/gguf_new_metadata.py" --force \
  --general-name "Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5" \
  "$D/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5.gguf" "$WORKDIR/q4lean5-fixed.gguf"
python "$LLAMA_MASTER/gguf-py/gguf/scripts/gguf_set_metadata.py" \
  "$WORKDIR/q4lean5-fixed.gguf" general.file_type 2 --force
"$LLAMA_MASTER/build/bin/llama-gguf-split" --split-max-size 45G \
  "$WORKDIR/q4lean5-fixed.gguf" "$WORKDIR/stage/Qwen3.8-Flash-Next-Heretic-Hybrid-q4lean5"
```

`q4lean5-fixed.gguf` was a temporary file; its sha256 was not recorded.

| shipped shard | bytes | sha256 |
|---|---|---|
| `…-q4lean5-00001-of-00003.gguf` | 44,846,695,616 | `4be39ea8d9a606069019be1801ce4ee640861a510092b727cc3558877dd3b43a` |
| `…-q4lean5-00002-of-00003.gguf` | 44,744,014,016 | `4ed19dd7e7e921219833e6b74c9ad16da5d5e180481c9203a87124cd5f9d7a04` |
| `…-q4lean5-00003-of-00003.gguf` | 11,897,802,304 | `6f41716f5f658234c5ed8d39ca89cc1566ec16f242117c3da61a22cc2f197e66` |

## Step 8 — MTP draft heads (`$LLAMA_MASTER`)

```sh
cd "$LLAMA_MASTER"
PYTHONPATH="$LLAMA_MASTER/gguf-py" python convert_hf_to_gguf.py --mtp --outtype bf16 \
  --outfile "$WORKDIR/stage/mtp-Qwen3.8-Flash-Next-Heretic-BF16.gguf" "$SRC"
"$LLAMA_MASTER/build/bin/llama-quantize" \
  "$WORKDIR/stage/mtp-Qwen3.8-Flash-Next-Heretic-BF16.gguf" \
  "$WORKDIR/stage/mtp-Qwen3.8-Flash-Next-Heretic-Q8_0.gguf" Q8_0 8
```

| output | bytes | sha256 |
|---|---|---|
| `mtp-…-BF16.gguf` | 7,770,760,576 | `7b112029d0a20590d8d080347619b3cdb94729a2c37eddbe18931544a1718e7c` |
| `mtp-…-Q8_0.gguf` | 4,137,429,376 | `5737f736f71cbb4fa2289ad073b96e2f284921cdae16fe903e2e43cc8854acdf` |

**Rebuilt byte-identically:** the same two commands on `ggml-org/llama.cpp` tag `v0.6.0`
(`d81235049384534c167caea52b85a694f6103d14`), with the Q8_0 quantize at **4** threads instead
of 8, produced both files with the same sha256 values.

## Side artifact — exactness reference (`$LLAMA_FORK`, 6 threads)

Not part of the release; the reference the published exactness figures are measured against.

```sh
LLAMA_MMAP_PREFETCH=0 "$Q" --pure \
  "$D/Qwen3.8-Flash-Next-Heretic-F16.gguf" \
  "$D/Qwen3.8-Flash-Next-Heretic-Q8_0-REF-pure.gguf" q8_0 6
```

| output | bytes | sha256 |
|---|---|---|
| `…-Q8_0-REF-pure.gguf` | 188,521,704,576 | `d5ab2a7328cd0677750935abef7c0465e9c6e56531b0bba82ea1db82d4158a59` |

## Determinism notes

- **Thread count.** Steps 3–6 ran at different thread counts (12, 6, 6, 6). A probe on a small
  synthetic F16 GGUF (not on this model) found `$LLAMA_FORK`'s `llama-quantize` output
  thread-invariant, and the MTP Q8_0 head above came out identical at 8 and 4 threads on two
  different trees. Expected, not proven, for the full chain.
- **Stock vs fork quantize.** On the same synthetic GGUF, stock `v0.6.0` `--pure q8_0` matched
  the fork byte for byte. That covers kernels, not the include/exclude gating of steps 3–6,
  which stock does not have.
- **Fork build state.** The `$LLAMA_FORK` binaries that ran steps 3–6 were compiled from
  `dfa0c0f` with every hunk of the shipped patch **except** the `LLAMA_MMAP_RANDOM` hunk in
  `src/llama-mmap.cpp`, which was added the day after the builds. That hunk only adds an
  `madvise` hint at load time; the patch's quantize code is the same as what ran.
- **Converter environment.** Python package versions for step 2 were not recorded. A different
  `transformers` / `numpy` / `gguf` version could in principle change the F16 bytes; compare
  against `2eace280…` before continuing.
- **Where a mismatch shows up.** If step 2 matches but a later step does not, the cause is in the
  quantize steps; compare tensor by tensor (by name, not by offset: storage order can differ
  between files that hold identical tensors).

## Verified vs inferred

| claim | status |
|---|---|
| commands, flags, thread counts, input/output names of steps 2–8 | **recorded** in the build session's command log |
| sha256 + size of F16, mmproj, q4ple, q4lean2, q4lean5, REF-pure | **verified**, re-hashed 2026-10-10 from the files produced by those commands |
| shipped shards = metadata rewrite + split of `e84a8f84…` | **recorded** pipeline; shard sha256 values verified against the release `SHA256SUMS` |
| MTP BF16 / Q8_0 reproducible | **verified**, byte-identical rebuild on v0.6.0 |
| Hybrid-f16 exact bytes / sha256 | **not recorded** (deleted) |
| step-2 Python package versions | **not recorded** |
| full chain reproduces `e84a8f84…` byte for byte | **unverified**: not re-run |
| thread count does not matter for steps 3–6 | **inferred** from a small-model probe |
