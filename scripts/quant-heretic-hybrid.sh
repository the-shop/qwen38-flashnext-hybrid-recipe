#!/usr/bin/env bash
# quant-heretic-hybrid.sh — build the max-quality hybrid GGUF for Qwen3.8-Flash-Next-Heretic.
#
# Multi-pass --include-weights quantize; everything NOT
# included is copied F16. (--tensor-type-file does NOT control output types in this fork —
# verified the hard way: it only reinterprets input storage.)
#
#   pass 1: ffn_gate_exps, ffn_up_exps           -> q4_K  (ne[0]=2560, block-256 OK)
#   pass 2: ffn_down_exps                        -> q4_0  (ne[0]=640: 640 % 256 != 0)
#   pass 3: ple_key, ple_value, ple_conv1d,
#           ple_norm_key/query/conv              -> q8_0  (dequant->f32 path; removes the
#                                                        per-decode 525MB F32 cast cost,)
#   PLE table (per_layer_token_embd) stays F16 — the tiered max-bf16 component.
#   Everything else (dense, attention, DeltaNet, hc, emb, lm_head, shared experts) stays F16.
#
# usage: quant-heretic-hybrid.sh [THREADS=12]
set -euo pipefail
# CRITICAL: without this the quantize tool eagerly mmap-pulls the whole 354GB input into the
# unified pool (measured: 71.8GiB RSS + swap pressure, 2026-10-03). Pages then stream per-tensor.
export LLAMA_MMAP_PREFETCH=0
THREADS="${1:-12}"
DIR="${MODELS_DIR:?set MODELS_DIR}/qwen3.8-flash-next-heretic-f16"
IN="$DIR/Qwen3.8-Flash-Next-Heretic-F16.gguf"
T1="$DIR/.t1-q4k.gguf"; T2="$DIR/.t2-down.gguf"
OUT="$DIR/Qwen3.8-Flash-Next-Heretic-Hybrid-f16.gguf"
QUANT="${QUANT:-${LLAMA_FORK:?set LLAMA_FORK}/build/bin/llama-quantize}"   # patched #27739 fork
GGUFPY="${GGUFPY:-python3}"                                               # needs numpy for gguf-py
export GGUF_PY_DIR="${LLAMA_TOOLS:?set LLAMA_TOOLS}/gguf-py"

[ -f "$IN" ] || { echo "missing $IN (run the f16 conversion first)"; exit 66; }
[ -x "$QUANT" ] || { echo "missing $QUANT"; exit 66; }

echo "== pass 1: gate/up exps -> q4_K =="
"$QUANT" --include-weights "ffn_gate_exps,ffn_up_exps" \
  --token-embedding-type f16 --output-tensor-type f16 \
  "$IN" "$T1" q4_K "$THREADS"

echo "== pass 2: down exps -> q4_0 =="
"$QUANT" --include-weights "ffn_down_exps" \
  --token-embedding-type f16 --output-tensor-type f16 \
  "$T1" "$T2" q4_0 "$THREADS"
rm -f "$T1"

echo "== pass 3: ple projections -> q8_0 =="
"$QUANT" --include-weights "ple_key,ple_value,ple_conv1d,ple_norm_key,ple_norm_query,ple_norm_conv" \
  --token-embedding-type f16 --output-tensor-type f16 \
  "$T2" "$OUT" q8_0 "$THREADS"
rm -f "$T2"

# census: types present in the output; no TQ1_0/TQ2_0 allowed (no Metal kernels)
"$GGUFPY" - "$OUT" <<'EOF'
import sys, collections
import os
sys.path.insert(0, os.environ['GGUF_PY_DIR'])
from gguf import GGUFReader
r = GGUFReader(sys.argv[1])
c = collections.Counter(t.tensor_type.name for t in r.tensors)
print('census:', dict(c))
bad = [k for k in c if k.startswith('TQ')]
sys.exit(1 if bad else 0)
EOF
echo "OK: $OUT"