package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Admin struct {
	ID           uuid.UUID  `gorm:"type:uuid;primaryKey"`
	Email        string     `gorm:"uniqueIndex;not null;size:255"`
	PasswordHash string     `gorm:"not null;size:255"`
	Name         string     `gorm:"size:255"`
	BrandScope   string     `gorm:"size:50;default:''"` // "" = super admin (all brands), "ssvid", "vidcombo"
	CreatedAt    time.Time
	LastLoginAt  *time.Time
}

// IsSuperAdmin returns true if this admin can see all brands.
func (a *Admin) IsSuperAdmin() bool {
	return a.BrandScope == ""
}

func (a *Admin) BeforeCreate(tx *gorm.DB) error {
	if a.ID == uuid.Nil {
		a.ID = uuid.New()
	}
	return nil
}
