package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/pkg/crypto"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/response"
)

const (
	DeviceKey    = "device"
	DeviceIDKey  = "device_id"
	DeviceBrandKey = "device_brand"
)

type AuthMiddleware struct {
	keyRepo *repository.ApiKeyRepository
	redis   *redis.Client
}

func NewAuthMiddleware(keyRepo *repository.ApiKeyRepository, rdb *redis.Client) *AuthMiddleware {
	return &AuthMiddleware{
		keyRepo: keyRepo,
		redis:   rdb,
	}
}

func (m *AuthMiddleware) RequireAPIKey() gin.HandlerFunc {
	return func(c *gin.Context) {
		rawKey := c.GetHeader("X-API-Key")
		if rawKey == "" {
			response.Error(c, http.StatusUnauthorized, "MISSING_API_KEY", "X-API-Key header is required")
			c.Abort()
			return
		}

		hash := crypto.HashAPIKey(rawKey)

		// Try Redis cache first
		if apiKey := m.getFromCache(hash); apiKey != nil {
			if !apiKey.IsValid() {
				response.Error(c, http.StatusUnauthorized, "EXPIRED_API_KEY", "API key has expired, please re-register")
				c.Abort()
				return
			}
			if !apiKey.Device.IsActive {
				response.Error(c, http.StatusForbidden, "DEVICE_INACTIVE", "Device has been deactivated")
				c.Abort()
				return
			}
			c.Set(DeviceKey, &apiKey.Device)
			c.Set(DeviceIDKey, apiKey.DeviceID)
			brand := apiKey.Device.Brand
			if brand == "" {
				brand = "svid" // Fallback for cached entries without brand field
			}
			c.Set(DeviceBrandKey, brand)
			c.Next()
			return
		}

		// Fallback to DB
		apiKey, err := m.keyRepo.FindByHash(hash)
		if err != nil {
			response.Error(c, http.StatusUnauthorized, "INVALID_API_KEY", "Invalid API key")
			c.Abort()
			return
		}

		if apiKey.IsRevoked {
			response.Error(c, http.StatusUnauthorized, "REVOKED_API_KEY", "API key has been revoked, please re-register")
			c.Abort()
			return
		}

		if !apiKey.IsValid() {
			response.Error(c, http.StatusUnauthorized, "EXPIRED_API_KEY", "API key has expired, please re-register")
			c.Abort()
			return
		}

		if !apiKey.Device.IsActive {
			response.Error(c, http.StatusForbidden, "DEVICE_INACTIVE", "Device has been deactivated")
			c.Abort()
			return
		}

		// Cache for 5 minutes
		m.setCache(hash, apiKey)

		c.Set(DeviceKey, &apiKey.Device)
		c.Set(DeviceIDKey, apiKey.DeviceID)
		c.Set(DeviceBrandKey, apiKey.Device.Brand)
		c.Next()
	}
}

func (m *AuthMiddleware) getFromCache(hash string) *model.ApiKey {
	if m.redis == nil {
		return nil
	}

	ctx := context.Background()
	data, err := m.redis.Get(ctx, "apikey:"+hash).Bytes()
	if err != nil {
		return nil
	}

	var key model.ApiKey
	if err := json.Unmarshal(data, &key); err != nil {
		return nil
	}
	return &key
}

func (m *AuthMiddleware) setCache(hash string, key *model.ApiKey) {
	if m.redis == nil {
		return
	}

	ctx := context.Background()
	data, err := json.Marshal(key)
	if err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to marshal API key for cache")
		return
	}

	if err := m.redis.Set(ctx, "apikey:"+hash, data, 5*time.Minute).Err(); err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to cache API key in Redis")
	}
}

// InvalidateCache removes a cached API key by its hash. Call this on key revocation.
func (m *AuthMiddleware) InvalidateCache(hash string) {
	if m.redis == nil {
		return
	}
	ctx := context.Background()
	m.redis.Del(ctx, "apikey:"+hash)
}
