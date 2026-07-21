//go:build integration

package handler

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/premium/dto"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/service"
)

// TestAdminCreateLicense_BillingCycleExpiry locks in the W1.1 fix: every
// billing cycle must produce the duration declared by service.AddBillingCycleToTime,
// not a uniform 1-year default. Before W1.1, semiannual licenses got +12 months
// instead of +6 because AdminCreateLicense had a bespoke if/else that only
// recognized "monthly" and treated everything else as yearly.
//
// We capture `now := time.Now()` right before the service call, then assert
// exact equality against `AddBillingCycleToTime(now, cycle)`. Tolerance is 2
// seconds — the only drift between the test's `now` and the service's internal
// `time.Now()` is wall-clock microseconds.
func TestAdminCreateLicense_BillingCycleExpiry(t *testing.T) {
	cases := []struct {
		name           string
		cycle          string
		expectLifetime bool
	}{
		{"monthly", "monthly", false},
		{"semiannual_regression_W1_1", "semiannual", false},
		{"yearly", "yearly", false},
		{"lifetime1", "lifetime1", true},
		{"lifetime2", "lifetime2", true},
		{"lifetime3", "lifetime3", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetDB(t)

			before := time.Now()
			email := "admin-create-" + tc.name + "@example.com"
			req := dto.AdminCreateLicenseRequest{
				BillingCycle: tc.cycle,
				Brand:        "svid",
				ContactEmail: &email,
				Notes:        "W1.1 regression test",
			}
			resp, err := testPremiumService.AdminCreateLicense(req, uuid.New())
			if err != nil {
				t.Fatalf("AdminCreateLicense(%q): %v", tc.cycle, err)
			}
			after := time.Now()

			// Reload from DB to make sure persistence didn't drop precision.
			var got model.PremiumLicense
			if err := testDB.First(&got, "license_key = ?", resp.LicenseKey).Error; err != nil {
				t.Fatalf("reload license: %v", err)
			}

			// Expected expiry: somewhere between AddBillingCycleToTime(before, cycle)
			// and AddBillingCycleToTime(after, cycle). The window is the wall-clock
			// time between `before` and `after`, typically sub-millisecond.
			expectedFromBefore := service.AddBillingCycleToTime(before, tc.cycle)
			expectedFromAfter := service.AddBillingCycleToTime(after, tc.cycle)

			if got.ExpiresAt.Before(expectedFromBefore.Add(-time.Second)) ||
				got.ExpiresAt.After(expectedFromAfter.Add(time.Second)) {
				t.Fatalf("cycle=%q: expires_at=%v not within [%v, %v]; W1.1 regression?",
					tc.cycle, got.ExpiresAt, expectedFromBefore, expectedFromAfter)
			}

			// Belt-and-braces semiannual-specific assertion: ~6 months, not ~12.
			if tc.cycle == "semiannual" {
				delta := got.ExpiresAt.Sub(before)
				if delta < 5*30*24*time.Hour || delta > 7*30*24*time.Hour {
					t.Fatalf("semiannual delta %v outside [5mo, 7mo]; W1.1 regression — fix re-introduces the 12mo bug?",
						delta)
				}
			}
		})
	}
}
