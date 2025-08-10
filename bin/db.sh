#!/usr/bin/env bash
set -euo pipefail

ENGINE="${ENGINE:-}"
if [[ -z "${ENGINE}" ]]; then
  if command -v podman >/dev/null 2>&1; then ENGINE="podman"; else ENGINE="docker"; fi
fi
COMPOSE="${ENGINE} compose"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# red(){ printf "\033[31m%s\033[0m\n" "$*"; }

cf() {
  case "$1" in
    pg|postgres) echo "engines/postgres/compose.yaml" ;;
    # mysql)       echo "engines/mysql/compose.yaml" ;;
    # redis)       echo "engines/redis/compose.yaml" ;;
    tools)       echo "tools/compose.yaml" ;;
    *) echo "unknown db: $1"; exit 1 ;;
  esac
}

ensure_net() {
  # Docker/Podman common: Create a network with the same name if it does not exist
  if ! ${ENGINE} network inspect db-lab-net >/dev/null 2>&1; then
    ${ENGINE} network create db-lab-net >/dev/null
  fi
}

up()    { ensure_net; $COMPOSE -f "$(cf "$1")" up -d; }
down()  { $COMPOSE -f "$(cf "$1")" down -v; }

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

help() {
  cat <<'H'
Usage: ./bin/db <cmd> <db>
  cmds: up | down | logs | ps | restart | cli | seed | conninfo
  db  : pg | mysql | redis
Examples:
  ./bin/db up pg
  ./bin/db cli mysql
H
}

cmd="${1:-help}"; db="${2:-}"
case "$cmd" in
  up|down|logs|ps|restart|cli|seed|conninfo)
    [[ -z "$db" ]] && { red "db required"; help; exit 1; }
    "$cmd" "$db"
    ;;
  *) help ;;
esac

