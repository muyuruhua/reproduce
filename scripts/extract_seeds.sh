#!/bin/bash
# ==============================================================================
# ChatAFL Reproduce — 从 results tarball 中提取 Crash/Volation 种子
# ==============================================================================
# 用法:
#   bash reproduce/scripts/extract_seeds.sh <results_dir> <target_name> [output_dir]
#
# 示例:
#   bash reproduce/scripts/extract_seeds.sh \
#       /path/to/results-bftpd_Mar-16_23-10-02_ten bftpd ./seeds/bftpd
# ==============================================================================
set -euo pipefail

RESULTS_DIR="${1:?Usage: $0 <results_dir> <target> [output_dir]}"
TARGET="${2:?Missing target name (bftpd|proftpd|kamailio|live555|forked-daapd|...)}"
OUT_DIR="${3:-./seeds/$TARGET}"

mkdir -p "$OUT_DIR/crashes" "$OUT_DIR/violations" "$OUT_DIR/hangs"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Seed Extractor — $TARGET"
echo "║  Source: $RESULTS_DIR"
echo "║  Output: $OUT_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"

TOTAL_CRASH=0
TOTAL_VIOL=0
TOTAL_HANG=0

for TARBALL in "$RESULTS_DIR"/out-*.tar.gz; do
    [ -f "$TARBALL" ] || continue
    RUN_NAME=$(basename "$TARBALL" .tar.gz)
    echo ""
    echo "--- $RUN_NAME ---"

    # ── Extract crashes ──
    CRASH_FILES=$(tar tzf "$TARBALL" 2>/dev/null | grep "replayable-crashes/" | grep -v "README.txt" || true)
    CRASH_CNT=$(echo "$CRASH_FILES" | grep -c . || echo 0)

    if [ "$CRASH_CNT" -gt 0 ] 2>/dev/null; then
        for cf in $CRASH_FILES; do
            [ -z "$cf" ] && continue
            SAFE_NAME=$(echo "$cf" | tr '/' '_' | tr ':,' '__')
            tar xzf "$TARBALL" -C "$OUT_DIR/crashes" --transform="s|.*/||" "$cf" 2>/dev/null
            # rename to include run prefix for uniqueness
            if [ -f "$OUT_DIR/crashes/$(basename "$cf")" ]; then
                mv "$OUT_DIR/crashes/$(basename "$cf")" "$OUT_DIR/crashes/${RUN_NAME}___$(basename "$cf")"
            fi
        done
        echo "  crashes:    $CRASH_CNT seeds"
        TOTAL_CRASH=$((TOTAL_CRASH + CRASH_CNT))
    fi

    # ── Extract violations ──
    VIOL_FILES=$(tar tzf "$TARBALL" 2>/dev/null | grep "replayable-violations/" | grep -v "README.txt" || true)
    VIOL_CNT=$(echo "$VIOL_FILES" | grep -c . || echo 0)

    if [ "$VIOL_CNT" -gt 0 ] 2>/dev/null; then
        for vf in $VIOL_FILES; do
            [ -z "$vf" ] && continue
            tar xzf "$TARBALL" -C "$OUT_DIR/violations" --transform="s|.*/||" "$vf" 2>/dev/null
            if [ -f "$OUT_DIR/violations/$(basename "$vf")" ]; then
                mv "$OUT_DIR/violations/$(basename "$vf")" \
                   "$OUT_DIR/violations/${RUN_NAME}___$(basename "$vf")"
            fi
        done
        echo "  violations: $VIOL_CNT seeds"
        TOTAL_VIOL=$((TOTAL_VIOL + VIOL_CNT))
    fi

    # ── Extract hangs ──
    HANG_FILES=$(tar tzf "$TARBALL" 2>/dev/null | grep "replayable-hangs/" | grep -v "README.txt" || true)
    HANG_CNT=$(echo "$HANG_FILES" | grep -c . || echo 0)

    if [ "$HANG_CNT" -gt 0 ] 2>/dev/null; then
        for hf in $HANG_FILES; do
            [ -z "$hf" ] && continue
            tar xzf "$TARBALL" -C "$OUT_DIR/hangs" --transform="s|.*/||" "$hf" 2>/dev/null
            if [ -f "$OUT_DIR/hangs/$(basename "$hf")" ]; then
                mv "$OUT_DIR/hangs/$(basename "$hf")" "$OUT_DIR/hangs/${RUN_NAME}___$(basename "$hf")"
            fi
        done
        echo "  hangs:      $HANG_CNT seeds"
        TOTAL_HANG=$((TOTAL_HANG + HANG_CNT))
    fi
done

# ── Generate seed manifest ──
MANIFEST="$OUT_DIR/seed_manifest.txt"
echo "# Seed Manifest — $TARGET" > "$MANIFEST"
echo "# Extracted: $(date -Iseconds)" >> "$MANIFEST"
echo "# Source: $RESULTS_DIR" >> "$MANIFEST"
echo "" >> "$MANIFEST"
echo "Total crashes:    $TOTAL_CRASH" >> "$MANIFEST"
echo "Total violations: $TOTAL_VIOL" >> "$MANIFEST"
echo "Total hangs:      $TOTAL_HANG" >> "$MANIFEST"
echo "" >> "$MANIFEST"

echo "Crashes:" >> "$MANIFEST"
ls -1 "$OUT_DIR/crashes/" 2>/dev/null | while read f; do
    echo "  $f ($(wc -c < "$OUT_DIR/crashes/$f") bytes)" >> "$MANIFEST"
done

echo "Violations:" >> "$MANIFEST"
ls -1 "$OUT_DIR/violations/" 2>/dev/null | while read f; do
    echo "  $f ($(wc -c < "$OUT_DIR/violations/$f") bytes)" >> "$MANIFEST"
done

# ── Summary ──
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Extraction Complete: $TARGET"
echo "║  Crashes:     $TOTAL_CRASH"
echo "║  Violations:  $TOTAL_VIOL"
echo "║  Hangs:       $TOTAL_HANG"
echo "║  Output:      $OUT_DIR"
echo "║  Manifest:    $MANIFEST"
echo "╚══════════════════════════════════════════════════════════════╝"
