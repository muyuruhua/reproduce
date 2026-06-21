#!/bin/bash
# forked-daapd 27.2 — 一键漏洞复现 (39 崩溃 + 160 逻辑漏洞)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/daapd_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "forked-daapd 27.2 — HTTP Smuggling + CRLF Injection + DoS"
echo "Note: Crashes require AFL persistent-mode. Docker standalone may not reproduce."
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" forked-daapd "$OUT_DIR/seeds"
for seed in "$OUT_DIR/seeds/crashes"/*; do
    [ -f "$seed" ] || continue
    bash "$ROOT/scripts/replay_crash.sh" forked-daapd "$seed" "$OUT_DIR/crash_$(basename "$seed")" 2>&1 | grep -E "CRASH|Signal|survived" | head -5
done
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" forked-daapd "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
