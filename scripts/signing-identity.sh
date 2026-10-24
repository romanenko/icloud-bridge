#!/bin/zsh

# Sets SIGNING_IDENTITY to a certificate SHA-1, avoiding ambiguous names across teams.
select_signing_identity() {
    local requested="${1:-}" identity_output line fingerprint name choice
    local -a fingerprints=() names=() matches=()
    identity_output="$(security find-identity -v -p codesigning)" || return 1
    while IFS= read -r line; do
        if [[ "$line" == *'"Apple Development:'* || "$line" == *'"Developer ID Application:'* ]]; then
            fingerprint="$(print -r -- "$line" | awk '{print $2}')"
            name="${line#*\"}"
            name="${name%%\"*}"
            fingerprints+=("$fingerprint")
            names+=("$name")
        fi
    done <<< "$identity_output"

    if (( ${#fingerprints} == 0 )); then
        echo "No Apple Development or Developer ID Application signing identity is available." >&2
        return 1
    fi

    if [[ -n "$requested" ]]; then
        for (( choice=1; choice<=${#fingerprints}; choice++ )); do
            if [[ "$requested" == "${names[$choice]}" || "${requested:u}" == "${fingerprints[$choice]:u}" ]]; then
                matches+=("$choice")
            fi
        done
        if (( ${#matches} != 1 )); then
            echo "Signing identity must match exactly one available certificate name or SHA-1: $requested" >&2
            printf '  %s\n' "${identity_output}" >&2
            return 1
        fi
        choice="${matches[1]}"
    elif (( ${#fingerprints} == 1 )); then
        choice=1
    else
        echo "Available signing identities:" >&2
        for (( choice=1; choice<=${#fingerprints}; choice++ )); do
            printf '  %d) %s [%s]\n' "$choice" "${names[$choice]}" "${fingerprints[$choice]}" >&2
        done
        if [[ ! -t 0 ]]; then
            echo "Multiple identities found. Set --signing-identity NAME_OR_SHA1 or CALENDAR_BRIDGE_SIGNING_IDENTITY." >&2
            return 1
        fi
        while true; do
            printf 'Choose a signing identity [1-%d]: ' "${#fingerprints}" >&2
            IFS= read -r choice || return 1
            if [[ "$choice" == <-> ]] && (( ${#choice} <= 4 && choice >= 1 && choice <= ${#fingerprints} )); then
                break
            fi
            echo "Enter a number from the list (Ctrl-D to cancel)." >&2
        done
    fi
    SIGNING_IDENTITY="${fingerprints[$choice]}"
    echo "Signing with ${names[$choice]} [$SIGNING_IDENTITY]" >&2
}
