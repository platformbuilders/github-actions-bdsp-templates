FROM google/cloud-sdk:slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    jq \
    docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
