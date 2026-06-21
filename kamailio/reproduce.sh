#!/bin/bash
# Kamailio 5.8.0 — 一键漏洞复现 (68 Heap崩溃 + 275 逻辑漏洞)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/kamailio_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "Kamailio 5.8.0 — Heap Corruption (CWE-122) + SIP Injection + Auth Bypass"
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" kamailio "$OUT_DIR/seeds"
for seed in "$OUT_DIR/seeds/crashes"/*; do
    [ -f "$seed" ] || continue
    bash "$ROOT/scripts/replay_crash.sh" kamailio "$seed" "$OUT_DIR/crash_$(basename "$seed")" 2>&1 | grep -E "CRASH|Signal" | head -5
done
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" kamailio "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
