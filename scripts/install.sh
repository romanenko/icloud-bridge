#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="iCloud Bridge.app"
APP_SOURCE="$ROOT_DIR/dist/$APP_NAME"
APP_DIRECTORY="$HOME/Applications"
APP_TARGET="$APP_DIRECTORY/$APP_NAME"
APP_EXECUTABLE="$APP_TARGET/Contents/MacOS/iCloudBridge"
LAUNCHER_DIRECTORY="$HOME/.local/bin"
LAUNCHER_PATH="$LAUNCHER_DIRECTORY/icloud-bridge"
LAUNCH_AGENT_DIRECTORY="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIRECTORY/com.icloudbridge.app.plist"
LOG_DIRECTORY="$HOME/Library/Logs/iCloud Bridge"
LAUNCH_AGENT_LABEL="com.icloudbridge.app"
USER_ID="$(id -u)"

if [[ ! -d "$APP_SOURCE" || "${1:-}" == "--build" ]]; then
    echo "Building the signed macOS app…"
    zsh "$ROOT_DIR/scripts/build-app.sh"
fi

if [[ ! -x "$APP_SOURCE/Contents/MacOS/iCloudBridge" ]]; then
    echo "The built app is missing its executable: $APP_SOURCE" >&2
    exit 1
fi

mkdir -p "$APP_DIRECTORY" "$LAUNCHER_DIRECTORY" "$LAUNCH_AGENT_DIRECTORY" "$LOG_DIRECTORY"

# Stop this user's managed instance before replacing its app bundle. A manually
# launched instance with the same bundle identifier is also asked to quit.
launchctl bootout "gui/$USER_ID/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
osascript -e 'tell application id "com.calendarbridge.app" to quit' >/dev/null 2>&1 || true

if [[ -e "$APP_TARGET" ]]; then
    rm -rf "$APP_TARGET"
fi
ditto "$APP_SOURCE" "$APP_TARGET"

install -m 755 "$ROOT_DIR/Packaging/icloud-bridge-launcher.sh" "$LAUNCHER_PATH"

TEMP_PLIST="$(mktemp -t icloud-bridge-launch-agent).plist"
trap 'rm -f "$TEMP_PLIST"' EXIT
sed \
    -e "s|__APP_EXECUTABLE__|$APP_EXECUTABLE|g" \
    -e "s|__LOG_DIRECTORY__|$LOG_DIRECTORY|g" \
    "$ROOT_DIR/Packaging/com.icloudbridge.app.plist.template" > "$TEMP_PLIST"
install -m 644 "$TEMP_PLIST" "$LAUNCH_AGENT_PATH"

launchctl bootstrap "gui/$USER_ID" "$LAUNCH_AGENT_PATH"

echo
echo "Installed $APP_NAME to: $APP_TARGET"
echo "Installed MCP launcher to: $LAUNCHER_PATH"
echo "Enabled launch-at-login via: $LAUNCH_AGENT_PATH"
echo
echo "Next: click iCloud Bridge in the menu bar and choose Request Missing Access."
echo "Then add the local MCP server to ChatGPT desktop using:"
echo "  Command: /bin/zsh"
echo "  Arguments: -lc 'exec \"\$HOME/.local/bin/icloud-bridge\" --stdio'"
