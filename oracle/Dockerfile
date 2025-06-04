FROM oraclelinux:7

WORKDIR /usr/local/src/
RUN yum -y install libaio && \
curl -O https://download.oracle.com/otn_software/linux/instantclient/216000/oracle-instantclient-basic-21.6.0.0.0-1.x86_64.rpm && \
curl -O https://download.oracle.com/otn_software/linux/instantclient/216000/oracle-instantclient-sqlplus-21.6.0.0.0-1.x86_64.rpm && \
rpm -ivh oracle-instantclient-*

CMD ["sleep", "infinity"]

