package web

import (
	"embed"
	"io/fs"
)

//go:embed all:admin/dist
var adminDist embed.FS

// AdminFS returns the embedded admin SPA filesystem, rooted at admin/dist.
func AdminFS() (fs.FS, error) {
	return fs.Sub(adminDist, "admin/dist")
}
