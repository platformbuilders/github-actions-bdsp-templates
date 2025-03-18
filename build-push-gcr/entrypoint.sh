#!/bin/bash

set -e

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"

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

docker build -t "$REPOSITORY_URI":"$SHORT_SHA" .
docker push "$REPOSITORY_URI":"$SHORT_SHA"

# Get image digest
IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI":"$SHORT_SHA" | cut -d '@' -f 2)
IMAGE_TAG="$SHORT_SHA"

# Output image tag and digest
echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"