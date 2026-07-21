package server

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
	playvalidator "github.com/go-playground/validator/v10"
	"github.com/snakeloader/backend/internal/middleware"
	"github.com/snakeloader/backend/internal/pkg/logger"
	customvalidator "github.com/snakeloader/backend/internal/pkg/validator"
	"github.com/snakeloader/backend/internal/response"
)

func New(mode string, rateLimiter *middleware.RateLimiter) *gin.Engine {
	return NewWithOptions(mode, rateLimiter, "")
}

// NewWithOptions builds the Gin engine with optional trusted-platform header
// (set via TRUSTED_PLATFORM env). When the service runs behind Cloudflare,
// pass "cloudflare" so c.ClientIP() resolves the user's real IP from
// CF-Connecting-IP instead of the Cloudflare edge node IP — without this,
// every user behind the same Cloudflare PoP shares one rate-limit bucket.
func NewWithOptions(mode string, rateLimiter *middleware.RateLimiter, trustedPlatform string) *gin.Engine {
	gin.SetMode(mode)

	engine := gin.New()

	// Register custom validators with Gin's binding engine. Loud-fail on
	// misconfiguration: a silent skip would let DTOs accept invalid keys
	// (license_key in particular gates Stripe cancellation flows).
	v, ok := binding.Validator.Engine().(*playvalidator.Validate)
	if !ok {
		logger.Log.Fatal().Msg("Gin validator engine is not go-playground/validator/v10 — custom validators cannot be registered")
	}
	if err := customvalidator.Register(v); err != nil {
		logger.Log.Fatal().Err(err).Msg("Failed to register custom validators")
	}

	// Return 405 Method Not Allowed instead of 404 when path matches but verb
	// doesn't. Industry-standard REST behavior; helps API consumers diagnose
	// integration mistakes faster.
	engine.HandleMethodNotAllowed = true
	engine.NoMethod(func(c *gin.Context) {
		response.Error(c, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "HTTP method not allowed for this route")
	})
	engine.NoRoute(func(c *gin.Context) {
		response.Error(c, http.StatusNotFound, "NOT_FOUND", "Route not found")
	})

	// Security: disable trusting X-Forwarded-For headers by default.
	// Without this, attackers can spoof their IP to bypass rate limiting.
	// Set TRUSTED_PROXIES env var (comma-separated) if behind a reverse proxy.
	engine.SetTrustedProxies(nil)

	// Resolve real client IP from CDN-injected header when running behind a
	// known CDN. Falls back to RemoteAddr when the header is absent (so this
	// is safe to enable in dev too — it just no-ops without the header).
	if platform := resolveTrustedPlatform(trustedPlatform); platform != "" {
		engine.TrustedPlatform = platform
		logger.Log.Info().
			Str("trusted_platform", trustedPlatform).
			Str("header", platform).
			Msg("Client IP resolution will use CDN-injected header")
	} else if trustedPlatform != "" {
		logger.Log.Warn().
			Str("trusted_platform", trustedPlatform).
			Msg("Unrecognized TRUSTED_PLATFORM value — falling back to RemoteAddr for client IP")
	}

	// Limit request body to 10 MB
	engine.MaxMultipartMemory = 10 << 20

	// Global middleware (order matters)
	engine.Use(middleware.Recovery())
	engine.Use(middleware.RequestID())
	engine.Use(middleware.SecureHeaders())
	engine.Use(middleware.MaxBodySize(10 << 20)) // 10 MB
	engine.Use(middleware.Logger())
	engine.Use(middleware.CORS())
	engine.Use(middleware.MetricsMiddleware())

	if rateLimiter != nil {
		engine.Use(rateLimiter.Middleware())
	}

	return engine
}

func resolveTrustedPlatform(name string) string {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "cloudflare", "cf":
		return gin.PlatformCloudflare
	case "google", "appengine", "gae":
		return gin.PlatformGoogleAppEngine
	case "flyio", "fly":
		return gin.PlatformFlyIO
	default:
		return ""
	}
}
