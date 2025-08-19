FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Add Microsoft's public key & repository, then install mssql-tools18 / unixODBC
RUN apt-get update && apt-get install -y curl gnupg apt-transport-https ca-certificates \
 && curl https://packages.microsoft.com/keys/microsoft.asc | tee /etc/apt/trusted.gpg.d/microsoft.asc >/dev/null \
 && . /etc/os-release \
 && echo "deb [arch=amd64,arm64,armhf] https://packages.microsoft.com/ubuntu/$VERSION_ID/prod $UBUNTU_CODENAME main" \
    > /etc/apt/sources.list.d/microsoft-prod.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev \
 && ln -s /opt/mssql-tools18/bin/sqlcmd /usr/local/bin/sqlcmd \
 && ln -s /opt/mssql-tools18/bin/bcp    /usr/local/bin/bcp \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /work
CMD ["bash"]

