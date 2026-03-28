#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Sources/Baguette/Resources"
ASSETS_DIR="$OUT_DIR/Assets.xcassets"
APPICON_DIR="$ASSETS_DIR/AppIcon.appiconset"
ICONSET_DIR="$ROOT_DIR/.build/Baguette.iconset"
ICNS_PATH="$OUT_DIR/Baguette.icns"

mkdir -p "$OUT_DIR"
mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
rm -rf "$APPICON_DIR"
mkdir -p "$ICONSET_DIR"
mkdir -p "$APPICON_DIR"

SWIFT_RENDERER="$ROOT_DIR/.build/render_baguette_icon.swift"
cat > "$SWIFT_RENDERER" <<'SWIFT'
import AppKit
import Foundation

if CommandLine.arguments.count != 3 {
    fputs("Usage: swift render.swift <size> <output_path>\n", stderr)
    exit(1)
}

guard let sizeValue = Double(CommandLine.arguments[1]), sizeValue > 0 else {
    fputs("Invalid size\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[2]
let pixelSize = Int(sizeValue)
let canvasSize = NSSize(width: Double(pixelSize), height: Double(pixelSize))
let canvasRect = NSRect(origin: .zero, size: canvasSize)
let inset = sizeValue * 0.04
let iconRect = canvasRect.insetBy(dx: inset, dy: inset)
let cornerRadius = sizeValue * 0.22

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fputs("Failed to allocate bitmap\n", stderr)
    exit(1)
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor.clear.setFill()
canvasRect.fill()

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.64, green: 0.84, blue: 0.98, alpha: 1.0),
    ending: NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.92, alpha: 1.0)
)!
let roundedRect = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
gradient.draw(in: roundedRect, angle: 90)

NSColor(calibratedWhite: 0.0, alpha: 0.12).setStroke()
roundedRect.lineWidth = max(1, sizeValue * 0.02)
roundedRect.stroke()

let baseFont = NSFont.systemFont(ofSize: sizeValue * 0.78)
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: baseFont,
    .paragraphStyle: paragraphStyle,
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0)
]

let emoji = "🥖" as NSString
let textSize = emoji.size(withAttributes: attributes)
let drawPoint = NSPoint(
    x: (sizeValue - textSize.width) / 2.0,
    y: (sizeValue - textSize.height) / 2.0
)
emoji.draw(at: drawPoint, withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to render PNG\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Failed to write PNG: \(error)\n", stderr)
    exit(1)
}
SWIFT

render_png() {
    local px="$1"
    local file="$2"
    swift "$SWIFT_RENDERER" "$px" "$ICONSET_DIR/$file"
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
