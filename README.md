# DBLab

Database container management tool for easy development environments.

## Quick Start

### Installation

#### Method 1: Using install script (Recommended)

```bash
git clone https://github.com/massa-kj/db-lab.git
cd db-lab
sudo ./install.sh
```

#### Method 2: Using Makefile

```bash
git clone https://github.com/massa-kj/db-lab.git
cd db-lab
make install
```

#### Method 3: Remote installation (Future)

```bash
curl -fsSL https://example.com/install.sh | bash
# or
wget -O - https://example.com/install.sh | bash
```

### Usage

```bash
# Initialize environment file
dblab init postgres --instance mydb

# Edit mydb.env to set passwords

# Start PostgreSQL instance
dblab up postgres --instance mydb --env-file mydb.env

# Expose port to host
dblab up postgres --instance mydb --env-file mydb.env --expose 5432

# List instances
dblab list postgres

# Stop instance
dblab down postgres --instance mydb

# Destroy instance (removes all data)
dblab destroy postgres --instance mydb
```

## Uninstallation

### Method 1: Standard uninstall (preserves user data)

```bash
sudo dblab-uninstall
```

### Method 2: Complete uninstall (removes everything)

```bash
sudo dblab-uninstall --remove-data --stop-containers
```

### Method 3: Using Makefile

```bash
# Standard uninstall
make uninstall

# Complete uninstall
make uninstall-clean
```

### Uninstall Options

- `--remove-data`: Remove user data directory (`~/.local/share/dblab`)
- `--stop-containers`: Stop all running DBLab containers before uninstall
- `--force`: Skip all confirmation prompts
- `--help`: Show detailed help message

**Note:** 
- By default, user data and running containers are preserved
- User data includes instance configurations and database volumes
- Use `--remove-data` to permanently delete all DBLab data

## Supported Engines

- PostgreSQL (`postgres`)

## Requirements

- Podman or Docker
- Linux or macOS
- Bash 4.0+

## License

MIT License
