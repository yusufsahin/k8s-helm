#!/bin/bash
set -e

# Kubernetes Uçtan Uca Test Ortamı Orkestratörü
# Bu script mevcut VM'leri kurar, içlerinde k8s bileşenlerini yükler,
# Master'ı init eder, CNI kurar ve Worker'ları Master'a bağlar.

echo "=> 1. VM'ler kontrol ediliyor ve gerekiyorsa oluşturuluyor..."
bash create_vms_multipass.sh

echo "=> 2. K8s kurulum dosyası VM'lere gönderiliyor ve çalıştırılıyor..."
for node in k8s-master k8s-worker-1 k8s-worker-2; do
  echo "--> $node için Kubernetes bileşenleri (setup_k8s.sh) kuruluyor..."
  multipass transfer setup_k8s.sh $node:/home/ubuntu/
  # Idempotent olduğu için tekrar tekrar çalıştırılabilir
  multipass exec $node -- sudo bash /home/ubuntu/setup_k8s.sh
done

echo "=> 3. Master (Control-Plane) başlatılıyor..."
# Daha önce init edilip edilmediğini kontrol ediyoruz (admin.conf varlığına bakarak)
MASTER_INIT_CHECK=$(multipass exec k8s-master -- sudo bash -c 'if [ -f /etc/kubernetes/admin.conf ]; then echo "OK"; else echo "NO"; fi')

if [ "$MASTER_INIT_CHECK" == "NO" ]; then
  echo "--> kubeadm init çalıştırılıyor..."
  MASTER_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
  # Kendi public IP'sini API Server advertise adresi olarak veriyoruz:
  multipass exec k8s-master -- sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$MASTER_IP
  
  echo "--> Kubeconfig ayarlanıyor..."
  multipass exec k8s-master -- bash -c 'mkdir -p $HOME/.kube && sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config'

  echo "--> Flannel CNI (Ağ Eklentisi) kuruluyor..."
  multipass exec k8s-master -- kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
else
  echo "--> Master halihazırda başlatılmış, adım atlanıyor."
fi

echo "=> 4. Worker Node'lar Master'a dahil ediliyor..."
# Dinamik olarak kubeadm join komutunu master içerisinden üretiyor ve kopyalıyoruz
JOIN_CMD=$(multipass exec k8s-master -- kubeadm token create --print-join-command)

for worker in k8s-worker-1 k8s-worker-2; do
  # Worker'ın zaten kümeye katılıp katılmadığını denetliyoruz
  WORKER_JOIN_CHECK=$(multipass exec $worker -- sudo bash -c 'if [ -f /etc/kubernetes/kubelet.conf ]; then echo "OK"; else echo "NO"; fi')
  if [ "$WORKER_JOIN_CHECK" == "NO" ]; then
    echo "--> $worker kümeye katılıyor..."
    multipass exec $worker -- sudo $JOIN_CMD
  else
    echo "--> $worker zaten kümede, atlanıyor."
  fi
done

echo "=> 5. Kubeconfig dışarı (sizin uzak linux ana makinenize) çıkarılıyor..."
# Ana makinenizden k8s cluster'ını kontrol edebilmeniz için admin.conf dosyasını alıyoruz.
mkdir -p ~/.kube
multipass transfer k8s-master:/home/ubuntu/.kube/config ~/.kube/k8s-test-cluster-config
export KUBECONFIG=~/.kube/k8s-test-cluster-config

echo "========================================================================"
echo "TAM OTOMASYON BAŞARIYLA TAMAMLANDI! 🎉"
echo "Artık manuel hiçbir şey yapmanıza gerek yok. Bütün Cluster ayağa kalktı."
echo ""
echo "Ana makinenizden Cluster'ı yönetmek için şu komutu verin:"
echo "  export KUBECONFIG=~/.kube/k8s-test-cluster-config"
echo "Ardından test edin:"
echo "  kubectl get nodes"
echo ""
echo "(Eğer ana makinenizde kubectl kurulu değilse 'sudo snap install kubectl --classic' ile kurabilirsiniz)."
echo "========================================================================"
