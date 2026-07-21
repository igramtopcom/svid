//go:build integration

package handler

import (
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/premium/model"
)

// seedDeviceLicense is a small fixture helper used by every W1.4 test below.
// Returns the created license so tests can re-read it for assertions.
func seedDeviceLicense(t *testing.T, opts struct {
	LicenseKey     string
	Brand          string
	SubscriptionID string
}) model.PremiumLicense {
	t.Helper()
	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, ?, 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-"+deviceID.String(), opts.Brand,
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}
	sub := opts.SubscriptionID
	license := model.PremiumLicense{
		ID:                   uuid.New(),
		DeviceID:             deviceID,
		Brand:                opts.Brand,
		LicenseKey:           opts.LicenseKey,
		Tier:                 "premium",
		BillingCycle:         "yearly",
		PaymentMethod:        "stripe",
		IsAutoRenew:          true,
		ExpiresAt:            time.Now().Add(180 * 24 * time.Hour).UTC().Truncate(time.Second),
		StripeSubscriptionID: &sub,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}
	return license
}

// seedInvoiceRow inserts a raw Invoice with whatever fingerprint fields the
// caller wants populated. Lets each test target a specific fallback leg.
func seedInvoiceRow(t *testing.T, inv model.Invoice) {
	t.Helper()
	if inv.ID == uuid.Nil {
		inv.ID = uuid.New()
	}
	if inv.Brand == "" {
		inv.Brand = "ssvid"
	}
	if inv.Status == "" {
		inv.Status = "paid"
	}
	if inv.Currency == "" {
		inv.Currency = "usd"
	}
	if err := testDB.Create(&inv).Error; err != nil {
		t.Fatalf("seed invoice: %v", err)
	}
}

// TestWebhook_ChargeRefunded_InvoiceFallback_DirectLicense covers the W1.4
// happy path for renewal-only refunds: payment_transactions has no row for
// the PaymentIntent (subscription_cycle invoices created by Stripe billing
// don't go through our CreateCheckoutSession path), but the invoices table
// has the PaymentIntent fingerprint with a direct LicenseID pointer.
// Refund must still revoke.
func TestWebhook_ChargeRefunded_InvoiceFallback_DirectLicense(t *testing.T) {
	resetDB(t)

	license := seedDeviceLicense(t, struct {
		LicenseKey     string
		Brand          string
		SubscriptionID string
	}{
		LicenseKey:     "SSVID-w14a-w14a-w14a-w14a-w14a-w14a-w14a-w14a",
		Brand:          "ssvid",
		SubscriptionID: "sub_test_w14_refund_direct",
	})

	pi := "pi_test_refunded" // matches fixture
	seedInvoiceRow(t, model.Invoice{
		StripeInvoiceID:       "in_test_w14_refund_direct",
		LicenseID:             &license.ID,
		Brand:                 "ssvid",
		ContactEmail:          "w14a@example.com",
		AmountDueCents:        4188,
		AmountPaidCents:       4188,
		StripePaymentIntentID: &pi,
	})

	payload := loadFixture(t, "charge.refunded.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if got.Tier != "free" {
		t.Fatalf("W1.4 invoice-fallback refund failed: tier=%q, want \"free\"", got.Tier)
	}
	if got.CancelledAt == nil {
		t.Fatalf("CancelledAt not stamped after invoice-fallback refund")
	}
}

// TestWebhook_ChargeRefunded_InvoiceFallback_OrphanInvoice covers the second
// fallback leg: invoice has no LicenseID (e.g. invoice.finalized fired before
// checkout completed), but its StripeSubscriptionID matches a license we own.
// The chain invoice → subscription → license must still find and revoke.
func TestWebhook_ChargeRefunded_InvoiceFallback_OrphanInvoice(t *testing.T) {
	resetDB(t)

	license := seedDeviceLicense(t, struct {
		LicenseKey     string
		Brand          string
		SubscriptionID string
	}{
		LicenseKey:     "SSVID-w14b-w14b-w14b-w14b-w14b-w14b-w14b-w14b",
		Brand:          "ssvid",
		SubscriptionID: "sub_test_w14_refund_orphan",
	})

	pi := "pi_test_refunded"
	sub := "sub_test_w14_refund_orphan"
	seedInvoiceRow(t, model.Invoice{
		StripeInvoiceID:       "in_test_w14_refund_orphan",
		LicenseID:             nil, // orphan
		StripeSubscriptionID:  &sub,
		StripePaymentIntentID: &pi,
		Brand:                 "ssvid",
		ContactEmail:          "w14b@example.com",
		AmountDueCents:        4188,
		AmountPaidCents:       4188,
	})

	payload := loadFixture(t, "charge.refunded.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if got.Tier != "free" {
		t.Fatalf("W1.4 orphan-invoice fallback failed: tier=%q, want \"free\"", got.Tier)
	}
}

// TestWebhook_ChargeDispute_InvoiceFallback_OrphanInvoice exercises the
// dispute path through the orphan-invoice (LicenseID NULL) recovery via
// stripe_subscription_id. Mirrors the refund orphan test for the dispute
// surface so a dispute on a renewal-only invoice still revokes.
func TestWebhook_ChargeDispute_InvoiceFallback_OrphanInvoice(t *testing.T) {
	resetDB(t)

	license := seedDeviceLicense(t, struct {
		LicenseKey     string
		Brand          string
		SubscriptionID string
	}{
		LicenseKey:     "SSVID-w14o-w14o-w14o-w14o-w14o-w14o-w14o-w14o",
		Brand:          "ssvid",
		SubscriptionID: "sub_test_w14_dispute_orphan",
	})
	pi := "pi_test_disputed"
	sub := "sub_test_w14_dispute_orphan"
	seedInvoiceRow(t, model.Invoice{
		StripeInvoiceID:       "in_test_w14_dispute_orphan",
		LicenseID:             nil,
		StripeSubscriptionID:  &sub,
		StripePaymentIntentID: &pi,
		Brand:                 "ssvid",
		ContactEmail:          "w14o@example.com",
		AmountDueCents:        4188,
		AmountPaidCents:       4188,
	})

	payload := loadFixture(t, "charge.dispute.created.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if got.Tier != "free" {
		t.Fatalf("W1.4 dispute orphan-invoice fallback failed: tier=%q", got.Tier)
	}
}

// TestWebhook_ChargeDispute_InvoiceFallback covers the dispute.created path
// going through the same fallback chain as charge.refunded.
func TestWebhook_ChargeDispute_InvoiceFallback(t *testing.T) {
	resetDB(t)

	license := seedDeviceLicense(t, struct {
		LicenseKey     string
		Brand          string
		SubscriptionID string
	}{
		LicenseKey:     "SSVID-w14c-w14c-w14c-w14c-w14c-w14c-w14c-w14c",
		Brand:          "ssvid",
		SubscriptionID: "sub_test_w14_dispute",
	})

	pi := "pi_test_disputed" // matches fixture
	seedInvoiceRow(t, model.Invoice{
		StripeInvoiceID:       "in_test_w14_dispute",
		LicenseID:             &license.ID,
		StripePaymentIntentID: &pi,
		Brand:                 "ssvid",
		ContactEmail:          "w14c@example.com",
		AmountDueCents:        4188,
		AmountPaidCents:       4188,
	})

	payload := loadFixture(t, "charge.dispute.created.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if got.Tier != "free" {
		t.Fatalf("W1.4 dispute invoice-fallback failed: tier=%q, want \"free\"", got.Tier)
	}
}

// TestWebhook_ChargeDispute_EmptyPaymentIntent_ResolvedViaChargeRetrieve
// verifies the W1.4 charge-resolver fallback: a dispute with empty
// payment_intent must call chargeResolver(charge_id) and use the returned
// PaymentIntent to drive the invoice-fallback revoke. The override avoids
// hitting real Stripe.
func TestWebhook_ChargeDispute_EmptyPaymentIntent_ResolvedViaChargeRetrieve(t *testing.T) {
	resetDB(t)

	// Replace the package-level chargeResolver with a stub that maps
	// ch_test_charge_only → pi_test_charge_only. Restore in t.Cleanup so we
	// don't leak the stub into other tests.
	originalResolver := chargeResolver
	chargeResolver = func(chargeID string) (string, error) {
		if chargeID == "ch_test_charge_only" {
			return "pi_test_charge_only", nil
		}
		return "", nil
	}
	t.Cleanup(func() { chargeResolver = originalResolver })

	license := seedDeviceLicense(t, struct {
		LicenseKey     string
		Brand          string
		SubscriptionID string
	}{
		LicenseKey:     "SSVID-w14e-w14e-w14e-w14e-w14e-w14e-w14e-w14e",
		Brand:          "ssvid",
		SubscriptionID: "sub_test_w14_empty_pi",
	})
	pi := "pi_test_charge_only"
	seedInvoiceRow(t, model.Invoice{
		StripeInvoiceID:       "in_test_w14_empty_pi",
		LicenseID:             &license.ID,
		StripePaymentIntentID: &pi,
		Brand:                 "ssvid",
		ContactEmail:          "w14e@example.com",
		AmountDueCents:        4188,
		AmountPaidCents:       4188,
	})

	payload := loadFixture(t, "charge.dispute.created_empty_pi.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("empty-PI dispute with working charge resolver should be 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if got.Tier != "free" {
		t.Fatalf("empty-PI dispute should still revoke via charge-resolver fallback: tier=%q", got.Tier)
	}
}

// TestWebhook_ChargeDispute_EmptyPaymentIntent_ResolverFails returns an error
// to surface the problem instead of silently dropping the dispute.
func TestWebhook_ChargeDispute_EmptyPaymentIntent_ResolverFails(t *testing.T) {
	resetDB(t)
	originalResolver := chargeResolver
	chargeResolver = func(chargeID string) (string, error) { return "", nil }
	t.Cleanup(func() { chargeResolver = originalResolver })

	payload := loadFixture(t, "charge.dispute.created_empty_pi.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code == http.StatusOK {
		t.Fatalf("empty-PI dispute + resolver returning empty should NOT be 200, got 200")
	}
}

// TestWebhook_DisputeClosed_WonRestoresViaInvoiceFallback verifies the W1.4
// step 9 restore path: a license revoked through the invoice fallback must
// be restorable through the same chain when the dispute is later won.
func TestWebhook_DisputeClosed_WonRestoresViaInvoiceFallback(t *testing.T) {
	resetDB(t)

	// Seed a license already revoked (mimics what dispute.created did).
	now := time.Now().UTC().Truncate(time.Second)
	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, 'ssvid', 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-w14d",
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}
	sub := "sub_test_w14_won"
	license := model.PremiumLicense{
		ID:                   uuid.New(),
		DeviceID:             deviceID,
		Brand:                "ssvid",
		LicenseKey:           "SSVID-w14d-w14d-w14d-w14d-w14d-w14d-w14d-w14d",
		Tier:                 "free", // revoked from prior dispute
		BillingCycle:         "yearly",
		PaymentMethod:        "stripe",
		IsAutoRenew:          false,
		ExpiresAt:            now.Add(180 * 24 * time.Hour),
		StripeSubscriptionID: &sub,
		CancelledAt:          &now,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}

	pi := "pi_test_disputed" // matches won fixture
	seedInvoiceRow(t, model.Invoice{
		StripeInvoiceID:       "in_test_w14_won",
		LicenseID:             &license.ID,
		StripePaymentIntentID: &pi,
		Brand:                 "ssvid",
		ContactEmail:          "w14d@example.com",
		AmountDueCents:        4188,
		AmountPaidCents:       4188,
	})

	payload := loadFixture(t, "charge.dispute.closed_won.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if got.Tier != "premium" {
		t.Fatalf("won-dispute did not restore tier via invoice fallback: tier=%q", got.Tier)
	}
	if got.CancelledAt != nil {
		t.Fatalf("CancelledAt should be cleared after won-dispute restore, got %v", got.CancelledAt)
	}
	// W1.4 fix: auto-renew must come back for Stripe subs after a won
	// dispute. Otherwise Stripe keeps charging but we silently flip to
	// "do not renew" — the worst combination.
	if !got.IsAutoRenew {
		t.Fatalf("won-dispute should restore IsAutoRenew=true for Stripe subscriptions, got false")
	}
}

// TestWebhook_InvoicePaid_NestedPaymentsShape verifies the defensive nested
// invoice.payments.data[].payment.payment_intent parser. A future Stripe API
// version upgrade that drops the top-level payment_intent field must not
// silently break the W1.4 fingerprint persistence.
func TestWebhook_InvoicePaid_NestedPaymentsShape(t *testing.T) {
	resetDB(t)

	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, 'ssvid', 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-nested",
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}
	sub := "sub_test_nested" // matches fixture
	license := model.PremiumLicense{
		ID:                   uuid.New(),
		DeviceID:             deviceID,
		Brand:                "ssvid",
		LicenseKey:           "SSVID-nstd-nstd-nstd-nstd-nstd-nstd-nstd-nstd",
		Tier:                 "premium",
		BillingCycle:         "yearly",
		PaymentMethod:        "stripe",
		IsAutoRenew:          true,
		ExpiresAt:            time.Now().Add(30 * 24 * time.Hour).UTC().Truncate(time.Second),
		StripeSubscriptionID: &sub,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}

	payload := loadFixture(t, "invoice.paid.nested_payments.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var inv model.Invoice
	if err := testDB.First(&inv, "stripe_invoice_id = ?", "in_test_nested").Error; err != nil {
		t.Fatalf("reload invoice: %v", err)
	}
	if inv.StripePaymentIntentID == nil || *inv.StripePaymentIntentID != "pi_test_nested" {
		got := "<nil>"
		if inv.StripePaymentIntentID != nil {
			got = *inv.StripePaymentIntentID
		}
		t.Fatalf("nested payment_intent not extracted: got %s, want pi_test_nested", got)
	}
	if inv.StripeSubscriptionID == nil || *inv.StripeSubscriptionID != "sub_test_nested" {
		got := "<nil>"
		if inv.StripeSubscriptionID != nil {
			got = *inv.StripeSubscriptionID
		}
		t.Fatalf("subscription_id not persisted: got %s, want sub_test_nested", got)
	}
}
