package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Ticket struct {
	ID          uuid.UUID       `gorm:"type:uuid;primaryKey"`
	DeviceID    uuid.UUID       `gorm:"type:uuid;not null;index"`
	Subject     string          `gorm:"size:500;not null"`
	Category    string          `gorm:"size:30;not null;default:'general'"` // general, billing, technical, feature_request
	Status      string          `gorm:"size:30;not null;default:'open';index"` // open, in_progress, waiting_for_customer, resolved, closed
	Priority    string          `gorm:"size:20;not null;default:'medium'"` // low, medium, high, critical
	AISessionID *uuid.UUID      `gorm:"type:uuid;index" json:"ai_session_id,omitempty"` // Link to AI chat session (escalation)
	CreatedAt   time.Time       `gorm:"index"`
	UpdatedAt   time.Time
	Messages    []TicketMessage `gorm:"foreignKey:TicketID;constraint:OnDelete:CASCADE"`
}

func (t *Ticket) BeforeCreate(tx *gorm.DB) error {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	if t.Category == "" {
		t.Category = "general"
	}
	if t.Status == "" {
		t.Status = "open"
	}
	if t.Priority == "" {
		t.Priority = "medium"
	}
	return nil
}

type TicketMessage struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey"`
	TicketID   uuid.UUID `gorm:"type:uuid;not null;index"`
	SenderType string    `gorm:"size:10;not null"` // device, admin
	SenderID   uuid.UUID `gorm:"type:uuid;not null"`
	Content    string    `gorm:"type:text;not null"`
	CreatedAt  time.Time `gorm:"index"`
}

func (m *TicketMessage) BeforeCreate(tx *gorm.DB) error {
	if m.ID == uuid.Nil {
		m.ID = uuid.New()
	}
	return nil
}
