#!/bin/bash
# Mosquitto v2.0.18 — 一键漏洞复现 (749 逻辑漏洞, 0 崩溃)
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir>}"; OUT_DIR="${2:-/tmp/mosquitto_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
echo "Mosquitto v2.0.18 — 749 logical vulns: ACL Bypass + Session Hijack + Will $SYS (NEW)"
echo "Note: 0 crash seeds. 2 NEW vulnerability patterns (No known CVE)."
bash "$ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" mosquitto-v2.0.18 "$OUT_DIR/seeds"
[ -d "$OUT_DIR/seeds/violations" ] && bash "$ROOT/scripts/replay_logical_vuln.sh" mosquitto-v2.0.18 "$OUT_DIR/seeds/violations" "$OUT_DIR/logical" 2>&1 | grep -E "CONFIRMED|Confirmed" | head -20
echo "Done. Results: $OUT_DIR"
