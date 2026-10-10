#!/usr/bin/env bash
# Reproducible runtime benchmark for Morax Garage (main app binary from .build/release).
# Usage: scripts/bench/bench_runtime.sh <out_dir> [launches=5] [sample_seconds=60]
# Measures: time-to-first-window (cold/warm proxy), CPU avg/peak, RSS avg/peak, threads,
# idle wakeups, child processes, physical footprint. Does not touch /Applications.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:?out dir}"; LAUNCHES="${2:-5}"; SECS="${3:-60}"
BIN="${MORAX_BENCH_BIN:-$ROOT/.build/release/MoraxCockpit}"
mkdir -p "$OUT"
WAITER="$OUT/wait_window"
[ -x "$WAITER" ] || swiftc -O "$ROOT/scripts/bench/wait_window.swift" -o "$WAITER"

# MORAX_BENCH_ARGS: extra launch args, e.g. "-dashboard_show_usage_quotas NO" to skip Keychain-backed feeds.
launch() { "$BIN" ${MORAX_BENCH_ARGS:-} >/dev/null 2>&1 & echo $!; }

echo "launch_ms" > "$OUT/launch.csv"
for i in $(seq "$LAUNCHES"); do
  pid=$(launch); ms=$("$WAITER" "$pid" 30 || true); echo "$ms" >> "$OUT/launch.csv"
  sleep 2; kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; sleep 1
done

pid=$(launch); "$WAITER" "$pid" 30 >/dev/null || true; sleep 5
# top gives instantaneous per-interval CPU (ps %cpu is a decaying average); first sample is discarded.
top -l "$((SECS + 1))" -s 1 -pid "$pid" -stats pid,cpu,idlew,mem,threads > "$OUT/top.txt" 2>&1 || true
echo "cpu,idlew,mem" > "$OUT/sample.csv"
grep -E "^$pid " "$OUT/top.txt" | tail -n +2 | awk '{print $2","$3","$4}' >> "$OUT/sample.csv"
footprint "$pid" 2>/dev/null | head -6 > "$OUT/footprint.txt" || true
ps -M -p "$pid" | tail -n +2 | wc -l | tr -d ' ' > "$OUT/threads.txt"
pgrep -P "$pid" -l > "$OUT/children.txt" || true
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true

{
  awk -F, 'NR>1&&$1!="timeout"{a[n++]=$1} END{asort_ok=0; s=0; for(i=0;i<n;i++)s+=a[i]; printf "launch_ms first=%s mean=%.0f n=%d\n", a[0], s/n, n}' "$OUT/launch.csv"
  awk -F, 'NR>1{c+=$1; if($1>m)m=$1; w+=$2; n++} END{printf "cpu_avg=%.2f cpu_peak=%.1f idle_wakeups_per_s=%.1f n=%d\n",c/n,m,w/n,n}' "$OUT/sample.csv"
  awk -F, 'NR>1{v=$3; gsub(/[+-]/,"",v); u=substr(v,length(v)); x=v+0; if(u=="K")x/=1024; if(u=="G")x*=1024; s+=x; if(x>m)m=x; n++} END{printf "mem_avg_mb=%.1f mem_peak_mb=%.1f\n",s/n,m}' "$OUT/sample.csv"
  echo "threads=$(cat "$OUT/threads.txt") children=$(wc -l < "$OUT/children.txt" | tr -d ' ')"
  grep Footprint "$OUT/footprint.txt" || true
} | tee "$OUT/summary.txt"
