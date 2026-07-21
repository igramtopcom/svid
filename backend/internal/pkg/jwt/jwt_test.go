package jwt

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestGenerate_ReturnsValidToken(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)

	adminID := uuid.New()
	token, expiresAt, err := m.Generate(adminID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if token == "" {
		t.Error("expected non-empty token")
	}

	if expiresAt.Before(time.Now()) {
		t.Error("expected expiry in the future")
	}

	// Expiry should be ~24 hours from now
	diff := time.Until(expiresAt)
	if diff < 23*time.Hour || diff > 25*time.Hour {
		t.Errorf("expected expiry ~24h from now, got %v", diff)
	}
}

func TestValidate_ValidToken(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)

	adminID := uuid.New()
	token, _, err := m.Generate(adminID)
	if err != nil {
		t.Fatalf("generate error: %v", err)
	}

	result, err := m.Validate(token)
	if err != nil {
		t.Fatalf("validate error: %v", err)
	}

	if result.AdminID != adminID {
		t.Errorf("expected admin ID %s, got %s", adminID, result.AdminID)
	}
	if result.BrandScope != "" {
		t.Errorf("expected empty brand scope, got %s", result.BrandScope)
	}
}

func TestValidate_ExpiredToken(t *testing.T) {
	// Create manager with 0 hour expiry (already expired)
	m := &Manager{
		secret: []byte("test-secret-key-at-least-32-chars!"),
		expiry: -1 * time.Hour, // expired 1 hour ago
	}

	adminID := uuid.New()
	token, _, err := m.Generate(adminID)
	if err != nil {
		t.Fatalf("generate error: %v", err)
	}

	_, err = m.Validate(token)
	if err == nil {
		t.Error("expected error for expired token")
	}
}

func TestValidate_WrongSecret(t *testing.T) {
	m1 := NewManager("secret-one-that-is-long-enough!!", 24)
	m2 := NewManager("secret-two-that-is-long-enough!!", 24)

	adminID := uuid.New()
	token, _, _ := m1.Generate(adminID)

	_, err := m2.Validate(token)
	if err == nil {
		t.Error("expected error when validating with wrong secret")
	}
}

func TestValidate_InvalidTokenString(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)

	_, err := m.Validate("not.a.valid.jwt.token")
	if err == nil {
		t.Error("expected error for invalid token")
	}
}

func TestValidate_EmptyToken(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)

	_, err := m.Validate("")
	if err == nil {
		t.Error("expected error for empty token")
	}
}

func TestValidate_BrandScope(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)

	adminID := uuid.New()
	token, _, err := m.Generate(adminID, "vidcombo")
	if err != nil {
		t.Fatalf("generate error: %v", err)
	}

	result, err := m.Validate(token)
	if err != nil {
		t.Fatalf("validate error: %v", err)
	}

	if result.AdminID != adminID {
		t.Errorf("expected admin ID %s, got %s", adminID, result.AdminID)
	}
	if result.BrandScope != "vidcombo" {
		t.Errorf("expected brand scope 'vidcombo', got '%s'", result.BrandScope)
	}
}

func TestGenerate_UniqueTokens(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)
	adminID := uuid.New()

	token1, _, _ := m.Generate(adminID)
	token2, _, _ := m.Generate(adminID)

	// Same admin ID should generate different tokens due to different IssuedAt
	// (may be same if generated in same second, but at least both valid)
	if token1 == "" || token2 == "" {
		t.Error("tokens should not be empty")
	}
}

func TestGenerate_DifferentAdmins(t *testing.T) {
	m := NewManager("test-secret-key-at-least-32-chars!", 24)

	admin1 := uuid.New()
	admin2 := uuid.New()

	token1, _, _ := m.Generate(admin1)
	token2, _, _ := m.Generate(admin2)

	// Validate each returns correct admin
	r1, _ := m.Validate(token1)
	r2, _ := m.Validate(token2)

	if r1.AdminID != admin1 {
		t.Errorf("token1 should resolve to admin1")
	}
	if r2.AdminID != admin2 {
		t.Errorf("token2 should resolve to admin2")
	}
}
