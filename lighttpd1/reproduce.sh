#!/bin/bash
# lighttpd 1.4.72-devel — 一键漏洞复现 (125 逻辑漏洞, 0 崩溃)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/lighttpd1_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "lighttpd 1.4.72-devel — 125 logical vulns: HTTP Smuggling + Path Traversal + CRLF Injection"
echo "Note: 0 crash seeds. ~53M executions, excellent memory safety."
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" lighttpd1 "$OUT_DIR/seeds"
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" lighttpd1 "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
