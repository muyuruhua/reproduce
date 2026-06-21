#!/bin/bash
# ==============================================================================
# BFTPD 6.1 — 一键漏洞复现 (500 Heap溢出 + 618 逻辑漏洞)
# ==============================================================================
# 前置条件: docker image inspect bftpd:latest
# 用法: bash reproduce/bftpd/reproduce.sh <results_dir> [output_dir]
# ==============================================================================
set -euo pipefail
RESULTS_DIR="${1:?Usage: $0 <results_dir_with_tarballs>}"
OUT_DIR="${2:-/tmp/bftpd_reproduce}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPRODUCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  BFTPD 6.1 — Vulnerability Reproduction                    ║"
echo "║  Heap Overflow (CWE-122): 500 seeds                        ║"
echo "║  Logical Vulns: 618 seeds (CRLF, Bounce, State, Auth, ...) ║"
echo "╚══════════════════════════════════════════════════════════════╝"

mkdir -p "$OUT_DIR"

# Step 1: Extract seeds
echo ""
echo "━━━ Step 1: Extracting seeds ━━━"
bash "$REPRODUCE_ROOT/scripts/extract_seeds.sh" "$RESULTS_DIR" bftpd "$OUT_DIR/seeds"

# Step 2: Replay crashes
echo ""
echo "━━━ Step 2: Replaying crash seeds ━━━"
CRASH_DIR="$OUT_DIR/seeds/crashes"
CRASH_FOUND=0
TOTAL_CRASH=0
if [ -d "$CRASH_DIR" ] && [ "$(ls -A "$CRASH_DIR" 2>/dev/null)" ]; then
    for seed in "$CRASH_DIR"/*; do
        [ -f "$seed" ] || continue
        TOTAL_CRASH=$((TOTAL_CRASH + 1))
        echo "  [$TOTAL_CRASH] $(basename "$seed")"
        bash "$REPRODUCE_ROOT/scripts/replay_crash.sh" bftpd "$seed" "$OUT_DIR/crash_$TOTAL_CRASH" 2>&1 | tail -5
        if grep -q "CRASH DETECTED" "$OUT_DIR/crash_$TOTAL_CRASH/replay.log" 2>/dev/null; then
            CRASH_FOUND=$((CRASH_FOUND + 1))
        fi
        [ $TOTAL_CRASH -ge 5 ] && break  # Sample first 5
    done
fi

# Step 3: Replay violations
echo ""
echo "━━━ Step 3: Replaying violation seeds ━━━"
VIOL_DIR="$OUT_DIR/seeds/violations"
if [ -d "$VIOL_DIR" ] && [ "$(ls -A "$VIOL_DIR" 2>/dev/null)" ]; then
    bash "$REPRODUCE_ROOT/scripts/replay_logical_vuln.sh" bftpd "$VIOL_DIR" "$OUT_DIR/logical" 2>&1 | tail -20
fi

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  BFTPD Reproduction Summary                                 ║"
echo "║  Crashes tested:   $TOTAL_CRASH (sample), Confirmed: $CRASH_FOUND"
echo "║  Results:          $OUT_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
