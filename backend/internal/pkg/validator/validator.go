package validator

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/go-playground/validator/v10"
)

// FormatValidationErrors converts validator.ValidationErrors to a user-friendly
// map. JSON parse errors are mapped to a generic "invalid JSON body" message
// instead of leaking the raw parser internals (industry-standard error hygiene).
func FormatValidationErrors(err error) map[string]string {
	errors := make(map[string]string)

	if ve, ok := err.(validator.ValidationErrors); ok {
		for _, fe := range ve {
			field := toSnakeCase(fe.Field())
			errors[field] = formatFieldError(fe)
		}
		return errors
	}

	if isJSONParseError(err) {
		errors["_error"] = "invalid JSON body"
		return errors
	}

	errors["_error"] = err.Error()
	return errors
}

// isJSONParseError detects errors emitted by encoding/json during decode.
// Avoids leaking parser internals (e.g. byte offsets, expected tokens) to
// untrusted callers.
func isJSONParseError(err error) bool {
	if err == nil {
		return false
	}
	var syntaxErr *json.SyntaxError
	var typeErr *json.UnmarshalTypeError
	if errors.As(err, &syntaxErr) || errors.As(err, &typeErr) {
		return true
	}
	if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
		return true
	}
	// Gin's binding wraps decode errors; the prefix is stable across versions.
	msg := err.Error()
	if strings.Contains(msg, "invalid character") ||
		strings.Contains(msg, "unexpected end of JSON") ||
		strings.Contains(msg, "cannot unmarshal") {
		return true
	}
	return false
}

func formatFieldError(fe validator.FieldError) string {
	switch fe.Tag() {
	case "required":
		return fmt.Sprintf("%s is required", toSnakeCase(fe.Field()))
	case "email":
		return "must be a valid email address"
	case "min":
		return fmt.Sprintf("must be at least %s characters", fe.Param())
	case "max":
		return fmt.Sprintf("must be at most %s characters", fe.Param())
	case "oneof":
		return fmt.Sprintf("must be one of: %s", fe.Param())
	case "uuid":
		return "must be a valid UUID"
	default:
		return fmt.Sprintf("failed validation: %s", fe.Tag())
	}
}

func toSnakeCase(s string) string {
	var result strings.Builder
	runes := []rune(s)
	for i, r := range runes {
		if i > 0 && r >= 'A' && r <= 'Z' {
			prev := runes[i-1]
			// Don't add underscore between consecutive uppercase (e.g., "ID" → "id", not "i_d")
			if prev >= 'a' && prev <= 'z' {
				result.WriteByte('_')
			} else if prev >= 'A' && prev <= 'Z' && i+1 < len(runes) && runes[i+1] >= 'a' && runes[i+1] <= 'z' {
				result.WriteByte('_')
			}
		}
		result.WriteRune(r)
	}
	return strings.ToLower(result.String())
}
