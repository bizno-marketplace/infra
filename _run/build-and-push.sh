#!/usr/bin/env bash
set -euo pipefail

# Usage: ./build-and-push.sh <image-name> [tag]
#
# Ex (tag defaults to the git short SHA):
#   ./build-and-push.sh auth-service
#   ./build-and-push.sh discovery-server
#   ./build-and-push.sh config-server
#   ./build-and-push.sh api-gateway
#
# Ex (custom tag):
#   ./build-and-push.sh auth-service xd
#
# Run this script from the infra repo root. Service repos are expected as
# siblings:
#
#   Bizno/
#     auth-service/
#     api-gateway/
#     discovery-server/
#     configserver/
#     infra/
#       build-and-push.sh   <- you are here
#
# If no tag is passed, it defaults to the short SHA of the current commit
# in that repo (e.g. a1b2c3d) — never :latest. This guarantees every build
# has a unique, traceable tag, so Kubernetes reliably detects the image
# change and rolls out.
#
# Repo path and k8s manifest path are both fixed per service (see the
# case block below) — never passed as arguments, they never change.
#
# After building and pushing, this script:
#   1. Patches the `image:` tag in that service's manifest.
#   2. Applies the manifest to the cluster and waits for rollout.

DOCKERHUB_USER="gervasioartur"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <image-name> [tag]"
  exit 1
fi

IMAGE_NAME="$1"
CUSTOM_TAG="${2:-}"

case "$IMAGE_NAME" in
  auth-service)
    REPO_PATH="../../auth-service"
    MANIFEST_PATH="../../auth-service/k8s/service/deployment.yml"
    ;;
  discovery-server)
    REPO_PATH="../../discovery-server"
    MANIFEST_PATH="../../discovery-server/k8s/deployment.yml"
    ;;
  configserver)
    REPO_PATH="../../configserver"
    MANIFEST_PATH="../../configserver/k8s/deployment.yml"
    ;;
  api-gateway)
    REPO_PATH="../../api-gateway"
    MANIFEST_PATH="../../api-gateway/k8s/deployment.yml"
    ;;
  *)
    echo "ERROR: unknown image name '$IMAGE_NAME'." >&2
    echo "Known names: auth-service, discovery-server, config-server, api-gateway" >&2
    exit 1
    ;;
esac

pushd "$REPO_PATH" > /dev/null

if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: there are uncommitted changes in $REPO_PATH."
  echo "The tag will reflect the last commit, not the current working tree."
fi

if [ -n "$CUSTOM_TAG" ]; then
  TAG="$CUSTOM_TAG"
else
  TAG=$(git rev-parse --short HEAD)
fi

FULL_IMAGE="${DOCKERHUB_USER}/${IMAGE_NAME}:${TAG}"

echo ">> Building ${FULL_IMAGE}..."
docker build -t "${FULL_IMAGE}" .

echo ">> Pushing ${FULL_IMAGE}..."
docker push "${FULL_IMAGE}"

popd > /dev/null

if [ ! -f "$MANIFEST_PATH" ]; then
  echo "ERROR: manifest not found at $MANIFEST_PATH" >&2
  exit 1
fi

echo ">> Updating image tag in ${MANIFEST_PATH}..."
sed -i.bak -E "s|(image: ${DOCKERHUB_USER}/${IMAGE_NAME}:)[^[:space:]]+|\1${TAG}|" "$MANIFEST_PATH"
rm -f "${MANIFEST_PATH}.bak"

echo ">> Applying ${MANIFEST_PATH} to the cluster..."
kubectl apply -f "$MANIFEST_PATH"

echo ">> Waiting for rollout..."
kubectl rollout status "deployment/${IMAGE_NAME}" -n bizno

echo ""
echo "Done. Image published: ${FULL_IMAGE}"
echo "Manifest updated and applied: ${MANIFEST_PATH}"