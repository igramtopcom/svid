package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type KnowledgeBase struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey"`
	Title     string    `gorm:"size:500;not null"`
	Content   string    `gorm:"type:text;not null"`
	Category  string    `gorm:"size:50;not null;default:'faq';index"` // faq, tutorial, troubleshooting
	Tags      string    `gorm:"type:text"`                           // JSON array of tags for search
	IsActive  bool      `gorm:"default:true"`
	CreatedAt time.Time `gorm:"index"`
	UpdatedAt time.Time
}

func (k *KnowledgeBase) BeforeCreate(tx *gorm.DB) error {
	if k.ID == uuid.Nil {
		k.ID = uuid.New()
	}
	if k.Category == "" {
		k.Category = "faq"
	}
	return nil
}
