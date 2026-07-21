package dto

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/premium/model"
)

func TestLicenseToResponse(t *testing.T) {
	id := uuid.New()
	deviceID := uuid.New()
	now := time.Now()
	expiresAt := now.Add(30 * 24 * time.Hour)

	license := &model.PremiumLicense{
		ID:            id,
		DeviceID:      deviceID,
		LicenseKey:    "SSVID-abcd-ef01-2345-6789-abcd-ef01-2345-6789",
		Tier:          "premium",
		BillingCycle:  "monthly",
		PaymentMethod: "stripe",
		IsAutoRenew:   true,
		ExpiresAt:     expiresAt,
		CreatedAt:     now,
		UpdatedAt:     now,
	}

	resp := LicenseToResponse(license)

	if resp.ID != id.String() {
		t.Errorf("expected ID %s, got %s", id.String(), resp.ID)
	}
	if resp.LicenseKey != "SSVID-abcd-ef01-2345-6789-abcd-ef01-2345-6789" {
		t.Errorf("expected license key SSVID-abcd-ef01-..., got %s", resp.LicenseKey)
	}
	if resp.Tier != "premium" {
		t.Errorf("expected tier premium, got %s", resp.Tier)
	}
	if resp.BillingCycle != "monthly" {
		t.Errorf("expected billing cycle monthly, got %s", resp.BillingCycle)
	}
	if resp.PaymentMethod != "stripe" {
		t.Errorf("expected payment method stripe, got %s", resp.PaymentMethod)
	}
	if !resp.IsAutoRenew {
		t.Error("expected IsAutoRenew to be true")
	}
}

func TestLicensesToResponse(t *testing.T) {
	licenses := []model.PremiumLicense{
		{ID: uuid.New(), LicenseKey: "SSVID-1111-2222-3333-4444-5555-6666-7777-8888", Tier: "premium", ExpiresAt: time.Now()},
		{ID: uuid.New(), LicenseKey: "VIDCOMBO-aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111", Tier: "free", ExpiresAt: time.Now()},
	}

	responses := LicensesToResponse(licenses)
	if len(responses) != 2 {
		t.Fatalf("expected 2 responses, got %d", len(responses))
	}
	if responses[0].LicenseKey != "SSVID-1111-2222-3333-4444-5555-6666-7777-8888" {
		t.Error("first response has wrong license key")
	}
	if responses[1].Tier != "free" {
		t.Error("second response has wrong tier")
	}
}

func TestTransactionToResponse(t *testing.T) {
	id := uuid.New()
	deviceID := uuid.New()
	sessionID := "cs_test_123"
	now := time.Now()

	txn := &model.PaymentTransaction{
		ID:              id,
		DeviceID:        deviceID,
		IdempotencyKey:  "idk-123",
		PaymentMethod:   "stripe",
		BillingCycle:    "yearly",
		AmountCents:     7999,
		Currency:        "USD",
		Status:          "completed",
		StripeSessionID: &sessionID,
		CompletedAt:     &now,
		CreatedAt:       now,
	}

	resp := TransactionToResponse(txn)

	if resp.ID != id.String() {
		t.Errorf("expected ID %s, got %s", id.String(), resp.ID)
	}
	if resp.PaymentMethod != "stripe" {
		t.Errorf("expected stripe, got %s", resp.PaymentMethod)
	}
	if resp.AmountCents != 7999 {
		t.Errorf("expected 7999, got %d", resp.AmountCents)
	}
	if resp.Status != "completed" {
		t.Errorf("expected completed, got %s", resp.Status)
	}
}
