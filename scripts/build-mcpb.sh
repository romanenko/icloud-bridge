#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/Packaging/claude-desktop/manifest.json"
LAUNCHER_SOURCE="$ROOT_DIR/Packaging/icloud-bridge-launcher.sh"
OUTPUT_DIRECTORY="$ROOT_DIR/dist"
OUTPUT_PATH="$OUTPUT_DIRECTORY/iCloud Bridge.mcpb"
STAGING_DIRECTORY="$(mktemp -d -t icloud-bridge-mcpb)"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

plutil -convert xml1 -o /dev/null "$MANIFEST_PATH"
mkdir -p "$STAGING_DIRECTORY/server" "$OUTPUT_DIRECTORY"
cp "$MANIFEST_PATH" "$STAGING_DIRECTORY/manifest.json"
cp "$LAUNCHER_SOURCE" "$STAGING_DIRECTORY/server/icloud-bridge"
chmod 755 "$STAGING_DIRECTORY/server/icloud-bridge"

if command -v mcpb >/dev/null 2>&1; then
    mcpb validate "$STAGING_DIRECTORY"
fi

rm -f "$OUTPUT_PATH"
(
    cd "$STAGING_DIRECTORY"
    /usr/bin/zip -X -q -r "$OUTPUT_PATH" manifest.json server
)

echo "Built $OUTPUT_PATH"
