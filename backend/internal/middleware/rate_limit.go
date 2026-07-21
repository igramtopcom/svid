package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/response"
)

type RateLimiter struct {
	redis         *redis.Client
	maxRequests   int
	windowSeconds int
}

func NewRateLimiter(rdb *redis.Client, maxRequests, windowSeconds int) *RateLimiter {
	return &RateLimiter{
		redis:         rdb,
		maxRequests:   maxRequests,
		windowSeconds: windowSeconds,
	}
}

func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	// Global rate limit fails OPEN: when Redis is unavailable, requests still
	// flow. Loss of rate limiting on non-sensitive endpoints is preferable to a
	// site-wide 503 storm.
	base := rl.rateLimitFunc("rate_limit", rl.maxRequests, rl.windowSeconds, false)
	return func(c *gin.Context) {
		if shouldSkipGlobalRateLimit(c.Request.URL.Path) {
			c.Next()
			return
		}
		base(c)
	}
}

// StrictMiddleware returns a rate limiter for sensitive endpoints (payment,
// register, restore, etc.). Fails CLOSED when Redis is unavailable: a 503
// Service Unavailable beats letting a botnet spam Stripe Checkout creation
// or device registration unmetered. Industry-standard for any endpoint
// whose abuse has financial or auth consequences.
func (rl *RateLimiter) StrictMiddleware(name string, maxRequests, windowSeconds int) gin.HandlerFunc {
	return rl.rateLimitFunc("strict_rl:"+name, maxRequests, windowSeconds, true)
}

func (rl *RateLimiter) rateLimitFunc(prefix string, maxReq, windowSec int, failClosed bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		if rl.redis == nil {
			if failClosed {
				logger.Log.Error().
					Str("prefix", prefix).
					Str("path", c.Request.URL.Path).
					Msg("Strict rate limiter Redis unavailable — denying request (fail-closed)")
				c.Header("Retry-After", "30")
				response.Error(c, http.StatusServiceUnavailable, "RATE_LIMITER_UNAVAILABLE", "Rate limiter temporarily unavailable, please retry shortly")
				c.Abort()
				return
			}
			c.Next()
			return
		}

		key := fmt.Sprintf("%s:%s", prefix, c.ClientIP())
		ctx := context.Background()

		count, err := rl.redis.Incr(ctx, key).Result()
		if err != nil {
			if failClosed {
				logger.Log.Error().
					Err(err).
					Str("prefix", prefix).
					Str("path", c.Request.URL.Path).
					Msg("Strict rate limiter Redis error — denying request (fail-closed)")
				c.Header("Retry-After", "30")
				response.Error(c, http.StatusServiceUnavailable, "RATE_LIMITER_UNAVAILABLE", "Rate limiter temporarily unavailable, please retry shortly")
				c.Abort()
				return
			}
			logger.Log.Warn().Err(err).Msg("Rate limiter Redis error, allowing request")
			c.Next()
			return
		}

		if count == 1 {
			rl.redis.Expire(ctx, key, time.Duration(windowSec)*time.Second)
		}

		c.Header("X-RateLimit-Limit", strconv.Itoa(maxReq))
		c.Header("X-RateLimit-Remaining", strconv.Itoa(max(0, maxReq-int(count))))

		if int(count) > maxReq {
			ttl, _ := rl.redis.TTL(ctx, key).Result()
			c.Header("Retry-After", strconv.Itoa(int(ttl.Seconds())))
			response.Error(c, http.StatusTooManyRequests, "RATE_LIMIT_EXCEEDED", "Too many requests, please try again later")
			c.Abort()
			return
		}

		c.Next()
	}
}

func shouldSkipGlobalRateLimit(path string) bool {
	switch {
	case path == "/health", path == "/health/live", path == "/health/ready":
		return true
	case strings.HasPrefix(path, "/dashboard-ui"):
		return true
	case strings.HasPrefix(path, "/admin/v1/") && !strings.HasPrefix(path, "/admin/v1/auth/"):
		return true
	default:
		return false
	}
}
