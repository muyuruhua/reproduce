#!/bin/bash
# ==============================================================================
# ChatAFL Vulnerability Reproduction — 一键构建所有 Docker 镜像
# ==============================================================================
# 用法:
#   export PROJECT_ROOT=/path/to/ChatAFL-master
#   bash reproduce/scripts/build_all_images.sh
#
# 可选参数:
#   bash reproduce/scripts/build_all_images.sh lightftp    # 只构建指定镜像
#   bash reproduce/scripts/build_all_images.sh --no-cache   # 不使用缓存
# ==============================================================================
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:?请设置 PROJECT_ROOT 环境变量指向 ChatAFL-master 根目录}"
PFBENCH="$PROJECT_ROOT/benchmark"

TARGET_FILTER="${1:-all}"
NO_CACHE="${NO_CACHE:-}"

if [ "$TARGET_FILTER" = "--no-cache" ]; then
    NO_CACHE="--no-cache"
    TARGET_FILTER="all"
fi

MAKE_OPT="${MAKE_OPT:--j$(nproc)}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ChatAFL Vulnerability Reproduction — Docker Image Builder  ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Project:  $PROJECT_ROOT"
echo "║  Target:   $TARGET_FILTER"
echo "║  Make Opt: $MAKE_OPT"
echo "║  No Cache: ${NO_CACHE:-false}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

build_image() {
    local target="$1"
    local subject_dir="$2"
    local image_name="$3"

    if [ "$TARGET_FILTER" != "all" ] && [ "$TARGET_FILTER" != "$target" ]; then
        return 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building: $image_name ($target)"
    echo "  Source:   $subject_dir"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cd "$PFBENCH/$subject_dir"
    docker build . -t "$image_name" --build-arg MAKE_OPT="$MAKE_OPT" $NO_CACHE
    echo "  ✓ $image_name built successfully"
}

# ── FTP Targets ───────────────────────────────────────────────────────
build_image "lightftp"   "subjects/FTP/LightFTP"        "lightftp"
build_image "bftpd"      "subjects/FTP/BFTPD"            "bftpd"
build_image "proftpd"    "subjects/FTP/ProFTPD"          "proftpd"
build_image "pure-ftpd"  "subjects/FTP/PureFTPD"         "pure-ftpd"

# ── SMTP ──────────────────────────────────────────────────────────────
build_image "exim"       "subjects/SMTP/Exim"            "exim"

# ── RTSP ──────────────────────────────────────────────────────────────
build_image "live555"    "subjects/RTSP/Live555"         "live555"

# ── SIP ───────────────────────────────────────────────────────────────
build_image "kamailio"   "subjects/SIP/Kamailio"         "kamailio"

# ── DAAP/HTTP ─────────────────────────────────────────────────────────
build_image "forked-daapd" "subjects/DAAP/forked-daapd"   "forked-daapd"

# ── HTTP ──────────────────────────────────────────────────────────────
build_image "lighttpd1"  "subjects/HTTP/Lighttpd1"       "lighttpd1"

# ── MQTT ──────────────────────────────────────────────────────────────
build_image "mosquitto-v2.0.18" "subjects/MQTT/Mosquitto-v2.0.18" "mosquitto-v2.0.18"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✓ All builds complete!                                      ║"
echo "║                                                              ║"
echo "║  Verify with:  docker images | grep -E 'lightftp|bftpd|'    ║"
echo "║  Next step:    bash reproduce/scripts/replay_crash.sh ...    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
