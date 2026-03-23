#!/usr/bin/env bash
set -euo pipefail

# Helm bootstrap scripti. Helm CLI kurar, resmi repolari ekler ve istenirse
# temel chart'lari yukler.

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export KUBECONFIG
INSTALL_METRICS_SERVER="${INSTALL_METRICS_SERVER:-true}"
INSTALL_INGRESS_NGINX="${INSTALL_INGRESS_NGINX:-true}"
INSTALL_CERT_MANAGER="${INSTALL_CERT_MANAGER:-false}"
WAIT_FOR_ROLLOUTS="${WAIT_FOR_ROLLOUTS:-true}"

INGRESS_SERVICE_TYPE="${INGRESS_SERVICE_TYPE:-NodePort}"
INGRESS_HTTP_NODEPORT="${INGRESS_HTTP_NODEPORT:-30081}"
INGRESS_HTTPS_NODEPORT="${INGRESS_HTTPS_NODEPORT:-30443}"

HELM_APT_KEYRING="/usr/share/keyrings/helm.gpg"
HELM_APT_SOURCE="/etc/apt/sources.list.d/helm-stable-debian.list"
HELM_APT_REPO="deb [signed-by=${HELM_APT_KEYRING}] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main"

SUDO=""
[ "${EUID}" -ne 0 ] && SUDO="sudo"

HELM_WAIT_ARGS=()
if [ "${WAIT_FOR_ROLLOUTS}" = "true" ]; then
  HELM_WAIT_ARGS=(--wait --timeout 10m)
fi

ensure_kubeconfig() {
  if [ ! -f "${KUBECONFIG}" ]; then
    echo "ERROR: kubeconfig bulunamadi: ${KUBECONFIG}"
    echo "Scripti cluster yonetici kullanicisi ile calistirin veya KUBECONFIG belirtin."
    exit 1
  fi
}

ensure_helm() {
  echo "=> Installing Helm CLI..."
  ${SUDO} apt-get update -qq
  ${SUDO} apt-get install -y -qq apt-transport-https ca-certificates curl gpg

  ${SUDO} install -m 0755 -d "$(dirname "${HELM_APT_KEYRING}")"
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | \
    gpg --dearmor | ${SUDO} tee "${HELM_APT_KEYRING}" > /dev/null
  ${SUDO} chmod a+r "${HELM_APT_KEYRING}"
  echo "${HELM_APT_REPO}" | ${SUDO} tee "${HELM_APT_SOURCE}" > /dev/null

  ${SUDO} apt-get update -qq
  if ! dpkg -s helm > /dev/null 2>&1; then
    ${SUDO} apt-get install -y -qq helm
  else
    echo "Helm is already installed, skipping package install."
  fi
}

ensure_repos() {
  echo "=> Adding Helm repos..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm repo update
}

install_metrics_server() {
  [ "${INSTALL_METRICS_SERVER}" = "true" ] || return 0

  local values_file
  values_file="$(mktemp)"
  cat <<'EOF' > "${values_file}"
apiService:
  insecureSkipTLSVerify: true
args:
  - --kubelet-insecure-tls
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
EOF

  echo "=> Installing metrics-server..."
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system \
    -f "${values_file}" \
    "${HELM_WAIT_ARGS[@]}"

  rm -f "${values_file}"
}

install_ingress_nginx() {
  [ "${INSTALL_INGRESS_NGINX}" = "true" ] || return 0

  local values_file
  values_file="$(mktemp)"

  echo "=> Installing ingress-nginx..."
  if [ "${INGRESS_SERVICE_TYPE}" = "NodePort" ]; then
    cat <<EOF > "${values_file}"
controller:
  watchIngressWithoutClass: true
  ingressClassResource:
    default: true
  service:
    type: NodePort
    nodePorts:
      http: ${INGRESS_HTTP_NODEPORT}
      https: ${INGRESS_HTTPS_NODEPORT}
EOF

    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      -f "${values_file}" \
      "${HELM_WAIT_ARGS[@]}"
  else
    cat <<EOF > "${values_file}"
controller:
  watchIngressWithoutClass: true
  ingressClassResource:
    default: true
  service:
    type: ${INGRESS_SERVICE_TYPE}
EOF

    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
      --namespace ingress-nginx \
      --create-namespace \
      -f "${values_file}" \
      "${HELM_WAIT_ARGS[@]}"
  fi

  rm -f "${values_file}"
}

install_cert_manager() {
  [ "${INSTALL_CERT_MANAGER}" = "true" ] || return 0

  echo "=> Installing cert-manager..."
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    "${HELM_WAIT_ARGS[@]}"
}

print_summary() {
  echo "=> Helm releases:"
  helm list -A

  if [ "${INSTALL_INGRESS_NGINX}" = "true" ]; then
    echo "=> ingress-nginx service:"
    kubectl --kubeconfig "${KUBECONFIG}" -n ingress-nginx get svc
  fi

  if [ "${INSTALL_METRICS_SERVER}" = "true" ]; then
    echo "=> metrics API status:"
    kubectl --kubeconfig "${KUBECONFIG}" top nodes || true
  fi
}

ensure_kubeconfig
ensure_helm
ensure_repos
install_metrics_server
install_ingress_nginx
install_cert_manager
print_summary
