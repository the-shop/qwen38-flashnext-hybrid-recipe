#!/usr/bin/env bash
# cache-janitor.sh — keep macOS out of swap while a big streaming job (CPU logits pass,
# quantize) streams a model file through the page cache.
#
# Why: llama.cpp mmap streaming accumulates file-backed pages until RAM is exhausted and the
# kernel starts compressing/paging other tenants into swap. That is (a) hostile to other
# workloads on the machine, and (b) corrupts any timing measurement taken on the same machine.
# The janitor periodically drops clean file-backed pages (sudo purge) when swap pressure
# appears, so the streaming job keeps re-reading from SSD (cheap: 7GB/s) instead of pushing
# the box into swap. Reference/exactness passes tolerate the re-reads; measurement passes
# must run on Metal (wired) and never need this.
#
# usage: cache-janitor.sh [SWAP_THRESHOLD_MB=4096] [INTERVAL_S=20] [LOGFILE]
set -uo pipefail
THRESH="${1:-4096}"; INTERVAL="${2:-20}"; LOG="${3:-/tmp/cache-janitor.log}"
pass() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }
pass "janitor start (threshold ${THRESH}MB, interval ${INTERVAL}s)"
while true; do
  USED=$(sysctl -n vm.swapusage | awk -F'used = ' '{print $2}' | awk '{print $1}' | sed 's/M//')
  FREE_PCT=$(memory_pressure -Q 2>/dev/null | sed -n 's/.*percentage: \([0-9]*\)%.*/\1/p')
  if [ -n "$USED" ] && [ "$USED" -gt "$THRESH" ] 2>/dev/null; then
    pass "swap ${USED}MB > ${THRESH}MB -> purge"
    sudo -n purge 2>/dev/null || pass "purge skipped (passwordless sudo unavailable; no cache drop this cycle)"
    sleep 2
    USED2=$(sysctl -n vm.swapusage | awk -F'used = ' '{print $2}' | awk '{print $1}' | sed 's/M//')
    pass "swap after purge: ${USED2}MB"
  fi
  sleep "$INTERVAL"
done
