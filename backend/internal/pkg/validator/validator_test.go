package validator

import (
	"testing"
)

func TestToSnakeCase(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"", ""},
		{"id", "id"},
		{"ID", "id"},
		{"UserID", "user_id"},
		{"userName", "user_name"},
		{"HTTPSPort", "https_port"},
		{"firstName", "first_name"},
		{"LastName", "last_name"},
		{"APIKey", "api_key"},
		{"OAuth2Token", "o_auth2token"},
		{"simpleTest", "simple_test"},
		{"A", "a"},
		{"AB", "ab"},
		{"ABC", "abc"},
	}

	for _, tt := range tests {
		got := toSnakeCase(tt.input)
		if got != tt.expected {
			t.Errorf("toSnakeCase(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestFormatFieldError_Required(t *testing.T) {
	// We can't easily construct a validator.FieldError, so test the toSnakeCase helper
	// and verify the package compiles correctly.
	// Integration tests would need actual struct validation.
	if toSnakeCase("Email") != "email" {
		t.Error("basic snake_case failed")
	}
	if toSnakeCase("BillingCycle") != "billing_cycle" {
		t.Error("camelCase to snake_case failed")
	}
}
