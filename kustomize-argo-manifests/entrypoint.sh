#!/bin/bash

set -euo pipefail

IMAGE_TAG="$1"
IMAGE_DIGEST="$2"
GITHUB_TOKEN="$3"
REPOSITORY_NAME=$(basename "$4")

ARGO_MANIFESTS_REPO_SLUG="github.com/platformbuilders/pnb-pefisa-gitops-manifets"
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

REPOSITORY_URI_BRANCH="us-docker.pkg.dev/image-registry-326015/${REPOSITORY_NAME}/${GITHUB_REF_NAME%%/*}"
echo "Determined Repository URI Branch: ${REPOSITORY_URI_BRANCH}"

# Clone manifests repo
git clone "https://${GITHUB_TOKEN}@${ARGO_MANIFESTS_REPO_SLUG}.git" "${ARGO_MANIFESTS_REPO_DIR}"
cd "${ARGO_MANIFESTS_REPO_DIR}"

if [[ "$IS_PROD_FLOW" == true ]]; then
  echo "Production flow: Checking out ${PR_BASE_BRANCH} and creating temporary branch..."
  git fetch origin "$PR_BASE_BRANCH"
  git checkout "$PR_BASE_BRANCH"
  git reset --hard "origin/${PR_BASE_BRANCH}"
  TIMESTAMP=$(date +%s)
  TEMP_BRANCH_NAME="prod-update-${REPOSITORY_NAME}-${IMAGE_TAG}-${TIMESTAMP}"
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
  echo "Production flow detected. Creating Pull Request from ${PR_HEAD_BRANCH} to ${PR_BASE_BRANCH}..."

  EXISTING_PR=$(gh pr list --repo "$ARGO_MANIFESTS_REPO_SLUG" --base "$PR_BASE_BRANCH" --head "$PR_HEAD_BRANCH" --json number --jq '.[].number' 2>/dev/null)

  if [[ -n "$EXISTING_PR" ]]; then
    echo "A PR already exists from branch ${PR_HEAD_BRANCH} to ${PR_BASE_BRANCH} (PR #${EXISTING_PR}) in the manifests repo."
  else
    echo "Creating Pull Request from ${PR_HEAD_BRANCH} to ${PR_BASE_BRANCH}..."
    PR_TITLE="Deploy ${REPOSITORY_NAME} ${IMAGE_TAG} to Production"
    PR_BODY="Automated PR for ${REPOSITORY_NAME} from source branch ${GITHUB_REF_NAME}.\n\nUpdate production overlay with image digest ${IMAGE_DIGEST} (tag ${IMAGE_TAG}).\n\nReady for review and merge to deploy to production."

    gh pr create --repo "$ARGO_MANIFESTS_REPO_SLUG" \
                 --title "$PR_TITLE" \
                 --body "$PR_BODY" \
                 --base "$PR_BASE_BRANCH" \
                 --head "$PR_HEAD_BRANCH"
  fi
fi
