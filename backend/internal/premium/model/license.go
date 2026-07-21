package model

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type PremiumLicense struct {
	ID                   uuid.UUID `gorm:"type:uuid;primaryKey"`
	DeviceID             uuid.UUID `gorm:"type:uuid;index;not null"`
	Brand                string    `gorm:"not null;default:'svid';size:20;index"`
	LicenseKey           string    `gorm:"uniqueIndex;not null;size:50"`
	Tier                 string    `gorm:"not null;default:'free';size:20"`
	BillingCycle         string    `gorm:"not null;size:20"`
	PaymentMethod        string    `gorm:"not null;size:20"`
	StripeCustomerID     *string   `gorm:"size:255"`
	StripeSubscriptionID *string   `gorm:"size:255"`
	IsAutoRenew          bool      `gorm:"default:true"`
	ExpiresAt            time.Time `gorm:"not null"`
	ContactEmail         *string   `gorm:"size:255"`
	ExpiryNotifiedAt     *time.Time
	CancelledAt          *time.Time
	CreatedBy            string `gorm:"size:36"` // Admin UUID who created (empty for system/webhook)
	UpdatedBy            string `gorm:"size:36"` // Admin UUID who last updated (empty for system/webhook)
	CreatedAt            time.Time
	UpdatedAt            time.Time
	LicenseDevices       []LicenseDevice `gorm:"foreignKey:LicenseID;constraint:OnDelete:CASCADE"`
}

func (l *PremiumLicense) BeforeCreate(tx *gorm.DB) error {
	if l.ID == uuid.Nil {
		l.ID = uuid.New()
	}
	if l.Tier == "" {
		l.Tier = "free"
	}
	return nil
}

// GenerateLicenseKey creates a brand-aware license key using HMAC-SHA256 with 128-bit entropy.
//
// Format per brand:
//   - svid:    SVID-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX    (44 chars)
//   - vidcombo: VIDCOMBO-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX  (48 chars)
//
// Brand is case-insensitive; prefix is always uppercase.
func GenerateLicenseKey(secret, brand string) string {
	raw := uuid.New().String()
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(raw))
	hash := hex.EncodeToString(mac.Sum(nil))[:32]

	prefix := brandKeyPrefix(brand)
	return fmt.Sprintf("%s-%s-%s-%s-%s-%s-%s-%s-%s",
		prefix,
		hash[0:4], hash[4:8], hash[8:12], hash[12:16],
		hash[16:20], hash[20:24], hash[24:28], hash[28:32])
}

// brandKeyPrefix returns the license key prefix for a brand.
func brandKeyPrefix(brand string) string {
	switch strings.ToLower(brand) {
	case "vidcombo":
		return "VIDCOMBO"
	default:
		return "SVID"
	}
}

// IsLifetimeBillingCycle reports whether the billing cycle is one of the
// non-expiring lifetime plans.
func IsLifetimeBillingCycle(billingCycle string) bool {
	switch strings.ToLower(strings.TrimSpace(billingCycle)) {
	case "lifetime", "lifetime1", "lifetime2", "lifetime3":
		return true
	default:
		return false
	}
}

// IsLicenseActiveAt applies the canonical premium-license activity semantics
// shared by dashboard, premium admin, and customer views.
func IsLicenseActiveAt(license *PremiumLicense, at time.Time) bool {
	if license == nil || license.Tier != "premium" || license.CancelledAt != nil {
		return false
	}
	return IsLifetimeBillingCycle(license.BillingCycle) || at.Before(license.ExpiresAt)
}

// ActivePremiumLicenseSQL returns the SQL predicate for an active premium
// license, using a single positional argument for the reference time.
func ActivePremiumLicenseSQL(alias string) string {
	prefix := ""
	if trimmed := strings.TrimSpace(alias); trimmed != "" {
		prefix = trimmed + "."
	}
	return prefix + "tier = 'premium' AND " + prefix + "cancelled_at IS NULL AND (" +
		prefix + "expires_at > ? OR " + prefix + "billing_cycle IN ('lifetime','lifetime1','lifetime2','lifetime3'))"
}

// ExpiredPremiumLicenseSQL returns the SQL predicate for an expired premium
// license. Lifetime plans are excluded because they do not expire.
func ExpiredPremiumLicenseSQL(alias string) string {
	prefix := ""
	if trimmed := strings.TrimSpace(alias); trimmed != "" {
		prefix = trimmed + "."
	}
	return prefix + "tier = 'premium' AND " + prefix + "cancelled_at IS NULL AND " +
		prefix + "billing_cycle NOT IN ('lifetime','lifetime1','lifetime2','lifetime3') AND " +
		prefix + "expires_at <= ?"
}
