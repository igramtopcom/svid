package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AuditLog struct {
	ID           uuid.UUID `gorm:"type:uuid;primaryKey"`
	AdminID      uuid.UUID `gorm:"type:uuid;not null;index"`
	AdminEmail   string    `gorm:"size:255"`
	Action       string    `gorm:"size:10;not null;index"` // POST, PUT, PATCH, DELETE
	ResourceType string    `gorm:"size:100;index"`         // e.g. "devices", "bugs", "licenses"
	ResourceID   string    `gorm:"size:100"`               // extracted from URL if present
	Path         string    `gorm:"size:500;not null"`
	RequestBody  string    `gorm:"type:text"`
	StatusCode   int       `gorm:"not null"`
	IPAddress    string    `gorm:"size:45"`
	CreatedAt    time.Time `gorm:"index"`
}

func (a *AuditLog) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return nil
}
