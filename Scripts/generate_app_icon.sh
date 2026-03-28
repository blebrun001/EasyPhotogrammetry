#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Sources/Baguette/Resources"
ICONSET_DIR="$ROOT_DIR/.build/Baguette.iconset"
ICNS_PATH="$OUT_DIR/Baguette.icns"

mkdir -p "$OUT_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

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
let canvasSize = NSSize(width: sizeValue, height: sizeValue)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

let image = NSImage(size: canvasSize)
image.lockFocus()

NSColor.white.setFill()
canvasRect.fill()

let baseFont = NSFont.systemFont(ofSize: sizeValue * 0.92)
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: baseFont,
    .paragraphStyle: paragraphStyle,
    .foregroundColor: NSColor.black
]

let emoji = "🥖" as NSString
let textSize = emoji.size(withAttributes: attributes)
let drawPoint = NSPoint(
    x: (sizeValue - textSize.width) / 2.0,
    y: (sizeValue - textSize.height) / 2.0
)
emoji.draw(at: drawPoint, withAttributes: attributes)

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
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

echo "Generated: $ICNS_PATH"
