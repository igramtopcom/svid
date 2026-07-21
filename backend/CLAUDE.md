# CLAUDE.md - SnakeLoader Backend

## Project Overview
Backend API + Admin Dashboard for SnakeLoader (Svid) desktop video downloader app.
- **Language**: Go 1.21+
- **Framework**: Gin (HTTP), GORM (ORM)
- **Database**: PostgreSQL 16, Redis 7
- **Admin UI**: React 18 + TypeScript + Vite (embedded in Go binary)

## Quick Commands
```bash
# Start infrastructure
docker compose up -d

# Run server (dev)
make run

# Build (includes admin dashboard)
make build

# Admin dashboard dev mode
make admin-dev
```

## Project Structure
```
snakeloader-backend/
├── cmd/api/main.go          # Entry point, DI wiring
├── internal/
│   ├── identity/            # Devices, API keys, Admins
│   ├── bugs/                # Bug reports, Crash reports
│   ├── product/             # Feature flags, Remote config, Releases, Announcements
│   ├── feedback/            # Tickets, Feature requests, Ratings
│   ├── assistant/           # AI chat sessions, Knowledge base
│   ├── analytics/           # Event tracking, Stats
│   ├── middleware/          # Auth, CORS, Rate limit, Logging
│   ├── database/            # PostgreSQL, Redis, Migrations
│   ├── config/              # Environment config
│   ├── response/            # Standard API response envelope
│   ├── server/              # Gin engine, Router
│   └── pkg/                 # Utilities (jwt, crypto, logger, validator)
├── web/
│   ├── embed.go             # Go embed directive for admin SPA
│   └── admin/               # React admin dashboard
└── docker-compose.yml       # PostgreSQL + Redis
```

## Architecture Pattern
- **Modular monolith** with manual dependency injection in `main.go`
- Each module follows: `model → repository → dto → service → handler`
- No framework magic - explicit wiring

## Authentication
- **Device auth**: API Key in `X-API-Key` header
  - Format: `snk_` + base64url (stored as SHA-256 hash)
  - Cached in Redis (5 min TTL)
- **Admin auth**: JWT Bearer token
  - `Authorization: Bearer <token>`
  - 24h expiry by default

## API Response Format
```json
// Success
{ "success": true, "data": { ... } }

// Error
{ "success": false, "error": { "code": "ERROR_CODE", "message": "..." } }

// Paginated
{ "success": true, "data": { "items": [...], "total": 100, "page": 1, "per_page": 20, "total_pages": 5 } }
```

## API Endpoints Summary

### Public
- `GET /health` - Health check
- `POST /api/v1/devices/register` - Register device, get API key

### Device Auth (`X-API-Key`)
- `POST /api/v1/devices/heartbeat`
- `POST /api/v1/bugs`, `GET /api/v1/bugs`, `GET /api/v1/bugs/:id`
- `POST /api/v1/crashes`
- `GET /api/v1/config/flags`, `GET /api/v1/config/remote`
- `GET /api/v1/updates/check`, `GET /api/v1/announcements`
- `POST /api/v1/tickets`, `GET /api/v1/tickets`, `POST /api/v1/tickets/:id/messages`
- `POST /api/v1/features`, `GET /api/v1/features`, `POST /api/v1/features/:id/vote`
- `POST /api/v1/ratings`
- `POST /api/v1/analytics/events`
- `POST /api/v1/assistant/sessions`, `GET /api/v1/assistant/sessions`, `POST /api/v1/assistant/sessions/:id/messages`

### Admin Auth (`Bearer JWT`)
- `POST /admin/v1/auth/login`
- Full CRUD for: devices, bugs, crashes, flags, config, releases, announcements, tickets, features, ratings, assistant sessions, knowledge base, analytics
- `GET /admin/v1/dashboard/stats`

### Admin Dashboard
- Served at `/dashboard-ui/` (embedded React SPA)

## Database Tables
- `devices`, `api_keys`, `admins` (identity)
- `bug_reports`, `bug_attachments`, `crash_reports` (bugs)
- `feature_flags`, `remote_configs`, `app_releases`, `announcements` (product)
- `tickets`, `ticket_messages`, `feature_requests`, `feature_votes`, `app_ratings` (feedback)
- `chat_sessions`, `chat_messages`, `knowledge_bases` (assistant)
- `analytics_events`, `daily_stats` (analytics)

## Environment Variables
See `.env.example` for all required variables:
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`
- `JWT_SECRET`, `JWT_EXPIRY_HOURS`
- `ADMIN_EMAIL`, `ADMIN_PASSWORD` (seed)
- `SERVER_PORT`, `GIN_MODE`

## Code Conventions
- Error codes: `UPPER_SNAKE_CASE` (e.g., `INVALID_API_KEY`, `DEVICE_NOT_FOUND`)
- All IDs: UUID v4 with `gorm:"type:uuid;primaryKey"`
- Pagination: `page` and `per_page` query params, max 100
- Timestamps: `created_at`, `updated_at` auto-managed by GORM

## Admin Dashboard (React)
Located in `web/admin/`:
- **Stack**: React 18, TypeScript, Vite, Tailwind CSS
- **State**: TanStack Query (server), Zustand (auth)
- **Build**: `npm run build` → embedded via `go:embed`
- **Dev**: `npm run dev` (port 3000, proxy to Go 8080)

## Common Tasks

### Add new API endpoint
1. Create/update model in `internal/<module>/model/`
2. Add repository method in `internal/<module>/repository/`
3. Create DTO in `internal/<module>/dto/`
4. Add service method in `internal/<module>/service/`
5. Add handler in `internal/<module>/handler/`
6. Register route in `internal/server/router.go`
7. Wire dependencies in `cmd/api/main.go`

### Add new database table
1. Create model struct with GORM tags
2. Add to `db.AutoMigrate()` in `internal/database/migrate.go`
3. Run server to auto-migrate

### Modify admin dashboard
1. Edit files in `web/admin/src/`
2. `cd web/admin && npm run build`
3. Restart Go server (or `make build`)
