package service

import (
	"testing"
	"time"
)

// TestAddBillingCycleToTime is the regression test for the VidCombo semiannual
// expiration bug. Before the fix, the expiration math was duplicated inline in 5
// places (CreateLicense, FindOrCreateLicenseForSession, FindOrCreateLicenseForCryptoInvoice,
// and the Stripe webhook renewal handler's expired+extend branches). 4 of those 5 used
// a 2-branch if/else (monthly vs everything-else=1year) and silently fell through to
// 1 year for `semiannual`. VidCombo semiannual ($29.34) subscribers got 365 days of
// premium instead of 180, and every renewal cycle drifted further off Stripe's
// actual billing cadence. This test pins down the calendar arithmetic for every
// supported billing cycle so any future regression breaks here.
func TestAddBillingCycleToTime(t *testing.T) {
	base := time.Date(2026, 1, 15, 12, 0, 0, 0, time.UTC)

	tests := []struct {
		cycle string
		want  time.Time
	}{
		{"monthly", time.Date(2026, 2, 15, 12, 0, 0, 0, time.UTC)},
		{"semiannual", time.Date(2026, 7, 15, 12, 0, 0, 0, time.UTC)},
		{"yearly", time.Date(2027, 1, 15, 12, 0, 0, 0, time.UTC)},
		{"lifetime", time.Date(2126, 1, 15, 12, 0, 0, 0, time.UTC)},
		{"lifetime1", time.Date(2126, 1, 15, 12, 0, 0, 0, time.UTC)},
		{"lifetime2", time.Date(2126, 1, 15, 12, 0, 0, 0, time.UTC)},
		{"lifetime3", time.Date(2126, 1, 15, 12, 0, 0, 0, time.UTC)},
		// Unknown cycles fail-safe to 1 year (preserves user access if validation
		// is bypassed). DTO validation should prevent this in production.
		{"unknown", time.Date(2027, 1, 15, 12, 0, 0, 0, time.UTC)},
		{"", time.Date(2027, 1, 15, 12, 0, 0, 0, time.UTC)},
	}

	for _, tt := range tests {
		got := AddBillingCycleToTime(base, tt.cycle)
		if !got.Equal(tt.want) {
			t.Errorf("AddBillingCycleToTime(base, %q) = %v, want %v", tt.cycle, got, tt.want)
		}
	}
}

// TestAddBillingCycleToTime_RenewalExtend verifies the renewal "still active"
// path: when an early renewal arrives, the extension is added to the current
// expiry (not now()), so users don't lose unused premium time.
func TestAddBillingCycleToTime_RenewalExtend(t *testing.T) {
	// VidCombo semiannual: license expires 2026-07-01, renewal arrives 1 month
	// early on 2026-06-01. New expiry should be 2027-01-01 (6 months from old
	// expiry), not 2026-12-01 (6 months from renewal date).
	currentExpiry := time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC)
	newExpiry := AddBillingCycleToTime(currentExpiry, "semiannual")
	want := time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)
	if !newExpiry.Equal(want) {
		t.Errorf("semiannual renewal extend: got %v, want %v", newExpiry, want)
	}
}

func TestAmountCentsForBillingCycle(t *testing.T) {
	// SSvid pricing
	ssvidTests := []struct {
		cycle    string
		expected int
	}{
		{"monthly", 799},
		{"yearly", 2999},
		{"lifetime", 8999},
		{"lifetime1", 8999},
		{"lifetime2", 8999},
		{"lifetime3", 8999},
		{"unknown", 0},
		{"", 0},
	}
	for _, tt := range ssvidTests {
		got := AmountCentsForBillingCycle(tt.cycle, "ssvid")
		if got != tt.expected {
			t.Errorf("AmountCentsForBillingCycle(%q, \"ssvid\") = %d, want %d", tt.cycle, got, tt.expected)
		}
	}

	// VidCombo pricing (3 plans: monthly, semiannual, yearly)
	vidcomboTests := []struct {
		cycle    string
		expected int
	}{
		{"monthly", 699},
		{"semiannual", 2934},
		{"yearly", 4188},
		{"unknown", 0},
		{"", 0},
	}
	for _, tt := range vidcomboTests {
		got := AmountCentsForBillingCycle(tt.cycle, "vidcombo")
		if got != tt.expected {
			t.Errorf("AmountCentsForBillingCycle(%q, \"vidcombo\") = %d, want %d", tt.cycle, got, tt.expected)
		}
	}
}

func TestIsLifetimePlan(t *testing.T) {
	tests := []struct {
		cycle    string
		expected bool
	}{
		{"lifetime", true},
		{"lifetime1", true},
		{"lifetime2", true},
		{"lifetime3", true},
		{"monthly", false},
		{"yearly", false},
		{"semiannual", false},
		{"", false},
	}

	for _, tt := range tests {
		got := IsLifetimePlan(tt.cycle)
		if got != tt.expected {
			t.Errorf("IsLifetimePlan(%q) = %v, want %v", tt.cycle, got, tt.expected)
		}
	}
}

func TestMaxDevicesForPlan(t *testing.T) {
	tests := []struct {
		cycle    string
		expected int
	}{
		{"lifetime", 5},
		{"lifetime1", 5},
		{"lifetime2", 5},
		{"lifetime3", 5},
		{"monthly", 5},
		{"semiannual", 5},
		{"yearly", 5},
		{"unknown", MaxDevicesPerLicense},
	}

	for _, tt := range tests {
		got := MaxDevicesForPlan(tt.cycle)
		if got != tt.expected {
			t.Errorf("MaxDevicesForPlan(%q) = %d, want %d", tt.cycle, got, tt.expected)
		}
	}
}

func TestRequiredConfirmations(t *testing.T) {
	tests := []struct {
		currency string
		expected int
	}{
		{"BTC", BTCConfirmations},
		{"LTC", LTCConfirmations},
		{"XMR", XMRConfirmations},
		{"ETH", 1}, // unknown defaults to 1
		{"", 1},
	}

	for _, tt := range tests {
		got := RequiredConfirmations(tt.currency)
		if got != tt.expected {
			t.Errorf("RequiredConfirmations(%q) = %d, want %d", tt.currency, got, tt.expected)
		}
	}
}

func TestCryptoStubAmount(t *testing.T) {
	btcAmount := cryptoStubAmount("BTC", "monthly", "ssvid")
	if btcAmount == "" || btcAmount == "0" {
		t.Error("BTC amount should not be empty or zero")
	}

	ltcAmount := cryptoStubAmount("LTC", "monthly", "ssvid")
	if ltcAmount == "" || ltcAmount == "0" {
		t.Error("LTC amount should not be empty or zero")
	}

	xmrAmount := cryptoStubAmount("XMR", "monthly", "ssvid")
	if xmrAmount == "" || xmrAmount == "0" {
		t.Error("XMR amount should not be empty or zero")
	}

	unknownAmount := cryptoStubAmount("ETH", "monthly", "ssvid")
	if unknownAmount != "0" {
		t.Errorf("unknown currency should return 0, got %s", unknownAmount)
	}

	vidcomboAmount := cryptoStubAmount("BTC", "monthly", "vidcombo")
	if vidcomboAmount == btcAmount {
		t.Errorf("brand-aware crypto amount should differ when pricing differs: ssvid=%s vidcombo=%s", btcAmount, vidcomboAmount)
	}
}

func TestCryptoStubAddress(t *testing.T) {
	btc := cryptoStubAddress("BTC")
	if len(btc) == 0 {
		t.Error("BTC address should not be empty")
	}
	if btc[:7] != "bc1qstu" {
		t.Errorf("BTC address should start with bc1qstub, got %s", btc[:7])
	}

	ltc := cryptoStubAddress("LTC")
	if len(ltc) == 0 {
		t.Error("LTC address should not be empty")
	}

	xmr := cryptoStubAddress("XMR")
	if len(xmr) == 0 {
		t.Error("XMR address should not be empty")
	}
}

func TestCryptoScheme(t *testing.T) {
	tests := []struct {
		currency string
		expected string
	}{
		{"BTC", "bitcoin"},
		{"LTC", "litecoin"},
		{"XMR", "monero"},
		{"ETH", "crypto"},
		{"", "crypto"},
	}

	for _, tt := range tests {
		got := cryptoScheme(tt.currency)
		if got != tt.expected {
			t.Errorf("cryptoScheme(%q) = %q, want %q", tt.currency, got, tt.expected)
		}
	}
}

func TestConstants(t *testing.T) {
	if MaxDevicesPerLicense != 3 {
		t.Errorf("expected MaxDevicesPerLicense=3, got %d", MaxDevicesPerLicense)
	}
	if MonthlyDurationDays != 30 {
		t.Errorf("expected MonthlyDurationDays=30, got %d", MonthlyDurationDays)
	}
	if YearlyDurationDays != 365 {
		t.Errorf("expected YearlyDurationDays=365, got %d", YearlyDurationDays)
	}
	if PostExpiryGraceDays != 7 {
		t.Errorf("expected PostExpiryGraceDays=7, got %d", PostExpiryGraceDays)
	}
}
