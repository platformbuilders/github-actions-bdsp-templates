#!/bin/bash

set -euo pipefail

IMAGE_TAG="$1"
IMAGE_DIGEST="$2"
GITHUB_TOKEN="$3"
REPOSITORY_NAME=$(basename "$4")

ARGO_MANIFESTS_REPO_SLUG="github.com/platformbuilders/pnb-pefisa-gitops-manifets"
ARGO_MANIFESTS_REPO_DIR="argo-manifests"

TARGET_OVERLAY_DIR=""
TARGET_MANIFEST_BRANCH=""
PR_BASE_BRANCH=""
IS_PROD_FLOW=false

if [[ "$GITHUB_REF_NAME" == "master" || "$GITHUB_REF_NAME" == "main" ]]; then
  TARGET_OVERLAY_DIR="prod"
  TARGET_MANIFEST_BRANCH="master"
  PR_BASE_BRANCH="master"
  IS_PROD_FLOW=true
elif [[ "$GITHUB_REF_NAME" == "develop" ]]; then
  TARGET_OVERLAY_DIR="develop"
  TARGET_MANIFEST_BRANCH="develop"
else
  TARGET_OVERLAY_DIR="homolog"
  TARGET_MANIFEST_BRANCH="homolog"
fi

echo "Target Overlay Directory: overlays/${TARGET_OVERLAY_DIR}"
echo "Target Manifest Branch (Initial Checkout): ${TARGET_MANIFEST_BRANCH}"
echo "Is Production Flow (Isolated PR): ${IS_PROD_FLOW}"

REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/${REPOSITORY_NAME}/${GITHUB_REF_NAME%%/*}"

# Clone manifests repo
git clone "https://${GITHUB_TOKEN}@${ARGO_MANIFESTS_REPO_SLUG}.git" "${ARGO_MANIFESTS_REPO_DIR}"
cd "${ARGO_MANIFESTS_REPO_DIR}"

if [[ "$IS_PROD_FLOW" == true ]]; then
  git fetch origin "$PR_BASE_BRANCH"
  git checkout "$PR_BASE_BRANCH"
  git reset --hard "origin/${PR_BASE_BRANCH}"
  TEMP_BRANCH_NAME="prod-update-${REPOSITORY_NAME}-${IMAGE_TAG}"
  git checkout -b "$TEMP_BRANCH_NAME"
  TARGET_PUSH_BRANCH="$TEMP_BRANCH_NAME"
  PR_HEAD_BRANCH="$TEMP_BRANCH_NAME"
else
  git fetch origin "$TARGET_MANIFEST_BRANCH"
  git checkout "$TARGET_MANIFEST_BRANCH"
  git reset --hard "origin/${TARGET_MANIFEST_BRANCH}"
  TARGET_PUSH_BRANCH="$TARGET_MANIFEST_BRANCH"
fi

OVERLAY_PATH="k8s/${REPOSITORY_NAME}/overlays/${TARGET_OVERLAY_DIR}"
PATCH_FILE="${OVERLAY_PATH}/deployment-patch.yaml"
KUSTOMIZATION_FILE="${OVERLAY_PATH}/kustomization.yaml"

# Update deployment-patch.yaml
yq -i ".metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$PATCH_FILE"
yq -i ".spec.template.metadata.labels.\"tags.datadoghq.com/version\" = \"$IMAGE_TAG\"" "$PATCH_FILE"

# Update image in kustomization
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
git commit -m "$COMMIT_MESSAGE"
git push origin "$TARGET_PUSH_BRANCH"

# Production PR logic
if [[ "$IS_PROD_FLOW" == true ]]; then
  echo "Production flow. Creating PR from ${PR_HEAD_BRANCH} to ${PR_BASE_BRANCH}."

  EXISTING_PR=$(gh pr list --repo "$ARGO_MANIFESTS_REPO_SLUG" --base "$PR_BASE_BRANCH" --head "$PR_HEAD_BRANCH" --json number --jq '.[].number' 2>/dev/null)

  if [[ -n "$EXISTING_PR" ]]; then
    echo "PR already exists (PR #${EXISTING_PR})."
  else
    PR_TITLE="Deploy ${REPOSITORY_NAME} ${IMAGE_TAG} to Production"
    PR_BODY="Automated PR for ${REPOSITORY_NAME} from source branch ${GITHUB_REF_NAME}.\n\nUpdate production overlay with image digest ${IMAGE_DIGEST} (tag ${IMAGE_TAG})."

    gh pr create --repo "$ARGO_MANIFESTS_REPO_SLUG" \
                 --title "$PR_TITLE" \
                 --body "$PR_BODY" \
                 --base "$PR_BASE_BRANCH" \
                 --head "$PR_HEAD_BRANCH"
  fi
fi
