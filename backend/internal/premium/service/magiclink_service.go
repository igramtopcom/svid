package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/repository"
)

// MagicLinkScope distinguishes restore vs portal redemption. Scope is checked
// against the signed claim at redeem time so a portal token can never be used
// to fetch a license key, and vice versa.
type MagicLinkScope string

const (
	ScopeRestore MagicLinkScope = "restore"
	ScopePortal  MagicLinkScope = "portal"

	magicLinkIssuer   = "ssvid-backend"
	magicLinkAudience = "ssvid-magic-link"
	magicLinkTokenTyp = "magic_link"

	// rateLimitWindow + rateLimitPerEmail bound how many issuance attempts
	// any single (normalized) email can drive in one window. Prevents the
	// "spray one email from many IPs" attack the per-IP middleware cannot
	// catch on its own.
	emailRateLimitWindow = time.Hour
	emailRateLimitMax    = 5
)

var (
	// ErrMagicLinkNotConfigured surfaces when Redis is unavailable at redeem
	// time. Redemption requires Redis SETNX for single-use enforcement; we
	// fail-closed rather than allow a token to be redeemed multiple times.
	ErrMagicLinkNotConfigured = errors.New("magic link service not configured")

	// ErrMagicLinkInvalid is the generic "this token is no good" sentinel.
	// All token-validation failure modes (bad signature, wrong alg, wrong
	// audience, wrong typ, malformed claims, expired, not-yet-valid) collapse
	// to this single error so the client can't probe for which constraint
	// failed via differential error messages.
	ErrMagicLinkInvalid = errors.New("magic link token invalid")

	// ErrMagicLinkAlreadyRedeemed signals SETNX returned 0 (token consumed).
	ErrMagicLinkAlreadyRedeemed = errors.New("magic link token already redeemed")

	// ErrMagicLinkRateLimited tracks the per-email issuance ceiling. Returned
	// to callers from Issue*; the public handler surfaces the same generic
	// {"sent": true} response to preserve enumeration resistance.
	ErrMagicLinkRateLimited = errors.New("magic link issuance rate limited")
)

// EmailSender is the narrow interface MagicLinkService uses to send messages.
// Production wires *email.Service from internal/pkg/email which already
// matches this shape. Tests inject a mock so they don't depend on SMTP or
// timing-sensitive goroutine sleeps.
type EmailSender interface {
	Send(to, subject, templateName string, data map[string]string) error
}

// MagicLinkService owns the W1.2/W1.3 issuance + redemption logic. Holds the
// long-lived dependencies (license repo, Redis, email sender, JWT secret,
// brand-aware base URLs) so handlers stay thin.
type MagicLinkService struct {
	licenseRepo *repository.LicenseRepository
	email       EmailSender
	rdb         *redis.Client
	cfg         config.MagicLinkConfig
	jwtSecret   []byte
}

func NewMagicLinkService(
	licenseRepo *repository.LicenseRepository,
	email EmailSender,
	rdb *redis.Client,
	cfg config.MagicLinkConfig,
	jwtSecret string,
) *MagicLinkService {
	if cfg.TTLMinutes <= 0 {
		cfg.TTLMinutes = 10
	}
	return &MagicLinkService{
		licenseRepo: licenseRepo,
		email:       email,
		rdb:         rdb,
		cfg:         cfg,
		jwtSecret:   []byte(jwtSecret),
	}
}

// magicLinkClaims is the exact shape of the JWS payload we sign + verify. Keep
// it locked to a struct (not jwt.MapClaims) so missing fields are caught at
// parse time rather than silently treated as empty strings.
type magicLinkClaims struct {
	Typ            string `json:"typ"`
	Scope          string `json:"scope"`
	LicenseID      string `json:"license_id"`
	EmailNormalized string `json:"email"`
	JTI            string `json:"jti"`
	jwt.RegisteredClaims
}

// IssueForRestore looks up the license by normalized email and, if found,
// builds a magic-link URL and ships it to the user's email via the configured
// EmailSender. Callers should always treat the return value as opaque — the
// public handlers respond {"sent": true} regardless of whether an email
// matched so attackers can't enumerate the customer base.
//
// Real DB / Redis errors propagate so the caller can decide whether to alert.
// Rate-limit hits return ErrMagicLinkRateLimited (handler still responds
// {"sent": true}).
func (s *MagicLinkService) IssueForRestore(ctx context.Context, email string) error {
	return s.issue(ctx, ScopeRestore, email, false)
}

// IssueForPortal mirrors IssueForRestore but looks up licenses that have a
// Stripe customer ID attached. An email that holds both an older Stripe
// license and a newer manual/crypto one still gets a working portal link.
func (s *MagicLinkService) IssueForPortal(ctx context.Context, email string) error {
	return s.issue(ctx, ScopePortal, email, true)
}

func (s *MagicLinkService) issue(ctx context.Context, scope MagicLinkScope, email string, requireStripe bool) error {
	normalized := NormalizeEmail(email)
	if normalized == "" {
		return ErrMagicLinkInvalid
	}

	if err := s.checkEmailRateLimit(ctx, normalized); err != nil {
		return err
	}

	if requireStripe {
		lic, err := s.licenseRepo.FindActiveStripeByEmail(normalized)
		if err != nil {
			return err
		}
		return s.signAndSend(scope, lic.ID, normalized, lic.Brand)
	}
	lic, err := s.licenseRepo.FindActiveByEmail(normalized, "")
	if err != nil {
		return err
	}
	return s.signAndSend(scope, lic.ID, normalized, lic.Brand)
}

func (s *MagicLinkService) signAndSend(scope MagicLinkScope, licenseID uuid.UUID, normalizedEmail, brand string) error {
	ttl := time.Duration(s.cfg.TTLMinutes) * time.Minute
	now := time.Now().UTC()
	claims := magicLinkClaims{
		Typ:             magicLinkTokenTyp,
		Scope:           string(scope),
		LicenseID:       licenseID.String(),
		EmailNormalized: normalizedEmail,
		JTI:             uuid.NewString(),
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    magicLinkIssuer,
			Audience:  jwt.ClaimStrings{magicLinkAudience},
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := tok.SignedString(s.jwtSecret)
	if err != nil {
		return fmt.Errorf("sign magic link: %w", err)
	}

	base := s.cfg.BaseURLSSvid
	if brand == "vidcombo" {
		base = s.cfg.BaseURLVidCombo
	}
	// Token lives in the URL fragment so it never lands in HTTP server logs,
	// referrer headers, or browser address-bar history shared with the
	// website's analytics. The website landing page reads it via
	// window.location.hash and POSTs to /premium/redeem.
	link := fmt.Sprintf("%s#token=%s&scope=%s", base, url.QueryEscape(signed), scope)

	// Send is intentionally synchronous from the caller's POV here. The
	// HANDLER wraps the call in a goroutine so the HTTP request returns
	// in constant time regardless of SMTP latency — that's what defuses
	// the timing-based enumeration leak.
	if s.email == nil {
		logger.Log.Warn().Str("scope", string(scope)).Str("email", normalizedEmail).
			Msg("Magic link not sent — EmailSender not wired (dev/test?)")
		return nil
	}
	subject := "Your SSvid login link"
	if brand == "vidcombo" {
		subject = "Your VidCombo login link"
	}
	if err := s.email.Send(normalizedEmail, subject, "magic_link", map[string]string{
		"Link":  link,
		"Scope": string(scope),
		"Brand": brand,
	}); err != nil {
		return fmt.Errorf("send magic link email: %w", err)
	}
	return nil
}

// RedemptionResult is what the handler hands back to the website after a
// successful redeem. Only one of LicenseKey / PortalURL is populated based on
// the token scope.
type RedemptionResult struct {
	Scope        MagicLinkScope
	LicenseKey   string
	BillingCycle string
	ExpiresAt    string
	PortalURL    string
}

// Redeem verifies a magic-link token and, on success, marks it consumed in
// Redis (SETNX with TTL). Single-use is enforced atomically — concurrent
// redemptions of the same token result in exactly one success.
//
// portalFactory is injected so the magic-link service doesn't import the
// Stripe service directly (avoids a circular package dependency). The handler
// supplies a closure that calls StripeService.CreatePortalSessionForLicense.
func (s *MagicLinkService) Redeem(
	ctx context.Context,
	tokenString string,
	expectedScope MagicLinkScope,
	portalFactory func(license uuid.UUID) (string, error),
) (*RedemptionResult, error) {
	if s.rdb == nil {
		return nil, ErrMagicLinkNotConfigured
	}
	claims, err := s.verifyToken(tokenString)
	if err != nil {
		return nil, ErrMagicLinkInvalid
	}
	if MagicLinkScope(claims.Scope) != expectedScope {
		return nil, ErrMagicLinkInvalid
	}

	licID, err := uuid.Parse(claims.LicenseID)
	if err != nil {
		return nil, ErrMagicLinkInvalid
	}

	// Atomic single-use via SETNX. The key is sha256(jti) so the raw token
	// never appears in Redis — limits blast radius if Redis dumps leak.
	jtiHash := sha256.Sum256([]byte(claims.JTI))
	redisKey := "magic_link:redeemed:" + hex.EncodeToString(jtiHash[:])
	ttl := time.Duration(s.cfg.TTLMinutes) * time.Minute
	ok, err := s.rdb.SetNX(ctx, redisKey, "1", ttl).Result()
	if err != nil {
		return nil, fmt.Errorf("redis setnx: %w", err)
	}
	if !ok {
		return nil, ErrMagicLinkAlreadyRedeemed
	}

	// Re-verify the license is still active + scope/email match the claim.
	// A token signed 9 minutes ago against a license that has since been
	// revoked, cancelled, or expired MUST NOT redeem — the active-window
	// check matches what VerifyLicense uses for runtime access decisions.
	lic, err := s.licenseRepo.FindByID(licID)
	if err != nil {
		return nil, ErrMagicLinkInvalid
	}
	if lic.Tier != "premium" {
		return nil, ErrMagicLinkInvalid
	}
	if lic.CancelledAt != nil {
		return nil, ErrMagicLinkInvalid
	}
	// Lifetime plans never expire; everything else gets the time check.
	if !IsLifetimePlan(lic.BillingCycle) && time.Now().After(lic.ExpiresAt) {
		return nil, ErrMagicLinkInvalid
	}
	if lic.ContactEmail == nil || NormalizeEmail(*lic.ContactEmail) != claims.EmailNormalized {
		return nil, ErrMagicLinkInvalid
	}

	switch expectedScope {
	case ScopeRestore:
		return &RedemptionResult{
			Scope:        ScopeRestore,
			LicenseKey:   lic.LicenseKey,
			BillingCycle: lic.BillingCycle,
			ExpiresAt:    lic.ExpiresAt.UTC().Format(time.RFC3339),
		}, nil
	case ScopePortal:
		if portalFactory == nil {
			return nil, ErrMagicLinkInvalid
		}
		portalURL, err := portalFactory(lic.ID)
		if err != nil {
			return nil, err
		}
		return &RedemptionResult{Scope: ScopePortal, PortalURL: portalURL}, nil
	default:
		return nil, ErrMagicLinkInvalid
	}
}

func (s *MagicLinkService) verifyToken(tokenString string) (*magicLinkClaims, error) {
	claims := &magicLinkClaims{}
	tok, err := jwt.ParseWithClaims(tokenString, claims, func(t *jwt.Token) (interface{}, error) {
		// Pin alg to HS256 to defuse alg=none / RS256 confusion attacks.
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.jwtSecret, nil
	}, jwt.WithValidMethods([]string{"HS256"}))
	if err != nil || !tok.Valid {
		return nil, fmt.Errorf("parse/validate: %w", err)
	}
	if claims.Typ != magicLinkTokenTyp {
		return nil, errors.New("unexpected typ")
	}
	if claims.Issuer != magicLinkIssuer {
		return nil, errors.New("unexpected iss")
	}
	found := false
	for _, aud := range claims.Audience {
		if aud == magicLinkAudience {
			found = true
			break
		}
	}
	if !found {
		return nil, errors.New("unexpected aud")
	}
	if claims.JTI == "" {
		return nil, errors.New("missing jti")
	}
	return claims, nil
}

// checkEmailRateLimit enforces emailRateLimitMax issuance requests per
// emailRateLimitWindow per normalized email. Sha256 is used so the raw
// address never lands as a Redis key.
func (s *MagicLinkService) checkEmailRateLimit(ctx context.Context, normalizedEmail string) error {
	if s.rdb == nil {
		// No Redis → fail closed for issuance too. The handler will surface
		// the generic {"sent": true} regardless, but the email is not sent.
		return ErrMagicLinkNotConfigured
	}
	hash := sha256.Sum256([]byte(normalizedEmail))
	key := "magic_link:email_rl:" + hex.EncodeToString(hash[:])
	n, err := s.rdb.Incr(ctx, key).Result()
	if err != nil {
		return fmt.Errorf("redis incr: %w", err)
	}
	if n == 1 {
		// First hit in window — set TTL. Use SetArgs with XX so we don't
		// stomp an existing TTL if there's an Incr/Expire race.
		if err := s.rdb.Expire(ctx, key, emailRateLimitWindow).Err(); err != nil {
			return fmt.Errorf("redis expire: %w", err)
		}
	}
	if n > emailRateLimitMax {
		return ErrMagicLinkRateLimited
	}
	return nil
}
