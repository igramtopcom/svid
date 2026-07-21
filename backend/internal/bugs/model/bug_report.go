package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type BugReport struct {
	ID          uuid.UUID      `gorm:"type:uuid;primaryKey"`
	DeviceID    uuid.UUID      `gorm:"type:uuid;not null;index"`
	Title       string         `gorm:"size:500;not null"`
	Description string         `gorm:"type:text;not null"`
	Steps       string         `gorm:"type:text"`              // steps to reproduce
	AppVersion  string         `gorm:"size:20"`
	OS          string         `gorm:"size:50"`
	OSVersion   string         `gorm:"size:50"`
	Status      string         `gorm:"size:20;default:'new';index"` // new, triaging, in_progress, resolved, closed
	Priority    string         `gorm:"size:20;default:'medium'"`    // critical, high, medium, low
	AdminNotes  string         `gorm:"type:text"`
	ResolvedAt  *time.Time
	CreatedAt   time.Time      `gorm:"index"`
	UpdatedAt   time.Time
	Attachments []BugAttachment `gorm:"foreignKey:BugReportID;constraint:OnDelete:CASCADE"`
}

func (b *BugReport) BeforeCreate(tx *gorm.DB) error {
	if b.ID == uuid.Nil {
		b.ID = uuid.New()
	}
	if b.Status == "" {
		b.Status = "new"
	}
	if b.Priority == "" {
		b.Priority = "medium"
	}
	return nil
}

type BugAttachment struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey"`
	BugReportID uuid.UUID `gorm:"type:uuid;not null;index"`
	FileName    string    `gorm:"size:255;not null"`
	FileURL     string    `gorm:"size:1024;not null"`
	FileType    string    `gorm:"size:50"` // screenshot, log, other
	FileSize    int64
	CreatedAt   time.Time
}

func (a *BugAttachment) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return nil
}
