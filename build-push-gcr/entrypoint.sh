#!/bin/bash

set -ex

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"

# Adicionar o diretório workspace à lista de diretórios seguros
git config --global --add safe.directory /github/workspace

# Get short SHA
SHORT_SHA=$(git rev-parse --short=7 HEAD)

# Build and Push Docker image
REPOSITORY_NAME=$(basename "$GITHUB_REPOSITORY")

if [[ "$GITHUB_REF_NAME" == "staging" ]]; then
  REPOSITORY_URI="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/staging"
elif [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then
  REPOSITORY_URI="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/master"
else
  echo "Branch not supported: $GITHUB_REF_NAME"
  exit 1
fi
echo "REPOSITORY_URI: $REPOSITORY_URI"

docker build -t "$REPOSITORY_URI":"$SHORT_SHA" .

gcloud auth configure-docker us-docker.pkg.dev

docker push "$REPOSITORY_URI":"$SHORT_SHA"

echo "Build and push realizado"

# Get image digest
IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI":"$SHORT_SHA" | cut -d '@' -f 2)

# Replace colons in digest
IMAGE_DIGEST_SAFE=$(echo "$IMAGE_DIGEST" | tr ':' '-')

# Tag image with safe digest
docker tag "$REPOSITORY_URI":"$SHORT_SHA" "$REPOSITORY_URI":"$IMAGE_DIGEST_SAFE"

# Push with safe digest tag
docker push "$REPOSITORY_URI":"$IMAGE_DIGEST_SAFE"

echo "Build and push realizado"

IMAGE_TAG="$SHORT_SHA" # Use original tag

# Output image tag and digest
echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"

echo "Outputs definidos"