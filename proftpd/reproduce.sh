#!/bin/bash
# ProFTPD 1.3.9rc1 — 一键漏洞复现 (62 Heap UAF + 1,142 逻辑漏洞)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/proftpd_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "ProFTPD 1.3.9rc1 — Heap UAF (CWE-416) + CRLF Injection (CWE-93, first discovery)"
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" proftpd "$OUT_DIR/seeds"
for seed in "$OUT_DIR/seeds/crashes"/*; do
    [ -f "$seed" ] || continue
    echo "Replaying: $(basename "$seed")"
    bash "$ROOT/scripts/replay_crash.sh" proftpd "$seed" "$OUT_DIR/crash_$(basename "$seed")" 2>&1 | grep -E "CRASH|AddressSanitizer" | head -5
done
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" proftpd "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
