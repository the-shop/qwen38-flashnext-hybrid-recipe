#!/usr/bin/env bash
# bench-hybrid-ladder.sh — one-stop measurement for a hybrid candidate test server.
#   usage: bench-hybrid-ladder.sh PORT LABEL [N_PREDICT]
# Runs: bench-model (decode+prefill), batch-4 throughput, verify-model 4-check bar,
# probe-sha byte-stability suite. Appends all results to logs/hybrid-campaign/results.tsv.
# bench-model and verify-model are NOT shipped: set BENCH_MODEL / VERIFY_MODEL to your own
# harness (called as: CMD PORT LABEL [N_PREDICT]); unset means that step is skipped.
# The logits exactness ladder is separate (scripts/logits-dump.cpp + scripts/compare-logits.py) because
# the reference pass loads a different GGUF directly. Published results from it are top-1 only
# (bins dumped before the logits-dump.cpp top-k heap fix support no KL/top-5).
set -uo pipefail
PORT="${1:?usage: bench-hybrid-ladder.sh PORT LABEL}"; LABEL="${2:-hybrid}"; NP="${3:-256}"
RES=logs/hybrid-campaign/results.tsv
mkdir -p logs/hybrid-campaign
touch "$RES"

echo "== $LABEL @ :$PORT =="
if [ -n "${BENCH_MODEL:-}" ]; then
  B=$("$BENCH_MODEL" "$PORT" "$LABEL" "$NP" 2>&1 | tail -1); echo "  $B"
  echo "$(date -u +%FT%TZ)	$LABEL	single	$B" >> "$RES"
else
  echo "  single: skipped (BENCH_MODEL unset)"
fi

# batch-4: four concurrent completions, sum throughput (decode amortizes shared reads)
BT=$(python3 - "$PORT" "$NP" <<'EOF'
import json, sys, urllib.request, threading, time
port, np = sys.argv[1], int(sys.argv[2])
prompt = "Write a complete Python implementation of an LRU cache class with get and put methods backed by a doubly linked list and a dict. Include docstrings and a short usage example."
results = []
def one():
    body = json.dumps({"prompt": prompt, "n_predict": np, "temperature": 0, "cache_prompt": False})
    req = urllib.request.Request(f"http://127.0.0.1:{port}/completion", data=body.encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.loads(r.read()); results.append(d.get("timings", {}))
t0 = time.time()
ts = [threading.Thread(target=one) for _ in range(4)]
[t.start() for t in ts]; [t.join() for t in ts]
wall = time.time() - t0
tot_tok = sum(t.get("predicted_n", 0) for t in results)
tot_s = sum(t.get("predicted_per_second", 0) or 0 for t in results)
print(f"batch4 wall={wall:.1f}s tokens={tot_tok} sum_tps={tot_s:.1f} agg_tps={tot_tok/wall:.1f}")
EOF
)
echo "  batch-4: $BT"
echo "$(date -u +%FT%TZ)	$LABEL	batch4	$BT" >> "$RES"

if [ -n "${VERIFY_MODEL:-}" ]; then
  V=$("$VERIFY_MODEL" "$PORT" "$LABEL" 2>&1 | tail -4 | tr '\n' ' | ')
  echo "  verify: $V"
  echo "$(date -u +%FT%TZ)	$LABEL	verify	$V" >> "$RES"
else
  echo "  verify: skipped (VERIFY_MODEL unset)"
fi

S=$(python3 scripts/probe-sha.py "$PORT" 2>&1 | tail -3 | tr '\n' ' | ')
echo "  probes: $S"
echo "$(date -u +%FT%TZ)	$LABEL	probes	$S" >> "$RES"
echo "== $LABEL done =="