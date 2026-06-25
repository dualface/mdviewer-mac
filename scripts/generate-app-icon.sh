#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SVG="$ROOT_DIR/App/Resources/AppIconSource/app-icon.svg"
ICONSET_DIR="$ROOT_DIR/App/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to generate app icons." >&2
  echo "Install it with: brew install librsvg" >&2
  exit 1
fi

mkdir -p "$ICONSET_DIR"

rsvg-convert -w 16 -h 16 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_16x16.png"
rsvg-convert -w 32 -h 32 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_16x16@2x.png"
rsvg-convert -w 32 -h 32 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_32x32.png"
rsvg-convert -w 64 -h 64 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_32x32@2x.png"
rsvg-convert -w 128 -h 128 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_128x128.png"
rsvg-convert -w 256 -h 256 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_128x128@2x.png"
rsvg-convert -w 256 -h 256 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_256x256.png"
rsvg-convert -w 512 -h 512 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_256x256@2x.png"
rsvg-convert -w 512 -h 512 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_512x512.png"
rsvg-convert -w 1024 -h 1024 "$SOURCE_SVG" -o "$ICONSET_DIR/icon_512x512@2x.png"

echo "Generated app icons in $ICONSET_DIR"
