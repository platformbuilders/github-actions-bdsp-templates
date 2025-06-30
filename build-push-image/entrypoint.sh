#!/bin/bash

set -e

GITHUB_REF_NAME="main"
echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"

# Adicionar o diretório workspace à lista de diretórios seguros
git config --global --add safe.directory /github/workspace

# Get short SHA
SHORT_SHA=$(git rev-parse --short=7 HEAD)
# Build and Push Docker image
REPOSITORY_NAME=$(basename "$GITHUB_REPOSITORY")

if [ "$DEPLOY_PROVIDER" == "GCP" ]; then
    SERVICE_ACCOUNT_KEY=$GCP_SERVICE_ACCOUNT_KEY
elif [ "$DEPLOY_PROVIDER" == "AWS" ]; then
    AWS_CREDS=$AWS_SERVICE_ACCOUNT_KEY
    AWS_CREDS_PROD=$AWS_SERVICE_ACCOUNT_KEY_PRD
    eval $AWS_CREDS
    eval $AWS_CREDS_PROD
else
  echo "DEPLOY_PROVIDER não definido ou inválido."
  exit 1
fi

if [ $DEPLOY_PROVIDER == "GCP" ];  then
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
elif [ $DEPLOY_PROVIDER == "AWS" ]; then
    REPOSITORY_URI_BRANCH_HML="756376728940.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME"  
    REPOSITORY_URI_BRANCH_PRD="715663453372.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME"

    case "$GITHUB_REF_NAME" in "staging" )
      REPOSITORY_URI_BRANCH=$REPOSITORY_URI_BRANCH_HML ;;
    
    "master")  
      REPOSITORY_URI_BRANCH=$REPOSITORY_URI_BRANCH_HML ;;
    
    "main")  
      REPOSITORY_URI_BRANCH=$REPOSITORY_URI_BRANCH_HML;;
    
    "develop")
      REPOSITORY_URI_BRANCH=$REPOSITORY_URI_BRANCH_HML;;
    
    "release")
      REPOSITORY_URI_BRANCH=$REPOSITORY_URI_BRANCH_HML;;
    
    "homolog")
      REPOSITORY_URI_BRANCH=$REPOSITORY_URI_BRANCH_HML;;
    * )
      
      echo "Branch not supported: $GITHUB_REF_NAME"
      exit 1
    esac
else
  echo "DEPLOY_PROVIDER não definido ou inválido."
  exit 1 

fi
# Definir REPOSITORY_URI para master
if [ $DEPLOY_PROVIDER == "GCP" ]; then
    REPOSITORY_URI_PRD="us-docker.pkg.dev/image-registry-326015/$REPOSITORY_NAME/master"
elif [ $DEPLOY_PROVIDER == "AWS" ]; then
    REPOSITORY_URI_PRD=$REPOSITORY_URI_BRANCH_PRD
fi

echo "REPOSITORY_URI_BRANCH: $REPOSITORY_URI_BRANCH"
echo "REPOSITORY_URI_PRD: $REPOSITORY_URI_PRD"



# Validar se a secret está em Base64
if echo "$SERVICE_ACCOUNT_KEY" | base64 -d &>/dev/null; then
    echo "Decodificando secret em Base64..."
    echo "$SERVICE_ACCOUNT_KEY" | base64 -d > gcp-sa.json
else
    echo "Secret já está no formato correto, salvando diretamente..."
    echo "$SERVICE_ACCOUNT_KEY" > gcp-sa.json
fi

if [ $DEPLOY_PROVIDER == "GCP" ]; then
  # Autenticar o gcloud
  gcloud auth activate-service-account --key-file=gcp-sa.json
  # Configurar o Docker para autenticar com o GCR
  gcloud auth configure-docker us-docker.pkg.dev
elif [ $DEPLOY_PROVIDER == "AWS" ]; then
  # Autenticar o AWS CLI
  aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
  aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
  aws configure set default.region "$AWS_REGION" --profile hml

  # Autenticar o Docker com o ECR HML
  aws ecr get-login-password  --region "$AWS_REGION" --profile hml | docker login --username AWS --password-stdin "$REPOSITORY_URI_BRANCH_HML"

  # Autenticar o Docker com o ECR PRD (outra conta)
  aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID_PRD"
  aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY_PRD"
  aws configure set default.region "$AWS_REGION_PRD" --profile prd

  aws ecr get-login-password --region "$AWS_REGION_PRD" --profile prd | docker login --username AWS --password-stdin "$REPOSITORY_URI_BRANCH_PRD"
fi

# Verificar se a branch é master ou main
if [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then

  if [[ "$PROJECT_TYPE" == "frontend" ]]; then
      echo "Branch master/main detectada para projeto frontend. Realizando build e push..."
      docker build -t "$REPOSITORY_URI_PRD":"$SHORT_SHA" .

      TAG_EXISTS=$(gcloud artifacts docker tags list "$REPOSITORY_URI_BRANCH" \
      --filter="tag~'$SHORT_SHA'" \
      --format="value(tag)" 2>/dev/null || true)

      if [[ -n "$TAG_EXISTS" ]]; then
        echo "Tag '$SHORT_SHA' já existe em $REPOSITORY_URI_BRANCH. Deletando..."
        gcloud artifacts docker tags delete "$REPOSITORY_URI_BRANCH:$SHORT_SHA" --quiet || true
      fi

      docker push "$REPOSITORY_URI_PRD":"$SHORT_SHA"

      IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REPOSITORY_URI_PRD":"$SHORT_SHA" | cut -d '@' -f 2)
      IMAGE_TAG="$SHORT_SHA" 
      IMAGE_URI="$REPOSITORY_URI_BRANCH:$SHORT_SHA"

      echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
      echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
      echo "IMAGE_URI=$IMAGE_URI" >> "$GITHUB_OUTPUT"
      echo "Outputs definidos"

      echo "Build e push concluídos para frontend em $GITHUB_REF_NAME."

  else
      
      if [ "$DEPLOY_PROVIDER" == "GCP" ]; then
        LATEST_IMAGE_LINE=$(gcloud artifacts docker images list --include-tags "$REPOSITORY_URI_PRD" \
            --sort-by=~UPDATE_TIME \
            --limit=1 \
            --quiet \
            | tail -n 1)

        if [[ -z "$LATEST_IMAGE_LINE" ]]; then
            echo "Erro Crítico: Nenhuma linha de dados retornada por gcloud."
            exit 1
        fi
      elif  [ "$DEPLOY_PROVIDER" == "AWS" ]; then
          LATEST_IMAGE_LINE=$(aws ecr describe-images \
            --repository-name "$REPOSITORY_NAME" \
            --region "$AWS_REGION_PRD" \
            --profile prd \
            --query 'sort_by(imageDetails,& imagePushedAt)[-1]' \
            --output json)

        if [[ -z "$LATEST_IMAGE_LINE" ]]; then
            echo "Erro Crítico: Nenhuma linha de dados retornada por AWS ECR."
            exit 1
        fi
      fi

      if [ "$DEPLOY_PROVIDER" == "GCP" ]; then
        IMAGE_DIGEST=$(echo "$LATEST_IMAGE_LINE" | awk '{print $2}')
        IMAGE_TAG=$(echo "$LATEST_IMAGE_LINE" | awk '{print $3}')

      elif [ "$DEPLOY_PROVIDER" == "AWS" ]; then
        IMAGE_DIGEST=$(echo "$LATEST_IMAGE_LINE" | jq -r '.imageDigest')
        IMAGE_TAG=$(echo "$LATEST_IMAGE_LINE" | jq -r '.imageTags[]' | grep -v latest)
      
      fi

      if [[ -z "$IMAGE_TAG" ]] || [[ -z "$IMAGE_DIGEST" ]] || [[ ! "$IMAGE_DIGEST" =~ ^sha256: ]]; then
         echo "Erro Crítico: Falha ao extrair tag ou digest válido da linha."
         echo "Linha processada: '$LATEST_IMAGE_LINE'"
         exit 1
      fi

        echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"
        echo "IMAGE_DIGEST=$IMAGE_DIGEST" >> "$GITHUB_OUTPUT"
        echo "Outputs definidos."

  fi


# Verificar se a branch é release/*, staging ou homolog
elif [[ "$GITHUB_REF_NAME" =~ ^release/ || "$GITHUB_REF_NAME" == "staging" || "$GITHUB_REF_NAME" == "homolog" ]]; then

  if [[ "$PROJECT_TYPE" == "frontend" ]]; then
      echo "Detectado projeto frontend. Realizando build e push..."
      docker build -t "$REPOSITORY_URI_BRANCH":"$SHORT_SHA" .

      TAG_EXISTS=$(gcloud artifacts docker tags list "$REPOSITORY_URI_BRANCH" \
      --filter="tag~'$SHORT_SHA'" \
      --format="value(tag)" 2>/dev/null || true)

      if [[ -n "$TAG_EXISTS" ]]; then
        echo "Tag '$SHORT_SHA' já existe em $REPOSITORY_URI_BRANCH. Deletando..."
        gcloud artifacts docker tags delete "$REPOSITORY_URI_BRANCH:$SHORT_SHA" --quiet || true
      fi

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

  if [ "$DEPLOY_PROVIDER" == "GCP" ]; then
    TAG_EXISTS=$(gcloud artifacts docker tags list "$REPOSITORY_URI_BRANCH" \
    --filter="tag~'$SHORT_SHA'" \
    --format="value(tag)" 2>/dev/null || true)

    if [[ -n "$TAG_EXISTS" ]]; then
      echo "Tag '$SHORT_SHA' já existe em $REPOSITORY_URI_BRANCH. Deletando..."
      gcloud artifacts docker tags delete "$REPOSITORY_URI_BRANCH:$SHORT_SHA" --quiet || true
    fi
  elif [ "$DEPLOY_PROVIDER" == "AWS" ]; then
    TAG_EXISTS=$(aws ecr describe-images \
    --repository-name "$REPOSITORY_NAME" \
    --region "$AWS_REGION" \
    --profile hml \
    --query "imageDetails[?contains(imageTags, '$SHORT_SHA')].imageTags[]" \
    --output text 2>/dev/null || true)

    if [[ -n "$TAG_EXISTS" ]]; then
      echo "Tag '$SHORT_SHA' já existe em $REPOSITORY_URI_BRANCH. Deletando..."
      aws ecr batch-delete-image \
        --repository-name "$REPOSITORY_NAME" \
        --region "$AWS_REGION" \
        --image-ids imageTag="$SHORT_SHA" \
        --output text || true
    fi
    
  fi
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

  TAG_EXISTS=$(gcloud artifacts docker tags list "$REPOSITORY_URI_BRANCH" \
    --filter="tag~'$SHORT_SHA'" \
    --format="value(tag)" 2>/dev/null || true)

  if [[ -n "$TAG_EXISTS" ]]; then
    echo "Tag '$SHORT_SHA' já existe em $REPOSITORY_URI_BRANCH. Deletando..."
    gcloud artifacts docker tags delete "$REPOSITORY_URI_BRANCH:$SHORT_SHA" --quiet || true
  fi

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

if [ "$DEPLOY_PROVIDER" == "GCP" ]; then
    echo "Removendo arquivo de chave do GCP..."
    rm -f gcp-sa.json
elif [ "$DEPLOY_PROVIDER" == "AWS" ]; then
    echo "Removendo credenciais do AWS..."
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_REGION
    unset AWS_ACCESS_KEY_ID_PRD
    unset AWS_SECRET_ACCESS_KEY_PRD
    unset AWS_REGION_PRD
fi

echo "Script de build e push concluído com sucesso."
echo "IMAGE_TAG=$IMAGE_TAG" >> "$GITHUB_OUTPUT"

