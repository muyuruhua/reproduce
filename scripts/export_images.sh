#!/bin/bash
# ==============================================================================
# ChatAFL Vulnerability Reproduction — Docker 镜像导出脚本
# ==============================================================================
# 用法:
#   bash reproduce/scripts/export_images.sh [output_dir]
#
# 生成文件:
#   <output_dir>/lightftp.tar.gz
#   <output_dir>/bftpd.tar.gz
#   ... (10个target，共约 17 GB)
#   <output_dir>/all_images.tar       (全部合一，约 17 GB)
#   <output_dir>/image_manifest.txt   (镜像清单+sha256)
# ==============================================================================
set -euo pipefail

OUT_DIR="${1:-$(pwd)/docker_images}"
mkdir -p "$OUT_DIR"
MANIFEST="$OUT_DIR/image_manifest.txt"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ChatAFL Reproduce — Docker Image Exporter                  ║"
echo "║  Output: $OUT_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"

echo "# ChatAFL Vulnerability Reproduction — Image Manifest" > "$MANIFEST"
echo "# Generated: $(date -Iseconds)" >> "$MANIFEST"
echo "# Docker version: $(docker --version)" >> "$MANIFEST"
echo "" >> "$MANIFEST"

IMAGES=(
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

ALL_FILES=()

for IMAGE in "${IMAGES[@]}"; do
    SAFE_NAME=$(echo "$IMAGE" | tr ':' '_' | tr '/' '_')
    TAR_FILE="$OUT_DIR/${SAFE_NAME}.tar.gz"

    echo ""
    echo "━━━ Exporting: $IMAGE ━━━"

    # Record metadata
    IMAGE_ID=$(docker image inspect "$IMAGE" --format '{{.ID}}' 2>/dev/null)
    IMAGE_SIZE=$(docker image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null)
    CREATED=$(docker image inspect "$IMAGE" --format '{{.Created}}' 2>/dev/null)

    echo "  Image ID:  $IMAGE_ID"
    echo "  Size:      $(numfmt --to=iec $IMAGE_SIZE 2>/dev/null || echo $IMAGE_SIZE)"
    echo "  Created:   $CREATED"

    # Export as compressed tar
    docker save "$IMAGE" | gzip > "$TAR_FILE"
    TAR_SIZE=$(stat --format=%s "$TAR_FILE")
    echo "  Exported:  $TAR_FILE ($(numfmt --to=iec $TAR_SIZE 2>/dev/null || echo ${TAR_SIZE}B))"

    ALL_FILES+=("$TAR_FILE")

    # Write manifest entry
    cat >> "$MANIFEST" << EOF
Image: $IMAGE
  ID: $IMAGE_ID
  Size: $IMAGE_SIZE bytes
  Created: $CREATED
  File: $(basename "$TAR_FILE")
  SHA256: $(sha256sum "$TAR_FILE" | awk '{print $1}')
EOF
done

# ── Optional: Create combined archive ──
echo ""
echo "━━━ Creating combined archive (all in one)... ━━━"
COMBINED="$OUT_DIR/all_images.tar"
docker save "${IMAGES[@]}" -o "$COMBINED"
COMBINED_SIZE=$(stat --format=%s "$COMBINED")
echo "  Combined:  $COMBINED ($(numfmt --to=iec $COMBINED_SIZE 2>/dev/null || echo ${COMBINED_SIZE}B))"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Export complete!                                           ║"
echo "║  Manifest: $MANIFEST"
echo "║                                                            ║"
echo "║  For GitHub upload (>100MB files require Git LFS):          ║"
echo "║    git lfs track 'docker_images/*.tar.gz'                   ║"
echo "║    git lfs track 'docker_images/all_images.tar'             ║"
echo "║                                                            ║"
echo "║  Or push to Docker Hub / GHCR:                             ║"
echo "║    See reproduce/scripts/push_to_registry.sh               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
