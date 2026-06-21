#!/bin/bash
# LightFTP v2.3 — 一键漏洞复现 (291 逻辑漏洞, 0 崩溃)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/lightftp_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "LightFTP v2.3 — 291 logical vulns: FTP Bounce + CRLF Injection + Path Traversal + State Violation"
echo "Note: 0 crash seeds. Memory safety rated GOOD."
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" lightftp "$OUT_DIR/seeds"
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" lightftp "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
