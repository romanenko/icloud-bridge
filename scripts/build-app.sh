#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/iCloud Bridge.app"
BUILD_DIR="$ROOT_DIR/.build/release"

swift build --package-path "$ROOT_DIR" --configuration release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/iCloudBridge" "$APP_DIR/Contents/MacOS/iCloudBridge"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

SIGNING_IDENTITY="${CALENDAR_BRIDGE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F '"' '/Apple Development:|Developer ID Application:/ { print $2; exit }')"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "No Apple Development or Developer ID Application signing identity is available." >&2
    echo "An ad-hoc signature cannot obtain macOS Calendar or Reminders permission." >&2
    exit 1
fi

codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT_DIR/Packaging/iCloudBridge.entitlements" \
    "$APP_DIR"

echo "Built $APP_DIR using $SIGNING_IDENTITY"
