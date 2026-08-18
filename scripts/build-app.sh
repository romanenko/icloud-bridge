#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/iCloud Bridge.app"
BUILD_DIR="$ROOT_DIR/.build/release"

build_app_executable() {
    local build_log build_status
    build_log="$(mktemp -t icloud-bridge-swift-build).log"

    if swift build --package-path "$ROOT_DIR" --configuration release 2>&1 | tee "$build_log"; then
        rm -f "$build_log"
        return 0
    else
        build_status="${pipestatus[1]}"
    fi

    # SwiftPM 6.3 can schedule SwiftMCP's build-tool executable before its
    # SwiftSyntax host modules are ready. The failed pass warms those modules,
    # so retry only this known transient failure and preserve every other error.
    if grep -Fq "SwiftMCPAggregatorTool" "$build_log" \
        && grep -Fq "no such module 'SwiftSyntax'" "$build_log"; then
        echo >&2
        echo "SwiftPM hit a transient SwiftSyntax build-tool ordering issue; retrying once…" >&2
        rm -f "$build_log"
        swift build --package-path "$ROOT_DIR" --configuration release
        return
    fi

    rm -f "$build_log"
    return "$build_status"
}

build_app_executable

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
