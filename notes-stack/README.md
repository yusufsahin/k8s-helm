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
