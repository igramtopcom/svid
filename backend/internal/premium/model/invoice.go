package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Invoice represents a Stripe invoice record.
//
// StripePaymentIntentID and StripeSubscriptionID enable the W1.4 refund/dispute
// fallback: when a charge.refunded fires for an invoice whose payment_intent
// is NOT in payment_transactions (e.g. renewal-only invoices created by the
// Stripe billing engine, not by our checkout flow), we resolve the license
// via invoice→license_id (direct), then invoice→subscription_id→license
// (orphan-invoice path) before giving up.
type Invoice struct {
	ID                    uuid.UUID  `gorm:"type:uuid;primaryKey"`
	StripeInvoiceID       string     `gorm:"uniqueIndex;not null;size:255"`
	LicenseID             *uuid.UUID `gorm:"type:uuid;index"`
	StripePaymentIntentID *string    `gorm:"size:255;index"`
	StripeSubscriptionID  *string    `gorm:"size:255;index"`
	Brand                 string     `gorm:"not null;default:'ssvid';size:50;index:idx_invoices_brand"`
	ContactEmail          string     `gorm:"not null;size:255;index"`
	Status                string     `gorm:"not null;default:'open';size:20;index"` // open, paid, void, uncollectible
	AmountDueCents        int        `gorm:"not null"`
	AmountPaidCents       int        `gorm:"not null;default:0"`
	Currency              string     `gorm:"not null;default:'usd';size:10"`
	BillingReason         string     `gorm:"size:50"` // subscription_create, subscription_cycle, manual
	InvoicePDFURL         string     `gorm:"size:1000"`
	HostedInvoiceURL      string     `gorm:"size:1000"`
	PeriodStart           *time.Time
	PeriodEnd             *time.Time
	PaidAt                *time.Time
	CreatedAt             time.Time
	UpdatedAt             time.Time
}

func (i *Invoice) BeforeCreate(tx *gorm.DB) error {
	if i.ID == uuid.Nil {
		i.ID = uuid.New()
	}
	if i.Brand == "" {
		i.Brand = "ssvid"
	}
	if i.Status == "" {
		i.Status = "open"
	}
	if i.Currency == "" {
		i.Currency = "usd"
	}
	return nil
}
