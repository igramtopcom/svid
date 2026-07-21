package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type ChatSession struct {
	ID        uuid.UUID     `gorm:"type:uuid;primaryKey"`
	DeviceID  uuid.UUID     `gorm:"type:uuid;not null;index"`
	Title     string        `gorm:"size:500"`
	Status    string        `gorm:"size:20;not null;default:'active';index"` // active, closed, escalated
	CreatedAt time.Time     `gorm:"index"`
	UpdatedAt time.Time
	Messages  []ChatMessage `gorm:"foreignKey:SessionID;constraint:OnDelete:CASCADE"`
}

func (s *ChatSession) BeforeCreate(tx *gorm.DB) error {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	if s.Status == "" {
		s.Status = "active"
	}
	return nil
}

type ChatMessage struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	SessionID  uuid.UUID `gorm:"type:uuid;not null;index"`
	Role       string    `gorm:"size:20;not null"` // user, assistant, system
	Content    string    `gorm:"type:text;not null"`
	TokensUsed int       `gorm:"default:0"`
	CreatedAt  time.Time `gorm:"index"`
}

func (m *ChatMessage) BeforeCreate(tx *gorm.DB) error {
	if m.ID == uuid.Nil {
		m.ID = uuid.New()
	}
	return nil
}
