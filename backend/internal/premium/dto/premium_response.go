package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/premium/model"
)

// PricingPlanResponse represents a single billing plan with pricing info.
type PricingPlanResponse struct {
	BillingCycle string `json:"billingCycle"`
	AmountCents  int    `json:"amountCents"`
	Currency     string `json:"currency"`
	Interval     string `json:"interval"`
	MaxDevices   int    `json:"maxDevices"`
	IsLifetime   bool   `json:"isLifetime"`
	DisplayName  string `json:"displayName"`
}

// PricingPlansResponse wraps plans with payment method availability.
type PricingPlansResponse struct {
	Plans         []PricingPlanResponse `json:"plans"`
	CryptoEnabled bool                  `json:"cryptoEnabled"`
}

// CheckoutResponse is returned when creating a Stripe Checkout session.
type CheckoutResponse struct {
	SessionID   string `json:"sessionId"`
	CheckoutURL string `json:"checkoutUrl"`
	ExpiresAt   string `json:"expiresAt"`
}

// PaymentResultResponse is returned when verifying a payment (Stripe or crypto).
type PaymentResultResponse struct {
	Status        string `json:"status"`
	SessionID     string `json:"sessionId,omitempty"`
	TransactionID string `json:"transactionId,omitempty"`
	LicenseKey    string `json:"licenseKey,omitempty"`
	PaymentMethod string `json:"paymentMethod"`
	BillingCycle  string `json:"billingCycle"`
	ExpiresAt     string `json:"expiresAt,omitempty"`
	ErrorMessage  string `json:"errorMessage,omitempty"`
	CreatedAt     string `json:"createdAt"`
}

// CryptoInvoiceResponse is returned when creating a crypto invoice.
type CryptoInvoiceResponse struct {
	InvoiceID     string `json:"invoiceId"`
	Currency      string `json:"currency"`
	Amount        string `json:"amount"`
	Address       string `json:"address"`
	PaymentURI    string `json:"paymentUri"`
	Confirmations int    `json:"confirmations"`
	ExpiresAt     string `json:"expiresAt"`
	CreatedAt     string `json:"createdAt"`
}

// PortalSessionResponse is returned when creating a Stripe Billing Portal session.
type PortalSessionResponse struct {
	URL string `json:"url"`
}

// LicenseVerifyResponse is returned when verifying a license key.
type LicenseVerifyResponse struct {
	IsValid      bool   `json:"is_valid"`
	Tier         string `json:"tier"`
	DeviceCount  int    `json:"device_count"`
	MaxDevices   int    `json:"max_devices"`
	BillingCycle string `json:"billing_cycle"`
	ExpiresAt    string `json:"expires_at"`
	IsAutoRenew  bool   `json:"is_auto_renew"`
	VerifiedAt   string `json:"verified_at,omitempty"`
	Reason       string `json:"reason,omitempty"`
}

// RestoreResponse is returned when restoring a license by email.
type RestoreResponse struct {
	LicenseKey   string `json:"license_key"`
	BillingCycle string `json:"billing_cycle"`
	ExpiresAt    string `json:"expires_at"`
}

// LicenseResponse is returned for admin license views.
type LicenseResponse struct {
	ID                   string  `json:"id"`
	DeviceID             string  `json:"device_id"`
	Brand                string  `json:"brand"`
	LicenseKey           string  `json:"license_key"`
	Tier                 string  `json:"tier"`
	BillingCycle         string  `json:"billing_cycle"`
	PaymentMethod        string  `json:"payment_method"`
	ContactEmail         *string `json:"contact_email,omitempty"`
	StripeCustomerID     *string `json:"stripe_customer_id,omitempty"`
	StripeSubscriptionID *string `json:"stripe_subscription_id,omitempty"`
	IsAutoRenew          bool    `json:"is_auto_renew"`
	ExpiresAt            string  `json:"expires_at"`
	CancelledAt          *string `json:"cancelled_at,omitempty"`
	CreatedBy            string  `json:"created_by,omitempty"`
	UpdatedBy            string  `json:"updated_by,omitempty"`
	CreatedAt            string  `json:"created_at"`
	UpdatedAt            string  `json:"updated_at"`
}

// TransactionResponse is returned for admin transaction views.
type TransactionResponse struct {
	ID              string  `json:"id"`
	LicenseID       *string `json:"license_id,omitempty"`
	DeviceID        string  `json:"device_id"`
	Brand           string  `json:"brand"`
	IdempotencyKey  string  `json:"idempotency_key"`
	PaymentMethod   string  `json:"payment_method"`
	BillingCycle    string  `json:"billing_cycle"`
	AmountCents     int     `json:"amount_cents"`
	Currency        string  `json:"currency"`
	Status          string  `json:"status"`
	StripeSessionID       *string `json:"stripe_session_id,omitempty"`
	StripePaymentIntentID *string `json:"stripe_payment_intent_id,omitempty"`
	CryptoInvoiceID       *string `json:"crypto_invoice_id,omitempty"`
	ErrorMessage    *string `json:"error_message,omitempty"`
	CompletedAt     *string `json:"completed_at,omitempty"`
	CreatedAt       string  `json:"created_at"`
	UpdatedAt       string  `json:"updated_at"`
}

// PremiumStatsResponse is returned for admin premium stats.
type PremiumStatsResponse struct {
	TotalLicenses    int64   `json:"total_licenses"`
	ActiveLicenses   int64   `json:"active_licenses"`
	ExpiredLicenses  int64   `json:"expired_licenses"`
	CancelledCount   int64   `json:"cancelled_count"`
	TotalRevenue     int64   `json:"total_revenue_cents"`
	MonthlyRevenue   int64   `json:"monthly_revenue_cents"`
	YearlyRevenue    int64   `json:"yearly_revenue_cents"`
	StripeCount      int64   `json:"stripe_count"`
	CryptoCount      int64   `json:"crypto_count"`
	ChurnRate        float64 `json:"churn_rate"`
}

// LicenseDeviceResponse is returned for device listings on a license.
type LicenseDeviceResponse struct {
	ID             string `json:"id"`
	LicenseID      string `json:"license_id"`
	DeviceID       string `json:"device_id"`
	DeviceName     string `json:"device_name,omitempty"`
	OS             string `json:"os,omitempty"`
	OSVersion      string `json:"os_version,omitempty"`
	AppVersion     string `json:"app_version,omitempty"`
	RegisteredAt   string `json:"registered_at"`
	LastVerifiedAt string `json:"last_verified_at"`
}

// LicenseDeviceToResponse converts a model to a DTO (without metadata).
func LicenseDeviceToResponse(ld *model.LicenseDevice) LicenseDeviceResponse {
	return LicenseDeviceResponse{
		ID:             ld.ID.String(),
		LicenseID:      ld.LicenseID.String(),
		DeviceID:       ld.DeviceID.String(),
		RegisteredAt:   ld.RegisteredAt.Format(time.RFC3339),
		LastVerifiedAt: ld.LastVerifiedAt.Format(time.RFC3339),
	}
}

// LicenseDevicesToResponse converts a slice of models to DTOs (without metadata).
func LicenseDevicesToResponse(devices []model.LicenseDevice) []LicenseDeviceResponse {
	result := make([]LicenseDeviceResponse, len(devices))
	for i, d := range devices {
		result[i] = LicenseDeviceToResponse(&d)
	}
	return result
}

// LicenseInfoResponse is returned for user-facing license info.
type LicenseInfoResponse struct {
	Tier          string                `json:"tier"`
	ExpiresAt     string                `json:"expires_at"`
	IsAutoRenew   bool                  `json:"is_auto_renew"`
	BillingCycle  string                `json:"billing_cycle"`
	PaymentMethod string                `json:"payment_method"`
	DeviceCount   int                   `json:"device_count"`
	MaxDevices    int                   `json:"max_devices"`
	LicenseKey    string                `json:"license_key"`
	CancelledAt   *string               `json:"cancelled_at,omitempty"`
	Devices       []LicenseDeviceResponse `json:"devices,omitempty"`
}

// LicenseToResponse converts a model to a DTO.
func LicenseToResponse(l *model.PremiumLicense) LicenseResponse {
	resp := LicenseResponse{
		ID:                   l.ID.String(),
		DeviceID:             l.DeviceID.String(),
		Brand:                l.Brand,
		LicenseKey:           l.LicenseKey,
		Tier:                 l.Tier,
		BillingCycle:         l.BillingCycle,
		PaymentMethod:        l.PaymentMethod,
		ContactEmail:         l.ContactEmail,
		StripeCustomerID:     l.StripeCustomerID,
		StripeSubscriptionID: l.StripeSubscriptionID,
		IsAutoRenew:          l.IsAutoRenew,
		ExpiresAt:            l.ExpiresAt.Format(time.RFC3339),
		CreatedBy:            l.CreatedBy,
		UpdatedBy:            l.UpdatedBy,
		CreatedAt:            l.CreatedAt.Format(time.RFC3339),
		UpdatedAt:            l.UpdatedAt.Format(time.RFC3339),
	}
	if l.CancelledAt != nil {
		s := l.CancelledAt.Format(time.RFC3339)
		resp.CancelledAt = &s
	}
	return resp
}

// LicensesToResponse converts a slice of models to DTOs.
func LicensesToResponse(licenses []model.PremiumLicense) []LicenseResponse {
	result := make([]LicenseResponse, len(licenses))
	for i, l := range licenses {
		result[i] = LicenseToResponse(&l)
	}
	return result
}

// TransactionToResponse converts a model to a DTO.
func TransactionToResponse(t *model.PaymentTransaction) TransactionResponse {
	resp := TransactionResponse{
		ID:                    t.ID.String(),
		DeviceID:              t.DeviceID.String(),
		Brand:                 t.Brand,
		IdempotencyKey:        t.IdempotencyKey,
		PaymentMethod:         t.PaymentMethod,
		BillingCycle:          t.BillingCycle,
		AmountCents:           t.AmountCents,
		Currency:              t.Currency,
		Status:                t.Status,
		StripeSessionID:       t.StripeSessionID,
		StripePaymentIntentID: t.StripePaymentIntentID,
		CryptoInvoiceID:       t.CryptoInvoiceID,
		ErrorMessage:          t.ErrorMessage,
		CreatedAt:             t.CreatedAt.Format(time.RFC3339),
		UpdatedAt:             t.UpdatedAt.Format(time.RFC3339),
	}
	if t.LicenseID != nil {
		s := t.LicenseID.String()
		resp.LicenseID = &s
	}
	if t.CompletedAt != nil {
		s := t.CompletedAt.Format(time.RFC3339)
		resp.CompletedAt = &s
	}
	return resp
}

// TransactionsToResponse converts a slice of models to DTOs.
func TransactionsToResponse(txns []model.PaymentTransaction) []TransactionResponse {
	result := make([]TransactionResponse, len(txns))
	for i, t := range txns {
		result[i] = TransactionToResponse(&t)
	}
	return result
}

// --- Enhanced DTOs for Business Dashboard ---

// EnhancedTransactionResponse includes linked license data (email, key).
type EnhancedTransactionResponse struct {
	TransactionResponse
	ContactEmail *string `json:"contact_email,omitempty"`
	LicenseKey   *string `json:"license_key,omitempty"`
}

// TransactionStatsResponse contains aggregate transaction statistics.
type TransactionStatsResponse struct {
	TotalTransactions int64            `json:"total_transactions"`
	TotalRevenue      int64            `json:"total_revenue_cents"`
	RevenueToday      int64            `json:"revenue_today_cents"`
	RevenueThisMonth  int64            `json:"revenue_this_month_cents"`
	ByStatus          map[string]int64 `json:"by_status"`
}

// SubscriptionResponse represents a subscription view of a license.
type SubscriptionResponse struct {
	LicenseResponse
	Status      string `json:"status"` // active, cancelled, expired
	DeviceCount int    `json:"device_count"`
	MaxDevices  int    `json:"max_devices"`
}

// SubscriptionStatsResponse contains aggregate subscription statistics.
type SubscriptionStatsResponse struct {
	ActiveCount    int64   `json:"active_count"`
	CancelledCount int64   `json:"cancelled_count"`
	ExpiredCount   int64   `json:"expired_count"`
	TotalCount     int64   `json:"total_count"`
	MRR            int64   `json:"mrr_cents"`
	ChurnRate      float64 `json:"churn_rate"`
}

// CustomerResponse represents an aggregate customer view.
type CustomerResponse struct {
	ContactEmail     string  `json:"contact_email"`
	StripeCustomerID *string `json:"stripe_customer_id,omitempty"`
	LicenseCount     int64   `json:"license_count"`
	ActiveLicenses   int64   `json:"active_licenses"`
	TotalSpentCents  int64   `json:"total_spent_cents"`
	FirstPurchase    string  `json:"first_purchase"`
	LastPurchase     string  `json:"last_purchase"`
}

// CustomerDetailResponse includes full customer data with licenses and transactions.
type CustomerDetailResponse struct {
	CustomerResponse
	Licenses     []LicenseResponse              `json:"licenses"`
	Transactions []EnhancedTransactionResponse   `json:"transactions"`
}

// CustomerStatsResponse contains aggregate customer statistics.
type CustomerStatsResponse struct {
	TotalCustomers  int64 `json:"total_customers"`
	TotalRevenue    int64 `json:"total_revenue_cents"`
	AvgRevenue      int64 `json:"avg_revenue_cents"`
}

// RevenueReportResponse holds comprehensive revenue data for the report page.
type RevenueReportResponse struct {
	TotalRevenue     int64                    `json:"total_revenue_cents"`
	RevenueToday     int64                    `json:"revenue_today_cents"`
	RevenueThisMonth int64                    `json:"revenue_this_month_cents"`
	TotalRefunded    int64                    `json:"total_refunded_cents"`
	RefundCount      int64                    `json:"refund_count"`
	NetRevenue       int64                    `json:"net_revenue_cents"`
	ByMethod         []RevenueMethodBreakdown `json:"by_method"`
	ByCycle          []RevenueCycleBreakdown  `json:"by_cycle"`
	DailyRevenue     []DailyRevenuePoint      `json:"daily_revenue"`
}

// RevenueMethodBreakdown holds revenue for a payment method.
type RevenueMethodBreakdown struct {
	PaymentMethod string `json:"payment_method"`
	AmountCents   int64  `json:"amount_cents"`
	Count         int64  `json:"count"`
}

// RevenueCycleBreakdown holds revenue for a billing cycle.
type RevenueCycleBreakdown struct {
	BillingCycle string `json:"billing_cycle"`
	AmountCents  int64  `json:"amount_cents"`
	Count        int64  `json:"count"`
}

// DailyRevenuePoint holds revenue for a single day.
type DailyRevenuePoint struct {
	Date        string `json:"date"`
	AmountCents int64  `json:"amount_cents"`
	Count       int64  `json:"count"`
}

// MRRPoint represents monthly recurring revenue for a single month.
type MRRPoint struct {
	Month       string `json:"month"`
	AmountCents int64  `json:"amount_cents"`
	Count       int    `json:"count"`
}

// InvoiceResponse represents an invoice for admin views.
type InvoiceResponse struct {
	ID               string  `json:"id"`
	StripeInvoiceID  string  `json:"stripe_invoice_id"`
	LicenseID        *string `json:"license_id,omitempty"`
	Brand            string  `json:"brand"`
	ContactEmail     string  `json:"contact_email"`
	Status           string  `json:"status"`
	AmountDueCents   int     `json:"amount_due_cents"`
	AmountPaidCents  int     `json:"amount_paid_cents"`
	Currency         string  `json:"currency"`
	BillingReason    string  `json:"billing_reason"`
	InvoicePDFURL    string  `json:"invoice_pdf_url,omitempty"`
	HostedInvoiceURL string  `json:"hosted_invoice_url,omitempty"`
	PeriodStart      *string `json:"period_start,omitempty"`
	PeriodEnd        *string `json:"period_end,omitempty"`
	PaidAt           *string `json:"paid_at,omitempty"`
	CreatedAt        string  `json:"created_at"`
	UpdatedAt        string  `json:"updated_at"`
}

// InvoiceToResponse converts a model to a DTO.
func InvoiceToResponse(inv *model.Invoice) InvoiceResponse {
	resp := InvoiceResponse{
		ID:               inv.ID.String(),
		StripeInvoiceID:  inv.StripeInvoiceID,
		Brand:            inv.Brand,
		ContactEmail:     inv.ContactEmail,
		Status:           inv.Status,
		AmountDueCents:   inv.AmountDueCents,
		AmountPaidCents:  inv.AmountPaidCents,
		Currency:         inv.Currency,
		BillingReason:    inv.BillingReason,
		InvoicePDFURL:    inv.InvoicePDFURL,
		HostedInvoiceURL: inv.HostedInvoiceURL,
		CreatedAt:        inv.CreatedAt.Format(time.RFC3339),
		UpdatedAt:        inv.UpdatedAt.Format(time.RFC3339),
	}
	if inv.LicenseID != nil {
		s := inv.LicenseID.String()
		resp.LicenseID = &s
	}
	if inv.PeriodStart != nil {
		s := inv.PeriodStart.Format(time.RFC3339)
		resp.PeriodStart = &s
	}
	if inv.PeriodEnd != nil {
		s := inv.PeriodEnd.Format(time.RFC3339)
		resp.PeriodEnd = &s
	}
	if inv.PaidAt != nil {
		s := inv.PaidAt.Format(time.RFC3339)
		resp.PaidAt = &s
	}
	return resp
}

// InvoicesToResponse converts a slice of invoices to DTOs.
func InvoicesToResponse(invoices []model.Invoice) []InvoiceResponse {
	result := make([]InvoiceResponse, len(invoices))
	for i, inv := range invoices {
		result[i] = InvoiceToResponse(&inv)
	}
	return result
}

// InvoiceStatsResponse contains aggregate invoice statistics.
type InvoiceStatsResponse struct {
	TotalInvoices int64            `json:"total_invoices"`
	TotalPaid     int64            `json:"total_paid_cents"`
	ByStatus      map[string]int64 `json:"by_status"`
}

// GlobalSearchResponse holds search results across all categories.
type GlobalSearchResponse struct {
	Licenses     []LicenseResponse              `json:"licenses"`
	Transactions []EnhancedTransactionResponse   `json:"transactions"`
	Customers    []CustomerResponse              `json:"customers"`
}
