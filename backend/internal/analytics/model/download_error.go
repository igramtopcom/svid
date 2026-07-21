package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type DownloadError struct {
	ID                   uuid.UUID `gorm:"type:uuid;primaryKey"`
	DeviceID             uuid.UUID `gorm:"type:uuid;not null;index"`
	URL                  string    `gorm:"type:text"`
	Platform             string    `gorm:"size:50;index"` // youtube, tiktok, instagram, etc.
	ErrorCode            string    `gorm:"size:50;index"` // extraction_failed, network_timeout, ffmpeg_error, etc.
	ErrorPhase           string    `gorm:"size:30;index"` // extraction, download, conversion, merge, post_process
	ErrorMessage         string    `gorm:"type:text"`
	DiagnosticErrorCode  string    `gorm:"size:80;index"` // backend-only reclassification; does not change client behavior
	DiagnosticErrorPhase string    `gorm:"size:30;index"`
	DiagnosticSignature  string    `gorm:"size:80;index"`
	AppVersion           string    `gorm:"size:20"`
	OS                   string    `gorm:"size:50"`
	OSVersion            string    `gorm:"size:50"`
	Metadata             string    `gorm:"type:text"` // JSON — extra context
	CreatedAt            time.Time `gorm:"index"`
}

func (e *DownloadError) BeforeCreate(tx *gorm.DB) error {
	if e.ID == uuid.Nil {
		e.ID = uuid.New()
	}
	return nil
}
