package validator

import (
	"regexp"

	"github.com/go-playground/validator/v10"
)

// licenseKeyRegex matches both supported brand prefixes followed by
// 8 hex groups of 4 chars each (length 44 for SVID, 48 for VIDCOMBO).
// Used by the `license_key` custom validator registered with Gin's binding.
var licenseKeyRegex = regexp.MustCompile(`^(SVID|VIDCOMBO)(-[0-9a-f]{4}){8}$`)

// Register attaches all custom validators to the provided validate engine.
// Returns the first registration error, if any. Wired from cmd/api/main.go
// after Gin creates its validator engine, and from TestMain of any DTO test
// that exercises a custom rule.
func Register(v *validator.Validate) error {
	return v.RegisterValidation("license_key", validateLicenseKey)
}

func validateLicenseKey(fl validator.FieldLevel) bool {
	return licenseKeyRegex.MatchString(fl.Field().String())
}
