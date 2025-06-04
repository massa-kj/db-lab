# Oracle Lab

## Build container image

```sh
git clone https://github.com/oracle/docker-images.git
```

```sh
cd ./docker-images/OracleDatabase/SingleInstance/dockerfiles/
# -x: Express Edition
./buildContainerImage.sh -v 21.3.0 -x
```

## Set up

```sh
docker compose up -d

# Wait until the server container is ready
docker logs oracle-database-1
# #########################
# DATABASE IS READY TO USE!
# #########################

# When connecting from local
sql -S system/oracle@localhost:1521 [@path]
# When the client also uses a container
docker compose exec client bash
sqlplus system/oracle@database:1521
```

