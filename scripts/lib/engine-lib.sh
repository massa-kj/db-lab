ensure_network() {
    if ! ${DBLAB_RUNTIME} network inspect "${DBLAB_NETWORK_NAME}" >/dev/null 2>&1; then
        ${DBLAB_RUNTIME} network create "${DBLAB_NETWORK_NAME}" >/dev/null
    fi
}

compose() { ${DBLAB_RUNTIME} compose "$@"; }
ctr_exec(){ ${DBLAB_RUNTIME} exec "$@"; }

