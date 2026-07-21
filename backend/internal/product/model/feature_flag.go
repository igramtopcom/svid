package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type FeatureFlag struct {
	ID            uuid.UUID `gorm:"type:uuid;primaryKey"`
	Key           string    `gorm:"uniqueIndex;not null;size:100"`
	Name          string    `gorm:"not null;size:255"`
	Description   string    `gorm:"type:text"`
	Enabled       bool      `gorm:"default:false"`
	Tiers         string    `gorm:"type:text"` // JSON array: ["free","pro"]
	Platforms     string    `gorm:"type:text"` // JSON array: ["macos","windows","linux"]
	MinAppVersion string    `gorm:"size:20"`
	Metadata      string    `gorm:"type:text"` // JSON object for extra config
	CreatedAt     time.Time `gorm:"index"`
	UpdatedAt     time.Time
}

func (f *FeatureFlag) BeforeCreate(tx *gorm.DB) error {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	return nil
}
