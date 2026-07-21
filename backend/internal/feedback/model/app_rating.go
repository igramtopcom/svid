package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AppRating struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	DeviceID   uuid.UUID `gorm:"type:uuid;not null;uniqueIndex"`
	Rating     int       `gorm:"not null"` // 1-5
	Review     string    `gorm:"type:text"`
	AppVersion string    `gorm:"size:20"`
	CreatedAt  time.Time `gorm:"index"`
	UpdatedAt  time.Time
}

func (r *AppRating) BeforeCreate(tx *gorm.DB) error {
	if r.ID == uuid.Nil {
		r.ID = uuid.New()
	}
	return nil
}
