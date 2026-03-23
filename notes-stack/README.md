# Notes Stack

Compose-first full stack notes app:

- ASP.NET Core Minimal API
- EF Core + PostgreSQL
- React + Context API
- Nginx serving the frontend and proxying `/api`

Ek dokuman:

- [Visibility Guide](./VISIBILITY_GUIDE.md)

## Local run

```powershell
docker compose up --build
```

UI:

- `http://localhost:18080`

API:

- `http://localhost:18081/api/notes`
- `http://localhost:18081/health`

## Stop

```powershell
docker compose down
```

## Helm Deploy Scripts

Local image build:

```bash
./build_images.sh
```

Remote Helm deploy:

```bash
SSH_PASSWORD='Frs@2024!' ./deploy_helm_remote.sh
```

Varsayilanlar:

- host: `192.168.106.130`
- user: `frs`
- release: `notes-stack`
- namespace: `notes-stack`
- URL: `http://192.168.106.130:30081/`
