#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_REQUESTED=false
CONFIGURE_INTEGRATIONS=true
OPEN_CLAUDE_DESKTOP=false
INTEGRATION_ARGUMENTS=()
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

usage() {
    cat <<'EOF'
Usage: zsh scripts/install.sh [options]

Build and install iCloud Bridge for the current macOS user. By default, the
installer registers every Codex and Claude Code CLI it finds on PATH.

Options:
  --build              Rebuild the signed app before installing it
  --codex              Register Codex (can be combined with --claude)
  --claude             Register Claude Code (alias: --claude-code)
  --all-integrations   Require and register both Codex and Claude Code
  --claude-desktop     Open Claude Desktop's extension install prompt
  --no-integrations    Install the app without changing MCP client settings
  -h, --help           Show this help
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --build)
            BUILD_REQUESTED=true
            ;;
        --codex)
            INTEGRATION_ARGUMENTS+=(--codex)
            ;;
        --claude|--claude-code)
            INTEGRATION_ARGUMENTS+=(--claude)
            ;;
        --all-integrations)
            INTEGRATION_ARGUMENTS=(--all)
            ;;
        --claude-desktop)
            OPEN_CLAUDE_DESKTOP=true
            ;;
        --no-integrations)
            CONFIGURE_INTEGRATIONS=false
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ! -d "$APP_SOURCE" || "$BUILD_REQUESTED" == true ]]; then
    echo "Building the signed macOS app…"
    zsh "$ROOT_DIR/scripts/build-app.sh"
fi

zsh "$ROOT_DIR/scripts/build-mcpb.sh"

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

if [[ "$CONFIGURE_INTEGRATIONS" == true ]]; then
    if ! zsh "$ROOT_DIR/scripts/configure-integrations.sh" \
        --launcher "$LAUNCHER_PATH" \
        "${INTEGRATION_ARGUMENTS[@]}"; then
        echo >&2
        echo "The app was installed, but one or more MCP integrations could not be configured." >&2
        echo "Fix the reported client configuration issue, then rerun:" >&2
        echo "  zsh $ROOT_DIR/scripts/configure-integrations.sh --all" >&2
        exit 1
    fi
fi

CLAUDE_BUNDLE_PATH="$ROOT_DIR/dist/iCloud Bridge.mcpb"
if [[ "$OPEN_CLAUDE_DESKTOP" == true ]]; then
    if [[ -d "/Applications/Claude.app" || -d "$HOME/Applications/Claude.app" ]]; then
        open "$CLAUDE_BUNDLE_PATH"
        echo "Opened the iCloud Bridge extension installer in Claude Desktop."
    else
        echo "Claude Desktop is not installed; its extension is ready at: $CLAUDE_BUNDLE_PATH" >&2
    fi
elif [[ -d "/Applications/Claude.app" || -d "$HOME/Applications/Claude.app" ]]; then
    echo "Claude Desktop extension ready: $CLAUDE_BUNDLE_PATH"
    echo "Install it with: open \"$CLAUDE_BUNDLE_PATH\""
fi

echo
echo "Next: click iCloud Bridge in the menu bar and choose Request Missing Access."
