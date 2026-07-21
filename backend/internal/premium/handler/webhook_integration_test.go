//go:build integration

package handler

import (
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/premium/model"
)

// TestWebhook_SignatureInvalid_Rejected confirms baseline signature gate
// still works against the real handler wiring. Acts as a smoke test for the
// integration harness itself.
func TestWebhook_SignatureInvalid_Rejected(t *testing.T) {
	resetDB(t)
	payload := loadFixture(t, "checkout.session.completed.json")
	h := http.Header{}
	h.Set("Stripe-Signature", "t=1,v1=deadbeef")
	h.Set("Content-Type", "application/json")
	w := postWebhook(t, payload, h)
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", w.Code, w.Body.String())
	}
}

// TestWebhook_DuplicateEventID_HandlerRunsOnce asserts the webhook_events
// dedup mechanism short-circuits the second delivery AT THE BUSINESS-EFFECT
// LEVEL — not just at the dedup row count. A retry of the same Stripe
// subscription_cycle event must NOT double-extend the license, otherwise the
// `subscription_create`-class bug reappears via the retry path.
//
// Seeds a yearly license, fires the same renewal event twice, asserts
// expires_at advances by exactly one year (not two).
func TestWebhook_DuplicateEventID_HandlerRunsOnce(t *testing.T) {
	resetDB(t)

	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, 'ssvid', 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-dup-"+deviceID.String(),
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}

	originalExpiry := time.Now().Add(15 * 24 * time.Hour).UTC().Truncate(time.Second)
	sub := "sub_test_cycle" // matches the fixture
	license := model.PremiumLicense{
		ID:                   uuid.New(),
		DeviceID:             deviceID,
		Brand:                "ssvid",
		LicenseKey:           "SSVID-dddd-eeee-ffff-1111-2222-3333-4444-5555",
		Tier:                 "premium",
		BillingCycle:         "yearly",
		PaymentMethod:        "stripe",
		IsAutoRenew:          true,
		ExpiresAt:            originalExpiry,
		StripeSubscriptionID: &sub,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}

	payload := loadFixture(t, "invoice.paid.subscription_cycle.json")
	for i := 0; i < 2; i++ {
		w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
		if w.Code != http.StatusOK {
			t.Fatalf("delivery %d expected 200, got %d body=%s", i, w.Code, w.Body.String())
		}
	}

	var rows int64
	if err := testDB.Table("webhook_events").
		Where("event_id = ?", "evt_test_invoice_paid_cycle").
		Count(&rows).Error; err != nil {
		t.Fatalf("count webhook_events: %v", err)
	}
	if rows != 1 {
		t.Fatalf("expected exactly 1 webhook_events row, got %d", rows)
	}

	// Business-effect assertion (Codex post-review: dedup row count alone is
	// not enough). After two deliveries the license expiry must advance by
	// exactly ONE billing cycle, not two.
	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	expectedAfterOne := originalExpiry.AddDate(1, 0, 0)
	expectedAfterTwo := originalExpiry.AddDate(2, 0, 0)
	diffOne := got.ExpiresAt.Sub(expectedAfterOne)
	diffTwo := got.ExpiresAt.Sub(expectedAfterTwo)
	if diffOne < -48*time.Hour || diffOne > 48*time.Hour {
		if diffTwo > -48*time.Hour && diffTwo < 48*time.Hour {
			t.Fatalf("DEDUP REGRESSION: expires_at advanced TWICE (%v ≈ %v); subscription_create-class bug reintroduced",
				got.ExpiresAt, expectedAfterTwo)
		}
		t.Fatalf("expires_at unexpected: want ~%v (advanced once), got %v", expectedAfterOne, got.ExpiresAt)
	}
}

// TestWebhook_ConcurrentDeliveries_ExactlyOneProcessed exercises the same
// event arriving concurrently. The current MarkProcessing implementation is
// known-racy (audit W3.1) — this test documents the current behavior so the
// W3.1 fix can flip the assertion. Currently both deliveries succeed; once
// W3.1 lands, exactly one should win the reclaim.
//
// For now we assert the weaker invariant: BOTH deliveries return 200 (no
// 500 / 409 surfaced to Stripe), AND the dedup row exists. The stronger
// "exactly one handler ran" assertion will be added in W3.1.
func TestWebhook_ConcurrentDeliveries_AllReturnOK(t *testing.T) {
	resetDB(t)
	payload := loadFixture(t, "customer.subscription.deleted.json")

	const N = 4
	var wg sync.WaitGroup
	wg.Add(N)
	codes := make([]int, N)
	for i := 0; i < N; i++ {
		go func(i int) {
			defer wg.Done()
			w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
			codes[i] = w.Code
		}(i)
	}
	wg.Wait()

	for i, c := range codes {
		if c != http.StatusOK {
			t.Fatalf("delivery %d: expected 200, got %d", i, c)
		}
	}
	var rows int64
	if err := testDB.Table("webhook_events").
		Where("event_id = ?", "evt_test_sub_deleted").
		Count(&rows).Error; err != nil {
		t.Fatalf("count: %v", err)
	}
	if rows != 1 {
		t.Fatalf("expected 1 webhook_events row, got %d", rows)
	}
}

// TestWebhook_SubscriptionCreate_DoesNotExtendExpiry locks in the
// regression behavior for the ae0867f1 fix. Setup: a license already exists
// for the subscription with a known expires_at. The subscription_create
// invoice fires. expires_at must NOT change.
func TestWebhook_SubscriptionCreate_DoesNotExtendExpiry(t *testing.T) {
	resetDB(t)

	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, 'ssvid', 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-"+deviceID.String(),
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}

	originalExpiry := time.Date(2027, 5, 20, 0, 0, 0, 0, time.UTC)
	sub := "sub_test_create"
	license := model.PremiumLicense{
		ID:                   uuid.New(),
		DeviceID:             deviceID,
		Brand:                "ssvid",
		LicenseKey:           "SSVID-1111-2222-3333-4444-5555-6666-7777-8888",
		Tier:                 "premium",
		BillingCycle:         "yearly",
		PaymentMethod:        "stripe",
		IsAutoRenew:          true,
		ExpiresAt:            originalExpiry,
		StripeSubscriptionID: &sub,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}

	payload := loadFixture(t, "invoice.paid.subscription_create.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if !got.ExpiresAt.Equal(originalExpiry) {
		t.Fatalf("expires_at changed: want %v got %v (subscription_create must NOT extend)",
			originalExpiry, got.ExpiresAt)
	}
}

// TestWebhook_SubscriptionCycle_ExtendsExpiry confirms the opposite: a real
// renewal (billing_reason=subscription_cycle) DOES extend the expiry. This
// is the positive case the bugfix preserved.
func TestWebhook_SubscriptionCycle_ExtendsExpiry(t *testing.T) {
	resetDB(t)

	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, 'ssvid', 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-cycle-"+deviceID.String(),
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}

	originalExpiry := time.Now().Add(15 * 24 * time.Hour).UTC().Truncate(time.Second)
	sub := "sub_test_cycle"
	license := model.PremiumLicense{
		ID:                   uuid.New(),
		DeviceID:             deviceID,
		Brand:                "ssvid",
		LicenseKey:           "SSVID-aaaa-bbbb-cccc-dddd-eeee-ffff-1111-2222",
		Tier:                 "premium",
		BillingCycle:         "yearly",
		PaymentMethod:        "stripe",
		IsAutoRenew:          true,
		ExpiresAt:            originalExpiry,
		StripeSubscriptionID: &sub,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}

	payload := loadFixture(t, "invoice.paid.subscription_cycle.json")
	w := postWebhook(t, payload, signStripeRequest(payload, testWebhookSecret))
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}

	var got model.PremiumLicense
	if err := testDB.First(&got, "id = ?", license.ID).Error; err != nil {
		t.Fatalf("reload license: %v", err)
	}
	if !got.ExpiresAt.After(originalExpiry) {
		t.Fatalf("expires_at not extended: want > %v got %v (subscription_cycle MUST extend)",
			originalExpiry, got.ExpiresAt)
	}
	// Expect roughly +1 year for a yearly license.
	expected := originalExpiry.AddDate(1, 0, 0)
	diff := got.ExpiresAt.Sub(expected)
	if diff < -48*time.Hour || diff > 48*time.Hour {
		t.Fatalf("expires_at extension off: want ~%v, got %v (diff %v)", expected, got.ExpiresAt, diff)
	}
}
