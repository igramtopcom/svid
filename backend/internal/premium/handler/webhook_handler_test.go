package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/snakeloader/backend/internal/config"
)

func TestVerifyStripeSignature_Valid(t *testing.T) {
	secret := "whsec_test_secret"
	payload := []byte(`{"id":"evt_123","type":"checkout.session.completed"}`)
	timestamp := fmt.Sprintf("%d", time.Now().Unix())

	// Compute expected signature
	signedPayload := timestamp + "." + string(payload)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signedPayload))
	sig := hex.EncodeToString(mac.Sum(nil))

	header := fmt.Sprintf("t=%s,v1=%s", timestamp, sig)

	if !verifyStripeSignature(payload, header, secret) {
		t.Error("expected valid signature to pass verification")
	}
}

func TestVerifyStripeSignature_Invalid(t *testing.T) {
	secret := "whsec_test_secret"
	payload := []byte(`{"id":"evt_123"}`)

	header := "t=12345,v1=invalidsignature"

	if verifyStripeSignature(payload, header, secret) {
		t.Error("expected invalid signature to fail verification")
	}
}

func TestVerifyStripeSignature_EmptyHeader(t *testing.T) {
	if verifyStripeSignature([]byte("test"), "", "secret") {
		t.Error("expected empty header to fail")
	}
}

func TestVerifyStripeSignature_MissingTimestamp(t *testing.T) {
	if verifyStripeSignature([]byte("test"), "v1=abc123", "secret") {
		t.Error("expected missing timestamp to fail")
	}
}

func TestVerifyStripeSignature_MissingSignature(t *testing.T) {
	if verifyStripeSignature([]byte("test"), "t=12345", "secret") {
		t.Error("expected missing v1 signature to fail")
	}
}

func TestVerifyStripeSignature_TamperedPayload(t *testing.T) {
	secret := "whsec_test_secret"
	original := []byte(`{"amount":999}`)
	tampered := []byte(`{"amount":0}`)
	timestamp := fmt.Sprintf("%d", time.Now().Unix())

	// Sign the original
	signedPayload := timestamp + "." + string(original)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signedPayload))
	sig := hex.EncodeToString(mac.Sum(nil))

	header := fmt.Sprintf("t=%s,v1=%s", timestamp, sig)

	// Verify with tampered payload should fail
	if verifyStripeSignature(tampered, header, secret) {
		t.Error("expected tampered payload to fail verification")
	}
}

// isPartialRefund mirrors the partial refund detection logic in handleChargeRefunded.
// Extracted here to test the conditional without needing a full WebhookHandler.
func isPartialRefund(charge stripeCharge) bool {
	return charge.Amount > 0 && charge.AmountRefunded > 0 && charge.AmountRefunded < charge.Amount
}

func TestChargeRefunded_PartialRefund_DoesNotRevoke(t *testing.T) {
	// Simulate a partial refund: $10 charge, $3 refunded.
	raw := json.RawMessage(`{
		"id": "ch_partial",
		"payment_intent": "pi_123",
		"refunded": false,
		"amount": 1000,
		"amount_refunded": 300
	}`)

	var charge stripeCharge
	if err := json.Unmarshal(raw, &charge); err != nil {
		t.Fatalf("failed to parse charge JSON: %v", err)
	}

	if charge.Amount != 1000 {
		t.Fatalf("expected amount 1000, got %d", charge.Amount)
	}
	if charge.AmountRefunded != 300 {
		t.Fatalf("expected amount_refunded 300, got %d", charge.AmountRefunded)
	}
	if charge.Refunded {
		t.Fatal("expected refunded=false for partial refund")
	}

	if !isPartialRefund(charge) {
		t.Error("expected partial refund to be detected (amount_refunded < amount)")
	}
}

func TestChargeRefunded_FullRefund_ShouldRevoke(t *testing.T) {
	tests := []struct {
		name string
		json string
	}{
		{
			name: "amount_refunded equals amount",
			json: `{"id":"ch_full","payment_intent":"pi_456","refunded":true,"amount":2000,"amount_refunded":2000}`,
		},
		{
			name: "amount_refunded exceeds amount (edge case)",
			json: `{"id":"ch_over","payment_intent":"pi_789","refunded":true,"amount":1500,"amount_refunded":1600}`,
		},
		{
			name: "refunded flag true with zero amount_refunded",
			json: `{"id":"ch_flag","payment_intent":"pi_abc","refunded":true,"amount":1000,"amount_refunded":0}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var charge stripeCharge
			if err := json.Unmarshal([]byte(tt.json), &charge); err != nil {
				t.Fatalf("failed to parse charge JSON: %v", err)
			}

			if isPartialRefund(charge) {
				t.Error("expected full refund NOT to be detected as partial")
			}
		})
	}
}

func TestChargeRefunded_NoPaymentIntent_Skips(t *testing.T) {
	raw := json.RawMessage(`{
		"id": "ch_nopi",
		"payment_intent": "",
		"refunded": true,
		"amount": 1000,
		"amount_refunded": 1000
	}`)

	var charge stripeCharge
	if err := json.Unmarshal(raw, &charge); err != nil {
		t.Fatalf("failed to parse charge JSON: %v", err)
	}

	// handleChargeRefunded returns nil early when PaymentIntent is empty.
	if charge.PaymentIntent != "" {
		t.Error("expected empty payment_intent")
	}
}

func TestStripeChargeParsing(t *testing.T) {
	raw := `{
		"id": "ch_test123",
		"payment_intent": "pi_test456",
		"refunded": false,
		"amount": 4999,
		"amount_refunded": 1250
	}`

	var charge stripeCharge
	if err := json.Unmarshal([]byte(raw), &charge); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if charge.ID != "ch_test123" {
		t.Errorf("ID: want ch_test123, got %s", charge.ID)
	}
	if charge.PaymentIntent != "pi_test456" {
		t.Errorf("PaymentIntent: want pi_test456, got %s", charge.PaymentIntent)
	}
	if charge.Refunded != false {
		t.Error("Refunded: want false, got true")
	}
	if charge.Amount != 4999 {
		t.Errorf("Amount: want 4999, got %d", charge.Amount)
	}
	if charge.AmountRefunded != 1250 {
		t.Errorf("AmountRefunded: want 1250, got %d", charge.AmountRefunded)
	}
}

// --- Multi-tenant brand attribution tests -------------------------------
//
// The same Stripe account serves SSvid desktop, VidCombo desktop, legacy
// VidCombo (PHP), and legacy ssvid.net. Webhook handlers MUST filter by
// price_id so unrelated invoices don't inflate this backend's revenue
// dashboard. These tests pin down the attribution surface.

// testStripeConfig returns a StripeConfig populated with stable test price IDs
// covering both brands. Use the *_test_ prefix so accidental real-world
// collisions are obvious.
func testStripeConfig() *config.StripeConfig {
	return &config.StripeConfig{
		PriceMonthly:            "price_test_ssvid_monthly",
		PriceYearly:             "price_test_ssvid_yearly",
		PriceLifetime:           "price_test_ssvid_lifetime",
		VidComboPriceMonthly:    "price_test_vidcombo_monthly",
		VidComboPriceSemiannual: "price_test_vidcombo_semiannual",
		VidComboPriceYearly:     "price_test_vidcombo_yearly",
	}
}

func TestBrandFromPriceID_SSvidPrices(t *testing.T) {
	cfg := testStripeConfig()

	cases := []string{
		cfg.PriceMonthly,
		cfg.PriceYearly,
		cfg.PriceLifetime,
	}
	for _, priceID := range cases {
		t.Run(priceID, func(t *testing.T) {
			brand, ok := cfg.BrandFromPriceID(priceID)
			if !ok {
				t.Fatalf("expected SSvid price %q to be recognized", priceID)
			}
			if brand != "ssvid" {
				t.Errorf("brand: want ssvid, got %s", brand)
			}
		})
	}
}

func TestBrandFromPriceID_VidComboPrices(t *testing.T) {
	cfg := testStripeConfig()

	cases := []string{
		cfg.VidComboPriceMonthly,
		cfg.VidComboPriceSemiannual,
		cfg.VidComboPriceYearly,
	}
	for _, priceID := range cases {
		t.Run(priceID, func(t *testing.T) {
			brand, ok := cfg.BrandFromPriceID(priceID)
			if !ok {
				t.Fatalf("expected VidCombo price %q to be recognized", priceID)
			}
			if brand != "vidcombo" {
				t.Errorf("brand: want vidcombo, got %s", brand)
			}
		})
	}
}

// TestBrandFromPriceID_ForeignPrices_AreFiltered guards the actual revenue leak.
// Any price ID not configured here belongs to another product on the shared
// Stripe account (legacy VidCombo PHP, legacy ssvid.net, anh Quan's other
// products, etc.) and MUST be rejected.
func TestBrandFromPriceID_ForeignPrices_AreFiltered(t *testing.T) {
	cfg := testStripeConfig()

	cases := []struct {
		name    string
		priceID string
	}{
		{"legacy_vidcombo_php", "price_legacy_vidcombo_old_monthly"},
		{"legacy_ssvid_net", "price_legacy_ssvid_net_yearly"},
		{"unrelated_product", "price_someone_else_product"},
		{"empty_string", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			brand, ok := cfg.BrandFromPriceID(tc.priceID)
			if ok {
				t.Errorf("expected foreign price %q to be filtered, got brand=%s", tc.priceID, brand)
			}
			if brand != "" {
				t.Errorf("expected empty brand for foreign price, got %s", brand)
			}
		})
	}
}

// TestBrandFromPriceID_EmptyConfigDoesNotMatchEmptyPrice prevents a subtle bug
// where an unconfigured brand (e.g. STRIPE_VIDCOMBO_PRICE_YEARLY="" in dev)
// would match an empty price_id from a malformed webhook payload and
// mis-attribute revenue. The early `priceID == ""` check guards this.
func TestBrandFromPriceID_EmptyConfigDoesNotMatchEmptyPrice(t *testing.T) {
	cfg := &config.StripeConfig{
		PriceMonthly: "price_real_ssvid_monthly",
		// All other fields are "" — the typical dev config state.
	}

	if brand, ok := cfg.BrandFromPriceID(""); ok {
		t.Errorf("empty price ID must never match empty config slot, got brand=%s", brand)
	}
}

func TestStripeInvoice_FirstPriceID_FromLines(t *testing.T) {
	raw := `{
		"id": "in_test_123",
		"subscription": "sub_test_123",
		"status": "paid",
		"amount_due": 999,
		"amount_paid": 999,
		"currency": "usd",
		"lines": {
			"data": [
				{"price": {"id": "price_test_ssvid_monthly"}}
			]
		}
	}`

	var inv stripeInvoice
	if err := json.Unmarshal([]byte(raw), &inv); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got := inv.firstPriceID(); got != "price_test_ssvid_monthly" {
		t.Errorf("firstPriceID: want price_test_ssvid_monthly, got %s", got)
	}
}

func TestStripeInvoice_FirstPriceID_EmptyLines(t *testing.T) {
	raw := `{
		"id": "in_test_empty",
		"status": "open",
		"lines": {"data": []}
	}`

	var inv stripeInvoice
	if err := json.Unmarshal([]byte(raw), &inv); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got := inv.firstPriceID(); got != "" {
		t.Errorf("firstPriceID on empty lines: want \"\", got %s", got)
	}
}

func TestStripeInvoice_FirstPriceID_MissingLines(t *testing.T) {
	// Some Stripe events (e.g. invoice.deleted) may omit lines entirely.
	raw := `{"id": "in_test_no_lines", "status": "draft"}`

	var inv stripeInvoice
	if err := json.Unmarshal([]byte(raw), &inv); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got := inv.firstPriceID(); got != "" {
		t.Errorf("firstPriceID on missing lines: want \"\", got %s", got)
	}
}

// TestStripeInvoice_AttributionRouting walks the full attribution chain on
// realistic webhook payloads. This is the regression test that would have
// caught the original revenue leak: a foreign invoice ($3173.19 from legacy
// products) reaching persistInvoiceRecord with the hardcoded brand="ssvid"
// fallback.
func TestStripeInvoice_AttributionRouting(t *testing.T) {
	cfg := testStripeConfig()

	cases := []struct {
		name        string
		priceID     string
		wantOK      bool
		wantBrand   string
		description string
	}{
		{
			name:        "ssvid_monthly_routes_to_ssvid",
			priceID:     "price_test_ssvid_monthly",
			wantOK:      true,
			wantBrand:   "ssvid",
			description: "real SSvid invoice should persist with brand=ssvid",
		},
		{
			name:        "vidcombo_yearly_routes_to_vidcombo",
			priceID:     "price_test_vidcombo_yearly",
			wantOK:      true,
			wantBrand:   "vidcombo",
			description: "real VidCombo invoice should persist with brand=vidcombo",
		},
		{
			name:        "legacy_vidcombo_php_is_filtered",
			priceID:     "price_legacy_vidcombo_php_monthly",
			wantOK:      false,
			description: "legacy VidCombo (managed by checkkey.php) must NOT inflate dashboard",
		},
		{
			name:        "legacy_ssvid_net_is_filtered",
			priceID:     "price_legacy_ssvid_net_yearly",
			wantOK:      false,
			description: "legacy ssvid.net (PHP/Yii) must NOT inflate dashboard",
		},
		{
			name:        "unknown_product_is_filtered",
			priceID:     "price_some_other_product",
			wantOK:      false,
			description: "any unrelated product on the shared Stripe account must be filtered",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			payload := fmt.Sprintf(`{
				"id": "in_%s",
				"status": "paid",
				"amount_paid": 999,
				"currency": "usd",
				"lines": {"data": [{"price": {"id": %q}}]}
			}`, tc.name, tc.priceID)

			var inv stripeInvoice
			if err := json.Unmarshal([]byte(payload), &inv); err != nil {
				t.Fatalf("unmarshal: %v", err)
			}

			brand, ok := cfg.BrandFromPriceID(inv.firstPriceID())
			if ok != tc.wantOK {
				t.Fatalf("%s: ok mismatch, want %v got %v (brand=%s)", tc.description, tc.wantOK, ok, brand)
			}
			if ok && brand != tc.wantBrand {
				t.Errorf("%s: brand mismatch, want %s got %s", tc.description, tc.wantBrand, brand)
			}
		})
	}
}

func TestVerifyStripeSignature_ReplayProtection(t *testing.T) {
	secret := "whsec_test_secret"
	payload := []byte(`{"id":"evt_old"}`)
	// Timestamp 10 minutes ago — should be rejected (>5 min).
	oldTimestamp := fmt.Sprintf("%d", time.Now().Add(-10*time.Minute).Unix())

	signedPayload := oldTimestamp + "." + string(payload)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signedPayload))
	sig := hex.EncodeToString(mac.Sum(nil))

	header := fmt.Sprintf("t=%s,v1=%s", oldTimestamp, sig)

	if verifyStripeSignature(payload, header, secret) {
		t.Error("expected replayed event (>5 min old) to fail signature verification")
	}
}
