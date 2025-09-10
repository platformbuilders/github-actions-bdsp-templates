#!/bin/bash

set -euo pipefail
IMAGE_TAG="$1"
IMAGE_DIGEST="$2"
GITHUB_TOKEN="$3"
REPOSITORY_NAME=$(basename "$4")

ARGO_MANIFESTS_REPO_SLUG="bitbucket.org/pernamlabs/pnb-pefisa-gitops-manifests"
ARGO_MANIFESTS_REPO_DIR="argo-manifests"

TARGET_OVERLAY_DIR=""
TARGET_MANIFEST_BRANCH="main"
PR_BASE_BRANCH=""
IS_PROD_FLOW=false

case "$GITHUB_REF_NAME" in
  "main"|"master")
    TARGET_OVERLAY_DIR="prod"
    PR_BASE_BRANCH="main"
    IS_PROD_FLOW=true
    ;;
  "staging"|"homolog"|release/*)
    TARGET_OVERLAY_DIR="homolog"
    IS_PROD_FLOW=false
    ;;
  "develop")
    TARGET_OVERLAY_DIR="develop"
    IS_PROD_FLOW=false
    ;;
  *)
    echo "No action needed for source branch '$GITHUB_REF_NAME'."
    exit 0
    ;;
esac

echo "Target Overlay Directory: overlays/${TARGET_OVERLAY_DIR}"
echo "Target Manifest Branch (Initial Checkout): ${TARGET_MANIFEST_BRANCH}"
echo "Is Production Flow (Isolated PR): ${IS_PROD_FLOW}"

if [ "$DEPLOY_PROVIDER" == "GCP" ]; then
  REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/${REPOSITORY_NAME}/${GITHUB_REF_NAME%%/*}"
  echo "Determined Repository URI Branch: ${REPOSITORY_URI_BRANCH}"

elif [[ $DEPLOY_PROVIDER == "AWS" && "$IS_PROD_FLOW" == "true" ]]; then
  REPOSITORY_URI_BRANCH="715663453372.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME"
  echo "Determined Repository URI Branch: ${REPOSITORY_URI_BRANCH}"

elif [[ $DEPLOY_PROVIDER == "AWS" && "$IS_PROD_FLOW" != "true"  ]]; then
  REPOSITORY_URI_BRANCH="756376728940.dkr.ecr.sa-east-1.amazonaws.com/$REPOSITORY_NAME" 
  echo "Determined Repository URI Branch: ${REPOSITORY_URI_BRANCH}"
fi

# Clone manifests repo
echo "Cloning Bitbucket repo..."
git clone "https://x-bitbucket-api-token-auth:${GITHUB_TOKEN}@${ARGO_MANIFESTS_REPO_SLUG}.git" "${ARGO_MANIFESTS_REPO_DIR}"
cd "${ARGO_MANIFESTS_REPO_DIR}"

if [[ "$IS_PROD_FLOW" == true ]]; then
  echo "Production flow: Checking out ${PR_BASE_BRANCH} and creating temporary branch..."
  git fetch origin "$PR_BASE_BRANCH"
  git checkout "$PR_BASE_BRANCH"
  git reset --hard "origin/${PR_BASE_BRANCH}"
  TIMESTAMP=$(date +%s)
  TEMP_BRANCH_NAME="prod-update-${REPOSITORY_NAME}-${IMAGE_TAG}-${TIMESTAMP}"
  TEMP_BRANCH_NAME=$(echo $TEMP_BRANCH_NAME | sed 's/://g')
  echo "Creating temporary branch: ${TEMP_BRANCH_NAME}"
  git checkout -b "$TEMP_BRANCH_NAME"
  TARGET_PUSH_BRANCH="$TEMP_BRANCH_NAME"
  PR_HEAD_BRANCH="$TEMP_BRANCH_NAME"
else
  echo "Non-production flow: Checking out ${TARGET_MANIFEST_BRANCH}..."
  git fetch origin "$TARGET_MANIFEST_BRANCH"
  git checkout "$TARGET_MANIFEST_BRANCH"
  git reset --hard "origin/${TARGET_MANIFEST_BRANCH}"
  TARGET_PUSH_BRANCH="$TARGET_MANIFEST_BRANCH"
fi

OVERLAY_PATH="k8s/${REPOSITORY_NAME}/overlays/${TARGET_OVERLAY_DIR}"
PATCH_FILE="${OVERLAY_PATH}/deployment-patch.yaml"
KUSTOMIZATION_FILE="${OVERLAY_PATH}/kustomization.yaml"

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "Error: Patch file (${PATCH_FILE}) not found on the current branch. Check the path and repository structure."
  exit 1
fi

if [[ ! -f "$KUSTOMIZATION_FILE" ]]; then
  echo "Error: Kustomization file (${KUSTOMIZATION_FILE}) not found on the current branch. Check the path and repository structure."
  exit 1
fi

# Update deployment-patch.yaml
echo "Updating version labels in patch file (${PATCH_FILE})...."
yq -i ".metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$PATCH_FILE"
yq -i ".spec.template.metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$PATCH_FILE"

# Update image in kustomization
echo "Executing kustomize edit set image in ${OVERLAY_PATH}..."
(
  cd "$OVERLAY_PATH"
  kustomize edit set image "IMAGE=${REPOSITORY_URI_BRANCH}@${IMAGE_DIGEST}"
)

# Git commit
git config --local user.email "actions@github.com"
git config --local user.name "GitHub Actions"

git add "$PATCH_FILE" "$KUSTOMIZATION_FILE"

if git diff --staged --quiet; then
  echo "No changes detected."
  exit 0
fi

COMMIT_MESSAGE="Update ${TARGET_OVERLAY_DIR} overlay for ${REPOSITORY_NAME} with image digest ${IMAGE_DIGEST} (tag ${IMAGE_TAG})"
echo "Committing with message: '${COMMIT_MESSAGE}'"
git commit -m "$COMMIT_MESSAGE"
echo "Pushing to origin/${TARGET_PUSH_BRANCH}..."
git push origin "$TARGET_PUSH_BRANCH"

if [[ "$IS_PROD_FLOW" == true ]]; then
  echo "Production flow detected. Creating Bitbucket Pull Request from ${PR_HEAD_BRANCH} to ${PR_BASE_BRANCH}..."

  BITBUCKET_REPO_API_SLUG=$(echo "$ARGO_MANIFESTS_REPO_SLUG" | cut -d'/' -f2-)
  BITBUCKET_API_URL="https://api.bitbucket.org/2.0/repositories/${BITBUCKET_REPO_API_SLUG}/pullrequests"
  
  PR_TITLE="Deploy ${REPOSITORY_NAME} to Production"
  PR_BODY="Automated PR for ${REPOSITORY_NAME} from source branch ${GITHUB_REF_NAME}. Update production overlay with image digest ${IMAGE_DIGEST} (tag ${IMAGE_TAG}). Ready for review and merge to deploy to production."

  curl -X POST "$BITBUCKET_API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
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
