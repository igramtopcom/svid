package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Announcement struct {
	ID              uuid.UUID  `gorm:"type:uuid;primaryKey"`
	Title           string     `gorm:"not null;size:500"`
	Content         string     `gorm:"type:text;not null"`
	Type            string     `gorm:"size:20;not null;default:'info'"` // info, warning, critical, maintenance
	TargetTiers     string     `gorm:"type:text"`                      // JSON array: ["free","pro"]
	TargetPlatforms string     `gorm:"type:text"`                      // JSON array: ["macos","windows","linux"]
	StartsAt        *time.Time `gorm:"index"`
	ExpiresAt       *time.Time `gorm:"index"`
	IsActive        bool       `gorm:"default:true"`
	CreatedAt       time.Time  `gorm:"index"`
	UpdatedAt       time.Time
}

func (a *Announcement) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	if a.Type == "" {
		a.Type = "info"
	}
	return nil
}
