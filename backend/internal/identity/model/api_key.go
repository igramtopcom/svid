package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type ApiKey struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey"`
	DeviceID  uuid.UUID `gorm:"type:uuid;not null;index"`
	KeyHash   string    `gorm:"uniqueIndex;not null;size:64"`
	CreatedAt time.Time
	UpdatedAt time.Time
	ExpiresAt time.Time
	IsRevoked bool   `gorm:"default:false"`
	Device    Device `gorm:"foreignKey:DeviceID"`
}

func (k *ApiKey) BeforeCreate(tx *gorm.DB) error {
	if k.ID == uuid.Nil {
		k.ID = uuid.New()
	}
	return nil
}

func (k *ApiKey) IsValid() bool {
	return !k.IsRevoked && time.Now().Before(k.ExpiresAt)
}
