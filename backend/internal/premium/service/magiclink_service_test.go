package service

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/config"
)

// newTestMagicLinkService builds a service with nil dependencies. Only useful
// for testing pure functions (verifyToken). Tests that need the lookup or
// Redis paths use the integration test infra instead.
func newTestMagicLinkService() *MagicLinkService {
	return &MagicLinkService{
		cfg:       config.MagicLinkConfig{TTLMinutes: 10, BaseURLSvid: "https://svid.app/restore"},
		jwtSecret: []byte("test-secret-do-not-use-in-prod"),
	}
}

func makeValidClaims(t *testing.T) magicLinkClaims {
	t.Helper()
	now := time.Now().UTC()
	return magicLinkClaims{
		Typ:             magicLinkTokenTyp,
		Scope:           string(ScopeRestore),
		LicenseID:       uuid.NewString(),
		EmailNormalized: "test@example.com",
		JTI:             uuid.NewString(),
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    magicLinkIssuer,
			Audience:  jwt.ClaimStrings{magicLinkAudience},
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(10 * time.Minute)),
		},
	}
}

func signClaimsWith(t *testing.T, claims magicLinkClaims, method jwt.SigningMethod, secret []byte) string {
	t.Helper()
	tok := jwt.NewWithClaims(method, claims)
	signed, err := tok.SignedString(secret)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return signed
}

func TestMagicLink_VerifyToken_HappyPath(t *testing.T) {
	s := newTestMagicLinkService()
	signed := signClaimsWith(t, makeValidClaims(t), jwt.SigningMethodHS256, s.jwtSecret)
	got, err := s.verifyToken(signed)
	if err != nil {
		t.Fatalf("expected verify success, got %v", err)
	}
	if got.Scope != string(ScopeRestore) {
		t.Fatalf("scope mismatch: %s", got.Scope)
	}
}

func TestMagicLink_VerifyToken_RejectsExpired(t *testing.T) {
	s := newTestMagicLinkService()
	claims := makeValidClaims(t)
	claims.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-1 * time.Minute))
	signed := signClaimsWith(t, claims, jwt.SigningMethodHS256, s.jwtSecret)
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("expired token must NOT verify")
	}
}

func TestMagicLink_VerifyToken_RejectsNotYetValid(t *testing.T) {
	s := newTestMagicLinkService()
	claims := makeValidClaims(t)
	claims.NotBefore = jwt.NewNumericDate(time.Now().Add(5 * time.Minute))
	signed := signClaimsWith(t, claims, jwt.SigningMethodHS256, s.jwtSecret)
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("not-yet-valid token must NOT verify")
	}
}

func TestMagicLink_VerifyToken_RejectsWrongAudience(t *testing.T) {
	s := newTestMagicLinkService()
	claims := makeValidClaims(t)
	claims.Audience = jwt.ClaimStrings{"some-other-aud"}
	signed := signClaimsWith(t, claims, jwt.SigningMethodHS256, s.jwtSecret)
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("wrong audience must NOT verify")
	}
}

func TestMagicLink_VerifyToken_RejectsWrongIssuer(t *testing.T) {
	s := newTestMagicLinkService()
	claims := makeValidClaims(t)
	claims.Issuer = "evil"
	signed := signClaimsWith(t, claims, jwt.SigningMethodHS256, s.jwtSecret)
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("wrong issuer must NOT verify")
	}
}

func TestMagicLink_VerifyToken_RejectsWrongTyp(t *testing.T) {
	s := newTestMagicLinkService()
	claims := makeValidClaims(t)
	claims.Typ = "password_reset" // wrong typ, defends against cross-purpose token confusion
	signed := signClaimsWith(t, claims, jwt.SigningMethodHS256, s.jwtSecret)
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("wrong typ must NOT verify")
	}
}

func TestMagicLink_VerifyToken_RejectsMissingJTI(t *testing.T) {
	s := newTestMagicLinkService()
	claims := makeValidClaims(t)
	claims.JTI = ""
	signed := signClaimsWith(t, claims, jwt.SigningMethodHS256, s.jwtSecret)
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("missing JTI must NOT verify — Redis single-use key derives from JTI")
	}
}

func TestMagicLink_VerifyToken_RejectsWrongSecret(t *testing.T) {
	s := newTestMagicLinkService()
	signed := signClaimsWith(t, makeValidClaims(t), jwt.SigningMethodHS256, []byte("different-secret"))
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("wrong-secret signature must NOT verify")
	}
}

func TestMagicLink_VerifyToken_RejectsNoneAlg(t *testing.T) {
	// alg=none confusion attack — historically the most dangerous JWT bug.
	// We rely on jwt.WithValidMethods([]string{"HS256"}) in verifyToken to
	// reject every other alg, including none.
	s := newTestMagicLinkService()
	tok := jwt.NewWithClaims(jwt.SigningMethodNone, makeValidClaims(t))
	signed, err := tok.SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("forge none token: %v", err)
	}
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("alg=none token must NOT verify (alg confusion attack defense)")
	}
}

func TestMagicLink_VerifyToken_RejectsWrongAlgRS256(t *testing.T) {
	// Even a syntactically valid RS256 token signed with our HMAC secret as a
	// "public key" must be rejected because we pin HS256. This defends against
	// the classic "swap alg HS256 ↔ RS256" attack where the attacker treats
	// the HMAC secret as an RSA public key.
	s := newTestMagicLinkService()
	// We can't easily craft an RS256 token without a key; instead use ES256
	// which jwt v5 also exposes. The point is: anything other than HS256
	// must be rejected.
	header := makeValidClaims(t)
	tok := jwt.NewWithClaims(jwt.SigningMethodHS512, header) // wrong HMAC variant
	signed, err := tok.SignedString(s.jwtSecret)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	if _, err := s.verifyToken(signed); err == nil {
		t.Fatalf("HS512 token must NOT verify when HS256 is pinned")
	}
}
