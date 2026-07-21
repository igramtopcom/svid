package pagination

const MaxPerPage = 100

// Normalize clamps pagination inputs to safe, predictable values.
// page is always at least 1.
// perPage falls back to defaultPerPage when missing/invalid and is capped at MaxPerPage.
func Normalize(page, perPage, defaultPerPage int) (int, int) {
	if defaultPerPage < 1 || defaultPerPage > MaxPerPage {
		defaultPerPage = 20
	}
	if page < 1 {
		page = 1
	}
	switch {
	case perPage < 1:
		perPage = defaultPerPage
	case perPage > MaxPerPage:
		perPage = MaxPerPage
	}
	return page, perPage
}
