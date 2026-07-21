package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// BootstrapEvent captures pre-auth startup/registration telemetry.
//
// It intentionally lives outside analytics_events because those rows require a
// registered device_id; using a fake device would corrupt active-device counts.
type BootstrapEvent struct {
	ID           uuid.UUID `gorm:"type:uuid;primaryKey"`
	InstallID    string    `gorm:"size:64;not null;index"`
	Brand        string    `gorm:"size:20;not null;index"`
	OS           string    `gorm:"size:50;not null;index"`
	OSVersion    string    `gorm:"size:80"`
	AppVersion   string    `gorm:"size:20;not null;index"`
	Stage        string    `gorm:"size:50;not null;index"`
	Status       string    `gorm:"size:20;not null;index"`
	ErrorCode    string    `gorm:"size:100;index"`
	ErrorMessage string    `gorm:"type:text"`
	Metadata     string    `gorm:"type:text"`
	IPAddress    string    `gorm:"size:64;index"`
	UserAgent    string    `gorm:"size:500"`
	CreatedAt    time.Time `gorm:"index"`
}

func (e *BootstrapEvent) BeforeCreate(tx *gorm.DB) error {
	if e.ID == uuid.Nil {
		e.ID = uuid.New()
	}
	return nil
}
