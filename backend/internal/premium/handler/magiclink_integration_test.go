//go:build integration

package handler

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/snakeloader/backend/internal/premium/service"
)

// licenseKeyForTest constructs a 44-char standard SVID key by hashing the
// supplied seed into eight 4-hex groups. Tests get unique-but-deterministic
// keys without bumping into the varchar(50) column ceiling.
func licenseKeyForTest(seed string) string {
	h := sha256.Sum256([]byte(seed))
	hexStr := hex.EncodeToString(h[:])
	groups := []string{
		hexStr[0:4], hexStr[4:8], hexStr[8:12], hexStr[12:16],
		hexStr[16:20], hexStr[20:24], hexStr[24:28], hexStr[28:32],
	}
	return "SVID-" + strings.Join(groups, "-")
}

func seedLicenseWithEmail(t *testing.T, email string) model.PremiumLicense {
	t.Helper()
	deviceID := uuid.New()
	if err := testDB.Exec(
		`INSERT INTO devices (id, hardware_id, brand, os, is_active, created_at, last_seen_at)
		 VALUES (?, ?, 'svid', 'macos', true, NOW(), NOW())`,
		deviceID, "test-hw-ml-"+deviceID.String(),
	).Error; err != nil {
		t.Fatalf("seed device: %v", err)
	}
	emailCopy := email
	license := model.PremiumLicense{
		ID:            uuid.New(),
		DeviceID:      deviceID,
		Brand:         "svid",
		// 44-char standard SVID key: "SVID" + 8 × "-XXXX". The suffix is
		// deterministic per UUID so seeds collide intentionally never.
		LicenseKey: licenseKeyForTest(uuid.NewString()),
		Tier:          "premium",
		BillingCycle:  "yearly",
		PaymentMethod: "stripe",
		IsAutoRenew:   true,
		ExpiresAt:     time.Now().Add(180 * 24 * time.Hour).UTC().Truncate(time.Second),
		ContactEmail:  &emailCopy,
	}
	if err := testDB.Create(&license).Error; err != nil {
		t.Fatalf("seed license: %v", err)
	}
	return license
}

func extractTokenFromLink(t *testing.T, link string) string {
	t.Helper()
	hashIdx := strings.Index(link, "#token=")
	if hashIdx < 0 {
		t.Fatalf("no token in link: %s", link)
	}
	frag := link[hashIdx+len("#token="):]
	parts := strings.SplitN(frag, "&", 2)
	tok, err := url.QueryUnescape(parts[0])
	if err != nil {
		t.Fatalf("unescape token: %v", err)
	}
	return tok
}

func resetMagicLinkState(t *testing.T) {
	t.Helper()
	resetDB(t)
	testRedis.FlushAll()
	testEmailSender.reset()
}

// TestMagicLink_IssueAndRedeem_HappyPath covers the W1.2 baseline: a request
// to web-restore-email for a known email produces an email containing a
// signed token, which then redeems successfully to a license key. The same
// token cannot be redeemed twice.
func TestMagicLink_IssueAndRedeem_HappyPath(t *testing.T) {
	resetMagicLinkState(t)
	license := seedLicenseWithEmail(t, "ml-happy@example.com")

	issueBody, _ := json.Marshal(map[string]string{"email": "ml-happy@example.com"})
	w := callHandler(t, testPremiumHandler.WebRestoreMagicLink, issueBody)
	if w.Code != http.StatusOK {
		t.Fatalf("issue: code=%d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "\"sent\":true") {
		t.Fatalf("issue body missing sent:true: %s", w.Body.String())
	}

	// Email send is async; poll briefly. Sub-100ms in practice.
	var calls []emailCall
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		calls = testEmailSender.snapshot()
		if len(calls) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if len(calls) != 1 {
		t.Fatalf("expected 1 email send, got %d", len(calls))
	}
	if calls[0].Template != "magic_link" || calls[0].To != "ml-happy@example.com" {
		t.Fatalf("wrong email send: %+v", calls[0])
	}

	token := extractTokenFromLink(t, calls[0].Data["Link"])

	redeemBody, _ := json.Marshal(map[string]string{"token": token, "scope": "restore"})
	w = callHandler(t, testPremiumHandler.RedeemMagicLink, redeemBody)
	if w.Code != http.StatusOK {
		t.Fatalf("redeem: code=%d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), license.LicenseKey) {
		t.Fatalf("redeem response missing license key: %s", w.Body.String())
	}

	// Replay: same token → 410 Gone.
	w = callHandler(t, testPremiumHandler.RedeemMagicLink, redeemBody)
	if w.Code != http.StatusGone {
		t.Fatalf("replay should be 410, got %d body=%s", w.Code, w.Body.String())
	}
}

// TestMagicLink_IssueForUnknownEmail_StillSendsTrue verifies enumeration
// resistance: a request for an email that has NO license returns the same
// {"sent": true} body, and no email is sent.
func TestMagicLink_IssueForUnknownEmail_StillSendsTrue(t *testing.T) {
	resetMagicLinkState(t)
	body, _ := json.Marshal(map[string]string{"email": "no-such-license@example.com"})
	w := callHandler(t, testPremiumHandler.WebRestoreMagicLink, body)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "\"sent\":true") {
		t.Fatalf("expected sent:true, got %s", w.Body.String())
	}
	// Give the goroutine a moment in case a buggy implementation tried to
	// send anyway.
	time.Sleep(50 * time.Millisecond)
	if calls := testEmailSender.snapshot(); len(calls) != 0 {
		t.Fatalf("unknown email leaked an SMTP send: %+v", calls)
	}
}

// TestMagicLink_Redeem_WrongScope_Rejected verifies that a token signed for
// "restore" cannot be redeemed as "portal" and vice versa.
func TestMagicLink_Redeem_WrongScope_Rejected(t *testing.T) {
	resetMagicLinkState(t)
	seedLicenseWithEmail(t, "ml-scope@example.com")

	issueBody, _ := json.Marshal(map[string]string{"email": "ml-scope@example.com"})
	if w := callHandler(t, testPremiumHandler.WebRestoreMagicLink, issueBody); w.Code != http.StatusOK {
		t.Fatalf("issue: %d %s", w.Code, w.Body.String())
	}
	// Wait for email.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(testEmailSender.snapshot()) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	calls := testEmailSender.snapshot()
	if len(calls) != 1 {
		t.Fatalf("expected 1 email, got %d", len(calls))
	}
	token := extractTokenFromLink(t, calls[0].Data["Link"])

	redeemWrongScope, _ := json.Marshal(map[string]string{"token": token, "scope": "portal"})
	w := callHandler(t, testPremiumHandler.RedeemMagicLink, redeemWrongScope)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("scope-confused redeem should be 401, got %d body=%s", w.Code, w.Body.String())
	}
}

// TestMagicLink_Redeem_ConcurrentDeliveries_ExactlyOneWins fires two
// concurrent redeem requests for the same token. The Redis SETNX must ensure
// exactly one wins; the other gets 410.
func TestMagicLink_Redeem_ConcurrentDeliveries_ExactlyOneWins(t *testing.T) {
	resetMagicLinkState(t)
	license := seedLicenseWithEmail(t, "ml-concurrent@example.com")
	_ = license

	issueBody, _ := json.Marshal(map[string]string{"email": "ml-concurrent@example.com"})
	if w := callHandler(t, testPremiumHandler.WebRestoreMagicLink, issueBody); w.Code != http.StatusOK {
		t.Fatalf("issue: %d", w.Code)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(testEmailSender.snapshot()) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	token := extractTokenFromLink(t, testEmailSender.snapshot()[0].Data["Link"])
	redeemBody, _ := json.Marshal(map[string]string{"token": token, "scope": "restore"})

	const N = 4
	var (
		wg       sync.WaitGroup
		successes int32
		gones    int32
	)
	wg.Add(N)
	for i := 0; i < N; i++ {
		go func() {
			defer wg.Done()
			w := callHandler(t, testPremiumHandler.RedeemMagicLink, redeemBody)
			switch w.Code {
			case http.StatusOK:
				atomic.AddInt32(&successes, 1)
			case http.StatusGone:
				atomic.AddInt32(&gones, 1)
			}
		}()
	}
	wg.Wait()

	if successes != 1 {
		t.Fatalf("exactly one redeem must succeed; got successes=%d gones=%d", successes, gones)
	}
	if gones != N-1 {
		t.Fatalf("expected N-1 410 responses, got successes=%d gones=%d", successes, gones)
	}
}

// TestMagicLink_Redeem_RedisDown_FailsClosed verifies the redeem path returns
// a 503 (or other non-200) when Redis is unavailable — single-use enforcement
// cannot be bypassed by killing Redis.
func TestMagicLink_Redeem_RedisDown_FailsClosed(t *testing.T) {
	resetMagicLinkState(t)
	seedLicenseWithEmail(t, "ml-rd@example.com")

	issueBody, _ := json.Marshal(map[string]string{"email": "ml-rd@example.com"})
	if w := callHandler(t, testPremiumHandler.WebRestoreMagicLink, issueBody); w.Code != http.StatusOK {
		t.Fatalf("issue: %d", w.Code)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if len(testEmailSender.snapshot()) > 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	token := extractTokenFromLink(t, testEmailSender.snapshot()[0].Data["Link"])

	// Simulate Redis outage.
	testRedis.Close()
	t.Cleanup(func() {
		// Restart miniredis for subsequent tests by re-running it on the same
		// addr is non-trivial; instead, give it a fresh instance + client.
		fresh, err := miniredisRestart(t)
		if err != nil {
			t.Logf("warn: miniredis restart failed (subsequent tests may fail): %v", err)
			return
		}
		testRedis = fresh
	})

	redeemBody, _ := json.Marshal(map[string]string{"token": token, "scope": "restore"})
	w := callHandler(t, testPremiumHandler.RedeemMagicLink, redeemBody)
	if w.Code == http.StatusOK {
		t.Fatalf("redis-down redeem must NOT return 200 (would bypass single-use). Got 200 body=%s", w.Body.String())
	}
}

// TestMagicLink_RestoreAuthRoute_BodyDeviceID_Ignored verifies the W1.2 auth
// fix: the authenticated /premium/restore route reads device_id from the
// auth-context middleware, not from the body. A request with an empty body
// device_id and an authenticated device that DOES own the license still
// succeeds.
func TestMagicLink_RestoreAuthRoute_BodyDeviceID_Ignored(t *testing.T) {
	resetDB(t)

	// Seed device + license_device row so the device is "on" the license.
	license := seedLicenseWithEmail(t, "ml-authrestore@example.com")
	if err := testDB.Exec(
		`INSERT INTO license_devices (id, license_id, device_id, registered_at, last_verified_at)
		 VALUES (?, ?, ?, NOW(), NOW())`,
		uuid.New(), license.ID, license.DeviceID,
	).Error; err != nil {
		t.Fatalf("seed license_devices: %v", err)
	}

	// Build a fake authenticated context with the device_id set.
	body, _ := json.Marshal(map[string]string{
		"email":     "ml-authrestore@example.com",
		"device_id": "", // body field should be IGNORED in favor of context
	})
	w := callWithAuth(t, testPremiumHandler.RestoreLicense, body, license.DeviceID)
	if w.Code != http.StatusOK {
		t.Fatalf("authenticated restore should succeed, got %d body=%s", w.Code, w.Body.String())
	}

	// Missing auth context → 401, NOT 404 (would expose existence indirectly).
	w = callHandler(t, testPremiumHandler.RestoreLicense, body)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated restore should be 401, got %d body=%s", w.Code, w.Body.String())
	}
}

// miniredisRestart spins up a fresh miniredis after a test killed the previous
// one. Returns the new instance; callers update testRedis + testRedisClient.
func miniredisRestart(t *testing.T) (*miniredis.Miniredis, error) {
	t.Helper()
	mini, err := miniredis.Run()
	if err != nil {
		return nil, err
	}
	testRedisClient = redis.NewClient(&redis.Options{Addr: mini.Addr()})
	testMagicLinkSvc = service.NewMagicLinkService(
		repository.NewLicenseRepository(testDB),
		testEmailSender,
		testRedisClient,
		testCfg.MagicLink,
		testCfg.JWT.Secret,
	)
	testPremiumHandler.SetMagicLinkService(testMagicLinkSvc)
	return mini, nil
}

// callWithAuth fires a request through the handler with DeviceIDKey
// pre-populated in the gin context — equivalent to passing through
// RequireAPIKey middleware in production.
func callWithAuth(t *testing.T, h gin.HandlerFunc, body []byte, deviceID uuid.UUID) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	c.Set(middleware.DeviceIDKey, deviceID)
	h(c)
	return w
}
