package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type PaymentTransaction struct {
	ID              uuid.UUID  `gorm:"type:uuid;primaryKey"`
	LicenseID       *uuid.UUID `gorm:"type:uuid;index"`
	DeviceID        uuid.UUID  `gorm:"type:uuid;index;not null"`
	Brand           string     `gorm:"not null;default:'ssvid';size:20;index"`
	IdempotencyKey  string     `gorm:"uniqueIndex;not null;size:255"`
	PaymentMethod   string     `gorm:"not null;size:20"`
	BillingCycle    string     `gorm:"not null;size:20"`
	AmountCents     int        `gorm:"not null"`
	Currency        string     `gorm:"not null;default:'USD';size:10"`
	Status          string     `gorm:"not null;default:'pending';size:20;index"`
	StripeSessionID       *string `gorm:"size:255"`
	StripePaymentIntentID *string `gorm:"size:255"`
	CryptoInvoiceID       *string `gorm:"size:255"`
	ErrorMessage    *string    `gorm:"size:1000"`
	CompletedAt     *time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

func (t *PaymentTransaction) BeforeCreate(tx *gorm.DB) error {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	if t.Status == "" {
		t.Status = "pending"
	}
	if t.Currency == "" {
		t.Currency = "USD"
	}
	return nil
}
