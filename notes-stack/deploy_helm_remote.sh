#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${SCRIPT_DIR}/.artifacts}"
CHART_DIR="${CHART_DIR:-${SCRIPT_DIR}/helm/notes-stack}"
REMOTE_SCRIPT_LOCAL="${REMOTE_SCRIPT_LOCAL:-${SCRIPT_DIR}/remote_install_helm_release.sh}"

REMOTE_HOST="${REMOTE_HOST:-192.168.106.130}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_USER="${REMOTE_USER:-frs}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/home/${REMOTE_USER}/notes-stack-deploy}"
SSH_PASSWORD="${SSH_PASSWORD:-}"

RELEASE_NAME="${RELEASE_NAME:-notes-stack}"
NAMESPACE="${NAMESPACE:-notes-stack}"
IMAGE_TAG="${IMAGE_TAG:-0.1.0}"
LOCAL_API_IMAGE_REPO="${LOCAL_API_IMAGE_REPO:-notes-stack-api}"
LOCAL_WEB_IMAGE_REPO="${LOCAL_WEB_IMAGE_REPO:-notes-stack-web}"
API_IMAGE_REPOSITORY="${API_IMAGE_REPOSITORY:-docker.io/library/notes-stack-api}"
WEB_IMAGE_REPOSITORY="${WEB_IMAGE_REPOSITORY:-docker.io/library/notes-stack-web}"
INGRESS_HOST="${INGRESS_HOST:-}"
INGRESS_PATH="${INGRESS_PATH:-/}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
POSTGRES_HOST_PATH="${POSTGRES_HOST_PATH:-/var/lib/notes-stack/postgres}"
PUBLIC_HOST="${PUBLIC_HOST:-${REMOTE_HOST}}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

quote() {
  printf '%q' "$1"
}

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

use_paramiko() {
  [ -n "${SSH_PASSWORD}" ] || return 1
  command -v python >/dev/null 2>&1 || return 1
  python -c 'import paramiko' >/dev/null 2>&1
}

upload_and_run_with_paramiko() {
  export SCRIPT_DIR ARTIFACTS_DIR CHART_DIR REMOTE_SCRIPT_LOCAL
  export REMOTE_HOST REMOTE_PORT REMOTE_USER REMOTE_BASE_DIR SSH_PASSWORD
  export RELEASE_NAME NAMESPACE IMAGE_TAG API_IMAGE_REPOSITORY WEB_IMAGE_REPOSITORY
  export INGRESS_HOST INGRESS_PATH INGRESS_CLASS_NAME HELM_TIMEOUT POSTGRES_HOST_PATH PUBLIC_HOST
  export API_ARCHIVE_NAME="$(api_archive_name)"
  export WEB_ARCHIVE_NAME="$(web_archive_name)"

  python <<'PY'
import os
import posixpath
import shlex
import sys
import paramiko

def normalize_msys_path(value: str) -> str:
    normalized = value.replace("\\", "/")
    for prefix in ("C:/Program Files/Git", "C:/Program Files (x86)/Git"):
        if normalized.startswith(prefix):
            rest = normalized[len(prefix):]
            return rest or "/"
    return normalized

host = os.environ["REMOTE_HOST"]
port = int(os.environ["REMOTE_PORT"])
user = os.environ["REMOTE_USER"]
password = os.environ["SSH_PASSWORD"]
remote_base_dir = normalize_msys_path(os.environ["REMOTE_BASE_DIR"])
remote_chart_dir = posixpath.join(remote_base_dir, "chart")
remote_images_dir = posixpath.join(remote_base_dir, "images")
remote_script_path = posixpath.join(remote_base_dir, "remote_install_helm_release.sh")
local_chart_dir = os.environ["CHART_DIR"]
local_script_path = os.environ["REMOTE_SCRIPT_LOCAL"]
local_artifacts_dir = os.environ["ARTIFACTS_DIR"]

api_archive_name = os.environ["API_ARCHIVE_NAME"]
web_archive_name = os.environ["WEB_ARCHIVE_NAME"]

env_names = [
    "REMOTE_BASE_DIR",
    "RELEASE_NAME",
    "NAMESPACE",
    "IMAGE_TAG",
    "API_IMAGE_REPOSITORY",
    "WEB_IMAGE_REPOSITORY",
    "API_ARCHIVE_NAME",
    "WEB_ARCHIVE_NAME",
    "INGRESS_HOST",
    "INGRESS_PATH",
    "INGRESS_CLASS_NAME",
    "HELM_TIMEOUT",
    "POSTGRES_HOST_PATH",
    "PUBLIC_HOST",
]

normalized_env_values = {
    "REMOTE_BASE_DIR": remote_base_dir,
    "INGRESS_PATH": normalize_msys_path(os.environ.get("INGRESS_PATH", "")),
    "POSTGRES_HOST_PATH": normalize_msys_path(os.environ.get("POSTGRES_HOST_PATH", "")),
}

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(
    host,
    port=port,
    username=user,
    password=password,
    look_for_keys=False,
    allow_agent=False,
    timeout=30,
)
sftp = client.open_sftp()

def ensure_dir(path: str) -> None:
    stdin, stdout, stderr = client.exec_command(f"mkdir -p {shlex.quote(path)}")
    exit_code = stdout.channel.recv_exit_status()
    if exit_code != 0:
        raise RuntimeError(stderr.read().decode("utf-8", errors="replace"))

def upload_tree(local_root: str, remote_root: str) -> None:
    for root, dirs, files in os.walk(local_root):
        rel_root = os.path.relpath(root, local_root)
        target_root = remote_root if rel_root == "." else posixpath.join(remote_root, *rel_root.split(os.sep))
        ensure_dir(target_root)
        for file_name in files:
            local_path = os.path.join(root, file_name)
            remote_path = posixpath.join(target_root, file_name)
            print(f"Uploading {local_path} -> {remote_path}")
            sftp.put(local_path, remote_path)

ensure_dir(remote_images_dir)
ensure_dir(remote_chart_dir)

for archive_name in (api_archive_name, web_archive_name):
    local_path = os.path.join(local_artifacts_dir, archive_name)
    remote_path = posixpath.join(remote_images_dir, archive_name)
    print(f"Uploading {local_path} -> {remote_path}")
    sftp.put(local_path, remote_path)

print(f"Uploading {local_script_path} -> {remote_script_path}")
sftp.put(local_script_path, remote_script_path)
upload_tree(local_chart_dir, remote_chart_dir)
sftp.close()

env_parts = [f"SUDO_PASSWORD={os.environ['SSH_PASSWORD']}"]
for name in env_names:
    value = normalized_env_values.get(name, os.environ.get(name, ""))
    env_parts.append(f"{name}={value}")

env_prefix = " ".join(f"{name}={shlex.quote(value)}" for name, value in (part.split("=", 1) for part in env_parts))
command = f"chmod +x {shlex.quote(remote_script_path)} && {env_prefix} bash {shlex.quote(remote_script_path)}"
stdin, stdout, stderr = client.exec_command(command, get_pty=True)
exit_code = stdout.channel.recv_exit_status()
sys.stdout.write(stdout.read().decode("utf-8", errors="replace"))
sys.stderr.write(stderr.read().decode("utf-8", errors="replace"))
client.close()
if exit_code != 0:
    raise SystemExit(exit_code)
PY
}

upload_and_run_with_ssh() {
  require_command ssh
  require_command scp

  local ssh_cmd=(ssh -p "${REMOTE_PORT}" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}")
  local scp_cmd=(scp -P "${REMOTE_PORT}" -o StrictHostKeyChecking=no)

  "${ssh_cmd[@]}" "mkdir -p $(quote "${REMOTE_BASE_DIR}/images") $(quote "${REMOTE_BASE_DIR}/chart")"
  "${scp_cmd[@]}" "${ARTIFACTS_DIR}/$(api_archive_name)" "${REMOTE_USER}@${REMOTE_HOST}:$(quote "${REMOTE_BASE_DIR}/images/$(api_archive_name)")"
  "${scp_cmd[@]}" "${ARTIFACTS_DIR}/$(web_archive_name)" "${REMOTE_USER}@${REMOTE_HOST}:$(quote "${REMOTE_BASE_DIR}/images/$(web_archive_name)")"
  "${scp_cmd[@]}" "${REMOTE_SCRIPT_LOCAL}" "${REMOTE_USER}@${REMOTE_HOST}:$(quote "${REMOTE_BASE_DIR}/remote_install_helm_release.sh")"
  "${ssh_cmd[@]}" "mkdir -p $(quote "${REMOTE_BASE_DIR}/chart")"
  tar -C "${CHART_DIR}" -czf - . | "${ssh_cmd[@]}" "tar -xzf - -C $(quote "${REMOTE_BASE_DIR}/chart")"

  local remote_env=(
    "REMOTE_BASE_DIR=${REMOTE_BASE_DIR}"
    "RELEASE_NAME=${RELEASE_NAME}"
    "NAMESPACE=${NAMESPACE}"
    "IMAGE_TAG=${IMAGE_TAG}"
    "API_IMAGE_REPOSITORY=${API_IMAGE_REPOSITORY}"
    "WEB_IMAGE_REPOSITORY=${WEB_IMAGE_REPOSITORY}"
    "API_ARCHIVE_NAME=$(api_archive_name)"
    "WEB_ARCHIVE_NAME=$(web_archive_name)"
    "INGRESS_HOST=${INGRESS_HOST}"
    "INGRESS_PATH=${INGRESS_PATH}"
    "INGRESS_CLASS_NAME=${INGRESS_CLASS_NAME}"
    "HELM_TIMEOUT=${HELM_TIMEOUT}"
    "POSTGRES_HOST_PATH=${POSTGRES_HOST_PATH}"
    "PUBLIC_HOST=${PUBLIC_HOST}"
  )

  if [ -n "${SSH_PASSWORD}" ]; then
    remote_env+=("SUDO_PASSWORD=${SSH_PASSWORD}")
  fi

  local remote_command=""
  local item
  for item in "${remote_env[@]}"; do
    remote_command+="$(quote "${item}") "
  done
  remote_command+="bash $(quote "${REMOTE_BASE_DIR}/remote_install_helm_release.sh")"
  "${ssh_cmd[@]}" "${remote_command}"
}

require_command docker

if [ ! -f "${CHART_DIR}/Chart.yaml" ]; then
  echo "ERROR: chart not found at ${CHART_DIR}" >&2
  exit 1
fi

if [ ! -f "${REMOTE_SCRIPT_LOCAL}" ]; then
  echo "ERROR: remote install script not found at ${REMOTE_SCRIPT_LOCAL}" >&2
  exit 1
fi

echo "=> Building and exporting images"
ARTIFACTS_DIR="${ARTIFACTS_DIR}" \
LOCAL_API_IMAGE_REPO="${LOCAL_API_IMAGE_REPO}" \
LOCAL_WEB_IMAGE_REPO="${LOCAL_WEB_IMAGE_REPO}" \
IMAGE_TAG="${IMAGE_TAG}" \
bash "${SCRIPT_DIR}/build_images.sh"

if use_paramiko; then
  echo "=> Using python/paramiko for upload and remote execution"
  upload_and_run_with_paramiko
else
  echo "=> Using ssh/scp for upload and remote execution"
  upload_and_run_with_ssh
fi

echo "=> Deploy finished"
echo "=> URL: http://${PUBLIC_HOST}:30081${INGRESS_PATH}"
