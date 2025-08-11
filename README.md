# db-lab

A sandbox environment for experimenting with SQL and NoSQL databases using container. Easily spin up multiple database containers and run queries.

## Features

- Supports multiple databases (currently SQL Server and Oracle)
  - SQL Server (sqlcmd)
	- Oracle (sqlcl, sqlplus)
	- SQLite (by python)
- Containerized environment for easy setup
- Command-line interface for executing SQL files
- Configurable via `.env` files
- Sample SQL files for testing and learning

## How to Use

```sh
cp .env.example .env

# Startup (network will be created automatically if it doesn't exist)
./bin/db pg up

# CLI (db-tools → service name)
./bin/db pg cli     # Opens psql

# If you want to connect from the host using a GUI/native client
./bin/db pg conninfo
```

## How to Add a New Database

