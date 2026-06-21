#!/bin/bash
# ==============================================================================
# 从 Excel 漏洞报告到复现 — 一步到位
# ==============================================================================
# 审核员在 vulnerability/*.xlsx 中看到一条漏洞后，只需提供 target 和 category，
# 本脚本自动从 ten_groups_data_ten/ 的 tarball 中找到匹配种子并复现。
#
# 用法:
#   bash scripts/reproduce_from_excel.sh <target> <type> <category>
#
#   type = crash | viol
#   category = Excel Category 列的值, e.g. 0x0020
#
# 示例:
#   bash scripts/reproduce_from_excel.sh bftpd crash  any     # 复现bftpd崩溃
#   bash scripts/reproduce_from_excel.sh bftpd viol  0x0020  # 复现CRLF注入(CWE-93)
#   bash scripts/reproduce_from_excel.sh exim   viol  0x04e0  # 复现SMTP走私
#   bash scripts/reproduce_from_excel.sh proftpd viol 0x0020  # 复现CRLF注入(ProFTPD首次发现)
# ==============================================================================
set -euo pipefail

TARGET="${1:?Usage: $0 <target> <crash|viol> [category_hex]}"
VTYPE="${2:?Usage: $0 <target> <crash|viol> [category_hex]}"
CAT_HEX="${3:-any}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPRO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPRO_ROOT/ten_groups_data_ten"
OUT_DIR="/tmp/excel_reproduce_${TARGET}_$(date +%H%M%S)"

# ── Find results directory ──
RESULTS_DIR=$(ls -d "$DATA_DIR"/results-${TARGET}_* 2>/dev/null | head -1)
if [ -z "$RESULTS_DIR" ]; then
    # try alternate naming
    RESULTS_DIR=$(ls -d "$DATA_DIR"/results-${TARGET}* 2>/dev/null | head -1)
fi
if [ -z "$RESULTS_DIR" ] || [ ! -d "$RESULTS_DIR" ]; then
    echo "[ERROR] 找不到 $TARGET 的 results 目录"
    echo "  已检查: $DATA_DIR/results-${TARGET}_*"
    echo "  可用目标:"
    ls "$DATA_DIR" 2>/dev/null | sed 's/results-//' | sed 's/_.*//' | sort -u | while read t; do echo "    - $t"; done
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Excel → 复现: $TARGET | type=$VTYPE | category=$CAT_HEX"
echo "║  数据源: $RESULTS_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Search all tarballs for matching seed ──
echo "━━━ Step 1: 在所有 tarball 中搜索匹配种子 ━━━"

# Normalize category: strip 0x prefix, pad to 4 hex digits
CAT_PATTERN=""
if [ "$VTYPE" = "crash" ]; then
    CAT_PATTERN="replayable-crashes/"
elif [ "$CAT_HEX" != "any" ]; then
    # Strip 0x prefix and pad
    CAT_NUM=$(echo "$CAT_HEX" | sed 's/^0x//i')
    CAT_PATTERN="replayable-violations/.*cat:${CAT_NUM}"
fi

FOUND=0
SELECTED_TAR=""
SELECTED_SEED=""

for TAR in "$RESULTS_DIR"/out-*-chatafl_opt_*.tar.gz; do
    [ -f "$TAR" ] || continue
    TAR_NAME=$(basename "$TAR")

    if [ "$VTYPE" = "crash" ]; then
        MATCH=$(tar tzf "$TAR" 2>/dev/null | grep "replayable-crashes/" | grep -v "README\|/$" | head -1)
    else
        MATCH=$(tar tzf "$TAR" 2>/dev/null | grep "replayable-violations/" | grep -v "README\|/$" | grep -i "cat.${CAT_NUM}$" | head -1 || true)
        if [ -z "$MATCH" ]; then
            MATCH=$(tar tzf "$TAR" 2>/dev/null | grep "replayable-violations/" | grep -v "README\|/$" | grep -i "cat:${CAT_NUM}" | head -1 || true)
        fi
    fi

    if [ -n "$MATCH" ]; then
        FOUND=$((FOUND+1))
        if [ $FOUND -eq 1 ]; then
            SELECTED_TAR="$TAR"
            SELECTED_SEED="$MATCH"
        fi
        echo "  [$FOUND] $TAR_NAME → $MATCH"
    fi
done

if [ $FOUND -eq 0 ]; then
    echo ""
    echo "[ERROR] 未找到匹配种子。"
    echo "  Target: $TARGET"
    echo "  Type:   $VTYPE"
    echo "  Category: $CAT_HEX"
    echo ""
    echo "  可用种子一览:"
    for TAR in "$RESULTS_DIR"/out-*-chatafl_opt_1.tar.gz; do
        [ -f "$TAR" ] || continue
        echo "  --- $(basename "$TAR") ---"
        tar tzf "$TAR" 2>/dev/null | grep "replayable-crashes/" | grep -v "README\|/$" | head -5
        tar tzf "$TAR" 2>/dev/null | grep "replayable-violations/" | grep -v "README\|/$" | head -5
        break
    done
    exit 1
fi

echo ""
echo "  找到 $FOUND 个匹配种子，选用第一个。"
echo "  Tarball: $(basename "$SELECTED_TAR")"
echo "  种子路径: $SELECTED_SEED"

# ── Step 2: Extract seed ──
echo ""
echo "━━━ Step 2: 提取种子 ━━━"

rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
tar xzf "$SELECTED_TAR" -C "$OUT_DIR" "$SELECTED_SEED" 2>/dev/null
EXTRACTED="$OUT_DIR/$SELECTED_SEED"

if [ ! -f "$EXTRACTED" ]; then
    echo "[ERROR] 提取失败: $SELECTED_SEED"
    exit 1
fi
echo "  ✓ 已提取: $EXTRACTED ($(wc -c < "$EXTRACTED") bytes)"

# ── Step 3: Replay ──
echo ""
echo "━━━ Step 3: Docker 重放复现 ━━━"
echo ""

if [ "$VTYPE" = "crash" ]; then
    bash "$SCRIPT_DIR/replay_crash.sh" "$TARGET" "$EXTRACTED" "$OUT_DIR/replay_output"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    grep -E "CRASH DETECTED|CRASH CONFIRMED|RESULT:|Not reproduced" "$OUT_DIR/replay_output/replay.log" 2>/dev/null || echo "  详见: $OUT_DIR/replay_output/replay.log"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    bash "$SCRIPT_DIR/replay_logical_vuln.sh" "$TARGET" "$EXTRACTED" "$OUT_DIR/replay_output"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    find "$OUT_DIR/replay_output" -name "verdict.txt" -exec grep -H "Confirmed\|violation(s) confirmed" {} \; 2>/dev/null | head -20
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "详细日志: $OUT_DIR"
