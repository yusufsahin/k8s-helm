#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-${SCRIPT_DIR}}"
CHART_DIR="${CHART_DIR:-${REMOTE_BASE_DIR}/chart}"
IMAGE_DIR="${IMAGE_DIR:-${REMOTE_BASE_DIR}/images}"

RELEASE_NAME="${RELEASE_NAME:-notes-stack}"
NAMESPACE="${NAMESPACE:-notes-stack}"
IMAGE_TAG="${IMAGE_TAG:-0.1.0}"

API_IMAGE_REPOSITORY="${API_IMAGE_REPOSITORY:-docker.io/library/notes-stack-api}"
WEB_IMAGE_REPOSITORY="${WEB_IMAGE_REPOSITORY:-docker.io/library/notes-stack-web}"
API_ARCHIVE_NAME="${API_ARCHIVE_NAME:-notes-stack-api-${IMAGE_TAG}.tar}"
WEB_ARCHIVE_NAME="${WEB_ARCHIVE_NAME:-notes-stack-web-${IMAGE_TAG}.tar}"

POSTGRES_HOST_PATH="${POSTGRES_HOST_PATH:-/var/lib/notes-stack/postgres}"
INGRESS_HOST="${INGRESS_HOST:-}"
INGRESS_PATH="${INGRESS_PATH:-/}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
PUBLIC_HOST="${PUBLIC_HOST:-}"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi

  if [ -n "${SUDO_PASSWORD}" ]; then
    printf '%s\n' "${SUDO_PASSWORD}" | sudo -S -- "$@"
    return
  fi

  sudo -- "$@"
}

helm_set_args=(
  --set "api.image.repository=${API_IMAGE_REPOSITORY}"
  --set "api.image.tag=${IMAGE_TAG}"
  --set "web.image.repository=${WEB_IMAGE_REPOSITORY}"
  --set "web.image.tag=${IMAGE_TAG}"
  --set "postgres.persistence.hostPath=${POSTGRES_HOST_PATH}"
  --set "ingress.className=${INGRESS_CLASS_NAME}"
  --set "ingress.path=${INGRESS_PATH}"
)

if [ -n "${INGRESS_HOST}" ]; then
  helm_set_args+=(--set "ingress.host=${INGRESS_HOST}")
fi

require_command helm
require_command kubectl
require_command ctr

if [ ! -f "${CHART_DIR}/Chart.yaml" ]; then
  echo "ERROR: chart not found at ${CHART_DIR}" >&2
  exit 1
fi

if [ ! -f "${IMAGE_DIR}/${API_ARCHIVE_NAME}" ]; then
  echo "ERROR: missing API image archive ${IMAGE_DIR}/${API_ARCHIVE_NAME}" >&2
  exit 1
fi

if [ ! -f "${IMAGE_DIR}/${WEB_ARCHIVE_NAME}" ]; then
  echo "ERROR: missing web image archive ${IMAGE_DIR}/${WEB_ARCHIVE_NAME}" >&2
  exit 1
fi

echo "=> Importing API image into containerd"
run_sudo ctr -n k8s.io images import "${IMAGE_DIR}/${API_ARCHIVE_NAME}"

echo "=> Importing web image into containerd"
run_sudo ctr -n k8s.io images import "${IMAGE_DIR}/${WEB_ARCHIVE_NAME}"

echo "=> Helm lint"
helm lint "${CHART_DIR}"

echo "=> Installing/upgrading Helm release ${RELEASE_NAME}"
helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --wait \
  --timeout "${HELM_TIMEOUT}" \
  "${helm_set_args[@]}"

echo "=> Pods"
kubectl -n "${NAMESPACE}" get pods -o wide

echo "=> Services"
kubectl -n "${NAMESPACE}" get svc

echo "=> Ingress"
kubectl -n "${NAMESPACE}" get ingress

if [ -n "${PUBLIC_HOST}" ]; then
  echo "=> Suggested URL: http://${PUBLIC_HOST}:30081${INGRESS_PATH}"
elif [ -n "${INGRESS_HOST}" ]; then
  echo "=> Suggested URL: http://${INGRESS_HOST}:30081${INGRESS_PATH}"
fi
