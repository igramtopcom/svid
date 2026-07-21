package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type CrashGroup struct {
	ID          uuid.UUID  `gorm:"type:uuid;primaryKey"`
	Fingerprint string     `gorm:"type:varchar(64);uniqueIndex;not null"` // SHA-256 of normalized stack trace
	Title       string     `gorm:"type:text;not null"`                   // Auto-extracted from error message
	Status      string     `gorm:"size:20;default:'new';index"`          // new, investigating, fixing, resolved, wont_fix
	Severity    string     `gorm:"size:20;default:'medium'"`             // critical, high, medium, low
	FirstSeenAt time.Time  `gorm:"not null"`
	LastSeenAt  time.Time  `gorm:"not null;index"`
	CrashCount  int64      `gorm:"default:0"`
	DeviceCount int64      `gorm:"default:0"`
	Versions    string     `gorm:"type:text"`  // JSON array of affected app versions
	Platforms   string     `gorm:"type:text"`  // JSON array of affected OS platforms
	AdminNotes  string     `gorm:"type:text"`
	AssignedTo  string     `gorm:"size:255"`
	ResolvedAt  *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

func (g *CrashGroup) BeforeCreate(tx *gorm.DB) error {
	if g.ID == uuid.Nil {
		g.ID = uuid.New()
	}
	if g.Status == "" {
		g.Status = "new"
	}
	if g.Severity == "" {
		g.Severity = "medium"
	}
	return nil
}
