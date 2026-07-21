package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// DiagnosticLog stores app log tails attached to bug or crash reports.
// Content is the last ~200 lines of the app's log file, sent as plain text.
type DiagnosticLog struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	ReportType string    `gorm:"size:10;not null;index:idx_diagnostic_report"` // "bug" or "crash"
	ReportID   uuid.UUID `gorm:"type:uuid;not null;index:idx_diagnostic_report"`
	Content    string    `gorm:"type:text;not null"`
	LineCount  int       `gorm:"default:0"`
	SizeBytes  int       `gorm:"default:0"`
	CreatedAt  time.Time
}

func (d *DiagnosticLog) BeforeCreate(tx *gorm.DB) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	return nil
}
