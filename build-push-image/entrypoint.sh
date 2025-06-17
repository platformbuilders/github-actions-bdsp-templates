#!/bin/bash

set -e

echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"

# Adicionar o diretório workspace à lista de diretórios seguros
git config --global --add safe.directory /github/workspace

# Get short SHA
SHORT_SHA=$(git rev-parse --short=7 HEAD)
# Build and Push Docker image
REPOSITORY_NAME=$(basename "$GITHUB_REPOSITORY")



if DEPLOY_PROVIDER == "GCP"
    # Definir REPOSITORY_URI para a branch
    case "$GITHUB_REF_NAME" in "staging" )
      REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/staging" ;;
    
    "master")  
      REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/master" ;;
    
    "main")  
      REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/master" ;;
    
    "develop")
      REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/develop";;
    
    "release")
      REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/release";;
    
    "homolog")
      REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/homolog" ;;
    * )
      
      echo "Branch not supported: $GITHUB_REF_NAME"
      exit 1
    esac    
elif DEPLOY_PROVIDER == "AWS"
  REPOSITORY_URI_BRANCH = 
    case "$GITHUB_REF_NAME" in "staging" )
      REPOSITORY_URI_BRANCH="756376728940.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME" ;;
    
    "master")  
      REPOSITORY_URI_BRANCH="715663453372.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME:master" ;;
    
    "main")  
      REPOSITORY_URI_BRANCH="715663453372.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME:master" ;;
    
    "develop")
      REPOSITORY_URI_BRANCH="756376728940.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME:develop";;
    
    "release")
      REPOSITORY_URI_BRANCH="715663453372.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME:release";;
    
    "homolog")
      REPOSITORY_URI_BRANCH="756376728940.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME:homolog";;
    * )
      
      echo "Branch not supported: $GITHUB_REF_NAME"
      exit 1
    esac
else
  echo "DEPLOY_PROVIDER não definido ou inválido."
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

  if [[ "$PROJECT_TYPE" == "frontend" ]]; then
      echo "Branch master/main detectada para projeto frontend. Realizando build e push..."
      docker build -t "$REPOSITORY_URI_PRD":"$SHORT_SHA" .
      docker push "$REPOSITORY_URI_PRD":"$SHORT_SHA"

      IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_PRD":"$SHORT_SHA" | cut -d '@' -f 2)
      IMAGE_TAG="$SHORT_SHA" 
      IMAGE_URI="$REPOSITORY_URI_BRANCH:$SHORT_SHA"

      echo "Build e push concluídos para frontend em $GITHUB_REF_NAME."

  else
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

        echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
        echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
        echo "Outputs definidos."

  fi # <<< Fim da lógica adicionada para frontend >>>


# Verificar se a branch é release/*, staging ou homolog (Mantido como no original)
elif [[ "$GITHUB_REF_NAME" =~ ^release/ || "$GITHUB_REF_NAME" == "staging" || "$GITHUB_REF_NAME" == "homolog" ]]; then

  if [[ "$PROJECT_TYPE" == "frontend" ]]; then
      echo "Detectado projeto frontend. Realizando build e push..."
      docker build -t "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" .
      docker push "$REPOSITORY_URI_BRANCH":"$SHORT_SHA"

      IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" | cut -d '@' -f 2)
      IMAGE_TAG="$SHORT_SHA"
      IMAGE_URI="$REPOSITORY_URI_BRANCH:$IMAGE_TAG"

      echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
      echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
      echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_OUTPUT"
      echo "Outputs definidos"

      echo "Build e push concluídos para frontend em $GITHUB_REF_NAME."

  else
    docker build -t "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" .
    docker tag "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" "$REPOSITORY_URI_PRD":"$SHORT_SHA"
    docker push "$REPOSITORY_URI_BRANCH":"$SHORT_SHA"
    docker push "$REPOSITORY_URI_PRD":"$SHORT_SHA"

    echo "Build e push realizado para $GITHUB_REF_NAME e master"

    IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" | cut -d '@' -f 2)
    IMAGE_TAG="$SHORT_SHA"
    IMAGE_URI="$REPOSITORY_URI_BRANCH:$IMAGE_TAG"

    echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
    echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
    echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_OUTPUT"
    echo "Outputs definidos"
  fi

else
  docker build -t "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" .
  docker push "$REPOSITORY_URI_BRANCH":"$SHORT_SHA"

  echo "Build e push realizado para $GITHUB_REF_NAME"

  IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" | cut -d '@' -f 2)
  IMAGE_TAG="$SHORT_SHA"
  IMAGE_URI="$REPOSITORY_URI_BRANCH:$IMAGE_TAG"

  echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
  echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
  echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_OUTPUT"
  echo "Outputs definidos"
fi

rm -f gcp-sa.json