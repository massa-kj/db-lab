## How to use

```sh
export $(grep -v '^#' .env | xargs)
```

```sh
docker compose down
# Remove volumes
docker compose down --volumes
```

```sh
sqlcmd -S "$MY_SQLSERVER_SERVERNAME" -U "$MY_SQLSERVER_SA_USERNAME" -P "$MY_SQLSERVER_SA_PASSWORD" -d "$MY_SQLSERVER_DATABASE" -i <filepath>
```

