#!/bin/bash

set -e

IMAGE_TAG=$INPUT_IMAGE_TAG
IMAGE_DIGEST=$INPUT_IMAGE_DIGEST
GITHUB_TOKEN=$INPUT_GITHUB_TOKEN

# Determinar o Target Repository
REPOSITORY_NAME=$(basename "${GITHUB_REPOSITORY_NAME}")
if [[ "${GITHUB_REF_NAME}" == "staging" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-hml"
elif [[ "${GITHUB_REF_NAME}" == "master" || "${GITHUB_REF_NAME}" == "main" ]]; then
  TARGET_REPO="${REPOSITORY_NAME}-prd"
else
  echo "Branch não suportada: ${GITHUB_REF_NAME}"
  exit 1
fi

# Clonar o repositório de destino
git clone https://${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY_OWNER}/${TARGET_REPO}.git target-repo

# Gerar o nome do arquivo de deployment dinamicamente
DEPLOYMENT_FILE=$(basename "${GITHUB_REPOSITORY_NAME}")-dp.yaml

# Atualizar o arquivo YAML
sed -i "s/tags.datadoghq.com\/version: \".*\"/tags.datadoghq.com\/version: \"$IMAGE_TAG\"/g" target-repo/${DEPLOYMENT_FILE}
sed -i "s/image: .*@sha256:.*$/image: us-docker.pkg.dev\/image-registry-326015\/${GITHUB_REPOSITORY_NAME}\/${GITHUB_REF_NAME}@${IMAGE_DIGEST}/g" target-repo/${DEPLOYMENT_FILE}

# Verificar a branch atual
if [[ "${GITHUB_REF_NAME}" == "master" || "${GITHUB_REF_NAME}" == "main" ]]; then
  # Abrir um Pull Request
  gh pr create --title "Update deployment with image: ${IMAGE_TAG}@${IMAGE_DIGEST}" --body "Update deployment." --base "${GITHUB_REF_NAME}" --head update-deployment
else
  # Fazer commit e push das alterações
  cd target-repo
  git config --local user.email "actions@github.com"
  git config --local user.name "GitHub Actions"
  git add ${DEPLOYMENT_FILE}
  git commit -m "Update deployment with image: ${IMAGE_TAG}@${IMAGE_DIGEST}"
  git push origin HEAD:${GITHUB_REF_NAME}
fi