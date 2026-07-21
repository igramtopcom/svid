package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// AlertConfig defines a threshold-based alert rule.
type AlertConfig struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey"`
	Name        string    `gorm:"size:100;not null"`
	MetricType  string    `gorm:"size:50;not null;index"` // crash_rate, error_rate, crash_spike
	Threshold   int       `gorm:"not null;default:10"`    // e.g. 10 crashes
	WindowMins  int       `gorm:"not null;default:60"`    // time window in minutes
	Channel     string    `gorm:"size:20;not null"`       // telegram, email
	Destination string    `gorm:"size:500;not null"`      // chat_id or email address
	IsEnabled   bool      `gorm:"default:true"`
	CooldownMins int     `gorm:"not null;default:60"` // min minutes between alerts
	LastFiredAt *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func (a *AlertConfig) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return nil
}

// AlertLog records each alert that was sent.
type AlertLog struct {
	ID            uuid.UUID `gorm:"type:uuid;primaryKey"`
	AlertConfigID uuid.UUID `gorm:"type:uuid;not null;index"`
	MetricValue   int       `gorm:"not null"` // actual value that triggered
	Message       string    `gorm:"type:text"`
	Channel       string    `gorm:"size:20;not null"`
	Status        string    `gorm:"size:20;not null;default:'sent'"` // sent, failed
	ErrorMessage  string    `gorm:"type:text"`
	CreatedAt     time.Time `gorm:"index"`
}

func (a *AlertLog) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return nil
}
