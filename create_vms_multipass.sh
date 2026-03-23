#!/usr/bin/env bash
set -euo pipefail

# Multipass uzerinde vanilla Kubernetes icin 1 control-plane ve N worker
# Ubuntu VM olusturur. Var olan instance'lari yeniden yaratmaz; durmuslarsa
# tekrar baslatir. Varsayilan olarak setup_k8s.sh ile node hazirligini da yapar.

UBUNTU_IMAGE="${UBUNTU_IMAGE:-24.04}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="${SETUP_SCRIPT:-${SCRIPT_DIR}/setup_k8s.sh}"
HELM_SCRIPT="${HELM_SCRIPT:-${SCRIPT_DIR}/setup_helm.sh}"
AUTO_SETUP_NODES="${AUTO_SETUP_NODES:-true}"

MASTER_NAME="k8s-master"
MASTER_CPU="${MASTER_CPU:-2}"
MASTER_MEM="${MASTER_MEM:-2G}"
MASTER_DISK="${MASTER_DISK:-15G}"

WORKER_PREFIX="k8s-worker"
WORKER_CPU="${WORKER_CPU:-2}"
WORKER_MEM="${WORKER_MEM:-2G}"
WORKER_DISK="${WORKER_DISK:-15G}"
WORKER_COUNT="${WORKER_COUNT:-2}"

has_command() {
  command -v "$1" >/dev/null 2>&1
}

ensure_snapd() {
  if has_command snap; then
    return
  fi

  if ! has_command apt-get; then
    echo "ERROR: snap komutu bulunamadi ve apt-get de yok."
    echo "Multipass'i once host uzerinde manuel kurun."
    exit 1
  fi

  echo "=> snapd bulunamadi. apt ile kuruluyor..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq snapd
  sudo systemctl enable --now snapd.socket >/dev/null 2>&1 || true
}

ensure_multipass() {
  echo "=> Multipass kontrol ediliyor..."

  if has_command multipass; then
    echo "Multipass zaten yuklu."
    return
  fi

  ensure_snapd
  echo "Multipass bulunamadi. Snap ile kuruluyor..."
  sudo snap install multipass
}

ensure_multipass_access() {
  local socket="/var/snap/multipass/common/multipass_socket"

  if [ -S "${socket}" ] && [ "$(id -u)" -ne 0 ]; then
    local socket_group
    socket_group="$(stat -c '%G' "${socket}")"

    if ! id -nG | tr ' ' '\n' | grep -Fxq "${socket_group}"; then
      echo "ERROR: Mevcut kullanici multipass socket grubunda degil: ${socket_group}"
      echo "Cozum: kullaniciyi ilgili gruba ekleyin ve oturumu yeniden acin."
      exit 1
    fi
  fi

  if ! multipass list >/dev/null 2>&1; then
    echo "ERROR: Multipass daemon veya socket erisimi dogrulanamadi."
    echo "Cozum: 'multipass version' ve 'multipass list' komutlarini hostta kontrol edin."
    exit 1
  fi
}

ensure_setup_script() {
  if [ ! -f "${SETUP_SCRIPT}" ]; then
    echo "ERROR: setup script bulunamadi: ${SETUP_SCRIPT}"
    exit 1
  fi
}

instance_exists() {
  multipass info "$1" >/dev/null 2>&1
}

instance_state() {
  multipass info "$1" | awk -F': ' '$1 == "State" { print $2; exit }'
}

ensure_instance() {
  local name="$1"
  local cpus="$2"
  local memory="$3"
  local disk="$4"
  local state=""

  if instance_exists "${name}"; then
    echo "--> ${name} zaten mevcut."
    echo "    Not: CPU/RAM/disk degerleri mevcut instance icin otomatik degistirilmez."

    state="$(instance_state "${name}")"
    case "${state}" in
      Running)
        echo "    Instance zaten calisiyor."
        ;;
      Stopped|Suspended)
        echo "    Instance durumu '${state}'. Start ediliyor..."
        multipass start "${name}"
        ;;
      *)
        echo "    Instance durumu '${state:-Unknown}'. Start deneniyor..."
        multipass start "${name}"
        ;;
    esac
  else
    echo "--> ${name} olusturuluyor..."
    multipass launch "${UBUNTU_IMAGE}" \
      --name "${name}" \
      --cpus "${cpus}" \
      --memory "${memory}" \
      --disk "${disk}"
  fi

  multipass exec "${name}" -- true >/dev/null
}

provision_instance() {
  local name="$1"

  echo "--> ${name} icin setup_k8s.sh kopyalaniyor..."
  multipass transfer "${SETUP_SCRIPT}" "${name}:/home/ubuntu/setup_k8s.sh"

  echo "--> ${name} icin containerd + Kubernetes paketleri kuruluyor..."
  multipass exec "${name}" -- sudo bash /home/ubuntu/setup_k8s.sh
}

ensure_multipass
ensure_multipass_access

if [ "${AUTO_SETUP_NODES}" = "true" ]; then
  ensure_setup_script
fi

echo "=> Control-plane node hazirlaniyor (${MASTER_NAME})..."
ensure_instance "${MASTER_NAME}" "${MASTER_CPU}" "${MASTER_MEM}" "${MASTER_DISK}"

for ((i=1; i<=WORKER_COUNT; i++)); do
  worker_name="${WORKER_PREFIX}-${i}"
  echo "=> Worker node hazirlaniyor (${worker_name})..."
  ensure_instance "${worker_name}" "${WORKER_CPU}" "${WORKER_MEM}" "${WORKER_DISK}"
done

if [ "${AUTO_SETUP_NODES}" = "true" ]; then
  echo "=> Tum node'larda setup_k8s.sh calistiriliyor..."
  provision_instance "${MASTER_NAME}"

  for ((i=1; i<=WORKER_COUNT; i++)); do
    worker_name="${WORKER_PREFIX}-${i}"
    provision_instance "${worker_name}"
  done
else
  echo "=> AUTO_SETUP_NODES=false, node hazirlama adimi atlandi."
fi

echo "--------------------------------------------------------"
echo "VM'ler hazir. Guncel durum ve IP adresleri:"
multipass list
echo "--------------------------------------------------------"

echo "Kullanim ipuclari:"
echo "1. Master shell acmak icin      : multipass shell ${MASTER_NAME}"
echo "2. Master init icin             : multipass exec ${MASTER_NAME} -- sudo kubeadm init --pod-network-cidr=10.244.0.0/16"
echo "3. Otomatik node setup kapatmak : AUTO_SETUP_NODES=false ./create_vms_multipass.sh"
echo "4. Helm bootstrap scripti       : multipass transfer ${HELM_SCRIPT} ${MASTER_NAME}:/home/ubuntu/ && multipass exec ${MASTER_NAME} -- bash /home/ubuntu/setup_helm.sh"
