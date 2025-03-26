#!/bin/bash

set -e

IMAGE_TAG=$1
IMAGE_DIGEST=$2
GITHUB_TOKEN=$3
REPOSITORY_NAME=$4

echo "IMAGE_TAG: $IMAGE_TAG"
echo "IMAGE_DIGEST: $IMAGE_DIGEST"

REPOSITORY_NAME=$(basename "$REPOSITORY_NAME")

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"
echo "REPOSITORY_NAME: $REPOSITORY_NAME"

# Determinar o Target Repository
if [[ "${GITHUB_REF_NAME}" == "staging" || "${GITHUB_REF_NAME}" =~ ^release/ || "${GITHUB_REF_NAME}" == "homolog"  ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-hml"
elif [[ "${GITHUB_REF_NAME}" == "develop" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-dev"
elif [[ "${GITHUB_REF_NAME}" == "master" || "${GITHUB_REF_NAME}" == "main" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-prd"
else
  echo "Branch não suportada: ${GITHUB_REF_NAME}"
  exit 1
fi

echo "TARGET_REPO: $TARGET_REPO"

# Clonar o repositório de destino
GIT_CLONE_COMMAND="git clone https://${GITHUB_TOKEN}@github.com/platformbuilders/${TARGET_REPO}.git argo-manifests"
echo "Executing: $GIT_CLONE_COMMAND"
$GIT_CLONE_COMMAND

# Encontrar o arquivo de deployment
DEPLOYMENT_FILE=$(find argo-manifests/ -name "*-dp.yaml")

if [[ -z "$DEPLOYMENT_FILE" ]]; then
  echo "Erro: Arquivo de deployment não encontrado."
  exit 1
fi

echo "Arquivo de deployment encontrado: $DEPLOYMENT_FILE"

# Atualizar o arquivo YAML

# Atualizar tags.datadoghq.com/version em metadata.labels
sed -i "s/\(tags.datadoghq.com\/version: \)\"[^\"]*\"/\1\"$IMAGE_TAG\"/g" $DEPLOYMENT_FILE

# Atualizar tags.datadoghq.com/version em template.metadata.labels
sed -i "s/\(tags.datadoghq.com\/version: \)\"[^\"]*\"/\1\"$IMAGE_TAG\"/g" $DEPLOYMENT_FILE

# Atualizar image
sed -i "s|\(image: us-docker.pkg.dev/image-registry-326015/${REPOSITORY_NAME}/${GITHUB_REF_NAME}@\)[^ ]*|\1${IMAGE_DIGEST}|g" $DEPLOYMENT_FILE

# Commit e push ou abrir PR
cd argo-manifests
git config --local user.email "actions@github.com"
git config --local user.name "GitHub Actions"
git add "$(basename $DEPLOYMENT_FILE)"
git commit -m "Update deployment with image: ${IMAGE_TAG}"

if [[ "${GITHUB_REF_NAME}" == "master" || "${GITHUB_REF_NAME}" == "main" ]]; then
  # Trabalhar na branch dev
  git checkout dev
  git push origin dev

  # Verificar se há mudanças entre dev e master
  if git diff --quiet origin/master..origin/dev; then
    echo "Nenhuma diferença entre master e dev. Nenhum PR será criado."
    exit 0
  fi
    
  # Criar PR da dev -> master
  echo "Alterações detectadas! Criando Pull Request..."
  gh pr create --title "Update deployment with image: ${IMAGE_TAG}" \
               --base master \
               --head dev

elif [[ "${GITHUB_REF_NAME}" == "staging" || "${GITHUB_REF_NAME}" =~ ^release/ || "${GITHUB_REF_NAME}" == "homolog" || "${GITHUB_REF_NAME}" == "develop"  ]]; then
  git checkout master
  git push origin master
else
  echo "Nenhuma ação necessária para a branch ${GITHUB_REF_NAME}"
fi
