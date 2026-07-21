package crypto

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"

	"golang.org/x/crypto/bcrypt"
)

const apiKeyPrefix = "snk_"

// GenerateAPIKey creates a new API key with snk_ prefix.
// Returns (rawKey, sha256Hash, error).
func GenerateAPIKey() (string, string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", "", fmt.Errorf("failed to generate random bytes: %w", err)
	}

	raw := apiKeyPrefix + base64.URLEncoding.WithPadding(base64.NoPadding).EncodeToString(bytes)
	hash := HashAPIKey(raw)

	return raw, hash, nil
}

// HashAPIKey returns the SHA-256 hex digest of a raw API key.
func HashAPIKey(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return fmt.Sprintf("%x", h)
}

// HashPassword hashes a password with bcrypt.
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("failed to hash password: %w", err)
	}
	return string(bytes), nil
}

// CheckPassword compares a plaintext password with a bcrypt hash.
func CheckPassword(password, hash string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
