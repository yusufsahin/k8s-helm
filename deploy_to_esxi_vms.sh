#!/usr/bin/env bash
set -euo pipefail

# VMware ESXi uzerindeki Ubuntu sanal makinelerine vanilla Kubernetes
# (kubeadm + kubelet + kubectl) ve containerd kurulumu yapar.

MASTER_IP="192.168.1.10"
WORKER1_IP="192.168.1.11"
WORKER2_IP="192.168.1.12"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="${SETUP_SCRIPT:-${SCRIPT_DIR}/setup_k8s.sh}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_ARGS=(-o StrictHostKeyChecking=no)
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
FLANNEL_MANIFEST_URL="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"

WORKER_IPS=()
[ -n "${WORKER1_IP}" ] && WORKER_IPS+=("${WORKER1_IP}")
[ -n "${WORKER2_IP}" ] && WORKER_IPS+=("${WORKER2_IP}")

run_ssh() {
  local ip="$1"
  shift
  ssh "${SSH_ARGS[@]}" "${SSH_USER}@${ip}" "$@"
}

run_scp() {
  scp "${SSH_ARGS[@]}" "$@"
}

require_passwordless_sudo() {
  local ip="$1"

  if ! run_ssh "${ip}" "sudo -n true" >/dev/null 2>&1; then
    echo "ERROR: ${SSH_USER}@${ip} icin passwordless sudo gerekli."
    echo "Cozum: root kullanin veya ${SSH_USER} icin NOPASSWD sudo tanimlayin."
    exit 1
  fi
}

require_local_setup_script() {
  if [ ! -f "${SETUP_SCRIPT}" ]; then
    echo "ERROR: setup script bulunamadi: ${SETUP_SCRIPT}"
    exit 1
  fi
}

ensure_remote_kubeconfig() {
  run_ssh "${MASTER_IP}" \
    'mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config'
}

copy_kubeconfig_to_local() {
  mkdir -p ~/.kube
  run_ssh "${MASTER_IP}" \
    'sudo install -o $(id -u) -g $(id -g) -m 600 /etc/kubernetes/admin.conf /tmp/k8s-esxi-config'
  run_scp "${SSH_USER}@${MASTER_IP}:/tmp/k8s-esxi-config" ~/.kube/k8s-esxi-config
  run_ssh "${MASTER_IP}" 'rm -f /tmp/k8s-esxi-config'
}

echo "=> 1. setup_k8s.sh tum node'lara kopyalaniyor ve calistiriliyor..."
require_local_setup_script
for ip in "${MASTER_IP}" "${WORKER_IPS[@]}"; do
  echo "--> ${ip} icin sudo erisimi ve paket kurulumu kontrol ediliyor..."
  require_passwordless_sudo "${ip}"
  run_scp "${SETUP_SCRIPT}" "${SSH_USER}@${ip}:/tmp/setup_k8s.sh"
  run_ssh "${ip}" "chmod +x /tmp/setup_k8s.sh && sudo /tmp/setup_k8s.sh"
done

echo "=> 2. Control-plane (${MASTER_IP}) hazirlaniyor..."
MASTER_INIT_CHECK=$(run_ssh "${MASTER_IP}" 'sudo test -f /etc/kubernetes/admin.conf && echo OK || echo NO')

if [ "${MASTER_INIT_CHECK}" = "NO" ]; then
  echo "--> kubeadm init calistiriliyor..."
  run_ssh "${MASTER_IP}" \
    "sudo kubeadm init --pod-network-cidr=${POD_NETWORK_CIDR} --apiserver-advertise-address=${MASTER_IP}"
else
  echo "--> Control-plane zaten initialize edilmis."
fi

echo "--> Master kubeconfig hazirlaniyor..."
ensure_remote_kubeconfig

echo "--> Flannel CNI uygulaniyor..."
run_ssh "${MASTER_IP}" \
  "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f ${FLANNEL_MANIFEST_URL}"

if [ "${#WORKER_IPS[@]}" -gt 0 ]; then
  echo "=> 3. Worker node'lar cluster'a dahil ediliyor..."
  JOIN_CMD=$(run_ssh "${MASTER_IP}" "sudo kubeadm token create --print-join-command")

  for worker_ip in "${WORKER_IPS[@]}"; do
    WORKER_JOIN_CHECK=$(run_ssh "${worker_ip}" 'sudo test -f /etc/kubernetes/kubelet.conf && echo OK || echo NO')
    if [ "${WORKER_JOIN_CHECK}" = "NO" ]; then
      echo "--> Worker ${worker_ip} cluster'a katiliyor..."
      run_ssh "${worker_ip}" "sudo ${JOIN_CMD}"
    else
      echo "--> Worker ${worker_ip} zaten cluster uyesi."
    fi
  done
else
  echo "=> 3. Worker listesi bos, worker join adimi atlandi."
fi

echo "=> 4. Kubeconfig yerel makineye kopyalaniyor..."
copy_kubeconfig_to_local

echo "========================================================================"
echo "ESXi uzerindeki vanilla Kubernetes + containerd kurulumu tamamlandi."
echo "Bu makinede cluster'i yonetmek icin:"
echo "export KUBECONFIG=~/.kube/k8s-esxi-config"
echo "kubectl get nodes"
echo "========================================================================"
