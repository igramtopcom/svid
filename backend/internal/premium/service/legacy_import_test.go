package service

import (
	"errors"
	"testing"
	"time"

	"github.com/snakeloader/backend/internal/premium/dto"
)

// buildValidLegacyRequestWithStatus returns a DTO that would pass every
// guard EXCEPT the Status check. Used by status-guard tests so the guard
// is exercised in isolation.
func buildValidLegacyRequestWithStatus(status string) dto.AdminImportLegacyLicenseRequest {
	return dto.AdminImportLegacyLicenseRequest{
		LicenseKey: "0123456789abcdef0123456789abcdef",
		Brand:      "vidcombo",
		Email:      "user@example.com",
		Plan:       "plan1",
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
		Status:     status,
	}
}

// TestMapLegacyPlanToBillingCycle pins the PHP → Go plan-tier mapping used
// by [AdminImportLegacyLicense]. A wrong mapping = wrong premium duration =
// either revenue loss (free months) or angry customer (premium too short),
// so every PHP `subscriptions.plan` value MUST be covered explicitly and
// unknown values MUST be rejected (no silent default).
func TestMapLegacyPlanToBillingCycle(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantCycle string
		wantOK    bool
	}{
		// Canonical PHP plan values from quantri.vidcombo.com subscriptions table.
		{"plan1 → monthly", "plan1", "monthly", true},
		{"plan2 → semiannual", "plan2", "semiannual", true},
		{"plan3 → yearly", "plan3", "yearly", true},
		{"lifetime", "lifetime", "lifetime", true},

		// Case-insensitive (defensive — PHP could mix case across legacy versions).
		{"PLAN1 uppercase", "PLAN1", "monthly", true},
		{"Plan2 mixed", "Plan2", "semiannual", true},
		{"LIFETIME upper", "LIFETIME", "lifetime", true},

		// Whitespace tolerance (admin CSV exports sometimes carry trailing spaces).
		{"plan1 with leading space", "  plan1", "monthly", true},
		{"plan2 with trailing space", "plan2 ", "semiannual", true},

		// Unknown plans MUST be rejected — silent default would silently
		// grant wrong tier to legacy users (e.g. plan99 → monthly fallback
		// = free yearly for a one-time customer).
		{"unknown plan99 rejected", "plan99", "", false},
		{"empty rejected", "", "", false},
		{"monthly literal not accepted (must be plan1)", "monthly", "", false},
		{"yearly literal not accepted (must be plan3)", "yearly", "", false},
		{"plan4 future-unknown rejected", "plan4", "", false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			gotCycle, gotOK := mapLegacyPlanToBillingCycle(tc.input)
			if gotCycle != tc.wantCycle {
				t.Errorf("mapLegacyPlanToBillingCycle(%q) cycle = %q, want %q",
					tc.input, gotCycle, tc.wantCycle)
			}
			if gotOK != tc.wantOK {
				t.Errorf("mapLegacyPlanToBillingCycle(%q) ok = %v, want %v",
					tc.input, gotOK, tc.wantOK)
			}
		})
	}
}

// TestLegacyImportPlanCoverageMatchesGoBillingCycleEnum guards against drift
// between the PHP plan mapping and the Go BillingCycle enum that [LicenseToResponse]
// emits. If billing-cycle enum changes upstream, this test flags before users
// hit "unknown billing cycle" UI errors.
func TestLegacyImportPlanCoverageMatchesGoBillingCycleEnum(t *testing.T) {
	// Every output of mapLegacyPlanToBillingCycle MUST be one of the values
	// accepted by AdminCreateLicenseRequest.BillingCycle binding:
	//   monthly | semiannual | yearly | lifetime | lifetime1 | lifetime2 | lifetime3
	valid := map[string]bool{
		"monthly":    true,
		"semiannual": true,
		"yearly":     true,
		"lifetime":   true,
		"lifetime1":  true,
		"lifetime2":  true,
		"lifetime3":  true,
	}

	phpPlans := []string{"plan1", "plan2", "plan3", "lifetime"}
	for _, plan := range phpPlans {
		cycle, ok := mapLegacyPlanToBillingCycle(plan)
		if !ok {
			t.Fatalf("PHP plan %q unexpectedly rejected by mapper", plan)
		}
		if !valid[cycle] {
			t.Errorf("PHP plan %q mapped to %q which is NOT in the Go BillingCycle enum — "+
				"will break dashboard + admin UI downstream", plan, cycle)
		}
	}
}

// TestLegacyImportSentinelErrorsAreDistinct guards against accidental
// merger of the safety-guard error sentinels. The handler maps each to a
// distinct HTTP status + error_code (INVALID_PLAN, BRAND_MISMATCH,
// ROW_REVOKED, PAYMENT_METHOD_MISMATCH, INVALID_EXPIRES_AT). If two
// errors compare equal under errors.Is, the handler switch would route
// both to the same response code and the operator/admin can't tell from
// the API what actually went wrong.
func TestLegacyImportSentinelErrorsAreDistinct(t *testing.T) {
	sentinels := []error{
		ErrLegacyImportInvalidPlan,
		ErrLegacyImportInvalidExpiresAt,
		ErrLegacyImportInvalidStatus,
		ErrLegacyImportBrandMismatch,
		ErrLegacyImportRowRevoked,
		ErrLegacyImportPaymentMethodMismatch,
	}
	for i, a := range sentinels {
		for j, b := range sentinels {
			if i == j {
				continue
			}
			if errors.Is(a, b) {
				t.Errorf("sentinel %d (%v) collides with sentinel %d (%v) — "+
					"handler switch will route both to same HTTP code",
					i, a, j, b)
			}
		}
	}
}

// TestLegacyImportSentinelErrorMessagesAreClientSafe verifies that the
// sentinel error messages don't leak internal implementation details
// (table names, GORM internals, DB column names, file paths). They are
// reflected back to admin clients via the API; should be human-readable
// without exposing infrastructure.
func TestLegacyImportSentinelErrorMessagesAreClientSafe(t *testing.T) {
	forbiddenSubstrings := []string{
		"gorm", "sql:", "pq:", "postgres", "premium_licenses",
		".go:", "panic", "stacktrace",
	}
	sentinels := []error{
		ErrLegacyImportInvalidPlan,
		ErrLegacyImportInvalidExpiresAt,
		ErrLegacyImportInvalidStatus,
		ErrLegacyImportBrandMismatch,
		ErrLegacyImportRowRevoked,
		ErrLegacyImportPaymentMethodMismatch,
	}
	for _, s := range sentinels {
		msg := s.Error()
		for _, bad := range forbiddenSubstrings {
			if containsCI(msg, bad) {
				t.Errorf("sentinel %v leaks internal substring %q via Error()",
					s, bad)
			}
		}
		if msg == "" {
			t.Errorf("sentinel has empty Error() — client gets confusing response")
		}
	}
}

// TestAdminImportLegacyLicense_StatusGuard verifies the service-layer Status
// check rejects refunded / cancelled / past_due rows that might slip past
// Gin binding (internal callers, bulk variants, service-to-service). The
// HTTP `oneof=active trialing` binding is the first line of defense; this
// guard is defense-in-depth so a contract regression upstream can't silently
// resurrect refunded users as premium. We pass a zero PremiumService — the
// guard fires before any repository call, so nil dependencies are safe here.
func TestAdminImportLegacyLicense_StatusGuard(t *testing.T) {
	rejectedStatuses := []string{
		"refunded", "cancelled", "past_due", "incomplete", "unpaid", "paused", "",
		"ACTIVE", // case-sensitive: HTTP binding is lowercase-only, guard mirrors
	}
	svc := &PremiumService{} // guard runs before any field is touched
	for _, status := range rejectedStatuses {
		_, err := svc.AdminImportLegacyLicense(buildValidLegacyRequestWithStatus(status), [16]byte{})
		if !errors.Is(err, ErrLegacyImportInvalidStatus) {
			t.Errorf("status=%q expected ErrLegacyImportInvalidStatus, got %v",
				status, err)
		}
	}
}

func containsCI(haystack, needle string) bool {
	if len(needle) == 0 {
		return true
	}
	if len(haystack) < len(needle) {
		return false
	}
	// Case-insensitive substring scan.
	for i := 0; i+len(needle) <= len(haystack); i++ {
		ok := true
		for j := 0; j < len(needle); j++ {
			ch1, ch2 := haystack[i+j], needle[j]
			if ch1 >= 'A' && ch1 <= 'Z' {
				ch1 += 'a' - 'A'
			}
			if ch2 >= 'A' && ch2 <= 'Z' {
				ch2 += 'a' - 'A'
			}
			if ch1 != ch2 {
				ok = false
				break
			}
		}
		if ok {
			return true
		}
	}
	return false
}
