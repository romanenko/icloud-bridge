#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIRECTORY="$(mktemp -d -t icloud-bridge-integration-tests)"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

mkdir -p "$TEST_DIRECTORY/bin" "$TEST_DIRECTORY/home"
ln -s "$ROOT_DIR/Tests/Installation/fixtures/mock-mcp-client.sh" "$TEST_DIRECTORY/bin/codex"
ln -s "$ROOT_DIR/Tests/Installation/fixtures/mock-mcp-client.sh" "$TEST_DIRECTORY/bin/claude"
cp "$ROOT_DIR/Packaging/icloud-bridge-launcher.sh" "$TEST_DIRECTORY/icloud-bridge"
chmod 755 "$TEST_DIRECTORY/icloud-bridge"

CALL_LOG="$TEST_DIRECTORY/calls.log"
HOME="$TEST_DIRECTORY/home" \
PATH="$TEST_DIRECTORY/bin:/usr/bin:/bin" \
MOCK_CALL_LOG="$CALL_LOG" \
    zsh "$ROOT_DIR/scripts/configure-integrations.sh" \
        --all \
        --launcher "$TEST_DIRECTORY/icloud-bridge"

expected_calls=(
    $'codex\tmcp\tremove\ticloud-bridge'
    $'codex\tmcp\tremove\ticloud_bridge'
    $'codex\tmcp\tadd\ticloud-bridge\t--\t'"$TEST_DIRECTORY"$'/icloud-bridge\t--stdio'
    $'codex\tmcp\tget\ticloud-bridge'
    $'claude\tmcp\tremove\t--scope\tuser\ticloud-bridge'
    $'claude\tmcp\tremove\t--scope\tuser\ticloud_bridge'
    $'claude\tmcp\tadd\t--transport\tstdio\t--scope\tuser\ticloud-bridge\t--\t'"$TEST_DIRECTORY"$'/icloud-bridge\t--stdio'
    $'claude\tmcp\tget\ticloud-bridge'
)

for expected_call in "${expected_calls[@]}"; do
    if ! grep -Fqx "$expected_call" "$CALL_LOG"; then
        echo "Missing expected client invocation: $expected_call" >&2
        exit 1
    fi
done

if HOME="$TEST_DIRECTORY/home" PATH="/usr/bin:/bin" \
    zsh "$ROOT_DIR/scripts/configure-integrations.sh" \
        --codex \
        --launcher "$TEST_DIRECTORY/icloud-bridge" >/dev/null 2>&1; then
    echo "An explicitly requested missing client should fail." >&2
    exit 1
fi

auto_output=$(HOME="$TEST_DIRECTORY/home" PATH="/usr/bin:/bin" \
    zsh "$ROOT_DIR/scripts/configure-integrations.sh" \
        --launcher "$TEST_DIRECTORY/icloud-bridge")
if [[ "$auto_output" != *"registration was skipped"* ]]; then
    echo "Automatic detection should explain when no supported client exists." >&2
    exit 1
fi

echo "Integration installer tests passed."
