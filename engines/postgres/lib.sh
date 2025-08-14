# Register the compose path for this DB
register_db "postgres" "engines/postgres/compose.yaml"

# commands

postgres_cli() {
  cmd='PGPASSWORD="${PGPASSWORD:-postgres}" psql "postgresql://${PGUSER:-postgres}:${PGPASSWORD:-postgres}@postgres:5432/${PGDATABASE:-postgres}"'
  run_compose postgres --profile cli run --rm cli "$cmd"
}

postgres_health() {
  run_compose postgres run --rm --no-deps postgres \
    pg_isready -h ${HOST_BIND:-postgres} -p ${PGPORT:-5432} -U "${PGUSER:-postgres}" -d "${PGDATABASE:-postgres}"
}

postgres_conninfo() {
  echo "postgresql://${PGUSER:-postgres}:${PGPASSWORD:-postgres}@${HOST_BIND:-127.0.0.1}:${PGPORT:-55432}/${PGDATABASE:-postgres}"
}

register_cmd "postgres" "cli" "postgres_cli"
register_cmd "postgres" "health" "postgres_health"
register_cmd "postgres" "conninfo" "postgres_conninfo"

