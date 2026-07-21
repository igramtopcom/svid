package dto

import "time"

// CheckoutRequest creates a Stripe Checkout session.
type CheckoutRequest struct {
	BillingCycle   string `json:"billingCycle" binding:"required,oneof=monthly semiannual yearly lifetime lifetime1 lifetime2 lifetime3"`
	IdempotencyKey string `json:"idempotencyKey" binding:"required,uuid"`
}

// WebCheckoutRequest creates a Stripe Checkout session from the public website (no device auth).
type WebCheckoutRequest struct {
	BillingCycle string `json:"billingCycle" binding:"required,oneof=monthly semiannual yearly lifetime lifetime1 lifetime2 lifetime3"`
}

// CancelRequest cancels a Stripe subscription.
type CancelRequest struct {
	// Length spans both Go-backend key formats: SVID- (44) and VIDCOMBO- (48).
	LicenseKey string `json:"licenseKey" binding:"required,min=44,max=48"`
}

// CryptoInvoiceRequest creates a BTCPay crypto invoice.
type CryptoInvoiceRequest struct {
	Currency       string `json:"currency" binding:"required,oneof=BTC LTC XMR"`
	BillingCycle   string `json:"billingCycle" binding:"required,oneof=monthly semiannual yearly lifetime lifetime1 lifetime2 lifetime3"`
	IdempotencyKey string `json:"idempotencyKey" binding:"required,uuid"`
}

// AdminUpdateLicenseRequest allows admin to update a license.
type AdminUpdateLicenseRequest struct {
	Tier        *string `json:"tier,omitempty" binding:"omitempty,oneof=free premium"`
	IsAutoRenew *bool   `json:"is_auto_renew,omitempty"`
	ExpiresAt   *string `json:"expires_at,omitempty"`
	CancelledAt *string `json:"cancelled_at,omitempty"`
}

// RefundRequest is the optional body for admin refund endpoint.
type RefundRequest struct {
	CancelLicense bool `json:"cancel_license"`
}

// RestoreRequest allows a user to restore their license by email.
// device_id is optional: if provided, verifies the device was on the license.
// brand is optional but recommended: scopes lookup so a VidCombo build never
// receives an Svid-format license (or vice versa) for cross-brand customers.
type RestoreRequest struct {
	Email    string `json:"email" binding:"required,email"`
	DeviceID string `json:"device_id" binding:"omitempty,uuid"`
	Brand    string `json:"brand" binding:"omitempty,oneof=svid vidcombo"`
}

// WebPortalRequest is used by the landing page to open Stripe Billing Portal.
type WebPortalRequest struct {
	Email string `json:"email" binding:"required,email"`
}

// MagicLinkRequest is the issuance payload for the magic-link restore/portal
// endpoints. Only email is required — device_id MUST NOT be accepted from the
// body on these public routes (W1.2/W1.3 enumeration resistance).
type MagicLinkRequest struct {
	Email string `json:"email" binding:"required,email"`
}

// RedeemRequest carries a single-use magic-link token from the website landing
// page back to the redeem endpoint. Scope must match the claim's scope or the
// redeem fails — a token signed for "portal" cannot be redeemed as "restore".
type RedeemRequest struct {
	Token string `json:"token" binding:"required,min=20"`
	Scope string `json:"scope" binding:"required,oneof=restore portal"`
}

// AdminCreateLicenseRequest allows admin to create a manual/comp license.
type AdminCreateLicenseRequest struct {
	BillingCycle  string  `json:"billing_cycle" binding:"required,oneof=monthly semiannual yearly lifetime lifetime1 lifetime2 lifetime3"`
	ContactEmail  *string `json:"contact_email,omitempty" binding:"omitempty,email"`
	Brand         string  `json:"brand,omitempty"`
	Notes         string  `json:"notes,omitempty"`
}

// AdminImportLegacyLicenseRequest carries a pre-existing license record from
// the VidCombo PHP backend (api.vidcombo.net / quantri.vidcombo.com MySQL)
// into the Go backend so that paid users who originally bought through the
// vidcombo.net landing page (PHP-issued 32-hex license keys) can use the
// in-app "Restore by Email" flow without manual support intervention.
//
// Unlike [AdminCreateLicenseRequest], this endpoint:
//   - PRESERVES the existing PHP license_key verbatim (no key generation).
//     The user already has this key in their mailbox from the original
//     purchase; generating a new key would invalidate everything they have.
//   - Accepts only status='active' subscriptions (refunded / cancelled /
//     past_due rows must NOT enter the Go DB — that would silently restore
//     premium for users who lost entitlement).
//   - Forces brand='vidcombo' (the only brand with a legacy PHP backend).
//   - Sets payment_method='stripe_legacy' to keep PHP-origin records
//     distinguishable from in-app Stripe purchases in admin dashboards.
//   - Is idempotent: upsert on license_key so the ETL can be re-run safely.
type AdminImportLegacyLicenseRequest struct {
	// LicenseKey is the original PHP-issued 32-character hex string (case
	// preserved — PHP `strtoupper(bin2hex(random_bytes(16)))` so it arrives
	// uppercase, but we accept any case and normalize downstream).
	LicenseKey string `json:"license_key" binding:"required,len=32,hexadecimal"`

	// Brand. Only vidcombo is valid for this endpoint — PHP legacy is a
	// VidCombo-only concept.
	Brand string `json:"brand" binding:"required,oneof=vidcombo"`

	// Email of the customer (from PHP customers.email). Used to match
	// "Restore by Email" requests.
	Email string `json:"email" binding:"required,email"`

	// Plan tier from PHP subscriptions.plan column:
	//   plan1 → monthly, plan2 → semiannual, plan3 → yearly, lifetime → lifetime.
	// Any other value rejected — ETL must explicitly map upstream.
	Plan string `json:"plan" binding:"required,oneof=plan1 plan2 plan3 lifetime"`

	// ExpiresAt from PHP subscriptions.current_period_end. Lifetime plans
	// may pass a sentinel far-future value but it MUST be present.
	ExpiresAt time.Time `json:"expires_at" binding:"required"`

	// Status from PHP subscriptions.status — server-side validated to be
	// 'active' or 'trialing'. Refunded/cancelled/past_due rejected.
	Status string `json:"status" binding:"required,oneof=active trialing"`

	// StripeCustomerID from PHP customers.customer_id. Optional but
	// preserves Stripe billing portal continuity.
	StripeCustomerID *string `json:"stripe_customer_id,omitempty"`

	// StripeSubscriptionID from PHP subscriptions.subscription_id. Optional.
	StripeSubscriptionID *string `json:"stripe_subscription_id,omitempty"`
}
