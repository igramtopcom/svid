package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Device struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	HardwareID string    `gorm:"not null;size:255"`
	Brand      string    `gorm:"not null;default:'svid';size:50;index:idx_devices_brand"`
	OS         string    `gorm:"not null;size:50"`
	OSVersion  string    `gorm:"size:50"`
	AppVersion string    `gorm:"size:20"`
	DeviceName string    `gorm:"size:255"`
	Tier       string    `gorm:"default:'free';size:20"`
	IsActive   bool      `gorm:"default:true"`
	CreatedAt  time.Time
	LastSeenAt time.Time
	ApiKeys    []ApiKey  `gorm:"foreignKey:DeviceID"`
}

func (d *Device) BeforeCreate(tx *gorm.DB) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	if d.Tier == "" {
		d.Tier = "free"
	}
	if d.Brand == "" {
		d.Brand = "svid"
	}
	d.IsActive = true
	d.LastSeenAt = time.Now()
	return nil
}
