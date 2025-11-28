#!/usr/bin/env bash
set -euo pipefail

#
# config_interpolator.sh
# -----------------------
# Expands all template strings `{...}` contained in FINAL_CONFIG (CFG).
# Must be called directly after merge_layers, before validator.
#

# Well-known vars for expansion (add as needed)
# Configured to be resilient for future OS/runtime portability
declare -A CONFIG_INTERP_ENV_PRESET=(
    ["XDG_DATA_HOME"]="${XDG_DATA_HOME:-$HOME/.local/share}"
    ["XDG_CONFIG_HOME"]="${XDG_CONFIG_HOME:-$HOME/.config}"
    ["HOME"]="$HOME"
    ["USER"]="$USER"
)

# Internal function: expand a single value
config_interpolate_value() {
    local -n __C="$1"
    local value="$2"

    #
    # 1. preset expansion ({XDG_DATA_HOME} etc.)
    #
    for k in "${!CONFIG_INTERP_ENV_PRESET[@]}"; do
        value="${value//\{$k\}/${CONFIG_INTERP_ENV_PRESET[$k]}}"
    done

    #
    # 2. {env:VAR} expansion
    #
    local pattern
    while [[ "$value" =~ \{env:([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        pattern="${BASH_REMATCH[1]}"
        value="${value//\{env:$pattern\}/${!pattern:-}}"
    done

    #
    # 3. CFG[key] expansion ({engine}, {instance}, {db.user}, etc)
    #
    # Note: Supports keys containing dots due to flat-key format
    #
    local key
    for key in "${!__C[@]}"; do
        # Replace if key with same name exists in {}
        value="${value//\{$key\}/${__C[$key]}}"
    done

    #
    # 4. bash variable expansion (${HOME} etc)
    #    - Explicitly avoid eval (security)
    #    - Limited expansion for `${VAR}` patterns only
    #
    while [[ "$value" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        local var="${BASH_REMATCH[1]}"
        local val="${!var:-}"
        value="${value//\$\{$var\}/$val}"
    done

    printf '%s' "$value"
}

#
# config_interpolator C
# → Destructively updates the entire CFG (assoc-array)
#
config_interpolator() {
    local -n C="$1"

    local key
    for key in "${!C[@]}"; do
        C[$key]="$(config_interpolate_value C "${C[$key]}")"
    done
}
