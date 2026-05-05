#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Sources/EasyPhotogrammetry/Resources"
ASSETS_DIR="$OUT_DIR/Assets.xcassets"
APPICON_DIR="$ASSETS_DIR/AppIcon.appiconset"
ICONSET_DIR="$ROOT_DIR/.build/EasyPhotogrammetry.iconset"
ICNS_PATH="$OUT_DIR/EasyPhotogrammetry.icns"
SOURCE_ICON="$ROOT_DIR/bestiole_2-Baguette.png"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Error: source icon not found at '$SOURCE_ICON'" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
rm -rf "$APPICON_DIR"
mkdir -p "$ICONSET_DIR"
mkdir -p "$APPICON_DIR"

render_png() {
    local px="$1"
    local file="$2"
    sips -z "$px" "$px" "$SOURCE_ICON" --out "$ICONSET_DIR/$file" >/dev/null
}

render_png 16 icon_16x16.png
render_png 32 icon_16x16@2x.png
render_png 32 icon_32x32.png
render_png 64 icon_32x32@2x.png
render_png 128 icon_128x128.png
render_png 256 icon_128x128@2x.png
render_png 256 icon_256x256.png
render_png 512 icon_256x256@2x.png
render_png 512 icon_512x512.png
render_png 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

cp "$ICONSET_DIR"/icon_16x16.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_16x16@2x.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_32x32.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_32x32@2x.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_128x128.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_128x128@2x.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_256x256.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_256x256@2x.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_512x512.png "$APPICON_DIR"/
cp "$ICONSET_DIR"/icon_512x512@2x.png "$APPICON_DIR"/

cat > "$APPICON_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Generated: $ICNS_PATH"
echo "Generated: $APPICON_DIR"
