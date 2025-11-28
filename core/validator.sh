#!/bin/bash

# core/validator.sh - Metadata validation and environment validation
# Validates metadata.yml files and environment variables against engine specifications

set -euo pipefail

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# Validate environment variables against metadata requirements
validate_env_against_metadata() {
    local metadata_file="$1"
    local env_prefix="$2"  # e.g., "DBLAB_PG_"
    
    log_debug "Validating environment against metadata: $metadata_file"
    
    if [[ ! -f "$metadata_file" ]]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    local validation_failed=false
    
    # Check required environment variables
    local required_vars
    required_vars=$(parse_yaml_array "$metadata_file" "required_env")
    
    while IFS= read -r var_name; do
        [[ -z "$var_name" ]] && continue
        
        # Check if variable exists in RESOLVED_ENV array or environment
        local var_value=""
        if [[ -n "${RESOLVED_ENV[$var_name]:-}" ]]; then
            var_value="${RESOLVED_ENV[$var_name]}"
        elif [[ -n "${!var_name:-}" ]]; then
            var_value="${!var_name}"
        fi
        
        if [[ -z "$var_value" ]]; then
            log_error "Required environment variable not set: $var_name"
            validation_failed=true
        fi
    done <<< "$required_vars"
    
    # Apply validation rules if present
    if grep -q "^validation:" "$metadata_file"; then
        if ! _apply_validation_rules "$metadata_file" "$env_prefix"; then
            validation_failed=true
        fi
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        return 1
    fi
    
    log_debug "Environment validation successful against metadata: $metadata_file"
    return 0
}

# Apply specific validation rules from metadata
_apply_validation_rules() {
    local metadata_file="$1"
    local env_prefix="$2"
    
    local validation_rules
    validation_rules=$(parse_yaml_section "$metadata_file" "validation")
    local validation_failed=false
    
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        
        # Remove surrounding quotes from value
        value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//')
        
        case "$key" in
            "user_regex")
                local user_var="${env_prefix}USER"
                local user_value=""
                if [[ -n "${RESOLVED_ENV[$user_var]:-}" ]]; then
                    user_value="${RESOLVED_ENV[$user_var]}"
                elif [[ -n "${!user_var:-}" ]]; then
                    user_value="${!user_var}"
                fi
                
                if [[ -n "$user_value" ]]; then
                    if ! echo "$user_value" | grep -qE "$value"; then
                        log_error "Invalid user format: $user_value (must match: $value)"
                        validation_failed=true
                    fi
                fi
                ;;
            "dbname_regex")
                local db_var="${env_prefix}DATABASE"
                local db_value=""
                if [[ -n "${RESOLVED_ENV[$db_var]:-}" ]]; then
                    db_value="${RESOLVED_ENV[$db_var]}"
                elif [[ -n "${!db_var:-}" ]]; then
                    db_value="${!db_var}"
                fi
                
                if [[ -n "$db_value" ]]; then
                    if ! echo "$db_value" | grep -qE "$value"; then
                        log_error "Invalid database name format: $db_value (must match: $value)"
                        validation_failed=true
                    fi
                fi
                ;;
            "password_min_length")
                local pass_var="${env_prefix}PASSWORD"
                local pass_value=""
                if [[ -n "${RESOLVED_ENV[$pass_var]:-}" ]]; then
                    pass_value="${RESOLVED_ENV[$pass_var]}"
                elif [[ -n "${!pass_var:-}" ]]; then
                    pass_value="${!pass_var}"
                else
                    # Try alternative password variable names
                    pass_var="${env_prefix}SA_PASSWORD"
                    if [[ -n "${RESOLVED_ENV[$pass_var]:-}" ]]; then
                        pass_value="${RESOLVED_ENV[$pass_var]}"
                    elif [[ -n "${!pass_var:-}" ]]; then
                        pass_value="${!pass_var}"
                    fi
                fi
                
                if [[ -n "$pass_value" ]]; then
                    local pass_length=${#pass_value}
                    if [[ "$pass_length" -lt "$value" ]]; then
                        log_error "Password too short: minimum $value characters required"
                        validation_failed=true
                    fi
                fi
                ;;
        esac
    done <<< "$validation_rules"
    
    [[ "$validation_failed" != "true" ]]
}

#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# validator.sh
# -------------------------------------------------------------
# Specialized for semantic validation.
# Loader does syntax/existence checks, validator does semantic checks.
#
# Adopts highly extensible "rule-based validator".
#
# Public functions:
#   validator_check <engine> <verb> <final_assoc> <fixed_assoc>
#
# final_assoc : merge_layers result (final config)
# fixed_assoc : instance.yml fixed attributes (immutable)
#
# =============================================================

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"


# =============================================================
# Internal: validation rule registration (array)
# =============================================================
declare -a VALIDATOR_RULES=()

# register function names
validator_register_rule() {
    VALIDATOR_RULES+=("$1")
}

# =============================================================
# Public: execute all validation
# =============================================================
validator_check() {
    local engine="$1"
    local verb="$2"
    local -n FINAL_CONFIG_REF="$3"
    local -n INSTANCE_FIXED_REF="$4"

    log_debug "[validator] start for engine=$engine verb=$verb"

    local rule
    for rule in "${VALIDATOR_RULES[@]}"; do
        # call rule function
        "$rule" "$engine" "$verb" FINAL_CONFIG_REF INSTANCE_FIXED_REF
    done

    log_debug "[validator] all checks passed"
}


# =============================================================
# ▼▼▼ Rule Definitions (modularized into small functions for easy addition/extension) ▼▼▼
# =============================================================


# -------------------------------------------------------------
# 1. Required fixed attributes existence check (structure guaranteed by loader, semantics here)
# -------------------------------------------------------------
_validate_fixed_required() {
    local engine="$1"
    local verb="$2"
    local -n FINAL="$3"
    local -n FIXED="$4"

    local req_keys=(engine instance version network.mode network.name)
    local key

    for key in "${req_keys[@]}"; do
        if [[ -z "${FIXED[$key]:-}" ]]; then
            log_error "[validator] missing fixed key: $key"
        fi
    done
}
# validator_register_rule "_validate_fixed_required"

# -------------------------------------------------------------
# 2. version.supported (check if defined in metadata)
# -------------------------------------------------------------
_validate_version_supported() {
    local engine="$1"
    local verb="$2"
    local -n FINAL="$3"
    local -n FIXED="$4"

    # metadata_loader が global に展開している想定
    if ! declare -p META_SUPPORTED_VERSIONS &>/dev/null; then
        return 0
    fi

    local ver="${FIXED[version]:-}"
    [[ -z "$ver" ]] && return 0   # May be empty before first up

    # No check needed if supported is empty
    if ((${#META_SUPPORTED_VERSIONS[@]} == 0)); then
        return 0
    fi

    local ok=""
    local idx
    for idx in "${!META_SUPPORTED_VERSIONS[@]}"; do
        if [[ "${META_SUPPORTED_VERSIONS[$idx]}" == "$ver" ]]; then
            ok=1
            break
        fi
    done

    if [[ -z "$ok" ]]; then
        log_error "[validator] version '$ver' is not supported for engine '$engine'"
    fi
}
validator_register_rule "_validate_version_supported"


# -------------------------------------------------------------
# 3. expose × ephemeral contradiction check
# -------------------------------------------------------------
_validate_expose_and_ephemeral() {
    local engine="$1"
    local verb="$2"
    local -n FINAL="$3"

    local ep="${FINAL[DBLAB_EPHEMERAL]:-false}"
    local expose_enabled="${FINAL[runtime.expose.enabled]:-false}"

    if [[ "$expose_enabled" == "true" && "$ep" == "true" ]]; then
        log_error "[validator] cannot expose ports in ephemeral mode"
    fi
}
validator_register_rule "_validate_expose_and_ephemeral"


# -------------------------------------------------------------
# 4. Port range check (port on env/runtime side)
# -------------------------------------------------------------
_validate_port_range() {
    local engine="$1"
    local verb="$2"
    local -n FINAL="$3"

    local port="${FINAL[db.port]:-}"
    if [[ -z "$port" ]]; then return 0; fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        log_error "[validator] invalid port (non-number): $port"
    fi

    if ((port < 1 || port > 65535)); then
        log_error "[validator] port out of range (1-65535): $port"
    fi
}
validator_register_rule "_validate_port_range"


# -------------------------------------------------------------
# 5. Expose port list format check (simple)
#    Format: "15432:5432"
# -------------------------------------------------------------
_validate_expose_ports_format() {
    local engine="$1"
    local verb="$2"
    local -n FINAL="$3"

    local ports="${FINAL[runtime.expose.ports]:-}"

    [[ -z "$ports" || "$ports" == "[]" ]] && return 0

    # ports are assumed to be comma-separated or single string for simple processing
    local p
    IFS=',' read -ra arr <<<"$ports"
    for p in "${arr[@]}"; do
        if ! [[ "$p" =~ ^[0-9]+:[0-9]+$ ]]; then
            log_error "[validator] invalid expose port mapping: '$p'"
        fi
    done
}
validator_register_rule "_validate_expose_ports_format"


# -------------------------------------------------------------
# 6. Check if instance exists during down (determined by fixed keys)
# -------------------------------------------------------------
_validate_down_requires_instance() {
    local engine="$1"
    local verb="$2"
    local -n FIXED="$4"

    if [[ "$verb" == "down" ]]; then
        if [[ -z "${FIXED[engine]:-}" || -z "${FIXED[instance]:-}" ]]; then
            log_error "[validator] cannot down: instance does not exist"
        fi
    fi
}
validator_register_rule "_validate_down_requires_instance"


# -------------------------------------------------------------
# 7. network.mode validity check
# -------------------------------------------------------------
_validate_network_mode() {
    local engine="$1"
    local verb="$2"
    local -n FIXED="$4"

    local mode="${FIXED[network.mode]:-}"

    case "$mode" in
        isolated|engine-shared)
            return 0 ;;
        *)
            log_error "[validator] invalid network.mode: $mode"
            ;;
    esac
}
validator_register_rule "_validate_network_mode"
