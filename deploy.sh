#!/usr/bin/env bash
set -euo pipefail

# --- CONFIGURATION ---
IMAGE_NAME="rust-hello"                  # Change this to your image name
REGISTRY="docker.io/allheil"         # Change to your registry (e.g., Docker Hub, GHCR, ECR)
CHART_PATH="./charts/$IMAGE_NAME"           # Path to Helm chart
RELEASE_NAME=$IMAGE_NAME                # Helm release name
NAMESPACE="default"                 # Kubernetes namespace

# --- STEP 1: Generate tag based on timestamp ---
TAG=$(date +"%Y%m%d%H%M%S")
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"
# Default to multi-arch build (override with PLATFORMS or legacy PLATFORM env vars)
PLATFORMS="${PLATFORMS:-${PLATFORM:-linux/amd64,linux/arm64}}"

echo "🕒 Generated tag: ${TAG}"
echo "📦 Full image: ${FULL_IMAGE}"
echo "🧭 Target platform(s): ${PLATFORMS}"

# --- STEP 2: Build & publish image(s) with podman buildx ---
echo "🐳 Building image(s) via podman buildx..."
if [[ "${PLATFORMS}" == *","* ]]; then
  podman -r buildx build \
    --platform "${PLATFORMS}" \
    --manifest "${FULL_IMAGE}" \
    --file Dockerfile \
    .

  echo "📤 Pushing multi-arch manifest..."
  podman -r manifest push --all "${FULL_IMAGE}" 
  # "docker://${FULL_IMAGE}"
else
  podman -r buildx build \
    --platform "${PLATFORMS}" \
    --tag "${FULL_IMAGE}" \
    --file Dockerfile \
    .

  echo "📤 Pushing image..."
  podman -r push "${FULL_IMAGE}"
fi

# --- STEP 4: Upgrade Helm release with new image tag ---
echo "🔧 Upgrading Helm release..."
helm upgrade "${RELEASE_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --set image.repository="${REGISTRY}/${IMAGE_NAME}" \
  --set image.tag="${TAG}" \
  --install

echo "✅ Deployment completed successfully!"
