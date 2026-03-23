#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${SCRIPT_DIR}/.artifacts}"

LOCAL_API_IMAGE_REPO="${LOCAL_API_IMAGE_REPO:-notes-stack-api}"
LOCAL_WEB_IMAGE_REPO="${LOCAL_WEB_IMAGE_REPO:-notes-stack-web}"
IMAGE_TAG="${IMAGE_TAG:-0.1.0}"

api_archive_name() {
  local repo_name
  repo_name="${LOCAL_API_IMAGE_REPO##*/}"
  printf '%s-%s.tar' "${repo_name}" "${IMAGE_TAG}"
}

web_archive_name() {
  local repo_name
  repo_name="${LOCAL_WEB_IMAGE_REPO##*/}"
  printf '%s-%s.tar' "${repo_name}" "${IMAGE_TAG}"
}

echo "=> Building API image ${LOCAL_API_IMAGE_REPO}:${IMAGE_TAG}"
docker build -t "${LOCAL_API_IMAGE_REPO}:${IMAGE_TAG}" "${SCRIPT_DIR}/src/Notes.Api"

echo "=> Building web image ${LOCAL_WEB_IMAGE_REPO}:${IMAGE_TAG}"
docker build -t "${LOCAL_WEB_IMAGE_REPO}:${IMAGE_TAG}" "${SCRIPT_DIR}/web"

mkdir -p "${ARTIFACTS_DIR}"

echo "=> Exporting API image archive"
docker save -o "${ARTIFACTS_DIR}/$(api_archive_name)" "${LOCAL_API_IMAGE_REPO}:${IMAGE_TAG}"

echo "=> Exporting web image archive"
docker save -o "${ARTIFACTS_DIR}/$(web_archive_name)" "${LOCAL_WEB_IMAGE_REPO}:${IMAGE_TAG}"

echo "=> Artifacts ready:"
echo "   ${ARTIFACTS_DIR}/$(api_archive_name)"
echo "   ${ARTIFACTS_DIR}/$(web_archive_name)"
