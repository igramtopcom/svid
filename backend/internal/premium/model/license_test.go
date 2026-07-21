package model

import (
	"strings"
	"testing"
	"time"
)

func TestGenerateLicenseKey_SSvid(t *testing.T) {
	key := GenerateLicenseKey("test-secret", "ssvid")

	if !strings.HasPrefix(key, "SSVID-") {
		t.Errorf("expected prefix SSVID-, got %s", key)
	}

	// SSVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (45 chars)
	if len(key) != 45 {
		t.Errorf("expected length 45, got %d (%s)", len(key), key)
	}

	parts := strings.Split(key, "-")
	if len(parts) != 9 {
		t.Errorf("expected 9 parts, got %d", len(parts))
	}
	if parts[0] != "SSVID" {
		t.Errorf("expected first part SSVID, got %s", parts[0])
	}
	for i := 1; i < 9; i++ {
		if len(parts[i]) != 4 {
			t.Errorf("part %d: expected 4 chars, got %d (%s)", i, len(parts[i]), parts[i])
		}
	}
}

func TestGenerateLicenseKey_VidCombo(t *testing.T) {
	key := GenerateLicenseKey("test-secret", "vidcombo")

	if !strings.HasPrefix(key, "VIDCOMBO-") {
		t.Errorf("expected prefix VIDCOMBO-, got %s", key)
	}

	// VIDCOMBO-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (48 chars)
	if len(key) != 48 {
		t.Errorf("expected length 48, got %d (%s)", len(key), key)
	}

	parts := strings.Split(key, "-")
	if len(parts) != 9 {
		t.Errorf("expected 9 parts, got %d", len(parts))
	}
	if parts[0] != "VIDCOMBO" {
		t.Errorf("expected first part VIDCOMBO, got %s", parts[0])
	}
	for i := 1; i < 9; i++ {
		if len(parts[i]) != 4 {
			t.Errorf("part %d: expected 4 chars, got %d (%s)", i, len(parts[i]), parts[i])
		}
	}
}

func TestGenerateLicenseKey_DefaultBrand(t *testing.T) {
	// Unknown brand defaults to SSVID
	key := GenerateLicenseKey("test-secret", "")
	if !strings.HasPrefix(key, "SSVID-") {
		t.Errorf("empty brand should default to SSVID-, got %s", key)
	}

	key2 := GenerateLicenseKey("test-secret", "unknown")
	if !strings.HasPrefix(key2, "SSVID-") {
		t.Errorf("unknown brand should default to SSVID-, got %s", key2)
	}
}

func TestGenerateLicenseKey_CaseInsensitive(t *testing.T) {
	key := GenerateLicenseKey("test-secret", "VidCombo")
	if !strings.HasPrefix(key, "VIDCOMBO-") {
		t.Errorf("mixed-case 'VidCombo' should produce VIDCOMBO- prefix, got %s", key)
	}

	key2 := GenerateLicenseKey("test-secret", "VIDCOMBO")
	if !strings.HasPrefix(key2, "VIDCOMBO-") {
		t.Errorf("uppercase 'VIDCOMBO' should produce VIDCOMBO- prefix, got %s", key2)
	}
}

func TestGenerateLicenseKey_Unique(t *testing.T) {
	keys := make(map[string]bool, 100)
	for i := 0; i < 100; i++ {
		key := GenerateLicenseKey("test-secret", "ssvid")
		if keys[key] {
			t.Fatalf("duplicate key generated: %s", key)
		}
		keys[key] = true
	}
}

func TestGenerateLicenseKey_HexChars(t *testing.T) {
	for _, brand := range []string{"ssvid", "vidcombo"} {
		key := GenerateLicenseKey("hex-test", brand)
		prefix := brandKeyPrefix(brand)
		// Remove prefix- and dashes
		hexPart := strings.ReplaceAll(key[len(prefix)+1:], "-", "")

		validHex := "0123456789abcdef"
		for _, c := range hexPart {
			if !strings.ContainsRune(validHex, c) {
				t.Errorf("[%s] non-hex character found: %c in key %s", brand, c, key)
			}
		}
	}
}

func TestIsLifetimeBillingCycle(t *testing.T) {
	tests := []struct {
		cycle string
		want  bool
	}{
		{"lifetime", true},
		{"lifetime1", true},
		{"lifetime2", true},
		{"lifetime3", true},
		{"monthly", false},
		{"semiannual", false},
		{"yearly", false},
		{"", false},
	}

	for _, tt := range tests {
		if got := IsLifetimeBillingCycle(tt.cycle); got != tt.want {
			t.Errorf("IsLifetimeBillingCycle(%q) = %v, want %v", tt.cycle, got, tt.want)
		}
	}
}

func TestIsLicenseActiveAt(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)
	cancelledAt := now.Add(-time.Hour)

	tests := []struct {
		name    string
		license *PremiumLicense
		want    bool
	}{
		{
			name: "active monthly premium",
			license: &PremiumLicense{
				Tier:         "premium",
				BillingCycle: "monthly",
				ExpiresAt:    now.Add(time.Hour),
			},
			want: true,
		},
		{
			name: "lifetime premium remains active after expiry timestamp",
			license: &PremiumLicense{
				Tier:         "premium",
				BillingCycle: "lifetime2",
				ExpiresAt:    now.Add(-24 * time.Hour),
			},
			want: true,
		},
		{
			name: "cancelled lifetime is not active",
			license: &PremiumLicense{
				Tier:         "premium",
				BillingCycle: "lifetime1",
				ExpiresAt:    now.Add(100 * 24 * time.Hour),
				CancelledAt:  &cancelledAt,
			},
			want: false,
		},
		{
			name: "expired monthly premium is inactive",
			license: &PremiumLicense{
				Tier:         "premium",
				BillingCycle: "monthly",
				ExpiresAt:    now.Add(-time.Second),
			},
			want: false,
		},
		{
			name: "free tier is never active premium",
			license: &PremiumLicense{
				Tier:         "free",
				BillingCycle: "monthly",
				ExpiresAt:    now.Add(time.Hour),
			},
			want: false,
		},
		{name: "nil license", license: nil, want: false},
	}

	for _, tt := range tests {
		if got := IsLicenseActiveAt(tt.license, now); got != tt.want {
			t.Errorf("%s: IsLicenseActiveAt(...) = %v, want %v", tt.name, got, tt.want)
		}
	}
}

func TestLicenseStatusSQLHelpers(t *testing.T) {
	active := ActivePremiumLicenseSQL("pl")
	if !strings.Contains(active, "pl.tier = 'premium'") ||
		!strings.Contains(active, "pl.cancelled_at IS NULL") ||
		!strings.Contains(active, "pl.billing_cycle IN ('lifetime','lifetime1','lifetime2','lifetime3')") {
		t.Fatalf("unexpected active SQL helper: %s", active)
	}

	expired := ExpiredPremiumLicenseSQL("")
	if !strings.Contains(expired, "tier = 'premium'") ||
		!strings.Contains(expired, "cancelled_at IS NULL") ||
		!strings.Contains(expired, "billing_cycle NOT IN ('lifetime','lifetime1','lifetime2','lifetime3')") ||
		!strings.Contains(expired, "expires_at <= ?") {
		t.Fatalf("unexpected expired SQL helper: %s", expired)
	}
}
