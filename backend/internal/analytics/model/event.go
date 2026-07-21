package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type AnalyticsEvent struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	DeviceID   uuid.UUID `gorm:"type:uuid;not null;index"`
	EventType  string    `gorm:"size:50;not null;index"` // app_open, download_start, download_complete, download_error, feature_used, etc.
	EventData  string    `gorm:"type:text"`              // JSON
	AppVersion string    `gorm:"size:20;index"`
	OS         string    `gorm:"size:50;index"`
	CreatedAt  time.Time `gorm:"index"`
}

func (e *AnalyticsEvent) BeforeCreate(tx *gorm.DB) error {
	if e.ID == uuid.Nil {
		e.ID = uuid.New()
	}
	return nil
}

type DailyStats struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	Date       time.Time `gorm:"type:date;not null;uniqueIndex:idx_date_metric"`
	MetricName string    `gorm:"size:50;not null;uniqueIndex:idx_date_metric"` // total_events, active_devices, downloads, errors, etc.
	Value      int64     `gorm:"not null;default:0"`
	Dimensions string    `gorm:"type:text"` // JSON breakdown
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

func (d *DailyStats) BeforeCreate(tx *gorm.DB) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	return nil
}
