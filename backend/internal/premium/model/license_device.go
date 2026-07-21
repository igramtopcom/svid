package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type LicenseDevice struct {
	ID             uuid.UUID `gorm:"type:uuid;primaryKey"`
	LicenseID      uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_license_device"`
	DeviceID       uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_license_device"`
	RegisteredAt   time.Time `gorm:"not null"`
	LastVerifiedAt time.Time `gorm:"not null"`
}

func (ld *LicenseDevice) BeforeCreate(tx *gorm.DB) error {
	if ld.ID == uuid.Nil {
		ld.ID = uuid.New()
	}
	now := time.Now()
	if ld.RegisteredAt.IsZero() {
		ld.RegisteredAt = now
	}
	if ld.LastVerifiedAt.IsZero() {
		ld.LastVerifiedAt = now
	}
	return nil
}
