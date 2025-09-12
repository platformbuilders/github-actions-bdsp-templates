#!/bin/bash

set -e

IMAGE_TAG="$1"
IMAGE_DIGEST="$2"
GITHUB_TOKEN="$3"
REPOSITORY_NAME="$4"

echo "IMAGE_TAG: $IMAGE_TAG"
echo "IMAGE_DIGEST: $IMAGE_DIGEST"

REPOSITORY_NAME=$(basename "$REPOSITORY_NAME")

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"
echo "REPOSITORY_NAME: $REPOSITORY_NAME"

# Determinar o Target Repository
if [[ "$GITHUB_REF_NAME" == "staging" || "$GITHUB_REF_NAME" =~ ^release/ || "$GITHUB_REF_NAME" == "homolog" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-hml"
elif [[ "$GITHUB_REF_NAME" == "develop" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-dev"
elif [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-prd"
else
  echo "Branch não suportada: $GITHUB_REF_NAME"
  exit 1
fi

echo "TARGET_REPO: $TARGET_REPO"

# Clonar o repositório de destino
GIT_CLONE_COMMAND="git clone https://${GITHUB_TOKEN}@github.com/platformbuilders/${TARGET_REPO}.git argo-manifests"
echo "Executing: $GIT_CLONE_COMMAND"
$GIT_CLONE_COMMAND

cd argo-manifests

if [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then
  # Checkout do branch dev ANTES de encontrar o arquivo
  git checkout dev

  # Encontrar o arquivo de deployment
  DEPLOYMENT_FILE=$(find . -name "*-dp.yaml")

  if [[ -z "$DEPLOYMENT_FILE" ]]; then
    echo "Erro: Arquivo de deployment não encontrado no branch dev."
    exit 1
  fi

  echo "Arquivo de deployment encontrado: $DEPLOYMENT_FILE"

  # Atualizar o arquivo YAML
  yq -i ".metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$DEPLOYMENT_FILE"
  yq -i ".spec.template.metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$DEPLOYMENT_FILE"
  yq -i ".spec.template.spec.containers[0].image = \"us-docker.pkg.dev/image-registry-326015/${REPOSITORY_NAME}/${GITHUB_REF_NAME}@$IMAGE_DIGEST\"" "$DEPLOYMENT_FILE"

  # Commit e push
  git config --local user.email "actions@github.com"
  git config --local user.name "GitHub Actions"
  git add "$(basename "$DEPLOYMENT_FILE")"
  git commit -m "Update deployment with image: $IMAGE_TAG"
  git push origin dev

  # Verificar se há mudanças entre dev e master
  if git diff --quiet origin/master..origin/dev; then
    echo "Nenhuma diferença entre master e dev. Nenhum PR será criado."
    exit 0
  fi

  # Verificar se já existe um PR aberto ESPECÍFICO para dev -> master
  EXISTING_PR=$(gh pr list --base master --head dev --json number --jq '.[].number' 2>/dev/null)

  if [[ -n "$EXISTING_PR" ]]; then
    echo "Já existe um PR aberto (PR #$EXISTING_PR)"
  else
    # Criar PR da dev -> master
    echo "Alterações detectadas! Criando Pull Request..."
    gh pr create --title "Update deployment with image: $IMAGE_TAG" \
                 --body "Update deployment with image: $IMAGE_TAG" \
                 --base master \
                 --head dev
  fi



elif [[ "$GITHUB_REF_NAME" == "staging" || "$GITHUB_REF_NAME" =~ ^release/ || "$GITHUB_REF_NAME" == "homolog" || "$GITHUB_REF_NAME" == "develop" ]]; then
  git checkout master

  # Encontrar o arquivo de deployment
  DEPLOYMENT_FILE=$(find . -name "*-dp.yaml")

  if [[ -z "$DEPLOYMENT_FILE" ]]; then
    echo "Erro: Arquivo de deployment não encontrado no branch master."
    exit 1
  fi

  echo "Arquivo de deployment encontrado: $DEPLOYMENT_FILE"

  if [[ "$GITHUB_REF_NAME" =~ ^release/ ]]; then
    GITHUB_REF_NAME="release"
  else
    GITHUB_REF_NAME="$GITHUB_REF_NAME"
  fi

  # Atualizar o arquivo YAML
  yq -i ".metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$DEPLOYMENT_FILE"
  yq -i ".spec.template.metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$DEPLOYMENT_FILE"
  yq -i ".spec.template.spec.containers[0].image = \"us-docker.pkg.dev/image-registry-326015/${REPOSITORY_NAME}/${GITHUB_REF_NAME}@$IMAGE_DIGEST\"" "$DEPLOYMENT_FILE"

  # Commit e push
  git config --local user.email "actions@github.com"
  git config --local user.name "GitHub Actions"
  git add "$(basename "$DEPLOYMENT_FILE")"
  git commit -m "Update deployment with image: $IMAGE_TAG"
  git push origin master
else
  echo "Nenhuma ação necessária para a branch $GITHUB_REF_NAME"
fi
