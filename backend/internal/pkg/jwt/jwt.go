package jwt

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type Manager struct {
	secret []byte
	expiry time.Duration
}

type Claims struct {
	AdminID    string `json:"admin_id"`
	BrandScope string `json:"brand_scope,omitempty"` // "" = super admin, "ssvid", "vidcombo"
	jwt.RegisteredClaims
}

func NewManager(secret string, expiryHours int) *Manager {
	return &Manager{
		secret: []byte(secret),
		expiry: time.Duration(expiryHours) * time.Hour,
	}
}

// Generate creates a new JWT token for an admin user.
func (m *Manager) Generate(adminID uuid.UUID, brandScope ...string) (string, time.Time, error) {
	expiresAt := time.Now().Add(m.expiry)

	scope := ""
	if len(brandScope) > 0 {
		scope = brandScope[0]
	}

	now := time.Now()
	claims := Claims{
		AdminID:    adminID.String(),
		BrandScope: scope,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        uuid.New().String(),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			Issuer:    "snakeloader",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(m.secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("failed to sign token: %w", err)
	}

	return signed, expiresAt, nil
}

// ValidateResult holds the parsed JWT claims.
type ValidateResult struct {
	AdminID    uuid.UUID
	BrandScope string
}

// Validate parses and validates a JWT token, returning the admin ID and brand scope.
func (m *Manager) Validate(tokenString string) (*ValidateResult, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return m.secret, nil
	})
	if err != nil {
		return nil, fmt.Errorf("invalid token: %w", err)
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}

	adminID, err := uuid.Parse(claims.AdminID)
	if err != nil {
		return nil, fmt.Errorf("invalid admin ID in token: %w", err)
	}

	return &ValidateResult{
		AdminID:    adminID,
		BrandScope: claims.BrandScope,
	}, nil
}
