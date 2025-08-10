# Register the compose path for this DB
register_db "postgres" "engines/postgres/compose.yaml"
# Alias
alias_db "pg" "postgres"

# commands

postgres_cli() {
  cmd='PGPASSWORD="${PGPASSWORD:-postgres}" psql "postgresql://${PGUSER:-postgres}:${PGPASSWORD:-postgres}@postgres:5432/${PGDATABASE:-postgres}"'
  $COMPOSE -f "engines/postgres/cli/compose-cli.yaml" run --rm pg-cli "$cmd"
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

