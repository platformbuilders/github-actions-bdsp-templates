FROM ubuntu:latest


RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    gnupg \
    curl \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && echo "deb https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list


RUN apt-get update && apt-get install -y \
    git \
    docker.io \
    google-cloud-sdk \
    jq \
    && rm -rf /var/lib/apt/lists/*
