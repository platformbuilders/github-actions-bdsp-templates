#!/bin/bash

set -ex

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"

# Adicionar o diretório workspace à lista de diretórios seguros
git config --global --add safe.directory /github/workspace

# Get short SHA
SHORT_SHA=$(git rev-parse --short=7 HEAD)
# Build and Push Docker image
REPOSITORY_NAME=$(basename "$GITHUB_REPOSITORY")

# Definir REPOSITORY_URI para a branch
if [[ "$GITHUB_REF_NAME" == "staging" ]]; then
  REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/staging"
elif [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then
  REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/master"
elif [[ "$GITHUB_REF_NAME" == "develop" ]]; then
  REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/develop"
elif [[ "$GITHUB_REF_NAME" =~ ^release/ ]]; then
  REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/release"
elif [[ "$GITHUB_REF_NAME" == "homolog" ]]; then
  REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/homolog"
else
  echo "Branch not supported: $GITHUB_REF_NAME"
  exit 1
fi

# Definir REPOSITORY_URI para master
REPOSITORY_URI_PRD="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/master"

echo "REPOSITORY_URI_BRANCH: $REPOSITORY_URI_BRANCH"
echo "REPOSITORY_URI_PRD: $REPOSITORY_URI_PRD"

# Validar se a secret está em Base64
if echo "$GCP_SERVICE_ACCOUNT_KEY" | base64 -d &>/dev/null; then
    echo "Decodificando secret em Base64..."
    echo "$GCP_SERVICE_ACCOUNT_KEY" | base64 -d > gcp-sa.json
else
    echo "Secret já está no formato correto, salvando diretamente..."
    echo "$GCP_SERVICE_ACCOUNT_KEY" > gcp-sa.json
fi

# Autenticar o gcloud
gcloud auth activate-service-account --key-file=gcp-sa.json
# Configurar o Docker para autenticar com o GCR
gcloud auth configure-docker us-docker.pkg.dev

# Verificar se a branch é master ou main
if [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then

  LATEST_IMAGE_LINE=$(gcloud artifacts docker images list --include-tags "$REPOSITORY_URI_PRD" \
      --sort-by=~UPDATE_TIME \
      --limit=1 \
      --quiet \
      | tail -n 1)

  if [[ -z "$LATEST_IMAGE_LINE" ]]; then
      echo "Erro Crítico: Nenhuma linha de dados retornada por gcloud."
      exit 1
  fi

  IMAGE_DIGEST=$(echo "$LATEST_IMAGE_LINE" | awk '{print $2}')
  IMAGE_TAG=$(echo "$LATEST_IMAGE_LINE" | awk '{print $3}')

  if [[ -z "$IMAGE_TAG" ]] || [[ -z "$IMAGE_DIGEST" ]] || [[ ! "$IMAGE_DIGEST" =~ ^sha256: ]]; then
     echo "Erro Crítico: Falha ao extrair tag ou digest válido da linha."
     echo "Linha processada: '$LATEST_IMAGE_LINE'"
     exit 1
  fi

  # Define os outputs
  echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
  echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
  echo "Outputs definidos."



# Verificar se a branch é release/*, staging ou homolog
elif [[ "$GITHUB_REF_NAME" =~ ^release/ || "$GITHUB_REF_NAME" == "staging" || "$GITHUB_REF_NAME" == "homolog" ]]; then
  docker build -t "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" .
  docker tag "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" "$REPOSITORY_URI_PRD":"$SHORT_SHA" # Tag a imagem para master
  docker push "$REPOSITORY_URI_BRANCH":"$SHORT_SHA"
  docker push "$REPOSITORY_URI_PRD":"$SHORT_SHA"

  echo "Build e push realizado para $GITHUB_REF_NAME e master"

  # Get image digest
  IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" | cut -d '@' -f 2)
  IMAGE_TAG="$SHORT_SHA" # Use original tag
  IMAGE_URI="$REPOSITORY_URI_BRANCH:$SHORT_SHA"

  # Output image tag and digest
  echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
  echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
  echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_OUTPUT"
  echo "Outputs definidos"

else
  docker build -t "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" .
  docker push "$REPOSITORY_URI_BRANCH":"$SHORT_SHA"

  echo "Build e push realizado para $GITHUB_REF_NAME"

  # Get image digest
  IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" | cut -d '@' -f 2)
  IMAGE_TAG="$SHORT_SHA" # Use original tag
  IMAGE_URI="$REPOSITORY_URI_BRANCH:$SHORT_SHA"

  # Output image tag and digest
  echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
  echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
  echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_OUTPUT"
  echo "Outputs definidos"
fi

rm -f gcp-sa.json
