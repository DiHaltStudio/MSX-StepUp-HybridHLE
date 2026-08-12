#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build/linux}"
GODOT_BIN="${GODOT_BIN:-godot}"

cmake -S "$PROJECT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGODOTCPP_TARGET=template_release
cmake --build "$BUILD_DIR" --parallel

EXPORT_DIR="$PROJECT_DIR/build/export"
mkdir -p "$EXPORT_DIR"
"$GODOT_BIN" --headless --import --path "$PROJECT_DIR"
"$GODOT_BIN" --headless --path "$PROJECT_DIR" \
    --export-release Linux "$EXPORT_DIR/MSX-StepUp-HybridHLE.x86_64"

echo "Export created in $EXPORT_DIR"
