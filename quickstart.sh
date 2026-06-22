#!/bin/bash
# ==============================================================================
# ChatAFL Vulnerability Reproduction — 一键快速开始
# ==============================================================================
# 审核人员从 GitHub 下载后，只需执行这一条命令即可验证所有漏洞。
#
# 前置条件:
#   1. Docker 已安装并运行
#   2. 当前目录是 reproduce/
#
# 用法:
#   cd reproduce
#   bash quickstart.sh              # 全部 10 个目标
#   bash quickstart.sh bftpd        # 单个目标
#   bash quickstart.sh --demo       # 快速演示模式 (每个目标只测1个种子)
# ==============================================================================
# set -euo pipefail  # disabled: grep -rl may return 0 results

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_BASE="${OUT_BASE:-/tmp/chatafl_reproduce_$(date +%Y%m%d_%H%M%S)}"
DEMO_MODE=0
TARGET_FILTER="${1:-all}"

if [ "$TARGET_FILTER" = "--demo" ]; then
    DEMO_MODE=1
    TARGET_FILTER="all"
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ChatAFL-Master 漏洞复现 — 一键验证脚本                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Step 0: Check Docker ──────────────────────────────────────────
echo -e "${YELLOW}[Step 0/3] 检查环境...${NC}"
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker 未运行。请先启动 Docker。${NC}"
    echo "  sudo systemctl start docker"
    exit 1
fi

# ── Step 1: Load images ───────────────────────────────────────────
echo -e "${YELLOW}[Step 1/3] 导入 Docker 镜像...${NC}"

IMAGES=("lightftp" "bftpd" "proftpd" "pure-ftpd" "exim" "live555"
        "kamailio" "forked-daapd" "lighttpd1" "mosquitto-v2.0.18")

LOADED=0; SKIPPED=0
for img in "${IMAGES[@]}"; do
    if docker image inspect "$img:latest" >/dev/null 2>&1; then
        SKIPPED=$((SKIPPED+1))
        continue
    fi
    TAR_FILE="$SCRIPT_DIR/docker_images/${img}_latest.tar.gz"
    if [ -f "$TAR_FILE" ]; then
        echo "  导入 $img ..."
        docker load -i "$TAR_FILE" >/dev/null 2>&1
        LOADED=$((LOADED+1))
        echo -e "  ${GREEN}✓${NC} $img"
    else
        echo -e "  ${RED}✗${NC} $img — 文件不存在: $TAR_FILE"
    fi
done
echo -e "  ${GREEN}已加载 $LOADED 个, 已存在 $SKIPPED 个${NC}"

# ── Step 2: Run reproductions ──────────────────────────────────────
echo ""
echo -e "${YELLOW}[Step 2/3] 开始复现漏洞...${NC}"
echo "  输出目录: $OUT_BASE"
mkdir -p "$OUT_BASE"


declare -A HAS_CRASH=(
    [bftpd]=1 [kamailio]=1 [proftpd]=1 [live555]=1 [forked-daapd]=1
    [exim]=0 [lightftp]=0 [lighttpd1]=0 [mosquitto-v2.0.18]=0 [pure-ftpd]=0
)

TOTAL_CRASH=0; CRASH_CONFIRMED=0; TOTAL_VIOL=0; VIOL_CONFIRMED=0

for target in "${IMAGES[@]}"; do
    [ "$TARGET_FILTER" != "all" ] && [ "$TARGET_FILTER" != "$target" ] && continue

    SEEDS_DIR="$SCRIPT_DIR/$target/seeds"
    [ -d "$SEEDS_DIR" ] || { echo "  $target: 无种子，跳过"; continue; }

    printf "\n${BLUE}━━━ %s ━━━${NC}\n" "$target"

    # ── Crash replay ──
    if [ "${HAS_CRASH[$target]:-0}" -eq 1 ] && [ -d "$SEEDS_DIR/crashes" ]; then
        crash_seeds=("$SEEDS_DIR/crashes"/*)
        MAX_C=${#crash_seeds[@]}
        [ "$DEMO_MODE" -eq 1 ] && MAX_C=1

        for ((i=0; i<MAX_C; i++)); do
            seed="${crash_seeds[$i]}"
            [ -f "$seed" ] || continue
            TOTAL_CRASH=$((TOTAL_CRASH+1))
            OUT="$OUT_BASE/${target}_crash_$((i+1))"
            mkdir -p "$OUT"

            echo -n "  Crash #$((i+1)): $(basename "$seed" | cut -c1-60)... "
            bash "$SCRIPT_DIR/scripts/replay_crash.sh" "$target" "$seed" "$OUT" >/dev/null 2>&1

            if grep -aq "CRASH DETECTED" "$OUT/replay.log" 2>/dev/null; then
                CRASH_CONFIRMED=$((CRASH_CONFIRMED+1))
                echo -e "${RED}✗ CRASH REPRODUCED ✓${NC}"
                grep -a "CRASH DETECTED\|AddressSanitizer" "$OUT/replay.log" | head -2 | while read l; do echo "    $l"; done
            else
                echo -e "${YELLOW}○ not reproduced${NC}"
            fi
        done
    fi

    # ── Violation replay ──
    if [ -d "$SEEDS_DIR/violations" ]; then
        viol_seeds=("$SEEDS_DIR/violations"/*)
        MAX_V=${#viol_seeds[@]}
        [ "$DEMO_MODE" -eq 1 ] && MAX_V=1

        for ((i=0; i<MAX_V; i++)); do
            seed="${viol_seeds[$i]}"
            [ -f "$seed" ] || continue
            TOTAL_VIOL=$((TOTAL_VIOL+1))
            SAFE=$(basename "$seed" | tr ':,=' '___')
            OUT="$OUT_BASE/${target}_viol_$SAFE"
            mkdir -p "$OUT"

            echo -n "  Viol #$((i+1)): $(basename "$seed" | cut -c1-60)... "
            bash "$SCRIPT_DIR/scripts/replay_logical_vuln.sh" "$target" "$seed" "$OUT" >/dev/null 2>&1

            # Find the actual verdict file (nested under safe_vname dir)
            VERDICT_FILE=$(find "$OUT" -name "verdict.txt" -type f 2>/dev/null | head -1)
            if [ -n "$VERDICT_FILE" ] && grep -qai "confirmed" "$VERDICT_FILE" 2>/dev/null; then
                VIOL_CONFIRMED=$((VIOL_CONFIRMED+1))
                echo -e "${RED}✗ VIOLATION CONFIRMED ✓${NC}"
                grep -ai "Confirmed" "$VERDICT_FILE" 2>/dev/null | head -3 | while read l; do echo "    $l"; done
            else
                echo -e "${YELLOW}○ not confirmed${NC}"
            fi
        done
    fi
done

# ── Step 3: Summary ────────────────────────────────────────────────
echo ""
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  [Step 3/3] 复现结果汇总                                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  崩溃复现:    %3d / %-3d                                        ║\n" "$CRASH_CONFIRMED" "$TOTAL_CRASH"
printf "║  逻辑漏洞:    %3d / %-3d  确认                                   ║\n" "$VIOL_CONFIRMED" "$TOTAL_VIOL"
echo "║                                                              ║"
echo "║  详细日志:  $OUT_BASE"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Per-target summary
echo ""
echo "分目标详情:"
printf "  %-22s %8s %10s\n" "Target" "Crash" "Violation"
printf "  %-22s %8s %10s\n" "----------------------" "--------" "----------"
for target in "${IMAGES[@]}"; do
    [ "$TARGET_FILTER" != "all" ] && [ "$TARGET_FILTER" != "$target" ] && continue
    C_OK=$(grep -ral "CRASH DETECTED" "$OUT_BASE/${target}_crash_"*/replay.log 2>/dev/null | wc -l || echo 0)
    V_OK=$(find "$OUT_BASE" -path "*/${target}_viol_*/*/verdict.txt" -exec grep -ali "Confirmed" {} \; 2>/dev/null | wc -l || echo 0)
    C_TOTAL=$(find "$OUT_BASE" -maxdepth 1 -name "${target}_crash_*" -type d 2>/dev/null | wc -l || echo 0)
    V_TOTAL=$(find "$OUT_BASE" -maxdepth 1 -name "${target}_viol_*" -type d 2>/dev/null | wc -l || echo 0)
    printf "  %-22s %3d/%-3d %7d/%-3d\n" "$target" "$C_OK" "$C_TOTAL" "$V_OK" "$V_TOTAL"
done

echo ""
echo -e "${GREEN}✅ 复现完成！审核人员可检查上述目录中的详细日志。${NC}"
