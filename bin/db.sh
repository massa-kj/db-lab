#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# TODO: engines -> databases
DB_DIR="$ROOT/engines"
cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

ENGINE="${ENGINE:-}"
if [[ -z "${ENGINE}" ]]; then
  if command -v podman >/dev/null 2>&1; then ENGINE="podman"; else ENGINE="docker"; fi
fi
COMPOSE="${ENGINE} compose"

# registry
declare -A DB_ALIASES=()      # e.g. "pg"="postgres"
declare -A DB_FUNCS=()        # e.g. "postgres:cli"="postgres_cli"
declare -A DB_COMPOSE=()      # e.g. "postgres"="engines/postgres/compose.yaml"

# Common Utilities
blue(){ printf "\033[34m%s\033[0m\n" "$*"; }
red(){ printf "\033[31m%s\033[0m\n" "$*"; }

ensure_net() {
  # Docker/Podman common: Create a network with the same name if it does not exist
  local net="${DB_LAB_NETWORK}"
  if ! ${ENGINE} network inspect "$net" >/dev/null 2>&1; then
    ${ENGINE} network create "$net" >/dev/null
  fi
}

# TODO: multi compose
run_compose() {
  local db="$1"; shift
  local file="${DB_COMPOSE[$db]}"
  $COMPOSE -f "$ROOT/$file" "$@"
}

# Registration API called from lib.sh
register_db() {
  local name="$1" compose="$2"; shift 2
  DB_COMPOSE["$name"]="$compose"
}
alias_db() {
  local alias="$1" name="$2"
  DB_ALIASES["$alias"]="$name"
}
register_cmd() {
  local name="$1" sub="$2" func="$3"
  DB_FUNCS["$name:$sub"]="$func"
}

# load libs
for lib in "$DB_DIR"/*/lib.sh; do
  # shellcheck disable=SC1090
  source "$lib"
done

# dispatch
usage() {
  cat <<EOF
Usage: db.sh <command> <db> [args...]

command:    up | down | logs | ps | restart | cli | seed | health | conninfo
db:         $(printf '%s ' "${!DB_COMPOSE[@]}" | sed 's/ $//')

DB Alias:   $(for key in "${!DB_ALIASES[@]}"; do printf '%s=%s ' "$key" "${DB_ALIASES[$key]}"; done)

Examples:
  db.sh up pg
  db.sh cli mysql
  db.sh health redis
EOF
}

# TODO: 
cf() {
  case "$1" in
    pg|postgres) echo "engines/postgres/compose.yaml" ;;
    # mysql)       echo "engines/mysql/compose.yaml" ;;
    # redis)       echo "engines/redis/compose.yaml" ;;
    tools)       echo "tools/compose.yaml" ;;
    *) echo "unknown db: $1"; exit 1 ;;
  esac
}

up()    { $COMPOSE -f "$(cf "$1")" up -d; }
down()  { $COMPOSE -f "$(cf "$1")" down -v; }
logs()  { $COMPOSE -f "$(cf "$1")" logs -f --tail=200; }
ps()    { $COMPOSE -f "$(cf "$1")" ps; }
restart(){ $COMPOSE -f "$(cf "$1")" restart; }

cli() {
  ensure_net

  local cmd
  case "$1" in
    pg|postgres)
      cmd='PGPASSWORD="${PGPASSWORD:-postgres}" psql "postgresql://${PGUSER:-postgres}:${PGPASSWORD:-postgres}@postgres:5432/${PGDATABASE:-postgres}"'
      ;;
    *)
      echo "usage: cli [pg|mysql|redis]" >&2
      return 2
      ;;
  esac

  $COMPOSE -f "$(cf tools)" run --rm db-tools "$cmd"
}

seed() {
  case "$1" in
    pg|postgres)
      $COMPOSE -f "$(cf tools)" run --rm db-tools bash -lc \
        'psql -h ${HOST_BIND:-127.0.0.1} -p ${PGPORT:-55432} -U ${PGUSER:-postgres} -d ${PGDATABASE:-postgres} -f init/postgres/01_schema.sql'
      ;;
    *) red "unknown db: $1"; exit 1 ;;
  esac
}

main() {
  ensure_net

  # parse args
  local sub db
  sub="${1:-}"; shift || true
  db="${1:-}"; [[ -n "$db" ]] && shift || true

  if [[ -z "$sub" || "$sub" == "-h" || "$sub" == "--help" ]]; then
    usage; return 2
  fi

  if [[ -n "$db" && -n "${DB_ALIASES[$db]+_}" ]]; then
    # alias resolution
    db="${DB_ALIASES[$db]}"
  fi

  case "$sub" in
    up|down|logs|ps|restart)
      [[ -z "$db" ]] && { echo "db required"; usage; exit 1; }
      "$sub" "$db"
      ;;
    cli|seed|health|conninfo)
      [[ -z "$db" ]] && { echo "db required"; usage; exit 1; }
      fn="${DB_FUNCS["$db:$sub"]:-}"
      [[ -z "$fn" ]] && { echo "unimplemented: $sub $db"; exit 2; }
      "$fn" "$@"
      ;;
    *) usage ;;
  esac
}

main "$@"

