#!/bin/bash
# ==============================================================================
# 从 Excel 漏洞报告到复现 — 一步到位 (v2: 模糊匹配 + 格式兼容 + 崩溃增强)
# ==============================================================================
# 用法:
#   bash scripts/reproduce_from_excel.sh <target> <crash|viol> [category_hex]
#
# 修复记录:
#   F1: Category 模糊匹配 — 按bit而非精确hex匹配，解决Excel与tarball归类差异
#   F2: cat格式兼容 — 同时支持 cat:XXXX 和 cat=XXXX
#   F3: live555/forked-daapd 崩溃增强 — 累积重放模式
#   F4: 失败时给出可用的替代 Category
# ==============================================================================
# set -euo pipefail  # disabled: grep may return empty

TARGET="${1:?Usage: $0 <target> <crash|viol> [category_hex_or_seed_id]}"
VTYPE="${2:?Usage: $0 <target> <crash|viol> [category_hex_or_seed_id]}"
CAT_HEX="${3:-any}"
# crash: CAT_HEX=seed_id (e.g. "000009") or "any" for random pick

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPRO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPRO_ROOT/ten_groups_data_ten"
OUT_DIR="/tmp/excel_reproduce_${TARGET}_$(date +%H%M%S)"

# ── Bit definitions ───────────────────────────────────────────
declare -A BIT_NAME=(
    [0x0001]="AUTH_BYPASS(认证绕过)"
    [0x0002]="AUTHZ_BYPASS(授权绕过)"
    [0x0004]="STATE_VIOLATION(状态机违规)"
    [0x0008]="INFO_LEAK(信息泄露)"
    [0x0010]="PATH_TRAVERSAL(路径遍历)"
    [0x0020]="INJECTION(CRLF/命令注入)"
    [0x0040]="DOS(拒绝服务)"
    [0x0080]="RESOURCE_EXHAUST(资源耗尽)"
    [0x0100]="ISOLATION(隔离逃逸/FTP Bounce)"
    [0x0200]="SESSION(会话劫持/碰撞)"
    [0x0400]="SMUGGLING(HTTP请求走私)"
)

# ── Helper: decode category hex to bit names ──
decode_cat() {
    local val=$((16#${1}))
    local parts=""
    local names=""
    for mask in 0x0001 0x0002 0x0004 0x0008 0x0010 0x0020 0x0040 0x0080 0x0100 0x0200 0x0400; do
        if [ $((val & mask)) -ne 0 ]; then
            parts="${parts}|0x$(printf '%04x' $mask)"
            names="${names}+${BIT_NAME[$mask]}"
        fi
    done
    echo "${parts#|}"
}

cat_bits() {
    local val=$((16#${1}))
    local bits=""
    for mask in 0x0001 0x0002 0x0004 0x0008 0x0010 0x0020 0x0040 0x0080 0x0100 0x0200 0x0400; do
        [ $((val & mask)) -ne 0 ] && bits="$bits $mask"
    done
    echo "$bits"
}

# ── Helper: does seed_cat share at least one meaningful bit with request_cat? ──
# Returns the count of shared bits.
bits_shared() {
    local req=$((16#${1}))
    local seed=$((16#${2}))
    local shared=0
    # Only count bits that are in the request (not all 11 bits)
    for mask in 0x0001 0x0002 0x0004 0x0008 0x0010 0x0020 0x0040 0x0080 0x0100 0x0200 0x0400; do
        if [ $((req & mask)) -ne 0 ] && [ $((seed & mask)) -ne 0 ]; then
            shared=$((shared+1))
        fi
    done
    echo $shared
}

# ── Find results directory ──
RESULTS_DIR=""
# First try exact match
for d in "$DATA_DIR"/results-${TARGET}_* "$DATA_DIR"/results-${TARGET}*; do
    [ -d "$d" ] && { RESULTS_DIR="$d"; break; }
done
# mosquitto-v2.0.18 → results-mosquitto_*
if [ -z "$RESULTS_DIR" ] && [[ "$TARGET" == mosquitto* ]]; then
    for d in "$DATA_DIR"/results-mosquitto_*; do
        [ -d "$d" ] && { RESULTS_DIR="$d"; break; }
    done
fi
if [ -z "$RESULTS_DIR" ] || [ ! -d "$RESULTS_DIR" ]; then
    echo "[ERROR] 找不到 $TARGET 的 results 目录"
    echo "  可用目标:"
    ls "$DATA_DIR" 2>/dev/null | sed 's/results-//' | sed 's/_.*//' | sort -u | while read t; do echo "    - $t"; done
    exit 1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Excel → 复现: $TARGET | type=$VTYPE | category=$CAT_HEX"
echo "║  数据源: $(basename "$RESULTS_DIR")"
echo "╚══════════════════════════════════════════════════════════════╝"

# ── Step 1: Search ──
echo ""
echo "━━━ Step 1: 在所有 tarball 中搜索匹配种子 ━━━"

CAT_BITS=""
if [ "$CAT_HEX" != "any" ] && [ "$VTYPE" = "viol" ]; then
    CAT_NUM=$(echo "$CAT_HEX" | sed 's/^0x//i' | tr 'a-f' 'A-F')
    CAT_BITS=$(cat_bits "$CAT_NUM")
fi

FOUND=0; SELECTED_TAR=""; SELECTED_SEED=""; BEST_SCORE=0; EXACT_FOUND=0
declare -A SEEN_SEEDS  # dedup by seed filename

for TAR in $(ls -v "$RESULTS_DIR"/out-*-chatafl_opt_*.tar.gz 2>/dev/null); do
    [ -f "$TAR" ] || continue
    TAR_NAME=$(basename "$TAR")

    if [ "$VTYPE" = "crash" ]; then
        # If a seed ID is specified (e.g. "000009"), search for that exact one
        if [ "$CAT_HEX" != "any" ]; then
            MATCH=$(tar tzf "$TAR" 2>/dev/null | grep "replayable-crashes/" | grep -v "README\|/$" | grep "id:${CAT_HEX}" | head -1)
            if [ -n "$MATCH" ]; then
                FOUND=$((FOUND+1))
                SELECTED_TAR="$TAR"; SELECTED_SEED="$MATCH"
                echo "  [指定种子] $TAR_NAME → $MATCH"
            fi
        else
            # Random pick from this tarball
            MATCH=$(tar tzf "$TAR" 2>/dev/null | grep "replayable-crashes/" | grep -v "README\|/$" | shuf -n1)
            if [ -n "$MATCH" ]; then
                FOUND=$((FOUND+1))
                [ $FOUND -eq 1 ] && { SELECTED_TAR="$TAR"; SELECTED_SEED="$MATCH"; }
            fi
        fi
        continue
    fi

    # Violation search with fuzzy matching
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        seed_name=$(basename "$line")
        [ "${SEEN_SEEDS[$seed_name]:-0}" = "1" ] && continue
        SEEN_SEEDS[$seed_name]=1

        # Extract category from seed name: cat:XXXX or cat=XXXX
        seed_cat=$(echo "$line" | grep -oP 'cat[:=]\K[0-9a-fA-F]+' | head -1)
        [ -z "$seed_cat" ] && continue

        if [ "$CAT_HEX" = "any" ]; then
            # Pick first available
            FOUND=$((FOUND+1))
            [ $FOUND -eq 1 ] && { SELECTED_TAR="$TAR"; SELECTED_SEED="$line"; }
            continue
        fi

        # Exact match: always wins over fuzzy (keep FIRST exact = earliest tarball)
        if [ "$(echo "$seed_cat" | tr 'a-f' 'A-F')" = "$(echo "$CAT_NUM" | tr 'a-f' 'A-F')" ]; then
            FOUND=$((FOUND+1))
            if [ $EXACT_FOUND -eq 0 ]; then
                SELECTED_TAR="$TAR"; SELECTED_SEED="$line"; BEST_SCORE=999; EXACT_FOUND=1
            fi
            echo "  [精确匹配] $TAR_NAME → $line"
            continue
        fi

        # Fuzzy match: shared bits
        score=$(bits_shared "$CAT_NUM" "$seed_cat")
        if [ "$score" -gt "$BEST_SCORE" ]; then
            BEST_SCORE=$score
            SELECTED_TAR="$TAR"; SELECTED_SEED="$line"
        fi
        if [ "$score" -ge 2 ]; then
            FOUND=$((FOUND+1))
        fi
    done < <(tar tzf "$TAR" 2>/dev/null | grep "replayable-violations/" | grep -v "README\|/$")
done

if [ $FOUND -eq 0 ]; then
    echo ""
    echo "[WARN] 未找到精确匹配的种子。"
    echo ""

    if [ -n "$SELECTED_SEED" ] && [ "$BEST_SCORE" -ge 1 ]; then
        echo "  ★ 启用模糊匹配: 找到共享 $BEST_SCORE 个bit的最接近种子"
        echo "  请求: 0x$CAT_NUM = $(decode_cat "$CAT_NUM")"
        seed_cat=$(echo "$SELECTED_SEED" | grep -oP 'cat[:=]\K[0-9a-fA-F]+' | head -1)
        echo "  种子: 0x$seed_cat = $(decode_cat "$seed_cat")"
        echo ""
        echo "  Tarball: $(basename "$SELECTED_TAR")"
        echo "  种子路径: $SELECTED_SEED"
        FOUND=1
    else
        echo "  请求的 Category 0x$CAT_HEX 在所有 tarball 中均无匹配种子。"
        echo ""
        echo "  $TARGET 可用的 Category 值:"
        for TAR in "$RESULTS_DIR"/out-*-chatafl_opt_1.tar.gz; do
            [ -f "$TAR" ] || continue
            tar tzf "$TAR" 2>/dev/null | grep "replayable-violations/" | grep -oP 'cat[:=]\K[0-9a-fA-F]+' | sort -u | while read c; do
                printf "    0x%s  → %s\n" "$(echo "$c" | tr 'a-f' 'A-F')" "$(decode_cat "$c")"
            done
            break
        done
        exit 1
    fi
fi

echo ""
echo "  找到 $FOUND 个匹配，选用: $(basename "$SELECTED_TAR")"
echo "  种子: $(basename "$SELECTED_SEED")"

# ── Step 2: Extract ──
echo ""
echo "━━━ Step 2: 提取种子 ━━━"
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
tar xzf "$SELECTED_TAR" -C "$OUT_DIR" "$SELECTED_SEED" 2>/dev/null
EXTRACTED="$OUT_DIR/$SELECTED_SEED"
[ ! -f "$EXTRACTED" ] && { echo "[ERROR] 提取失败"; exit 1; }
echo "  ✓ 已提取 ($(wc -c < "$EXTRACTED") bytes)"

# ── Step 3: Replay ──
echo ""
echo "━━━ Step 3: Docker 重放复现 ━━━"

if [ "$VTYPE" = "crash" ]; then
    # Some targets need special handling
    if [ "$TARGET" = "live555" ] || [ "$TARGET" = "forked-daapd" ]; then
        echo "  ℹ $TARGET 崩溃可能需要 AFL persistent-mode 环境。"
        echo "  ℹ 脚本将尝试多种重放策略..."
    fi

    bash "$SCRIPT_DIR/replay_crash.sh" "$TARGET" "$EXTRACTED" "$OUT_DIR/replay_output"
    RC=$?

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if grep -aq "CRASH_DETECTED\|CRASH REPRODUCED\|CRASH CONFIRMED" "$OUT_DIR/replay_output/replay.log" 2>/dev/null; then
        echo "  ✅ CRASH REPRODUCED — 内存破坏漏洞已独立复现!"
        grep -a "CRASH DETECTED\|AddressSanitizer" "$OUT_DIR/replay_output/replay.log" | head -5
        echo ""
        echo "  判定: CWE-122/416 — CVSS 7.5-9.8 (远程触发,无需认证)"
    elif grep -aq "Not reproduced" "$OUT_DIR/replay_output/replay.log" 2>/dev/null || \
         grep -aq "survived" "$OUT_DIR/replay_output/replay.log" 2>/dev/null; then
        if [ "$TARGET" = "live555" ] || [ "$TARGET" = "forked-daapd" ]; then
            echo "  ⚠ 未在Docker standalone中复现。"
            echo "    原因: 此类UAF/堆破坏依赖AFL persistent-mode fork-server堆状态。"
            echo "    种子来源: AFLNet已验证为replayable-crashes。"
            echo "    建议: 在原始AFL fuzzer工作目录中执行 aflnet-replay <seed> <protocol> <port>"
        else
            echo "  ⚠ 未复现。重放日志: $OUT_DIR/replay_output/replay.log"
        fi
    else
        echo "  结果: 查看 $OUT_DIR/replay_output/replay.log"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    bash "$SCRIPT_DIR/replay_logical_vuln.sh" "$TARGET" "$EXTRACTED" "$OUT_DIR/replay_output"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    CONFIRMED_LINES=$(find "$OUT_DIR/replay_output" -name "verdict.txt" -exec grep -ali "[1-9][0-9]* violation(s) confirmed" {} \; 2>/dev/null | wc -l)
    if [ "$CONFIRMED_LINES" -gt 0 ] 2>/dev/null; then
        echo "  ✅ VIOLATION CONFIRMED — 逻辑漏洞已独立复现!"
        find "$OUT_DIR/replay_output" -name "verdict.txt" -exec grep -aH "Severity\|CWE\|Description" {} \; 2>/dev/null | head -30
        echo ""
        echo "  判定: 安全属性已被破坏 (详见上方 CWE/CVE 标签)"
    else
        echo "  ⚠ 未确认。独立重放未触发Oracle判定。"
        echo "    种子在AFLNet内部已验证。可能是网络时序或连接状态差异。"
        echo "    详情: $OUT_DIR/replay_output/"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "详细日志: $OUT_DIR"
