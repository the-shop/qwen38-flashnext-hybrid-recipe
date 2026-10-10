#!/usr/bin/env bash
# serve-flashnext-hybrid.sh — test server (default :8095) for the hybrid Qwen3.8-Flash-Next-Heretic.
# Same engine/flags discipline as the baseline serving script (not shipped; PR#27739 build), differences:
#   - MODEL defaults to the hybrid GGUF (F16 dense + Q4 experts + selectable PLE type)
#   - LLAMA_MMAP_PREFETCH=0 is exported: disables the eager whole-file pull-in (local
#     patch, src/llama-mmap.cpp) so the PLE/tiered pages fault in on demand instead of
#     thrashing the unified pool at load. CRITICAL for the F16-PLE variant and the
#     pure-F16 reference runs.
#   - -ot ple_ngram_embd=CPU keeps the PLE table host-side (mmap/SSD-tiered), as the baseline config does.
#   - --parallel 1 by default (measurement server; another client's request shares the
#     decode batch and moves logits — tune discipline).
#   - MTP opt-in via MTP=<draft.gguf> (Q8_0 sidecar; n_max pinned to 1).
set -euo pipefail
export LLAMA_MMAP_PREFETCH=0

# MODELS_DIR is only needed when MODEL is unset; otherwise the default MMPROJ sits next to MODEL.
if [ -n "${MODEL:-}" ]; then DIR="$(dirname "$MODEL")"
else DIR="${MODELS_DIR:?set MODELS_DIR or MODEL}/qwen3.8-flash-next-heretic-f16"; fi
MODEL="${MODEL:-$DIR/Qwen3.8-Flash-Next-Heretic-Hybrid-f16.gguf}"
MMPROJ="${MMPROJ:-$DIR/mmproj-Qwen3.8-Flash-Next-Heretic-F16.gguf}"
[ "$MMPROJ" = "off" ] && MMPROJ=""   # vision not needed for text gates; costs ~0.9GB wired when on
MTP="${MTP:-}"
ALIAS="${ALIAS:-qwen3.8-flash-next-hybrid}"
PORT="${PORT:-8095}"
CTX="${CTX:-262144}"
KVTYPE="${KVTYPE:-f16}"
THINK="${THINK:-true}"
SLOTS="${SLOTS:-1}"
CPU_MOE="${CPU_MOE:-0}"
NO_WARMUP="${NO_WARMUP:-0}"
LOAD_MODE="${LOAD_MODE:-}"
DRAFT_OT="${DRAFT_OT:-}"
OT="${OT:-ple_ngram_embd=CPU,per_layer_token_embd=CPU}"
CACHE_RAM="${CACHE_RAM:-4096}"
BIN="${BIN:-${LLAMA_FORK:?set LLAMA_FORK or BIN}/build/bin/llama-server}"

[ -x "$BIN" ] || { echo "serve-flashnext-hybrid: missing $BIN" >&2; exit 66; }
[ -f "$MODEL" ] || { echo "serve-flashnext-hybrid: missing $MODEL" >&2; exit 66; }

EXTRA=()
# QSA (sparse attention) needs per-sequence streams: --kv-unified with >1 slots silently
# falls back to DENSE attention (fork warning; output may differ). KV_UNIFIED=0 drops the flag.
[ "${KV_UNIFIED:-1}" = "1" ] && EXTRA+=(--kv-unified)
[ -n "$MMPROJ" ] && EXTRA+=(--mmproj "$MMPROJ" --image-min-tokens 1024)
# CPU_MOE=1: keep routed experts host-side via per-tensor placement (--cpu-moe is broken for
# qwen4exp in this tree: nil Metal buffers). Wired footprint drops ~96GB -> fits default cap.
[ "$CPU_MOE" = "1" ] && EXTRA+=(-ot "ffn_gate_exps=CPU" -ot "ffn_up_exps=CPU" -ot "ffn_down_exps=CPU")
[ "$NO_WARMUP" = "1" ] && EXTRA+=(--no-warmup)
[ -n "$LOAD_MODE" ] && EXTRA+=(--load-mode "$LOAD_MODE")
if [ -n "$MTP" ]; then
  EXTRA+=(--spec-type draft-mtp -md "$MTP" --spec-draft-n-max 1)
  [ -n "$DRAFT_OT" ] && EXTRA+=(--spec-draft-override-tensor "$DRAFT_OT")
fi

CMD=("$BIN" \
  --model "$MODEL" \
  --alias "$ALIAS" \
  --host 127.0.0.1 --port "$PORT" \
  --ctx-size "$CTX" \
  --parallel "$SLOTS" \
  --n-gpu-layers 999 \
  --fit off \
  -ot "$OT" \
  --flash-attn on \
  --cache-type-k "$KVTYPE" \
  --cache-type-v "$KVTYPE" \
  --jinja \
  --chat-template-kwargs "{\"enable_thinking\":$THINK}" \
  --reasoning-format auto \
  --temp 1.0 --top-p 0.95 --top-k 20 \
  --cache-ram "$CACHE_RAM" \
  --predict "${PREDICT:-52428}" \
  --metrics)

if [ ${#EXTRA[@]} -gt 0 ]; then CMD+=("${EXTRA[@]}"); fi

if [ "${PRINT:-0}" = 1 ]; then printf '%s\n' "${CMD[@]}"; exit 0; fi
exec "${CMD[@]}"