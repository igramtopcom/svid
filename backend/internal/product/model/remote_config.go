package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type RemoteConfig struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey"`
	Key         string    `gorm:"uniqueIndex;not null;size:100"`
	Value       string    `gorm:"type:text;not null"`
	ValueType   string    `gorm:"size:20;not null;default:'string'"` // string, number, boolean, json
	Description string    `gorm:"type:text"`
	CreatedAt   time.Time `gorm:"index"`
	UpdatedAt   time.Time
}

func (r *RemoteConfig) BeforeCreate(tx *gorm.DB) error {
	if r.ID == uuid.Nil {
		r.ID = uuid.New()
	}
	if r.ValueType == "" {
		r.ValueType = "string"
	}
	return nil
}
