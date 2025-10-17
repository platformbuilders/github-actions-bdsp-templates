FROM ubuntu:latest

RUN apt-get update && \
    apt-get install -y git gh curl jq && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]