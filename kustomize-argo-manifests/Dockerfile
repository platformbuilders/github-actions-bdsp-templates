FROM ubuntu:latest

ENV KUSTOMIZE_VER=5.3.0

RUN apt-get update && \
    apt-get install -y git gh curl tar gzip && \
    curl -sSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    curl -sSL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VER}/kustomize_v${KUSTOMIZE_VER}_linux_amd64.tar.gz -o /tmp/kustomize.tar.gz && \
    tar -xf /tmp/kustomize.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/kustomize && \
    rm -rf /var/lib/apt/lists/* /tmp/kustomize.tar.gz

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
