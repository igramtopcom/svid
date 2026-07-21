// Package docs placeholder for swagger documentation.
// This file MUST be committed — the server needs it for `go build`.
// router.go imports this package; without it, `go mod tidy` tries to
// fetch github.com/snakeloader/backend/docs from the internet (which
// doesn't exist as a public repo).
//
// Regenerate full swagger docs with:
//   cd backend && swag init -g cmd/api/main.go -o docs/
package docs
