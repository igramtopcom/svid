package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type CrashReport struct {
	ID           uuid.UUID  `gorm:"type:uuid;primaryKey"`
	DeviceID     uuid.UUID  `gorm:"type:uuid;not null;index"`
	CrashGroupID *uuid.UUID `gorm:"type:uuid;index"` // FK to crash_groups
	StackTrace   string     `gorm:"type:text;not null"`
	ErrorMessage string     `gorm:"type:text"`
	AppVersion   string     `gorm:"size:20"`
	OS           string     `gorm:"size:50"`
	OSVersion    string     `gorm:"size:50"`
	Severity     string     `gorm:"size:20;default:'medium'"` // critical, high, medium, low
	Metadata     string     `gorm:"type:text"`                // JSON string for extra context
	AdminNotes   string     `gorm:"type:text"`
	CreatedAt    time.Time  `gorm:"index"`
}

func (c *CrashReport) BeforeCreate(tx *gorm.DB) error {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	if c.Severity == "" {
		c.Severity = "medium"
	}
	return nil
}
