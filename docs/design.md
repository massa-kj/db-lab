# Design

## Project Scope

* **Supported DB Engines**: PostgreSQL, MySQL, Redis, MongoDB, SQL Server, Oracle, SQLite
* **Container Runtime**: Podman, Docker (Podman as primary)
* **Intended Use Cases**:
  * Connect and operate databases launched in containers or existing databases
    * Manage independent containers for each engine & profile (env, future yaml), operations through CLI/GUI
      * (Depending on engine) Enable CLI and GUI to be launched as containerized services
    * Launch only CLI or GUI containers to verify and operate against real databases
  * Switch and compare different versions of engines
    * Verification of DB engine version upgrades, etc.
  * Sequential execution of SQL files in specified folders, or direct query execution

---

## System Design

### Directory Structure

```
dblab
├── engines/            # Per-engine definitions
│   ├── postgres/
│   │   ├── README.md
│   │   ├── compose.tmpl.yaml
│   │   ├── default.env
│   │   ├── schema.yaml
│   │   ├── lib.sh      # Loaded only during target engine execution. Common library loading, etc. commands/* source this
│   │   ├── meta.sh     # Loaded for all engines during command execution. Registers aliases, etc.
│   │   ├── cli.Dockerfile
│   │   └── commands/
│   │       ├── up
│   │       ├── down
│   │       ├── cli
│   │       ├── seed
│   │       └── health
│   ├── mysql/
│   ├── redis/
│   ├── mongodb/
│   ├── sqlserver/
│   ├── oracle/
│   └── sqlite/
├── commands/
│   ├── manage
│   └── ...
├── common/
│   ├── lib/
│   │   ├── logger.sh
│   │   ├── engine-lib.sh
│   │   ├── env-loader.sh
│   │   ├── env-validator.sh   # env schema validation
│   │   ├── registry.sh     # API for alias registration etc.
│   │   ├── resolver.sh     # Command resolution
│   │   └── ...
│   └── commands/           # Fallback common commands
│       ├── ps
│       ├── up
│       └── down
├── scripts/
│   └── install.sh
├── docs
│   └── design.md       # (this file)
├── default.env
│── dblab.sh            # Entry point
└── README.md
```

```txt
~
├── .config/
│   └── dblab/          # User overrides (not committed)
│       ├── common.env
│       ├── {profile}.env    # Instance-specific environment settings
│       └── plugins/         # User extension plugins
│           └── {engine}/
│               └── commands/
├── .local/
│   └── share/
│       └── dblab/
│           ├── registry.yaml      # Instance registration information
│           └── {engine}/
│               └── {instance}/
│                   └── data/      # Data persistence
```

### Core Components

* **dblab.sh**:
  Entry point.
  Execution format 1: `db {engine} {command} [args...]`
  Execution format 2: `db {command} [args...]`

* **engines/**:
  Manages compose, env, commands per engine unit.
  Engine additions are also performed at this granularity.

* **lib/**:
  Common function group. Responsible for:

  * Command registration and dispatch
  * Network existence guarantee
  * Automatic help generation

Additional responsibilities:

* Compose file generation: Add `generate_compose_file()` to `engine-lib.sh` to generate compose per instance from template
* Env schema validation: Add `env-validator.sh` to perform validation based on `engines/{engine}/schema.yaml`
* Dynamic registry: `registry.sh` can register and deregister per instance at runtime

### Engine Command Resolution Order

Complete resolution order considering instance identifiers and plugin ecosystem:

1. `$XDG_CONFIG_HOME/dblab/plugins/{engine}/commands/{cmd}` (User extension plugins)
2. `engines/{engine}/commands/{cmd}` (Engine-specific implementation)
3. `common/commands/{cmd}` (Thin difference absorption across engines)

## Load environment variables

1. Direct command line specification (`VAR=... db ...`)
2. `db {engine} {command} --profile {profile_path}`: Additional env definition at startup
3. `$XDG_CONFIG_HOME/dblab/{profile}.env`: Profile-specific settings
4. `$XDG_CONFIG_HOME/dblab/common.env`: User common settings
5. `engines/{engine}/default.env`: Default definition per engine
6. `default.env`: System common default definition
   - Is this design good for the purpose of "eliminating in-code defaults"?
   - Consider "schema + validation"?
     - Define **required/optional/type/allowed values** (e.g., YAML/JSON/TOML any format).
     - Validate at runtime and **immediately error exit if missing/invalid** (don't "automatically make it nice").

* Basically use `DBLAB_*` for collision avoidance, engine-specific ones are `DBLAB_PG_* / DBLAB_MYSQL_* / DBLAB_REDIS_* ...`

### Instance Identifier (instance)

To run multiple instances on the same host, we introduce explicit instance identifiers. Main variables:

```sh
DBLAB_ENGINE=postgres
DBLAB_INSTANCE=pg16-test   # Instance identifier
DBLAB_PROFILE=$XDG_CONFIG_HOME/dblab/pg16-test.env
```

Generated compose and resources use this `INSTANCE` for naming to avoid collisions. Example:

```yaml
services:
  db:
    container_name: "${DBLAB_ENGINE}_${DBLAB_INSTANCE}_db"
    networks:
      - "${DBLAB_NETWORK:-$(resolve_network_name)}"
volumes:
  - "${XDG_DATA_HOME:-~/.local/share}/dblab/${DBLAB_ENGINE}/${DBLAB_INSTANCE}/data:/var/lib/postgresql/data"
```

Here `resolve_network_name()` determines network names based on `DBLAB_NETWORK_STRATEGY`:

```sh
resolve_network_name() {
  # Priority to DBLAB_NETWORK if explicitly specified
  if [[ -n "${DBLAB_NETWORK}" ]]; then
    echo "${DBLAB_NETWORK}"
    return
  fi
  
  # If DBLAB_NETWORK is not specified, determine according to STRATEGY
  case "${DBLAB_NETWORK_STRATEGY:-isolated}" in
    "isolated")
      echo "dblab_${DBLAB_ENGINE}_${DBLAB_INSTANCE}_net"
      ;;
    "engine-shared")
      echo "dblab_${DBLAB_ENGINE}_shared_net"
      ;;
    "shared")
      echo "dblab_shared_net"
      ;;
    *)
      echo "dblab_${DBLAB_ENGINE}_${DBLAB_INSTANCE}_net"
      ;;
  esac
}
```

Common commands like `dblab ps` and `dblab down` can operate with `(engine, instance)` pairs.

---

## Command Design

* 1 command = 1 executable file
  → Any language (shell / Rust / Python etc. can be mixed)
* Common commands: `up, down, logs, ps, restart`
  If individual engines don't have these implementations, common implementation resolves
* Engine-specific: `cli, gui, exec, health, conninfo, migrate, ...`

### Usage

#### Basic

```sh
dblab {engine} {command} [args...]
```

- command is an executable file placed in `engines/{engine}/commands/` per engine
- Custom commands can be prepared, but basic commands require contracts

#### Common Options

* `--profile {file|dir}` Specify additional env file/directory (multiple allowed)
* `--instance {id}` Instance specification (same as `DBLAB_INSTANCE`)
* `--engine {engine}` Explicit engine specification (same as `DBLAB_ENGINE`)

### Basic Command Contracts

**up**:
- Start the engine

**down**:
- Stop the engine

**cli**:
- Start CLI container for target engine
- Tool execution options, shell login options

**shell**
- Shell login to specified container

---

## Networking

* Common management of container networks
* Existence guarantee with `ensure_network()` function
* Not yet fully defined. Need to consider including security.

### Network naming and exposure rules

* **Default network name** reflects instance isolation: `dblab_${ENGINE}_${INSTANCE}_net`
* **Network sharing**: Can be explicitly specified with `DBLAB_NETWORK` environment variable
* **Network strategy**:
  - `isolated` (default): Isolated per instance
  - `shared`: Share specified network
  - `engine-shared`: Share between instances of the same engine (`dblab_${ENGINE}_shared_net`)
* CLI/GUI containers are placed on the same network in principle
* External port exposure is disabled by default (`DBLAB_EXPOSE_PORTS=false`). Add `-p` only when explicitly specifying `--expose` or `DBLAB_EXPOSE_PORTS=true`
* Implement Podman and Docker difference absorption in `engine-lib.sh`. Prioritize Podman, use Docker if not present

#### Network Configuration Examples

```sh
# 1. Isolated (default)
# Specify nothing, or explicitly specify
DBLAB_NETWORK_STRATEGY=isolated
# Result: dblab_postgres_pg16_net, dblab_postgres_pg15_net (independent)

# 2. Shared within same engine
DBLAB_NETWORK_STRATEGY=engine-shared
# Result: dblab_postgres_shared_net (pg16, pg15 on same network)

# 3. System shared network (default name)
DBLAB_NETWORK_STRATEGY=shared
# Result: dblab_shared_net (all instances on same network)

# 4. Custom network specification (simplest)
DBLAB_NETWORK=my_custom_network
# Result: my_custom_network (no STRATEGY specification needed)

# 5. Join existing external network
DBLAB_NETWORK=app_network
# Result: app_network (use existing network)
```

**Priority**: `DBLAB_NETWORK` > `DBLAB_NETWORK_STRATEGY` > default(isolated)

---

## Usage Flow (Internal)

```sh
# Start PostgreSQL (default instance, isolated network)
db postgres up

# Start PostgreSQL (specified instance, isolated network)
db postgres up --instance pg16-test

# Start PostgreSQL (shared network within same engine)
DBLAB_NETWORK_STRATEGY=engine-shared db postgres up --instance pg16-test

# Start PostgreSQL (custom network)
DBLAB_NETWORK=dev_network db postgres up --instance pg16-test

# Start multiple instances on same network
DBLAB_NETWORK=shared_dev_net db postgres up --instance pg16
DBLAB_NETWORK=shared_dev_net db mysql up --instance mysql8

# Start Redis CLI
db redis cli

# Start CLI for specified instance
db postgres cli --instance pg16-test

# Execute SQL files (multiple files or directory)
db postgres exec ./init --instance pg16-test

# Start with profile specification
db postgres up --profile ~/.config/dblab/my-pg-config.env
```

---

## Extensibility

* **Engine Addition Procedure**

  1. Create `engines/{engine}/`
  2. Place `compose.tmpl.yaml` / `default.env` / `schema.yaml` / `commands/`
  3. Register in `registry.sh`
* **Command Addition**
  Add executable file to `engines/{engine}/commands/`
  Automatically reflected in help

* **Plugin Placement Rules (User Extensions)**

  Search order:

  1. `$XDG_CONFIG_HOME/dblab/plugins/{engine}/commands/{cmd}` (User plugins)
  2. `engines/{engine}/commands/{cmd}` (Core engine implementation)
  3. `common/commands/{cmd}` (Common implementation)

  This ensures priority of external plugins while maintaining compatibility with core implementation.

* **Default Instance**

  Use `default` instance when `DBLAB_INSTANCE` is not specified.
  This maintains backward compatibility with existing commands like `db postgres up`.

---

## Future Notes (TBD・Memo)

* CI: Startup verification for each engine & command smoke test
* GUI containers (pgAdmin, Adminer, etc.)
* SQL Server / Oracle specific constraints → Specify `MSSQL_PID`, license notation in `README.md`
* Documentation of Podman/Docker difference absorption layer (especially networking)

---

### Roadmap

* **Container Orchestration**

  * Kubernetes Support

    * Automatic manifest generation with `Helm chart` and `Kustomize`
    * Enable each DB engine to start with StatefulSet / Deployment
    * Assume two-tier configuration: Podman/Docker Compose for development, k8s for production/verification

* **Infrastructure as Code (IaC)**

  * External resource management with Terraform / Pulumi

    * RDS, Aurora, Azure SQL, Oracle Cloud DB, etc.
    * Consider mechanism to absorb differences between `.env` and IaC
  * Assume GitOps-style operation and integrate with CI/CD pipeline

* **CI/CD Enhancement**

  * Automate **smoke test** for each engine with GitHub Actions or GitLab CI
  * Verify DB startup and basic operations during Pull Requests
  * Version upgrade detection (automatically verify when new DB containers are released)

* **Security / Licensing**

  * Explicitly manage license modes for SQL Server / Oracle
  * Integrate security scanning (Trivy, Grype) into CI
  * Policy-based enforcement of `0.0.0.0` bind prohibition rules

* **Extensibility**

  * GUI tool integration (pgAdmin, Adminer, Mongo Express, Redis Insight)
  * External engine addition through `db plugins` mechanism (users can extend independently)
  * Standardization of test data generation and seeding mechanisms

* **Future Development Ideas**

  * WASM-based lightweight client (CLI-equivalent operations from Web)
  * AI-assisted SQL execution and verification (natural language → SQL)
  * Metrics monitoring in collaboration with Observability (Prometheus/Grafana)

### Interactive Management (`db manage`)

**Purpose**: State visualization and operation aggregation across engines and containers (both TUI/non-interactive modes).
**Principle**: Use existing `db {engine} {command}` as the *sole foundation*, and `manage` focuses on being a *thin UI that calls them*.

**Modes**
- TUI: MVP based on `fzf`. Future option for Rust implementation with `ratatui`, etc.
- Non-interactive: `db manage --mode=list --format json` (for CI/automation)

**Representative Subcommands**
- List/Filter: `--filter "engine=postgres,version=16"`
- Batch Apply: `--apply up|down|restart|logs|cli|seed|health|sql`
- Safety Guard: Destructive operations require `--yes`. Warn when `0.0.0.0` is detected.

**Dependencies and Abstraction**
- Container backend switches with `CONTAINER_BACKEND={docker|podman}`, uses only abstract API of `common/lib`.
- Network creation only allowed through `ensure_network()`. Independent creation is prohibited.
- Instance management only through `registry.sh` API.

### Registry / Completion metadata

* `registry.sh` enables holding runtime information per engine and instance in YAML/JSON (`$XDG_DATA_HOME/dblab/registry.yaml`)

  Registration example:

  ```yaml
  postgres:
    pg16-test:
      container_id: abc123
      network: dblab_postgres_pg16-test_net
      port: 5432
    pg15:
      container_id: def456
  ```

* Metadata registration API for completion and help:

  ```bash
  registry_register "postgres" "up" "Start PostgreSQL container"
  registry_register "postgres" "cli" "Open psql session"
  ```

  This enables automatic alignment of command descriptions in `db --help` and shell completion.

### Env schema validation

* Place `schema.yaml` in each engine. Example:

  ```yaml
  required:
    - DBLAB_PG_VERSION
    - DBLAB_PG_PORT
  optional:
    - DBLAB_PG_VOLUME
  types:
    DBLAB_PG_PORT: int
  dependencies:
    - if: DBLAB_USE_SSL == "true"
      require:
        - DBLAB_SSL_CERT
  ```

* `env-validator.sh` validates this schema and performs type conversion, undefined checks, and dependency checks. Immediately error exit on failure.

* Assume interface that can be replaced with Rust (`serde`) implementation in the future.

### Volumes and data isolation

* Persistence paths are isolated per instance:

  ```yaml
  volumes:
    - "${XDG_DATA_HOME:-~/.local/share}/dblab/${DBLAB_ENGINE}/${DBLAB_INSTANCE}/data:/var/lib/postgresql/data"
  ```

  This prevents volume name and path conflicts.

### Security notes

* External exposure disabled by default. Prepare warning and failure mode when dangerous bind (`0.0.0.0`) is detected
* Introduce `DBLAB_LOG_LEVEL` to control log verbosity
* Integrate Pod/Container image scanning (Trivy, etc.) into CI
