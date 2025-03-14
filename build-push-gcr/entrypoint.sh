#!/bin/bash

set -e

GCP_SERVICE_ACCOUNT_KEY=$1

# Decode service account key
echo "$GCP_SERVICE_ACCOUNT_KEY" | base64 -d > gcp-service-account.json

# Authenticate with GCP
gcloud auth activate-service-account --key-file=gcp-service-account.json

# Get short SHA
SHORT_SHA=$(git rev-parse --short=7 HEAD)

# Build and Push Docker image
REPOSITORY_NAME=$(basename "$REPOSITORY_NAME")

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"
echo "REPOSITORY_NAME: $REPOSITORY_NAME"

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

# Clean up service account key
rm gcp-service-account.json