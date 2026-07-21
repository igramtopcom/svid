package crypto

import (
	"strings"
	"testing"
)

func TestGenerateAPIKey_Format(t *testing.T) {
	raw, hash, err := GenerateAPIKey()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Raw key should start with "snk_"
	if !strings.HasPrefix(raw, "snk_") {
		t.Errorf("expected snk_ prefix, got %s", raw[:4])
	}

	// Hash should be 64 hex chars (SHA-256)
	if len(hash) != 64 {
		t.Errorf("expected hash length 64, got %d", len(hash))
	}

	// Hash should be lowercase hex
	for _, c := range hash {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			t.Errorf("non-hex char in hash: %c", c)
		}
	}
}

func TestGenerateAPIKey_Unique(t *testing.T) {
	keys := make(map[string]bool, 50)
	for i := 0; i < 50; i++ {
		raw, _, err := GenerateAPIKey()
		if err != nil {
			t.Fatalf("error on iteration %d: %v", i, err)
		}
		if keys[raw] {
			t.Fatalf("duplicate key generated: %s", raw)
		}
		keys[raw] = true
	}
}

func TestHashAPIKey_Deterministic(t *testing.T) {
	key := "snk_dGVzdGtleQ"
	hash1 := HashAPIKey(key)
	hash2 := HashAPIKey(key)

	if hash1 != hash2 {
		t.Errorf("hashing same key should produce same result: %s != %s", hash1, hash2)
	}
}

func TestHashAPIKey_DifferentKeys(t *testing.T) {
	hash1 := HashAPIKey("snk_key1")
	hash2 := HashAPIKey("snk_key2")

	if hash1 == hash2 {
		t.Error("different keys should produce different hashes")
	}
}

func TestHashAPIKey_Length(t *testing.T) {
	hash := HashAPIKey("snk_anything")
	if len(hash) != 64 {
		t.Errorf("expected SHA-256 hash length 64, got %d", len(hash))
	}
}

func TestHashPassword_ReturnsHash(t *testing.T) {
	hash, err := HashPassword("mypassword123")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if hash == "" {
		t.Error("expected non-empty hash")
	}

	// Bcrypt hashes start with $2
	if !strings.HasPrefix(hash, "$2") {
		t.Errorf("expected bcrypt hash prefix $2, got %s", hash[:2])
	}
}

func TestHashPassword_DifferentSalts(t *testing.T) {
	hash1, _ := HashPassword("samepassword")
	hash2, _ := HashPassword("samepassword")

	// bcrypt uses random salts, so same password → different hashes
	if hash1 == hash2 {
		t.Error("same password should produce different hashes due to salt")
	}
}

func TestCheckPassword_Valid(t *testing.T) {
	password := "correctpassword"
	hash, _ := HashPassword(password)

	if !CheckPassword(password, hash) {
		t.Error("expected valid password check to return true")
	}
}

func TestCheckPassword_Invalid(t *testing.T) {
	hash, _ := HashPassword("correctpassword")

	if CheckPassword("wrongpassword", hash) {
		t.Error("expected invalid password check to return false")
	}
}

func TestCheckPassword_EmptyPassword(t *testing.T) {
	hash, _ := HashPassword("notempty")

	if CheckPassword("", hash) {
		t.Error("empty password should not match")
	}
}

func TestGenerateAPIKey_HashMatchesRaw(t *testing.T) {
	raw, hash, _ := GenerateAPIKey()

	// The hash returned should match hashing the raw key
	recomputed := HashAPIKey(raw)
	if hash != recomputed {
		t.Errorf("generated hash doesn't match: %s != %s", hash, recomputed)
	}
}
