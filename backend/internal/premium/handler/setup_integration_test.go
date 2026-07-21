//go:build integration

package handler

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/database"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/snakeloader/backend/internal/premium/service"
	"gorm.io/gorm"
)

// recordingEmailSender captures every Send call so tests can assert what
// recipient/template/data the magic-link service handed to SMTP without
// actually sending mail. Safe for concurrent use; the magic-link handler
// fires sends from a goroutine.
type recordingEmailSender struct {
	mu    sync.Mutex
	calls []emailCall
}

type emailCall struct {
	To       string
	Subject  string
	Template string
	Data     map[string]string
}

func (r *recordingEmailSender) Send(to, subject, templateName string, data map[string]string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	cp := make(map[string]string, len(data))
	for k, v := range data {
		cp[k] = v
	}
	r.calls = append(r.calls, emailCall{To: to, Subject: subject, Template: templateName, Data: cp})
	return nil
}

func (r *recordingEmailSender) snapshot() []emailCall {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]emailCall, len(r.calls))
	copy(out, r.calls)
	return out
}

func (r *recordingEmailSender) reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = nil
}

// Package-level fixtures populated once by TestMain. Tests must call
// resetDB(t) at the start of each test that mutates state.
var (
	testDB             *gorm.DB
	testCfg            *config.Config
	testWebhookHandler *WebhookHandler
	testPremiumService *service.PremiumService
	testPremiumHandler *PremiumHandler
	testMagicLinkSvc   *service.MagicLinkService
	testRedis          *miniredis.Miniredis
	testRedisClient    *redis.Client
	testEmailSender    *recordingEmailSender
)

const testWebhookSecret = "whsec_test_secret_do_not_use_in_prod"

// TestMain spins up the schema once, then delegates to m.Run.
// Tests are gated by `//go:build integration` so the default `go test ./...`
// (no Postgres) keeps working. Run with `make test-webhook`.
func TestMain(m *testing.M) {
	logger.Init("warn")

	cfg := loadTestConfig()
	testCfg = cfg

	db, err := database.NewPostgresDB(cfg.Database, cfg.Server.GinMode)
	if err != nil {
		fmt.Fprintf(os.Stderr, "TestMain: connect Postgres: %v\n", err)
		os.Exit(1)
	}
	testDB = db

	// Run migrations once. AutoMigrate is idempotent — run it twice to verify
	// no migration introduces a non-idempotent step that would silently break
	// in production deploys.
	if err := database.RunMigrations(db); err != nil {
		fmt.Fprintf(os.Stderr, "TestMain: first AutoMigrate: %v\n", err)
		os.Exit(1)
	}
	if err := database.RunMigrations(db); err != nil {
		fmt.Fprintf(os.Stderr, "TestMain: second AutoMigrate (idempotency check): %v\n", err)
		os.Exit(1)
	}

	// Build a webhook handler wired with the test DB. Stripe/Crypto services
	// are instantiated against the test config — they'll be no-ops for tests
	// that exercise webhook handlers without calling out to real Stripe.
	licenseRepo := repository.NewLicenseRepository(db)
	txnRepo := repository.NewTransactionRepository(db)
	invoiceRepo := repository.NewInvoiceRepository(db)
	webhookRepo := repository.NewWebhookEventRepository(db)

	stripeSvc := service.NewStripeService(&cfg.Stripe, db, licenseRepo, txnRepo, cfg.JWT.Secret)
	cryptoSvc := service.NewCryptoService(&cfg.BTCPay, licenseRepo, txnRepo, cfg.JWT.Secret)
	premiumSvc := service.NewPremiumService(licenseRepo, txnRepo, cfg.JWT.Secret, stripeSvc, cryptoSvc)
	premiumSvc.SetInvoiceRepo(invoiceRepo)
	stripeSvc.SetPremiumService(premiumSvc)
	cryptoSvc.SetPremiumService(premiumSvc)

	cfg.Stripe.WebhookSecret = testWebhookSecret
	testWebhookHandler = NewWebhookHandler(&cfg.Stripe, premiumSvc, webhookRepo, db)
	testPremiumService = premiumSvc

	// W1.2/W1.3 magic-link integration test wiring: in-process Redis +
	// recording email sender. Tests can reach in via testRedis to simulate
	// outages and via testEmailSender to inspect sent links.
	mini, err := miniredis.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "TestMain: start miniredis: %v\n", err)
		os.Exit(1)
	}
	testRedis = mini
	testRedisClient = redis.NewClient(&redis.Options{Addr: mini.Addr()})
	testEmailSender = &recordingEmailSender{}
	cfg.MagicLink = config.MagicLinkConfig{
		BaseURLSSvid:    "https://ssvid.app/restore",
		BaseURLVidCombo: "https://vidcombo.com/restore",
		TTLMinutes:      10,
	}
	testMagicLinkSvc = service.NewMagicLinkService(licenseRepo, testEmailSender, testRedisClient, cfg.MagicLink, cfg.JWT.Secret)
	testPremiumHandler = NewPremiumHandler(premiumSvc, false)
	testPremiumHandler.SetMagicLinkService(testMagicLinkSvc)

	gin.SetMode(gin.TestMode)

	os.Exit(m.Run())
}

// loadTestConfig builds a config from DB_* env vars set by the make target /
// CI services block. Falls back to compose-test defaults for local dev.
func loadTestConfig() *config.Config {
	get := func(env, def string) string {
		if v := os.Getenv(env); v != "" {
			return v
		}
		return def
	}
	cfg := &config.Config{
		Server: config.ServerConfig{GinMode: "test"},
		Database: config.DatabaseConfig{
			Host:     get("DB_HOST", "localhost"),
			Port:     get("DB_PORT", "5433"),
			User:     get("DB_USER", "snakeloader"),
			Password: get("DB_PASSWORD", "test"),
			DBName:   get("DB_NAME", "snakeloader_test"),
			SSLMode:  get("DB_SSL_MODE", "disable"),
		},
		JWT: config.JWTConfig{
			Secret:      "test_jwt_secret_for_integration_tests_only",
			ExpiryHours: 24,
		},
		// Stub price IDs matching the test fixtures. Required so the
		// handler's BrandFromPriceID whitelist treats fixture invoices as
		// "ours" rather than filtering them out as foreign products.
		Stripe: config.StripeConfig{
			PriceMonthly:  "price_test_monthly_ssvid",
			PriceYearly:   "price_test_yearly_ssvid",
			PriceLifetime: "price_test_lifetime_ssvid",
			VidComboPriceMonthly:    "price_test_monthly_vidcombo",
			VidComboPriceSemiannual: "price_test_semiannual_vidcombo",
			VidComboPriceYearly:     "price_test_yearly_vidcombo",
		},
	}
	// BTCPay deliberately left zero-value — crypto service uses IsConfigured()
	// guards which short-circuit when secrets are absent.
	return cfg
}

// resetDB truncates every table touched by the payment subsystem. CASCADE
// handles FK references (license_devices -> premium_licenses, etc.).
// RESTART IDENTITY is a no-op for UUID PKs but harmless. Single statement is
// atomic, so ordering is irrelevant.
func resetDB(t *testing.T) {
	t.Helper()
	stmt := `TRUNCATE TABLE
		license_devices,
		invoices,
		payment_transactions,
		premium_licenses,
		webhook_events,
		devices
		RESTART IDENTITY CASCADE`
	if err := testDB.Exec(stmt).Error; err != nil {
		t.Fatalf("resetDB: %v", err)
	}
}

// signStripeRequest produces a valid Stripe-Signature header for the given
// payload signed by `secret`. Generated on the fly so each fixture run uses
// a current timestamp (avoids the 5-minute replay-window rejection).
func signStripeRequest(payload []byte, secret string) http.Header {
	ts := strconv.FormatInt(time.Now().Unix(), 10)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(ts + "." + string(payload)))
	sig := hex.EncodeToString(mac.Sum(nil))
	h := http.Header{}
	h.Set("Stripe-Signature", "t="+ts+",v1="+sig)
	h.Set("Content-Type", "application/json")
	return h
}

// postWebhook fires a request through the real Gin handler. Returns the
// recorded response for assertions. Uses the package-level testWebhookHandler.
func postWebhook(t *testing.T, body []byte, sig http.Header) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/stripe", bytes.NewReader(body))
	for k, vs := range sig {
		for _, v := range vs {
			req.Header.Add(k, v)
		}
	}
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	testWebhookHandler.StripeWebhook(c)
	return w
}

// callHandler fires a POST through the supplied PremiumHandler method without
// going through the full Gin router (so we don't need to wire all the routes
// + auth middleware just to test one handler). Returns the recorded response.
func callHandler(t *testing.T, h gin.HandlerFunc, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	c, _ := gin.CreateTestContext(w)
	c.Request = req
	h(c)
	return w
}

// loadFixture reads testdata/stripe/<name> and returns its bytes.
func loadFixture(t *testing.T, name string) []byte {
	t.Helper()
	path := filepath.Join("testdata", "stripe", name)
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("loadFixture %s: %v", name, err)
	}
	return b
}

// reseedEventID rewrites the top-level `id` field of a Stripe event payload
// to a fresh value. Useful when a test wants to fire the same fixture twice
// without hitting the idempotency dedup. Returns the new payload.
func reseedEventID(t *testing.T, payload []byte, newID string) []byte {
	t.Helper()
	var obj map[string]interface{}
	if err := json.Unmarshal(payload, &obj); err != nil {
		t.Fatalf("reseedEventID unmarshal: %v", err)
	}
	obj["id"] = newID
	out, err := json.Marshal(obj)
	if err != nil {
		t.Fatalf("reseedEventID marshal: %v", err)
	}
	return out
}
