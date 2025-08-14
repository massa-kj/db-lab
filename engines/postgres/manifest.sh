# Default version and capabilities declaration
: "${POSTGRES_VER_DEFAULT:=16}"

# Version resolution (finalize core DBLAB_VER to match PG)
: "${PG_VER:=${DBLAB_VER:-$POSTGRES_VER_DEFAULT}}"

