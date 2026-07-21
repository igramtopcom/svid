package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/identity/model"
	"gorm.io/gorm"
)

type ApiKeyRepository struct {
	db *gorm.DB
}

func NewApiKeyRepository(db *gorm.DB) *ApiKeyRepository {
	return &ApiKeyRepository{db: db}
}

func (r *ApiKeyRepository) FindByHash(hash string) (*model.ApiKey, error) {
	var key model.ApiKey
	err := r.db.Preload("Device").Where("key_hash = ?", hash).First(&key).Error
	if err != nil {
		return nil, err
	}
	return &key, nil
}

func (r *ApiKeyRepository) FindActiveByDeviceID(deviceID uuid.UUID) (*model.ApiKey, error) {
	var key model.ApiKey
	err := r.db.Where("device_id = ? AND is_revoked = false AND expires_at > NOW()", deviceID).
		First(&key).Error
	if err != nil {
		return nil, err
	}
	return &key, nil
}

func (r *ApiKeyRepository) Create(key *model.ApiKey) error {
	return r.db.Create(key).Error
}

func (r *ApiKeyRepository) RevokeAllForDevice(deviceID uuid.UUID) error {
	return r.db.Model(&model.ApiKey{}).
		Where("device_id = ? AND is_revoked = false", deviceID).
		Update("is_revoked", true).Error
}

// FindHashesByDeviceID returns key hashes for all non-revoked keys belonging to a device.
// Used for cache invalidation when a device's keys are revoked or the device is deactivated.
func (r *ApiKeyRepository) FindHashesByDeviceID(deviceID uuid.UUID) ([]string, error) {
	var hashes []string
	err := r.db.Model(&model.ApiKey{}).
		Where("device_id = ? AND is_revoked = false", deviceID).
		Pluck("key_hash", &hashes).Error
	return hashes, err
}
