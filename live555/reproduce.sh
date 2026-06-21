#!/bin/bash
# LIVE555 RTSP — 一键漏洞复现 (72 UAF + 298 逻辑漏洞)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/live555_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "LIVE555 RTSP — Heap UAF (CWE-416) + Duplicate SETUP + State Violation"
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" live555 "$OUT_DIR/seeds"
for seed in "$OUT_DIR/seeds/crashes"/*; do
    [ -f "$seed" ] || continue
    bash "$ROOT/scripts/replay_crash.sh" live555 "$seed" "$OUT_DIR/crash_$(basename "$seed")" 2>&1 | grep -E "CRASH|Signal|survived" | head -5
done
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" live555 "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
