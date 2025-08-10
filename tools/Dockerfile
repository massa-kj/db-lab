FROM alpine:3.20

RUN apk add --no-cache \
      postgresql-client \
      bash curl jq coreutils ca-certificates

WORKDIR /work
ENTRYPOINT ["/bin/sh", "-lc"]
CMD ["bash"]

