package model

import "time"

// WebhookEvent tracks processed webhook events to prevent duplicate processing.
// Status flow: "processing" → "processed" (success) or "failed" (error, allows retry).
type WebhookEvent struct {
	ID          uint       `gorm:"primaryKey;autoIncrement"`
	EventID     string     `gorm:"size:255;not null;uniqueIndex:uk_event_id"`
	EventType   string     `gorm:"size:100;not null"`
	Status      string     `gorm:"size:20;not null;default:processing"` // processing, processed, failed
	ProcessedAt *time.Time `gorm:""`
	CreatedAt   time.Time  `gorm:"autoCreateTime"`
}
