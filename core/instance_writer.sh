#!/usr/bin/env bash
set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"

# ---------------------------------------------------------
# instance_writer.sh
# -------------------
#  - Dedicated to instance.yml generation and updates
#  - Separated from loader; only writer has side effects
#
# Prerequisites:
#   - yaml_parse_file <path> <assoc_name>
#   - yaml_render_assoc <assoc_name>
#   - Use log/info/error from lib.sh if available (otherwise keep to echo)
#
# Metadata integration:
#   - db.* varies by engine, so defined in metadata.yml
#   - metadata_loader side builds "array of db.* keys" and
#     passes it as the 2nd argument to instance_writer_create_initial
# ---------------------------------------------------------

# Current time (ISO8601)
_now_iso() {
    date -Iseconds
}

# Instance file path
_instance_file() {
    local engine="$1"
    local instance="$2"
    echo "${HOME}/.local/share/dblab/${engine}/${instance}/instance.yml"
}

# ---------------------------------------------------------
# instance_file_exists
# ---------------------------------------------------------
# Public function to check if instance.yml exists
# ---------------------------------------------------------
instance_file_exists() {
    local engine="$1"
    local instance="$2"
    local file
    file="$(_instance_file "$engine" "$instance")"
    [[ -f "$file" ]]
}

# ---------------------------------------------------------
# instance_writer_create_initial
# ---------------------------------------------------------
# On initial generation, write immutable attributes + semi-immutable attributes + initial state
# Idempotency: if instance.yml already exists, do nothing
#
# @param cfg_array_name       # Final CFG after merge_layers + validation (declare -A)
# @param db_fields_array_name # Full key name array like "db.user" (from metadata)
#
# Example:
#   declare -A CFG=(
#     [engine]="postgres"
#     [instance]="pg16"
#     [version]="16"
#     [image]="postgres:16"
#     [db.user]="postgres"
#     [db.password]="secret"
#     [db.database]="app"
#     [db.port]="5432"
#     [storage.persistent]="true"
#     [storage.data_dir]="/home/.../data"
#     [storage.config_dir]="/home/.../config"
#     [network.mode]="isolated"
#     [network.name]="dblab_postgres_pg16_net"
#   )
#
#   DB_FIELDS=( "db.user" "db.password" "db.database" "db.port" )
#
#   instance_writer_create_initial CFG DB_FIELDS
# ---------------------------------------------------------
instance_writer_create_initial() {
    local cfg_name="$1"
    local db_fields_name="$2"

    # Reference original associative array/array with nameref
    local -n cfg="$cfg_name"
    local -n db_fields="$db_fields_name"

    # Get engine and instance from CFG
    local engine="${cfg[engine]:-}"
    local instance="${cfg[instance]:-}"
    
    # Validate required fields
    if [[ -z "$engine" ]]; then
        echo "[instance_writer] ERROR: engine not specified in CFG" >&2
        return 1
    fi
    if [[ -z "$instance" ]]; then
        echo "[instance_writer] ERROR: instance not specified in CFG" >&2
        return 1
    fi

    local file
    file="$(_instance_file "$engine" "$instance")"
    
    # Idempotency check: if file already exists, do nothing
    if [[ -f "$file" ]]; then
        return 0
    fi

    mkdir -p "$(dirname "$file")"

    # New associative array for building YAML
    declare -A inst=()

    # --- Essential immutable attributes ---
    inst[engine]="$engine"
    inst[instance]="$instance"

    if [[ -n "${cfg[db.version]+_}" ]]; then
        inst[version]="${cfg[db.version]}"
    fi
    if [[ -n "${cfg[image]+_}" ]]; then
        inst[image]="${cfg[image]}"
    fi
    inst[created]="$(_now_iso)"

    for field in "${db_fields[@]}"; do
        if [[ -n "${cfg[$field]+_}" ]]; then
            inst["$field"]="${cfg[$field]}"
        else
            # Whether it's required is the responsibility of metadata/validator side,
            # so do nothing here even if it doesn't exist (don't error)
            :
        fi
    done

    # --- storage (currently treated as fixed schema common to all engines) ---
    if [[ -n "${cfg[storage.persistent]+_}" ]]; then
        inst[storage.persistent]="${cfg[storage.persistent]}"
    fi
    if [[ -n "${cfg[storage.data_dir]+_}" ]]; then
        inst[storage.data_dir]="${cfg[storage.data_dir]}"
    fi
    if [[ -n "${cfg[storage.config_dir]+_}" ]]; then
        inst[storage.config_dir]="${cfg[storage.config_dir]}"
    fi
    if [[ -n "${cfg[storage.log_dir]+_}" ]]; then
        inst[storage.log_dir]="${cfg[storage.log_dir]}"
    fi

    # --- network (semi-immutable: mode changed by dedicated command, name is immutable) ---
    if [[ -n "${cfg[network.mode]+_}" ]]; then
        inst[network.mode]="${cfg[network.mode]}"
    fi
    if [[ -n "${cfg[network.name]+_}" ]]; then
        inst[network.name]="${cfg[network.name]}"
    fi

    # --- runtime.* not saved here as policy ---
    #   ※ Each expose/resources managed by profile env.
    #   ※ If we want to save in future, can add runtime_fields definition to metadata side,
    #      and iterate similar to db_fields.

    # --- state initialization ---
    inst[state.last_up]=""
    inst[state.last_down]=""
    inst[state.last_cli]=""
    inst[state.last_health]=""

    # YAML save
    _save_assoc "$file" inst
}

# ---------------------------------------------------------
# update_state_up
# ---------------------------------------------------------
update_state_up() {
    local engine="$1"
    local instance="$2"
    # TODO: Modify to allow setting multiple values at once
    update_state "$engine" "$instance" "last_up" "$(_now_iso)"
    update_state "$engine" "$instance" "status" "running"
}

# ---------------------------------------------------------
# update_state_down
# ---------------------------------------------------------
update_state_down() {
    local engine="$1"
    local instance="$2"
    update_state "$engine" "$instance" "last_down" "$(_now_iso)"
    update_state "$engine" "$instance" "status" "stopped"
}

# ---------------------------------------------------------
# update_state
# ---------------------------------------------------------
# Update arbitrary state key
#
# @param engine
# @param instance
# @param key   # Example: last_cli
# @param value
# ---------------------------------------------------------
# TODO: Modify to allow setting multiple values at once
update_state() {
    local engine="$1"
    local instance="$2"
    local state_key="$3"
    local value="$4"

    local file
    file="$(_instance_file "$engine" "$instance")"

    if [[ ! -f "$file" ]]; then
        echo "[instance_writer] instance.yml not found: $file" >&2
        return 1
    fi

    declare -A inst=()
    yaml_parse_file "$file" inst

    inst["state.${state_key}"]="$value"

    _save_assoc "$file" inst
}

# ---------------------------------------------------------
# update_network_mode (Dedicated update API for semi-immutable attributes)
# ---------------------------------------------------------
update_network_mode() {
    local engine="$1"
    local instance="$2"
    local mode="$3"

    local file
    file="$(_instance_file "$engine" "$instance")"

    if [[ ! -f "$file" ]]; then
        echo "[instance_writer] instance.yml not found: $file" >&2
        return 1
    fi

    declare -A inst=()
    yaml_parse_file "$file" inst

    inst[network.mode]="$mode"

    _save_assoc "$file" inst
}

# ---------------------------------------------------------
# update_runtime_value (OPTIONAL)
# ---------------------------------------------------------
# Use only when you want to save runtime.*.
# Normally unused as current spec recommends profile env.
# ---------------------------------------------------------
update_runtime_value() {
    local engine="$1"
    local instance="$2"
    local key="$3"    # Example: "expose.ports"
    local value="$4"  # "15432:5432"

    local file
    file="$(_instance_file "$engine" "$instance")"
    if [[ ! -f "$file" ]]; then
        echo "[instance_writer] instance.yml not found: $file" >&2
        return 1
    fi

    declare -A inst=()
    yaml_parse_file "$file" inst

    inst["runtime.${key}"]="$value"

    _save_assoc "$file" inst
}

# ---------------------------------------------------------
# _save_assoc (internal use)
# ---------------------------------------------------------
# Save given associative array as YAML to file
# Safe update with atomic write (tmp → mv)
#
# @param file
# @param assoc_name  # declare -A assoc_name
# ---------------------------------------------------------
_save_assoc() {
    local file="$1"
    local assoc_name="$2"

    local tmp="${file}.tmp"

    # Reference original associative array with nameref
    local -n data="$assoc_name"

    {
        echo "# Auto-generated by dblab instance_writer"
        echo "# Do not edit manually unless you know what you are doing."
        echo
        yaml_render_assoc data
    } > "$tmp"

    mv "$tmp" "$file"
}
