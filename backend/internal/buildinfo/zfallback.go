package buildinfo

// zfallback.go runs last alphabetically (after buildinfo.go and embedded.go),
// filling in the literal "dev" / "unknown" placeholders so /version always
// has non-empty values. Anything earlier wins over this — the named-after-z
// trick is intentional ordering.

func init() {
	if Version == "" && GitSHA != "" {
		short := GitSHA
		if len(short) > 12 {
			short = short[:12]
		}
		Version = "git-" + short
	}
	if Version == "" {
		Version = "dev"
	}
	if GitSHA == "" {
		GitSHA = "unknown"
	}
	if BuildTime == "" {
		BuildTime = "unknown"
	}
}
