#!/bin/zsh
set -eu

client_name="${0:t}"
{
    printf '%s' "$client_name"
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "$MOCK_CALL_LOG"

exit 0
