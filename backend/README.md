# SnakeLoader Backend

Backend API and Admin Dashboard for SnakeLoader (SSvid) - a desktop video downloader application.

## Tech Stack

- **Go 1.21+** - Backend language
- **Gin** - HTTP web framework
- **GORM** - ORM with auto-migration
- **PostgreSQL 16** - Primary database
- **Redis 7** - Caching & rate limiting
- **React 18** - Admin dashboard (embedded SPA)
- **TypeScript + Vite + Tailwind** - Admin frontend

## Features

### API Modules
- **Identity** - Device registration, API key management, Admin authentication
- **Bug Reporting** - Bug reports with attachments, Crash reports
- **Product Control** - Feature flags, Remote config, App releases, Announcements
- **Feedback** - Support tickets, Feature requests with voting, App ratings
- **AI Assistant** - Chat sessions, Knowledge base
- **Analytics** - Event tracking, Usage statistics

### Admin Dashboard
- Full-featured web dashboard at `/dashboard-ui/`
- Embedded in Go binary (single binary deployment)
- Real-time stats, charts, and management tools

## Quick Start

### Prerequisites
- Go 1.21+
- Docker & Docker Compose
- Node.js 18+ (for admin dashboard development)

### Setup

1. **Clone and configure**
```bash
git clone https://github.com/dinhvanmy/snakeloader-backend.git
cd snakeloader-backend
cp .env.example .env
# Edit .env with your settings
```

2. **Start infrastructure**
```bash
docker compose up -d
```

3. **Run the server**
```bash
make run
```

4. **Access**
- API: http://localhost:8080
- Health: http://localhost:8080/health
- Admin Dashboard: http://localhost:8080/dashboard-ui/

### Default Admin
- Email: `admin@snakeloader.com`
- Password: Set in `.env` (`ADMIN_PASSWORD`)

## Development

### Available Commands

```bash
make run          # Run development server
make build        # Build binary (includes admin dashboard)
make admin-dev    # Run admin dashboard in dev mode (hot reload)
make admin-build  # Build admin dashboard only
make docker-up    # Start PostgreSQL + Redis
make docker-down  # Stop infrastructure
make docker-reset # Reset database (delete all data)
make tidy         # Go mod tidy
```

### Project Structure

```
├── cmd/api/           # Application entry point
├── internal/
│   ├── identity/      # Device & admin management
│   ├── bugs/          # Bug & crash reporting
│   ├── product/       # Feature flags, releases
│   ├── feedback/      # Tickets, feature requests
│   ├── assistant/     # AI chat, knowledge base
│   ├── analytics/     # Event tracking
│   ├── middleware/    # Auth, CORS, rate limiting
│   ├── database/      # DB connections, migrations
│   └── server/        # HTTP server, routing
├── web/admin/         # React admin dashboard
└── docker-compose.yml
```

## API Authentication

### Device Authentication
```bash
# Register device
curl -X POST http://localhost:8080/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{"hardware_id":"unique-id","os":"windows","os_version":"11","app_version":"1.0.0"}'

# Use API key
curl http://localhost:8080/api/v1/config/flags \
  -H "X-API-Key: snk_..."
```

### Admin Authentication
```bash
# Login
curl -X POST http://localhost:8080/admin/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@snakeloader.com","password":"..."}'

# Use JWT token
curl http://localhost:8080/admin/v1/devices \
  -H "Authorization: Bearer eyJ..."
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_PORT` | HTTP server port | `8080` |
| `GIN_MODE` | Gin mode (debug/release) | `debug` |
| `DB_HOST` | PostgreSQL host | `localhost` |
| `DB_PORT` | PostgreSQL port | `5432` |
| `DB_USER` | Database user | `postgres` |
| `DB_PASSWORD` | Database password | - |
| `DB_NAME` | Database name | `snakeloader` |
| `REDIS_HOST` | Redis host | `localhost` |
| `REDIS_PORT` | Redis port | `6379` |
| `JWT_SECRET` | JWT signing secret | - |
| `JWT_EXPIRY_HOURS` | JWT token expiry | `24` |
| `ADMIN_EMAIL` | Default admin email | - |
| `ADMIN_PASSWORD` | Default admin password | - |

## Deployment

### Single Binary
```bash
make build
./bin/api
```
The admin dashboard is embedded in the binary - no separate web server needed.

### Docker

**ALWAYS use `make docker-image`, not bare `docker build`.** The
wrapper computes `VERSION` / `GIT_SHA` / `BUILD_TIME` from the local
git checkout and ldflags-injects them into `internal/buildinfo`, so
`/health` and `/version` report a real build identity.

```bash
# Recommended — production deploys MUST use this path.
make docker-image                              # tag = snakeloader-backend:latest
IMAGE_TAG=snakeloader-backend:v1.6.4 make docker-image
docker run -p 8080:8080 --env-file .env snakeloader-backend

# Manual fallback (will NOT inject build identity — only use for ad-hoc
# debugging of the Dockerfile itself):
#   docker build -t snakeloader-backend .
```

If `/health` returns `version=dev` or `git_sha=unknown` in production,
the deploy path bypassed the wrapper. Audit 2026-04-27 found this
exact regression on the live server.

## Related Projects

- [SnakeLoader App](https://github.com/dinhvanmy/snakeloader) - Flutter + Rust desktop application

## License

Private - All rights reserved
