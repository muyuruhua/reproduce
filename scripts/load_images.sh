#!/bin/bash
# ==============================================================================
# ChatAFL Vulnerability Reproduction — Docker 镜像导入脚本 (审核人员使用)
# ==============================================================================
# 用法:
#   # 从独立 tar.gz 文件导入
#   bash reproduce/scripts/load_images.sh ./docker_images/
#
#   # 从合并的 all_images.tar 导入（更快，一次io）
#   bash reproduce/scripts/load_images.sh ./docker_images/all_images.tar
#
#   # 导入单个镜像
#   docker load -i ./docker_images/bftpd_latest.tar.gz
# ==============================================================================
set -euo pipefail

INPUT="${1:?Usage: $0 <image_dir_or_tarball>}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ChatAFL Reproduce — Docker Image Importer                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"

load_single() {
    local f="$1"
    echo "  Loading: $(basename "$f") ..."
    docker load -i "$f"
}

if [ -f "$INPUT" ]; then
    # Single file (e.g. all_images.tar)
    echo ""
    echo "Loading from: $INPUT"
    echo ""
    docker load -i "$INPUT"
else
    # Directory with .tar.gz files
    echo ""
    echo "Scanning: $INPUT"
    echo ""

    COUNT=0
    for f in "$INPUT"/*.tar.gz; do
        [ -f "$f" ] || continue
        load_single "$f"
        COUNT=$((COUNT+1))
    done

    # Also check for extracted .tar files
    for f in "$INPUT"/*.tar; do
        [ -f "$f" ] || continue
        # skip all_images.tar if also have .gz
        [ "$(basename "$f")" = "all_images.tar" ] && continue
        load_single "$f"
        COUNT=$((COUNT+1))
    done

    if [ $COUNT -eq 0 ]; then
        echo "[ERROR] No .tar.gz or .tar files found in $INPUT"
        echo "Expected: lightftp_latest.tar.gz, bftpd_latest.tar.gz, ..."
        exit 1
    fi
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Verifying imported images...                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"

REQUIRED=(
    "lightftp:latest"
    "bftpd:latest"
    "proftpd:latest"
    "pure-ftpd:latest"
    "exim:latest"
    "live555:latest"
    "kamailio:latest"
    "forked-daapd:latest"
    "lighttpd1:latest"
    "mosquitto-v2.0.18:latest"
)

ALL_OK=1
for img in "${REQUIRED[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
        echo "  ✓ $img"
    else
        echo "  ✗ $img — MISSING!"
        ALL_OK=0
    fi
done

echo ""
if [ $ALL_OK -eq 1 ]; then
    echo "✅ All 10 images imported successfully!"
    echo "   Next step: reproduce/scripts/extract_seeds.sh"
else
    echo "⚠️  Some images are missing. Verify your import source."
    exit 1
fi
