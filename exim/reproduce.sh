#!/bin/bash
# Exim 4.96-221 — 一键漏洞复现 (1,050 逻辑漏洞: SMTP走私+开放中继+状态违规)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/exim_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "Exim 4.96-221 — SMTP Smuggling (CVE-2023-51766 complementary) + Open Relay + State Violation"
echo "Note: 0 crash seeds. All vulnerabilities are logical/protocol-level."
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" exim "$OUT_DIR/seeds"
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" exim "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
