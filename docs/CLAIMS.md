# Claims audit — what survived, what was retracted

The measurement campaign's report (not shipped) is a chronological record and carries its own
SUPERSEDED-VALUE NOTICE. This is the filtered view. **Publish only from column A.**

## A. Surviving — q4lean5, the winner

| number | mandatory caveat |
|---|---|
| 101,488,511,616 B unsplit (3 shards total 101,488,511,936 B) | byte-verified |
| 4.59 BPW | census: Q6_K 423 · F32 388 · F16 169 · Q8_0 99 · Q4_0 145 |
| wired 79.48 GiB @ ctx 262144 | only with KV q4_0, MMPROJ=off, host-pinned PLE+embeddings, `iogpu.wired_limit_mb=122880` |
| wired 75.90 GiB @ ctx 4096, SLOTS=4 | same config |
| decode 49.96 t/s, single stream | with MTP Q8_0 draft, acceptance 0.905; measured on the #27739 fork build with the fork-converted sidecar — not re-measured on stock llama.cpp |
| batch-4 aggregate 86.38 t/s | with MTP, QSA on, acceptance 0.921; same fork-build caveat |
| c8 ≈69.0 t/s | **degrades vs batch-4** — report it, do not bury it |
| verify-model 4/4 | every canonical capture |

### Exactness — like-for-like KV, 1153 positions, vs `Q8_0-REF-pure`

| KV pair | top-1 |
|---|---|
| F16 / F16 | 95.06% |
| q8_0 / q8_0 | 94.54% |
| **q4_0 / q4_0 (served config)** | **94.62%** |

Top-1 only: the stored bins keep the argmax plus token ids 0-255 (a top-k heap bug in logits-dump.cpp, fixed in this release), so KL, top-5 and p99 from these bins are invalid and withdrawn.

### Byte-identity results (mechanism, reusable)

- draft Q8_0 == Q4_K_M (sha `87bf8b780d3e7a85`) → draft quant is output-neutral
- `LOAD_MODE=none` == mmap on the winner (sha `2d59e26b0dab9a71`)
- PLE warm vs post-purge cold → identical

## B. Retracted — do NOT publish

| claim | why it fell |
|---|---|
| q4ple 39.4 t/s single / 82.0 batch-4 / 148.1 prefill; UD-Q4_K_XL baseline 35.9 / 140.9 / 71.2 | measured under `kv_unified=true` = **dense-attention fallback, not QSA**. Not like-for-like. |
| "+10% decode / +15% batch-4 vs baseline" | derives from those rows. **No like-for-like QSA comparison against the UD-Q4_K_XL baseline exists anywhere in the record.** |
| q8 RSS 31.6–33.8 GiB, wired 5 GiB | captures contradict → RSS 9.8/9.9, wired 8 GiB |
| "MTP 9.45 t/s, 4.6x" | the 2.07→9.45 jump was page-cache warmth; MTP is neutral-to-slightly-negative on the Q8_0 sibling's serving config |
| n_max sweep "39.6 / 39.4 flat, pin n_max=1" | logs identical apart from timings; the parameter may never have applied. **No conclusion.** |
| `--no-repack` "proved" the swap storm | warm-cache + wrong-process confound (the 123.4 GiB CPU_REPACK came from logits-dump) |
| q4lean2/4 hostemb wired rows incl. 80.22/79.00 GiB | captures deleted — NOT REPRODUCIBLE |
| "200 t/s not reachable at any quant" | extrapolation, not measurement |
| every mean-KL, top-5 and p99-KL figure from the exactness ladder (e.g. 0.2678 / 0.2863 / 0.2990 mean KL; 0.2637 vs 0.0842 anchor comparison) | `logits-dump.cpp` used a max-heap where a min-heap was needed, so each stored "top-256" is token ids 0-255 plus the argmax. Only top-1 survives. Fixed in `scripts/logits-dump.cpp`; the bins were not re-dumped. |

## C. True but hazardous without their caveat

1. **Every exactness number is vs a q8_0 reference, not BF16** — and the F16 source is itself a
   lossy re-encode of a natively-bf16 checkpoint. Two removes from BF16.
2. **Do not quote our 94.62% against the published 89.5% anchor.** Different corpus, different
   metric implementation, different reference. The campaign report says so explicitly.
3. **94.62% is a collision** across two different measurements (superseded q4ple baseline (F16-KV) row, and
   the surviving q4lean5 q4_0/q4_0 row). Always name the KV type on both sides.
4. **The 60–80 GiB wired band is config-bound, not a property of the file.**
5. **q8's 98.01% top-1 is not a quantization-fidelity number** — same weights; the drift is
   repack vs no-repack kernel ordering. Printing it beside q4lean5 invites misreading.
6. **MTP-on output is not byte-identical to greedy** (`573c15e0ecbb745a` vs `87bf8b780d3e7a85`).
   All exactness figures are draft-free. Quoting MTP throughput beside exactness implies they
   were measured together. They were not.
7. **The UD-Q4_K_XL baseline is a quant of the BASE model, ours is of the HERETIC weights.** Same
   architecture and parameter count, so size and throughput remain comparable — but it is not
   the same model, and our copy of UD-Q4_K_XL was locally re-split 4→5 shards rather than
   pristine Unsloth. Say so in any public comparison.
8. **Do not confuse UD-Q4_K_XL with UD-IQ4_XS.** Both are on disk: UD-Q4_K_XL (5 shards, base
   model dir, Unsloth, the baseline) and UD-IQ4_XS (42 shards, heretic dir, groxaxo, never used
   as a baseline).
9. The campaign's 93.12% auto-accept floor is **self-referential** (q4ple baseline − 1.5) — an
   internal gate, meaningless to a reader. Do not print the threshold.
