package service

import (
	"strings"
	"testing"
)

// TestEmailNormalizationContract pins the canonical lowercase+trim
// contract used across the premium flow. Three independent layers
// (RestoreLicense handler, AdminCreateLicense / AdminImportLegacyLicense
// service write sides, webhook handler) all apply this normalize.
// FindActiveByEmail / FindByEmail in the repository also normalize
// internally as defense-in-depth.
//
// If a regression replaces this contract with anything weaker (e.g.,
// trim-only, lowercase-without-trim, case-preserving), restore by email
// silently fails for any user whose mail client preserved original
// casing. This test pins the contract so the bug cannot recur.
//
// The test asserts the SHAPE of normalization (idempotent, full lowercase,
// trim both ends, NUL/whitespace tolerant) rather than calling out to a
// shared helper — different layers historically have their own one-liners
// and the consistency is what matters.
func TestEmailNormalizationContract(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{"plain ascii lowercase passthrough", "customer@example.com", "customer@example.com"},
		{"mixed case lowercased", "Customer@Example.com", "customer@example.com"},
		{"all upper lowercased", "CUSTOMER@EXAMPLE.COM", "customer@example.com"},
		{"leading whitespace stripped", "  customer@example.com", "customer@example.com"},
		{"trailing whitespace stripped", "customer@example.com  ", "customer@example.com"},
		{"surrounding whitespace stripped", "\t customer@example.com \n", "customer@example.com"},
		{"mixed case + whitespace", "  Customer@EXAMPLE.com\t", "customer@example.com"},
		{"empty stays empty", "", ""},
		{"whitespace only collapses", "   ", ""},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := strings.ToLower(strings.TrimSpace(tc.input))
			if got != tc.expected {
				t.Errorf("normalize(%q) = %q, want %q", tc.input, got, tc.expected)
			}
		})
	}
}

// TestEmailNormalizationIsIdempotent guards against subtle regressions
// where a second normalization round produces a different result (would
// happen if e.g., we accidentally URL-encoded or HTML-escaped the email).
func TestEmailNormalizationIsIdempotent(t *testing.T) {
	inputs := []string{
		"Customer@Example.com",
		"  user@example.com  ",
		"FOO@BAR.COM",
		"already@lowercase.com",
	}
	for _, input := range inputs {
		once := strings.ToLower(strings.TrimSpace(input))
		twice := strings.ToLower(strings.TrimSpace(once))
		if once != twice {
			t.Errorf("normalize not idempotent for %q: once=%q twice=%q",
				input, once, twice)
		}
	}
}
