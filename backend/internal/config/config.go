package config

import (
	"os"
	"strconv"

	"github.com/joho/godotenv"
	"github.com/snakeloader/backend/internal/pkg/logger"
)

type Config struct {
	Server    ServerConfig
	Database  DatabaseConfig
	Redis     RedisConfig
	JWT       JWTConfig
	APIKey    APIKeyConfig
	Admin     AdminConfig
	RateLimit RateLimitConfig
	Gemini    GeminiConfig
	Stripe    StripeConfig
	BTCPay    BTCPayConfig
	Email     EmailConfig
	Telegram  TelegramConfig
	CI        CIConfig
	MagicLink MagicLinkConfig
}

// MagicLinkConfig holds the brand-aware redirect bases + TTL for the W1.2/W1.3
// magic-link flow. Issued tokens carry a single-use JWT; the website landing
// page reads the token from the URL fragment and POSTs it to /premium/redeem.
type MagicLinkConfig struct {
	BaseURLSSvid    string
	BaseURLVidCombo string
	TTLMinutes      int
}

type CIConfig struct {
	ReleaseSecret string
}

type TelegramConfig struct {
	BotToken    string
	AdminChatID string // Default chat ID for admin notifications
}

type EmailConfig struct {
	SMTPHost string
	SMTPPort int
	Username string
	Password string
	From     string
}

type StripeConfig struct {
	SecretKey      string
	WebhookSecret  string
	PriceMonthly  string
	PriceYearly   string
	PriceLifetime string
	// VidCombo brand-specific Stripe price IDs (same Stripe account, different products)
	VidComboPriceMonthly    string
	VidComboPriceSemiannual string
	VidComboPriceYearly     string
	SuccessURL         string
	CancelURL          string
	VidComboSuccessURL string
	VidComboCancelURL  string
}

// BrandFromPriceID maps a Stripe price ID back to its brand. Returns ("", false)
// for any price not owned by this backend (e.g. legacy VidCombo PHP-only prices,
// ssvid.net, or any other product on the shared Stripe account). Webhook handlers
// MUST use this to filter events — the same Stripe account serves multiple
// products and we only persist invoices for prices we configured here.
//
func (s *StripeConfig) BrandFromPriceID(priceID string) (string, bool) {
	if priceID == "" {
		return "", false
	}
	switch priceID {
	case s.PriceMonthly, s.PriceYearly, s.PriceLifetime:
		return "ssvid", true
	case s.VidComboPriceMonthly, s.VidComboPriceSemiannual, s.VidComboPriceYearly:
		return "vidcombo", true
	}
	return "", false
}

type BTCPayConfig struct {
	ServerURL string
	StoreID   string
	APIKey    string
}

type GeminiConfig struct {
	APIKey string
	Model  string
}

type ServerConfig struct {
	Port            string
	GinMode         string
	EnableSwagger   bool
	TrustedPlatform string
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

func (d DatabaseConfig) DSN() string {
	return "host=" + d.Host +
		" port=" + d.Port +
		" user=" + d.User +
		" password=" + d.Password +
		" dbname=" + d.DBName +
		" sslmode=" + d.SSLMode +
		" TimeZone=UTC"
}

// SafeDSN returns the DSN with password redacted, safe for logging.
func (d DatabaseConfig) SafeDSN() string {
	return "host=" + d.Host +
		" port=" + d.Port +
		" user=" + d.User +
		" password=**** dbname=" + d.DBName +
		" sslmode=" + d.SSLMode
}

type RedisConfig struct {
	URL string
}

type JWTConfig struct {
	Secret      string
	ExpiryHours int
}

type APIKeyConfig struct {
	ExpiryDays int
}

type AdminConfig struct {
	Email    string
	Password string
}

type RateLimitConfig struct {
	Requests      int
	WindowSeconds int
}

func Load() *Config {
	if err := godotenv.Load(); err != nil {
		logger.Log.Warn().Msg("No .env file found, using environment variables")
	}

	ginMode := getEnv("GIN_MODE", "debug")
	jwtSecret := getEnv("JWT_SECRET", "dev-secret-key")
	isProduction := ginMode == "release"

	// Swagger is opt-in via env regardless of Gin mode. Decoupled from GIN_MODE
	// so flipping Gin to release doesn't auto-disable docs in dev, and so a
	// production server accidentally running GIN_MODE=debug doesn't leak docs.
	enableSwagger := getEnvBool("ENABLE_SWAGGER", false)

	// Loud warning when production-like environment is detected but GIN_MODE is
	// debug — fatal checks below (JWT secret strength, DB SSL, ADMIN_PASSWORD,
	// STRIPE_WEBHOOK_SECRET) are gated on isProduction and silently skip,
	// leaving the service vulnerable. This is a tripwire, not a fatal, to avoid
	// crashing a misconfigured-but-running deployment.
	prodHint := os.Getenv("PORT") != "" || os.Getenv("DB_SSL_MODE") == "require" || os.Getenv("DB_SSL_MODE") == "verify-full"
	if !isProduction && prodHint {
		logger.Log.Warn().
			Str("gin_mode", ginMode).
			Bool("enable_swagger", enableSwagger).
			Msg("CRITICAL: production-like environment detected but GIN_MODE != release. Strict secret checks (JWT, DB SSL, admin password, Stripe webhook) are NOT enforced. Set GIN_MODE=release after verifying env secrets.")
	}

	// Enforce strong JWT secret in production
	if isProduction && (jwtSecret == "dev-secret-key" || len(jwtSecret) < 32) {
		logger.Log.Fatal().Msg("JWT_SECRET must be at least 32 characters in production mode")
	}

	// Enforce DB SSL in production
	dbSSLMode := getEnv("DB_SSL_MODE", "disable")
	if isProduction && dbSSLMode == "disable" {
		logger.Log.Fatal().Msg("DB_SSL_MODE must not be 'disable' in production mode (use 'require' or 'verify-full')")
	}

	// Enforce Gemini API key from env — no hardcoded fallback
	geminiKey := getEnv("GEMINI_API_KEY", "")
	if geminiKey == "" {
		logger.Log.Warn().Msg("GEMINI_API_KEY not set — AI chat will use keyword fallback")
	}

	// Warn if admin credentials use defaults
	adminEmail := getEnv("ADMIN_EMAIL", "admin@ssvid.app")
	adminPassword := getEnv("ADMIN_PASSWORD", "")
	if adminPassword == "" && isProduction {
		logger.Log.Fatal().Msg("ADMIN_PASSWORD must be set in production mode")
	}
	if adminPassword == "" {
		adminPassword = "admin123"
		logger.Log.Warn().Msg("Using default admin password — set ADMIN_PASSWORD env var for production")
	}

	// Warn if payment keys are not configured
	stripeKey := getEnv("STRIPE_SECRET_KEY", "")
	if stripeKey == "" {
		logger.Log.Warn().Msg("STRIPE_SECRET_KEY not set — Stripe payments disabled")
	}
	stripeWebhookSecret := getEnv("STRIPE_WEBHOOK_SECRET", "")
	if stripeKey != "" && stripeWebhookSecret == "" {
		if isProduction {
			logger.Log.Fatal().Msg("STRIPE_WEBHOOK_SECRET must be set when Stripe is configured in production — webhooks will reject all events without it")
		} else {
			logger.Log.Warn().Msg("STRIPE_WEBHOOK_SECRET not set — Stripe webhooks will reject all events")
		}
	}
	btcpayKey := getEnv("BTCPAY_API_KEY", "")
	if btcpayKey == "" {
		logger.Log.Warn().Msg("BTCPAY_API_KEY not set — crypto payments disabled")
	}

	// Warn if VidCombo brand Stripe price IDs are missing. VidCombo has its
	// own pricing (monthly/semiannual/yearly) that maps to different Stripe
	// products in the same account. Missing vars → pricing endpoint falls
	// back to SSvid prices for VidCombo devices, which is wrong.
	if stripeKey != "" {
		vcMissing := []string{}
		if getEnv("STRIPE_VIDCOMBO_PRICE_MONTHLY", "") == "" {
			vcMissing = append(vcMissing, "STRIPE_VIDCOMBO_PRICE_MONTHLY")
		}
		if getEnv("STRIPE_VIDCOMBO_PRICE_SEMIANNUAL", "") == "" {
			vcMissing = append(vcMissing, "STRIPE_VIDCOMBO_PRICE_SEMIANNUAL")
		}
		if getEnv("STRIPE_VIDCOMBO_PRICE_YEARLY", "") == "" {
			vcMissing = append(vcMissing, "STRIPE_VIDCOMBO_PRICE_YEARLY")
		}
		if len(vcMissing) > 0 {
			logger.Log.Warn().
				Strs("missing", vcMissing).
				Msg("VidCombo Stripe price IDs not set — VidCombo brand pricing will fall back to SSvid prices")
		}
	}

	return &Config{
		Server: ServerConfig{
			Port:            getEnv("PORT", "8080"),
			GinMode:         ginMode,
			EnableSwagger:   enableSwagger,
			TrustedPlatform: getEnv("TRUSTED_PLATFORM", ""),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     getEnv("DB_USER", "snakeloader"),
			Password: getEnv("DB_PASSWORD", "snakeloader_dev_2025"),
			DBName:   getEnv("DB_NAME", "snakeloader_dev"),
			SSLMode:  dbSSLMode,
		},
		Redis: RedisConfig{
			URL: getEnv("REDIS_URL", "redis://localhost:6379/0"),
		},
		JWT: JWTConfig{
			Secret:      jwtSecret,
			ExpiryHours: getEnvInt("JWT_EXPIRY_HOURS", 24),
		},
		APIKey: APIKeyConfig{
			ExpiryDays: getEnvInt("API_KEY_EXPIRY_DAYS", 365),
		},
		Admin: AdminConfig{
			Email:    adminEmail,
			Password: adminPassword,
		},
		RateLimit: RateLimitConfig{
			Requests:      getEnvInt("RATE_LIMIT_REQUESTS", 100),
			WindowSeconds: getEnvInt("RATE_LIMIT_WINDOW_SECONDS", 60),
		},
		Gemini: GeminiConfig{
			APIKey: geminiKey,
			Model:  getEnv("GEMINI_MODEL", "gemini-2.5-flash"),
		},
		Stripe: StripeConfig{
			SecretKey:      stripeKey,
			WebhookSecret:  stripeWebhookSecret,
			PriceMonthly:  getEnv("STRIPE_PRICE_MONTHLY", ""),
			PriceYearly:   getEnv("STRIPE_PRICE_YEARLY", ""),
			PriceLifetime: getEnv("STRIPE_PRICE_LIFETIME", ""),
			VidComboPriceMonthly:    getEnv("STRIPE_VIDCOMBO_PRICE_MONTHLY", ""),
			VidComboPriceSemiannual: getEnv("STRIPE_VIDCOMBO_PRICE_SEMIANNUAL", ""),
			VidComboPriceYearly:     getEnv("STRIPE_VIDCOMBO_PRICE_YEARLY", ""),
			SuccessURL:         getEnv("STRIPE_SUCCESS_URL", "https://ssvid.app/payment/success"),
			CancelURL:          getEnv("STRIPE_CANCEL_URL", "https://ssvid.app/payment/cancel"),
			VidComboSuccessURL: getEnv("STRIPE_VIDCOMBO_SUCCESS_URL", ""),
			VidComboCancelURL:  getEnv("STRIPE_VIDCOMBO_CANCEL_URL", ""),
		},
		BTCPay: BTCPayConfig{
			ServerURL: getEnv("BTCPAY_SERVER_URL", ""),
			StoreID:   getEnv("BTCPAY_STORE_ID", ""),
			APIKey:    btcpayKey,
		},
		Telegram: TelegramConfig{
			BotToken:    getEnv("TELEGRAM_BOT_TOKEN", ""),
			AdminChatID: getEnv("TELEGRAM_ADMIN_CHAT_ID", ""),
		},
		Email: EmailConfig{
			SMTPHost: getEnv("SMTP_HOST", ""),
			SMTPPort: getEnvInt("SMTP_PORT", 587),
			Username: getEnv("SMTP_USERNAME", ""),
			Password: getEnv("SMTP_PASSWORD", ""),
			From:     getEnv("SMTP_FROM", "noreply@ssvid.app"),
		},
		CI: CIConfig{
			ReleaseSecret: getEnv("CI_RELEASE_SECRET", ""),
		},
		MagicLink: MagicLinkConfig{
			BaseURLSSvid:    getEnv("MAGIC_LINK_BASE_SSVID", "https://ssvid.app/restore"),
			BaseURLVidCombo: getEnv("MAGIC_LINK_BASE_VIDCOMBO", "https://vidcombo.com/restore"),
			TTLMinutes:      getEnvInt("MAGIC_LINK_TTL_MIN", 10),
		},
	}
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if val := os.Getenv(key); val != "" {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return fallback
}

func getEnvBool(key string, fallback bool) bool {
	if val := os.Getenv(key); val != "" {
		switch val {
		case "1", "true", "TRUE", "True", "yes", "YES", "on", "ON":
			return true
		case "0", "false", "FALSE", "False", "no", "NO", "off", "OFF":
			return false
		}
	}
	return fallback
}
