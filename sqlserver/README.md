# SQL Server

## How to use

### Using SQL Server container

1. Start SQL Server container

    ```sh
    docker compose up -d
    ```

1. Configure the .env file

    ```sh
    cp .env.template .env
    vi .env
    ```

1. Run SQL files

    ```sh
    # path: sql file or directory including sql files
    ./run.sh <path> [<path> ...] [--env <env-file>]
    ```

1. Stop SQL Server container

    ```sh
    docker compose down
    ```

    > Note: If you want to delete all the data, use `docker compose down -v`.

### Using an existing SQL Server

1. Configure the .env file

    ```sh
    cp .env.template .env
    vi .env
    ```

1. Run SQL files

    ```sh
    # path: sql file or directory including sql files
    ./run.sh <path> [<path> ...] [--env <env-file>]
    ```

## note

- Install sqlcmd in local

  ```sh
  # e.g. using brew
  brew install sqlcmd
  ```

