package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/identity/dto"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/identity/repository"
	"github.com/snakeloader/backend/internal/pkg/crypto"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"gorm.io/gorm"
)

var (
	ErrDeviceNotFound   = errors.New("device not found")
	ErrDeviceInactive   = errors.New("device is inactive")
	ErrRegisterCooldown = errors.New("registration cooldown active")
)

// DeviceNotifier is an optional hook for sending device event notifications.
type DeviceNotifier interface {
	NotifyNewDevice(deviceID, os, osVersion, appVersion, deviceName string)
	NotifyRegistrationAnomaly(ip string, count int64, latestHardwareID string)
}

// CacheInvalidator is called to remove a cached API key by its hash.
// Wired from AuthMiddleware.InvalidateCache to keep Redis cache in sync with DB.
type CacheInvalidator func(hash string)

type DeviceService struct {
	deviceRepo       *repository.DeviceRepository
	keyRepo          *repository.ApiKeyRepository
	keyConfig        *config.APIKeyConfig
	rdb              *redis.Client    // nil = no cooldown enforcement
	notifier         DeviceNotifier   // nil = no notifications
	cacheInvalidator CacheInvalidator // nil = no cache invalidation
}

func NewDeviceService(
	deviceRepo *repository.DeviceRepository,
	keyRepo *repository.ApiKeyRepository,
	keyConfig *config.APIKeyConfig,
) *DeviceService {
	return &DeviceService{
		deviceRepo: deviceRepo,
		keyRepo:    keyRepo,
		keyConfig:  keyConfig,
	}
}

// SetRedis wires the Redis client for cooldown enforcement.
func (s *DeviceService) SetRedis(rdb *redis.Client) { s.rdb = rdb }

// SetNotifier wires the event notifier (called after construction to avoid circular deps).
func (s *DeviceService) SetNotifier(n DeviceNotifier) { s.notifier = n }

// SetCacheInvalidator wires the API key cache invalidation callback.
// Typically set to AuthMiddleware.InvalidateCache.
func (s *DeviceService) SetCacheInvalidator(fn CacheInvalidator) { s.cacheInvalidator = fn }

// invalidateCacheForDevice removes all cached API keys for a device from Redis.
func (s *DeviceService) invalidateCacheForDevice(deviceID uuid.UUID) {
	if s.cacheInvalidator == nil {
		return
	}
	hashes, err := s.keyRepo.FindHashesByDeviceID(deviceID)
	if err != nil {
		logger.Log.Warn().Err(err).Str("device_id", deviceID.String()).Msg("Failed to find key hashes for cache invalidation")
		return
	}
	for _, h := range hashes {
		s.cacheInvalidator(h)
	}
}

// RegisterDevice handles idempotent device registration.
// If hardware_id exists: update info, ensure valid key.
// If new: create device + generate key.
// clientIP and userAgent are logged for audit purposes.
func (s *DeviceService) RegisterDevice(req dto.RegisterDeviceRequest, clientIP, userAgent string) (*dto.RegisterResponse, error) {
	// Default brand to "ssvid" if not provided (backward compatible)
	brand := req.Brand
	if brand == "" {
		brand = "ssvid"
	}

	// Re-register cooldown: 60s per (brand + hardware_id) to prevent DOS via key rotation
	if s.rdb != nil {
		cooldownKey := fmt.Sprintf("register_cooldown:%s:%s", brand, req.HardwareID)
		ctx := context.Background()
		if exists, _ := s.rdb.Exists(ctx, cooldownKey).Result(); exists > 0 {
			logger.Log.Warn().
				Str("hardware_id", req.HardwareID).
				Str("brand", brand).
				Str("ip", clientIP).
				Msg("Register cooldown active — rejected")
			return nil, ErrRegisterCooldown
		}
		// Set cooldown for 60 seconds
		s.rdb.Set(ctx, cooldownKey, "1", 60*time.Second)
	}

	// Look up by (brand, hardware_id) — allows same device to register under both brands
	existing, err := s.deviceRepo.FindByBrandAndHardwareID(brand, req.HardwareID)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	// Fingerprint migration: if new hardware_id not found but legacy provided,
	// look up by legacy and migrate the device to the new fingerprint.
	if existing == nil && req.LegacyHardwareID != "" {
		legacy, legacyErr := s.deviceRepo.FindByBrandAndHardwareID(brand, req.LegacyHardwareID)
		if legacyErr == nil && legacy != nil {
			logger.Log.Info().
				Str("device_id", legacy.ID.String()).
				Str("old_hw_id", req.LegacyHardwareID).
				Str("new_hw_id", req.HardwareID).
				Str("brand", brand).
				Str("ip", clientIP).
				Msg("Fingerprint migration: updating hardware_id")
			legacy.HardwareID = req.HardwareID
			existing = legacy
		}
	}

	if existing != nil {
		// Deactivated devices cannot re-register
		if !existing.IsActive {
			return nil, ErrDeviceInactive
		}

		// Update device info
		existing.OSVersion = req.OSVersion
		existing.AppVersion = req.AppVersion
		existing.LastSeenAt = time.Now()
		if req.DeviceName != "" {
			existing.DeviceName = req.DeviceName
		}
		if err := s.deviceRepo.Update(existing); err != nil {
			return nil, err
		}

		// Check for valid API key
		activeKey, keyErr := s.keyRepo.FindActiveByDeviceID(existing.ID)
		if keyErr == nil && activeKey != nil {
			// Has valid key - revoke old keys before generating new one
			s.invalidateCacheForDevice(existing.ID)
			if err := s.keyRepo.RevokeAllForDevice(existing.ID); err != nil {
				logger.Log.Warn().Err(err).Str("device_id", existing.ID.String()).Msg("Failed to revoke old API keys on re-register")
			}
			rawKey, err := s.generateAPIKey(existing.ID)
			if err != nil {
				return nil, err
			}
			return &dto.RegisterResponse{
				DeviceID: existing.ID.String(),
				ApiKey:   rawKey,
				IsNew:    false,
			}, nil
		}

		// No valid key - revoke old ones and generate new
		// Revoke in DB FIRST, then invalidate cache to prevent TOCTOU race
		// where a concurrent request re-caches the about-to-be-revoked key.
		if revokeErr := s.keyRepo.RevokeAllForDevice(existing.ID); revokeErr != nil {
			logger.Log.Warn().Err(revokeErr).Str("device_id", existing.ID.String()).Msg("Failed to revoke old API keys on re-register")
		}
		s.invalidateCacheForDevice(existing.ID)
		rawKey, err := s.generateAPIKey(existing.ID)
		if err != nil {
			return nil, err
		}

		logger.Log.Info().
			Str("device_id", existing.ID.String()).
			Str("ip", clientIP).
			Str("user_agent", userAgent).
			Msg("Device re-registered with new key")
		return &dto.RegisterResponse{
			DeviceID: existing.ID.String(),
			ApiKey:   rawKey,
			IsNew:    false,
		}, nil
	}

	// New device
	device := &model.Device{
		HardwareID: req.HardwareID,
		Brand:      brand,
		OS:         req.OS,
		OSVersion:  req.OSVersion,
		AppVersion: req.AppVersion,
		DeviceName: req.DeviceName,
	}

	if err := s.deviceRepo.Create(device); err != nil {
		return nil, err
	}

	rawKey, err := s.generateAPIKey(device.ID)
	if err != nil {
		return nil, err
	}

	logger.Log.Info().
		Str("device_id", device.ID.String()).
		Str("brand", brand).
		Str("os", device.OS).
		Str("ip", clientIP).
		Str("user_agent", userAgent).
		Msg("New device registered")

	// S1.1: Telegram notification for new device
	if s.notifier != nil {
		s.notifier.NotifyNewDevice(device.ID.String(), device.OS, device.OSVersion, device.AppVersion, device.DeviceName)
	}

	// Anomaly detection: alert if same IP registers >10 devices in 1 hour
	if s.rdb != nil && s.notifier != nil {
		anomalyKey := fmt.Sprintf("register_ip_count:%s", clientIP)
		ctx := context.Background()
		count, err := s.rdb.Incr(ctx, anomalyKey).Result()
		if err == nil {
			if count == 1 {
				s.rdb.Expire(ctx, anomalyKey, 1*time.Hour)
			}
			if count == 11 { // Alert once at threshold, not every subsequent request
				s.notifier.NotifyRegistrationAnomaly(clientIP, count, req.HardwareID)
			}
		}
	}

	return &dto.RegisterResponse{
		DeviceID: device.ID.String(),
		ApiKey:   rawKey,
		IsNew:    true,
	}, nil
}

// Heartbeat updates device last_seen and app_version.
func (s *DeviceService) Heartbeat(deviceID uuid.UUID, req dto.HeartbeatRequest) (*dto.HeartbeatResponse, error) {
	device, err := s.deviceRepo.FindByID(deviceID)
	if err != nil {
		return nil, ErrDeviceNotFound
	}

	device.AppVersion = req.AppVersion
	device.LastSeenAt = time.Now()
	// Update brand if app sends it and it differs (fixes pre-multi-brand registrations)
	if req.Brand != "" && device.Brand != req.Brand {
		device.Brand = req.Brand
	}
	// Sync tier from client (VidCombo premium verified via PHP checkkey.php)
	if req.Tier != "" {
		device.Tier = req.Tier
	}
	if err := s.deviceRepo.Update(device); err != nil {
		return nil, err
	}

	return &dto.HeartbeatResponse{
		ServerTime: time.Now().UTC().Format(time.RFC3339),
	}, nil
}

// GetDevice returns a device by ID.
func (s *DeviceService) GetDevice(id uuid.UUID) (*dto.DeviceResponse, error) {
	device, err := s.deviceRepo.FindByID(id)
	if err != nil {
		return nil, ErrDeviceNotFound
	}
	resp := dto.DeviceToResponse(device)
	return &resp, nil
}

// ListDevices returns paginated devices with optional filters.
func (s *DeviceService) ListDevices(page, perPage int, os, brand, search string, isActive *bool) ([]dto.DeviceResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	devices, total, err := s.deviceRepo.List(page, perPage, os, brand, search, isActive)
	if err != nil {
		return nil, 0, err
	}

	return dto.DevicesToResponse(devices), total, nil
}

// UpdateDevice updates a device's tier or is_active status.
func (s *DeviceService) UpdateDevice(id uuid.UUID, req dto.UpdateDeviceRequest) (*dto.DeviceResponse, error) {
	device, err := s.deviceRepo.FindByID(id)
	if err != nil {
		return nil, ErrDeviceNotFound
	}

	if req.Tier != nil {
		device.Tier = *req.Tier
	}
	if req.IsActive != nil {
		device.IsActive = *req.IsActive
	}

	if err := s.deviceRepo.Update(device); err != nil {
		return nil, err
	}

	// Invalidate cached API keys when device status changes (active/inactive, tier).
	// The cache stores the full ApiKey+Device struct, so any device field change
	// requires invalidation to prevent stale data (e.g. deactivated device still passing auth).
	s.invalidateCacheForDevice(id)

	resp := dto.DeviceToResponse(device)
	return &resp, nil
}

func (s *DeviceService) generateAPIKey(deviceID uuid.UUID) (string, error) {
	raw, hash, err := crypto.GenerateAPIKey()
	if err != nil {
		return "", err
	}

	key := &model.ApiKey{
		DeviceID:  deviceID,
		KeyHash:   hash,
		ExpiresAt: time.Now().AddDate(0, 0, s.keyConfig.ExpiryDays),
	}

	if err := s.keyRepo.Create(key); err != nil {
		return "", err
	}

	return raw, nil
}
