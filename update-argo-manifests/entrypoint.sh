#!/bin/bash

set -e

IMAGE_TAG="$1"
IMAGE_DIGEST="$2"
GITHUB_TOKEN="$3"
REPOSITORY_NAME="$4"
BITBUCKET_TOKEN="$5"
BITBUCKET_USERNAME="$6"

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

ARGO_MANIFESTS_REPO_SLUG="bitbucket.org/pernamlabs/${TARGET_REPO}"
echo "TARGET_REPO: $TARGET_REPO"

# Clonar o repositório de destino
GIT_CLONE_COMMAND="git clone https://${BITBUCKET_TOKEN}@bitbucket.org/pernamlabs/${TARGET_REPO}.git argo-manifests"
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
  EXISTING_PR=$(curl -s -G -u "${BITBUCKET_USERNAME}:${BITBUCKET_TOKEN}" \
                --data-urlencode 'q=state="OPEN" AND source.branch.name="'dev'" AND destination.branch.name="'"${$GITHUB_REF_NAME}"'"' \
                "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_REPO_API_SLUG}/pullrequests" \
                | jq -r 'if .size>0 then .values[0].links.html.href else "NENHUM PR ABERTO" end')
  

  if [[ -n "$EXISTING_PR" ]]; then
    echo "Já existe um PR aberto (PR #$EXISTING_PR)"
  else
    # Criar PR da dev -> master
    echo "Alterações detectadas! Criando Pull Request..."
    BITBUCKET_REPO_API_SLUG=$(echo "$ARGO_MANIFESTS_REPO_SLUG" | cut -d'/' -f2-)
    BITBUCKET_API_URL="https://api.bitbucket.org/2.0/repositories/${BITBUCKET_REPO_API_SLUG}/pullrequests"
      
    PR_TITLE="Deploy ${REPOSITORY_NAME} to Production"
    PR_BODY="Automated PR for ${REPOSITORY_NAME} from source branch ${GITHUB_REF_NAME}. Update production overlay with image digest ${IMAGE_DIGEST} (tag ${IMAGE_TAG}). Ready for review and merge to deploy to production."
    
    curl -X POST "$BITBUCKET_API_URL" \
      -u "${BITBUCKET_USERNAME}:${BITBUCKET_TOKEN}" \
      -H "Content-Type: application/json" \
        -d @- << EOF
{
  "title": "${PR_TITLE}",
  "description": "${PR_BODY}",
  "source": {
    "branch": {
      "name": "${PR_HEAD_BRANCH}"
    }
  },
  "destination": {
    "branch": {
      "name": "${PR_BASE_BRANCH}"
    }
  },
  "close_source_branch": true
}
EOF
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
