#!/bin/zsh
set -uo pipefail

MCP_NAME="icloud-bridge"
LEGACY_MCP_NAMES=("icloud_bridge")
LAUNCHER_PATH="${ICLOUD_BRIDGE_LAUNCHER:-$HOME/.local/bin/icloud-bridge}"
TARGETS=()
EXPLICIT_SELECTION=false

usage() {
    cat <<'EOF'
Usage: zsh scripts/configure-integrations.sh [options]

Register iCloud Bridge as a user-level MCP server.

Options:
  --codex             Configure Codex only (can be combined with --claude)
  --claude            Configure Claude Code only (alias: --claude-code)
  --all               Configure both Codex and Claude Code
  --launcher PATH     Use a specific installed iCloud Bridge launcher
  -h, --help          Show this help

With no client options, every supported CLI found on PATH is configured.
EOF
}

add_target() {
    local target="$1"
    if (( ${TARGETS[(Ie)$target]} == 0 )); then
        TARGETS+=("$target")
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --codex)
            EXPLICIT_SELECTION=true
            add_target codex
            ;;
        --claude|--claude-code)
            EXPLICIT_SELECTION=true
            add_target claude
            ;;
        --all)
            EXPLICIT_SELECTION=true
            add_target codex
            add_target claude
            ;;
        --launcher)
            if (( $# < 2 )); then
                echo "--launcher requires a path." >&2
                exit 2
            fi
            shift
            LAUNCHER_PATH="$1"
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

if [[ ! -x "$LAUNCHER_PATH" ]]; then
    echo "The iCloud Bridge launcher is not executable: $LAUNCHER_PATH" >&2
    echo "Run scripts/install.sh first, or pass --launcher PATH." >&2
    exit 1
fi

if [[ "$EXPLICIT_SELECTION" == false ]]; then
    command -v codex >/dev/null 2>&1 && add_target codex
    command -v claude >/dev/null 2>&1 && add_target claude
fi

if (( ${#TARGETS[@]} == 0 )); then
    echo "No Codex or Claude Code CLI was found on PATH; MCP registration was skipped."
    echo "After installing a client, run:"
    echo "  zsh scripts/configure-integrations.sh --all"
    exit 0
fi

failures=0
configured=()

configure_codex() {
    local client_path
    client_path="$(command -v codex 2>/dev/null || true)"
    if [[ -z "$client_path" ]]; then
        echo "Codex CLI was requested but was not found on PATH." >&2
        return 1
    fi

    # The native CLI preserves unrelated TOML settings and handles quoted table
    # names correctly. Removing first makes this operation safe to repeat after
    # the app or launcher moves.
    local old_name
    for old_name in "$MCP_NAME" "${LEGACY_MCP_NAMES[@]}"; do
        "$client_path" mcp remove "$old_name" >/dev/null 2>&1 || true
    done

    local output
    if ! output=$("$client_path" mcp add "$MCP_NAME" -- "$LAUNCHER_PATH" --stdio 2>&1); then
        echo "Unable to configure Codex:" >&2
        echo "$output" >&2
        return 1
    fi

    if ! "$client_path" mcp get "$MCP_NAME" >/dev/null 2>&1; then
        echo "Codex accepted the MCP entry, but it could not be read back." >&2
        return 1
    fi

    echo "Configured Codex (user-level MCP server)."
}

configure_claude() {
    local client_path
    client_path="$(command -v claude 2>/dev/null || true)"
    if [[ -z "$client_path" ]]; then
        echo "Claude Code CLI was requested but was not found on PATH." >&2
        return 1
    fi

    # User scope matches Pen's cross-project integration behavior while keeping
    # Claude's project configuration untouched.
    local old_name
    for old_name in "$MCP_NAME" "${LEGACY_MCP_NAMES[@]}"; do
        "$client_path" mcp remove --scope user "$old_name" >/dev/null 2>&1 || true
    done

    local output
    if ! output=$("$client_path" mcp add --transport stdio --scope user "$MCP_NAME" -- "$LAUNCHER_PATH" --stdio 2>&1); then
        echo "Unable to configure Claude Code:" >&2
        echo "$output" >&2
        return 1
    fi

    if ! "$client_path" mcp get "$MCP_NAME" >/dev/null 2>&1; then
        echo "Claude Code accepted the MCP entry, but it could not be read back." >&2
        return 1
    fi

    echo "Configured Claude Code (user-level MCP server)."
}

for target in "${TARGETS[@]}"; do
    case "$target" in
        codex)
            if configure_codex; then
                configured+=("Codex")
            else
                (( failures += 1 ))
            fi
            ;;
        claude)
            if configure_claude; then
                configured+=("Claude Code")
            else
                (( failures += 1 ))
            fi
            ;;
    esac
done

if (( ${#configured[@]} > 0 )); then
    echo "Start a new ${(j: or :)configured} session to load iCloud Bridge."
fi

if (( failures > 0 )); then
    exit 1
fi
