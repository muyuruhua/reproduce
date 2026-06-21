#!/bin/bash
# Pure-FTPd 1.0.51 — 一键漏洞复现 (1,164 逻辑漏洞, 0 崩溃)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/pureftpd_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "Pure-FTPd 1.0.51 — 1,164 logical vulns: CRLF Injection + FTP Bounce + State Violation"
echo "Note: 0 crash seeds. ~246h fuzzing, memory safety rated GOOD."
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" pure-ftpd "$OUT_DIR/seeds"
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" pure-ftpd "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
