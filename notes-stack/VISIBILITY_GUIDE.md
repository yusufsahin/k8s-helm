# Notes Stack Visibility Guide

Bu guide'in amaci `notes-stack` uygulamasini farkli ortamlarda nasil gorunur kilacagimizi netlestirmek.

Kisa cevap:

- Local Docker testinde UI zaten gorunur: `http://localhost:18080`
- Ayni agdan gorunur yapmak icin host IP + firewall gerekir
- Kubernetes'te hizli test icin `NodePort`
- Kubernetes'te dogru yol `Ingress`

## Mimari

Akis su:

`Browser -> notes-web (Nginx) -> notes-api (ASP.NET Core) -> postgres`

Buradan cikacak kural:

- Public olacak katman: `notes-web`
- Internal kalacak katman: `notes-api`
- Private kalacak katman: `postgres`

Yani disariya normalde sadece web katmanini acacagiz. API ve veritabani dogrudan public edilmemeli.

## 1. Local Docker Compose

### Baslat

```powershell
cd C:\Projects\Kubernetes\notes-stack
docker compose up --build -d
```

### Erisim

- UI: `http://localhost:18080`
- API debug: `http://localhost:18081/api/notes`
- Health: `http://localhost:18081/health`

### Durdur

```powershell
docker compose down
```

## 2. Ayni Agdaki Baska Makineden Gorunur Yapmak

Eger ayni LAN icindeki baska bir cihazdan bu uygulamayi gormek istiyorsan:

1. Windows host IP'sini bul:

```powershell
ipconfig
```

2. UI icin firewall ac:

```powershell
New-NetFirewallRule -DisplayName "notes-stack-ui" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 18080
```

3. Baska cihazdan sunu ac:

```text
http://<windows-host-ip>:18080
```

Not:

- API'yi disariya acmak zorunda degilsin
- Sadece UI gorunsun istiyorsan `18080` yeterli
- `18081` debug amaclidir

## 3. Kubernetes'te Hemen Gorunur Yapmak: NodePort

Bu yontem lab, demo ve hizli test icin iyidir. Tek node cluster'da pratiktir.

### Neyi expose edecegiz?

Sadece `notes-web` service'ini expose edecegiz.

- `notes-api`: `ClusterIP`
- `postgres`: `ClusterIP`
- `notes-web`: `NodePort`

### Ornek service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: notes-web
spec:
  type: NodePort
  selector:
    app: notes-web
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30080
```

### Erisim

Mevcut lab node'un ic IP'si `192.168.106.130` ise:

```text
http://192.168.106.130:30080
```

### Neden yeterli?

Cunku React uygulamasi Nginx arkasinda calisiyor. Browser sadece web'e gider, web de API'ye arkadan ulasir.

## 4. Onerilen Yol: ingress-nginx

Bu repo'da [setup_helm.sh](../setup_helm.sh) ile `ingress-nginx` zaten `NodePort` modunda kurulabiliyor.

Varsayilan portlar:

- HTTP: `30081`
- HTTPS: `30443`

Bu durumda akis soyle olur:

`Browser -> ingress-nginx:30081 -> notes-web -> notes-api -> postgres`

### Neden Ingress daha dogru?

- Tek porttan birden fazla uygulama yayinlayabilirsin
- Domain bazli route yazabilirsin
- Sonra TLS eklemek daha kolay olur
- Helm chart'a cevirmek daha temiz olur

### Host dosyasi ile lokal domain

Windows makinede `C:\Windows\System32\drivers\etc\hosts` dosyasina su satiri eklenebilir:

```text
192.168.106.130 notes.local
```

### Ornek ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: notes-web
spec:
  ingressClassName: nginx
  rules:
    - host: notes.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: notes-web
                port:
                  number: 80
```

### Erisim

```text
http://notes.local:30081
```

Istersen host header ile de test edebilirsin:

```powershell
curl.exe -H "Host: notes.local" http://192.168.106.130:30081
```

## 5. Bizim Icin Onerilen Strateji

Bu repo ve mevcut single-node lab icin en mantikli sira:

1. Localde `docker compose` ile test et
2. Kubernetes manifest'e gecince `notes-web` ve `notes-api` icin `ClusterIP` service tanimla
3. Disariya sadece `Ingress` ac
4. `postgres` sadece cluster icinde kalsin
5. API'yi ancak gerekirse `kubectl port-forward` ile debug et

## 6. API'yi Neden Dogrudan Public Etmeyelim?

Cunku su anda tarayici zaten `notes-web` katmanina gidiyor. `notes-web` icindeki Nginx `/api` isteklerini backend'e proxy'liyor.

Bu sayede:

- browser tek origin gorur
- CORS karmasasi azalir
- public surface daha kucuk olur
- ingress tarafinda yonetim daha kolay olur

## 7. Kubernetes'e Gecerken Kritik Not

Su an compose tarafinda Nginx config'i backend'e su isimle gidiyor:

```nginx
proxy_pass http://api:8080;
```

Bu compose icin dogru, cunku service adi `api`.

Ama Kubernetes'te service ismi buyuk ihtimalle `notes-api` olacak. O yuzden manifest/Helm asamasinda iki yoldan birini sececegiz:

1. Nginx upstream'i `http://notes-api:8080` yapacagiz
2. Ya da `/api` route'unu ingress seviyesinde ayiracagiz

Bu ayar yapilmazsa UI acilir ama API istekleri fail eder.

## 8. Hata Ayiklama

### Local Docker

```powershell
docker compose ps
docker compose logs -f
```

### Kubernetes

```powershell
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl -n ingress-nginx get svc
kubectl logs deploy/notes-web
kubectl logs deploy/notes-api
```

### Sadece API debug etmek icin

```powershell
kubectl port-forward svc/notes-api 18081:8080
```

Sonra:

```text
http://localhost:18081/api/notes
```

## 9. Sonuc

Bu uygulama icin dogru gorunurluk modeli su:

- Local: `docker compose`
- Demo: `NodePort`
- Daha duzgun cluster erisimi: `Ingress`
- Public olmayan katmanlar: `notes-api`, `postgres`

Bir sonraki teknik adim olarak `notes-stack` icin Kubernetes manifest setini uretip bu guide'daki `NodePort` ve `Ingress` modeline gore ilerlemek en dogru yol.
