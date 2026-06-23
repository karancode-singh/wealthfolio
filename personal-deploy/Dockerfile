# Wraps the official wealthfolio image with Litestream for SQLite replication.
# Zero code changes to the app — Litestream handles backup/restore to S3.

FROM wealthfolio/wealthfolio:latest

USER root

# Install Litestream (static binary) — v0.5.x has native Tigris support
ARG LITESTREAM_VERSION=0.5.8
ARG TARGETARCH=amd64
RUN apk add --no-cache wget ca-certificates && \
    wget -qO /tmp/litestream.tar.gz \
      "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-x86_64.tar.gz" && \
    tar -xzf /tmp/litestream.tar.gz -C /usr/local/bin && \
    rm /tmp/litestream.tar.gz && \
    apk del wget

COPY litestream.yml /etc/litestream.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    chown 1000:1000 /etc/litestream.yml /entrypoint.sh

USER 1000:1000

# Override the default CMD with our entrypoint that handles restore + replicate
ENTRYPOINT ["/entrypoint.sh"]
