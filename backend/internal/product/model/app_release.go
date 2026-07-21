package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AppRelease struct {
	ID           uuid.UUID `gorm:"type:uuid;primaryKey"`
	Version      string    `gorm:"not null;size:20"`
	Platform     string    `gorm:"not null;size:50"`                  // macos, windows, linux
	Channel      string    `gorm:"not null;size:20;default:'stable'"` // stable, beta, alpha
	Brand        string    `gorm:"not null;size:20;default:'ssvid'"`  // ssvid, vidcombo
	ReleaseNotes string    `gorm:"type:text"`
	DownloadURL  string    `gorm:"type:text"`
	FileSize     int64     `gorm:"default:0"`
	Checksum     string    `gorm:"size:64"` // SHA-256
	IsMandatory  bool      `gorm:"default:false"`
	IsActive     bool      `gorm:"default:true"`
	PublishedAt  *time.Time
	CreatedAt    time.Time `gorm:"index"`
	UpdatedAt    time.Time
}

func (a *AppRelease) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	if a.Channel == "" {
		a.Channel = "stable"
	}
	return nil
}
