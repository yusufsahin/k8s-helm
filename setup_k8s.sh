#!/usr/bin/env bash
set -euo pipefail

# Idempotent vanilla Kubernetes (kubeadm, kubelet, kubectl) + containerd
# kurulum scripti. Ubuntu 22.04 / 24.04 icin hedeflenmistir.

K8S_VERSION="${K8S_VERSION:-v1.30}"
export DEBIAN_FRONTEND=noninteractive

echo "=> Checking if running as root..."
if [ "${EUID}" -ne 0 ]; then
  echo "Please run as root (use sudo ./setup_k8s.sh)"
  exit 1
fi

echo "=> Disabling swap..."
swapoff -a
sed -ri '/^[^#].*\sswap\s/s/^/#/' /etc/fstab

echo "=> Loading kernel modules..."
cat <<'EOF' | tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "=> Setting sysctl params..."
cat <<'EOF' | tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system > /dev/null

echo "=> Installing dependencies..."
apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gpg lsb-release

echo "=> Installing containerd..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
if ! dpkg -s containerd.io > /dev/null 2>&1; then
  apt-get install -y -qq containerd.io
else
  echo "containerd is already installed, ensuring configuration..."
fi

echo "=> Configuring containerd..."
install -m 0755 -d /etc/containerd

# Some distro packages ship a config that disables the CRI plugin.
if [ ! -f /etc/containerd/config.toml ] || grep -Eq '^\s*disabled_plugins\s*=.*\bcri\b' /etc/containerd/config.toml; then
  containerd config default | tee /etc/containerd/config.toml > /dev/null
fi

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sed -i 's/systemd_cgroup = false/systemd_cgroup = true/g' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd
systemctl is-active --quiet containerd

echo "=> Writing crictl config..."
cat <<'EOF' | tee /etc/crictl.yaml > /dev/null
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
pull-image-on-create: false
EOF

echo "=> Installing Kubernetes components (kubeadm, kubelet, kubectl)..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

echo \
  "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

apt-get update -qq
if ! dpkg -s kubeadm kubelet kubectl > /dev/null 2>&1; then
  apt-get install -y -qq kubelet kubeadm kubectl
else
  echo "Kubernetes components are already installed, ensuring service state..."
fi

apt-mark hold kubelet kubeadm kubectl > /dev/null
systemctl enable --now kubelet

echo "=> Setup completed successfully on this node."
echo "--------------------------------------------------------"
echo "If this is the control-plane node, you can now run:"
echo "  sudo kubeadm init --pod-network-cidr=10.244.0.0/16"
echo
echo "If this is a worker node, wait for the control-plane initialization"
echo "and use the generated 'kubeadm join' command."
echo "--------------------------------------------------------"
