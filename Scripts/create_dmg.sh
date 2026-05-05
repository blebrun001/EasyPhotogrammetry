#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <path-to-app> <version-or-tag>" >&2
  exit 1
fi

APP_PATH="$1"
VERSION_INPUT="$2"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: app bundle not found at '$APP_PATH'" >&2
  exit 1
fi

if [[ "${APP_PATH##*.}" != "app" ]]; then
  echo "Error: expected a .app bundle path, got '$APP_PATH'" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"

VERSION="${VERSION_INPUT#refs/tags/}"
VERSION="${VERSION#v}"
if [[ -z "$VERSION" ]]; then
  echo "Error: version/tag cannot be empty" >&2
  exit 1
fi

DMG_NAME="EasyPhotogrammetry-${VERSION}-macos-arm64.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
VOLUME_NAME="EasyPhotogrammetry ${VERSION}"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "DMG created at: $DMG_PATH"
