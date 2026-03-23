# Ubuntu Uzerinde Containerd ile Vanilla Kubernetes Kurulum Rehberi

Bu rehber, Ubuntu 22.04 veya 24.04 uzerinde `containerd` runtime ile
vanilla Kubernetes kurulumunu anlatir. Kurulumun ortak node hazirligi
`setup_k8s.sh`, ESXi uzerindeki otomasyon akisi ise `deploy_to_esxi_vms.sh`
icinde yer alir.

Multipass kullaniyorsaniz `create_vms_multipass.sh` varsayilan olarak VM'leri
olusturduktan sonra her node icinde `setup_k8s.sh` de calistirir.

## 1. On gereksinimler

- Control-plane icin en az 2 vCPU ve 2 GB RAM onerilir.
- Tum node'lar birbirine ag seviyesinde erisebilmelidir.
- Node'larda internet cikisi olmalidir.
- SSH ile baglandiginiz kullanicida `passwordless sudo` olmali ya da direkt `root` kullanilmalidir.

## 2. Tum node'lar icin ortak kurulum

`setup_k8s.sh` su islemleri yapar:

1. Swap kapatir ve `/etc/fstab` icinde kalici hale getirir.
2. `overlay` ve `br_netfilter` modullerini yukler.
3. Kubernetes icin gerekli sysctl ayarlarini uygular.
4. Docker deposundan `containerd.io` kurar.
5. Bazi paketlerin getirdigi `disabled_plugins = ["cri"]` ayarini temizleyip CRI'yi aktif hale getirir.
6. `containerd` icin `SystemdCgroup = true` ayarini sabitler.
7. `crictl` icin `/etc/crictl.yaml` olusturur.
8. `pkgs.k8s.io` uzerinden `kubeadm`, `kubelet` ve `kubectl` kurar.
9. `kubelet` ve `containerd` servislerini enable eder.

Calistirma:

```bash
chmod +x setup_k8s.sh
sudo ./setup_k8s.sh
```

Notlar:

- Varsayilan Kubernetes repo kanali `v1.30` olarak tanimlidir.
- Farkli bir kanal icin scripti calistirmadan once `K8S_VERSION` degiskenini set edebilirsiniz.

```bash
sudo K8S_VERSION=v1.30 ./setup_k8s.sh
```

## 3. Control-plane baslatma

Master node uzerinde:

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
```

Ardindan `kubectl` kullanimi icin:

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## 4. CNI kurulumu

Bu akista varsayilan CNI olarak Flannel kullanilir:

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

`kubeadm init` icinde verilen `--pod-network-cidr=10.244.0.0/16` degeri Flannel ile uyumludur.

## 5. Worker node'lari cluster'a ekleme

`kubeadm init` sonunda uretilen join komutunu worker node'larda `sudo` ile calistirin:

```bash
sudo kubeadm join <MASTER_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

## 6. ESXi otomasyonu

`deploy_to_esxi_vms.sh` su akisi izler:

1. `setup_k8s.sh` dosyasini tum node'lara kopyalar.
2. Tum node'larda temel vanilla Kubernetes + containerd kurulumunu yapar.
3. Master node'da `kubeadm init` calistirir.
4. Flannel manifestini uygular.
5. Worker node'lari otomatik join eder.
6. Yerel makineye `~/.kube/k8s-esxi-config` olarak kubeconfig indirir.

Script tekrar calistirilabilir:

- Daha once initialize edilmis control-plane tekrar `kubeadm init` yapmaz.
- Cluster'a katilmis worker node'lari tekrar join etmez.
- Master kubeconfig dosyasini yeniden olusturur ve lokal kopyayi tazeler.

## 7. Dogrulama

Master node uzerinde veya yerel makinede indirilen kubeconfig ile:

```bash
kubectl get nodes
kubectl get pods -A
```

Tum node'lar `Ready` oldugunda vanilla Kubernetes + containerd kurulumu tamamlanmistir.

## 8. Helm

`setup_helm.sh` Helm'i ayri bir adim olarak kurar ve Helm repo/bootstrap islemlerini yapar.
Varsayilan akista su bilesenleri Helm ile kurar:

- `metrics-server`
- `ingress-nginx`

Tek node veya bare-metal ortam icin ingress servisi varsayilan olarak `NodePort` tipinde kurulur.

Calistirma:

```bash
chmod +x setup_helm.sh
./setup_helm.sh
```

Tek node ortamda varsayilan ingress portlari:

- HTTP: `30081`
- HTTPS: `30443`
