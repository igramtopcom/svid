package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/snakeloader/backend/internal/premium/service"
	"github.com/snakeloader/backend/internal/response"
	stripecharge "github.com/stripe/stripe-go/v81/charge"
	"gorm.io/gorm"
)

// chargeResolver is overridable in tests so we don't make real Stripe API
// calls. Production uses stripecharge.Get; tests inject a fake to return
// canned PaymentIntent values.
var chargeResolver = func(chargeID string) (string, error) {
	ch, err := stripecharge.Get(chargeID, nil)
	if err != nil {
		return "", err
	}
	if ch.PaymentIntent != nil {
		return ch.PaymentIntent.ID, nil
	}
	return "", nil
}

// WebhookHandler handles Stripe webhook events.
type WebhookHandler struct {
	cfg            *config.StripeConfig
	premiumService *service.PremiumService
	webhookRepo    *repository.WebhookEventRepository
	db             *gorm.DB
}

func NewWebhookHandler(cfg *config.StripeConfig, premiumSvc *service.PremiumService, webhookRepo *repository.WebhookEventRepository, db *gorm.DB) *WebhookHandler {
	return &WebhookHandler{cfg: cfg, premiumService: premiumSvc, webhookRepo: webhookRepo, db: db}
}

// StripeWebhook handles incoming Stripe webhook events.
// POST /api/v1/webhooks/stripe
func (h *WebhookHandler) StripeWebhook(c *gin.Context) {
	body, err := io.ReadAll(io.LimitReader(c.Request.Body, 65536))
	if err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_PAYLOAD", "Cannot read request body")
		return
	}

	// Reject all webhooks if secret is not configured (prevents forgery)
	if h.cfg.WebhookSecret == "" {
		response.Error(c, http.StatusServiceUnavailable, "WEBHOOK_NOT_CONFIGURED", "Webhook not configured")
		return
	}

	// Verify Stripe signature
	sig := c.GetHeader("Stripe-Signature")
	if !verifyStripeSignature(body, sig, h.cfg.WebhookSecret) {
		response.Error(c, http.StatusForbidden, "INVALID_SIGNATURE", "Webhook signature verification failed")
		return
	}

	var event stripeEvent
	if err := json.Unmarshal(body, &event); err != nil {
		response.Error(c, http.StatusBadRequest, "INVALID_JSON", "Cannot parse webhook event")
		return
	}

	// Idempotency: claim the event for processing.
	// Three outcomes:
	//   - Process: new claim or stale-reclaim → run the handler
	//   - Skip:    event already processed successfully → return 200
	//   - Retry:   another worker holds a fresh in-flight claim → return 409
	//             so Stripe retries within its 3-day redelivery window.
	//             Returning 200 here would risk permanent event loss if the
	//             lock-holder crashes before MarkCompleted (Round 9 catch).
	action, markErr := h.webhookRepo.MarkProcessing(event.ID, event.Type)
	if markErr != nil {
		// DB error - return 500 so Stripe retries
		logger.Log.Error().Err(markErr).Str("event_id", event.ID).Msg("DB error in idempotency check")
		response.Error(c, http.StatusInternalServerError, "DB_ERROR", "Database error")
		return
	}
	switch action {
	case repository.WebhookActionSkip:
		logger.Log.Debug().
			Str("event_id", event.ID).
			Str("event_type", event.Type).
			Msg("Duplicate webhook event — already processed")
		response.Success(c, http.StatusOK, gin.H{"received": true, "duplicate": true})
		return
	case repository.WebhookActionRetry:
		logger.Log.Info().
			Str("event_id", event.ID).
			Str("event_type", event.Type).
			Msg("Webhook event in-flight by another worker — signaling Stripe to retry")
		response.Error(c, http.StatusConflict, "EVENT_IN_FLIGHT", "Event currently being processed by another worker; retry")
		return
	case repository.WebhookActionProcess:
		// fallthrough to dispatch below
	}

	logger.Log.Info().
		Str("event_type", event.Type).
		Str("event_id", event.ID).
		Msg("Stripe webhook received")

	var processingErr error
	switch event.Type {
	case "checkout.session.completed":
		processingErr = h.handleCheckoutCompleted(event.Data.Raw)
	case "invoice.paid":
		processingErr = h.handleInvoicePaid(event.Data.Raw)
	case "customer.subscription.deleted":
		processingErr = h.handleSubscriptionDeleted(event.Data.Raw)
	case "charge.refunded":
		processingErr = h.handleChargeRefunded(event.Data.Raw)
	case "customer.subscription.updated":
		processingErr = h.handleSubscriptionUpdated(event.Data.Raw)
	case "charge.dispute.created":
		processingErr = h.handleChargeDispute(event.Data.Raw)
	case "charge.dispute.closed":
		processingErr = h.handleDisputeClosed(event.Data.Raw)
	case "invoice.payment_failed":
		processingErr = h.handleInvoicePaymentFailed(event.Data.Raw)
	case "invoice.finalized", "invoice.voided", "invoice.marked_uncollectible":
		processingErr = h.handleInvoiceStatusChange(event.Data.Raw)
	default:
		logger.Log.Debug().Str("event_type", event.Type).Msg("Unhandled webhook event type")
	}

	if processingErr != nil {
		logger.Log.Error().Err(processingErr).
			Str("event_id", event.ID).
			Str("event_type", event.Type).
			Msg("Webhook processing failed, marking as failed for retry")
		// Mark as "failed" so Stripe retry will reclaim and reprocess
		if failErr := h.webhookRepo.MarkFailed(event.ID); failErr != nil {
			logger.Log.Error().Err(failErr).Str("event_id", event.ID).
				Msg("CRITICAL: Failed to mark webhook event as failed")
		}
		// Return 500 so Stripe retries
		response.Error(c, http.StatusInternalServerError, "PROCESSING_FAILED", "Webhook processing failed")
		return
	}

	// Processing succeeded — mark as completed
	if completeErr := h.webhookRepo.MarkCompleted(event.ID); completeErr != nil {
		// Non-fatal: event was processed successfully, worst case is a redundant retry
		logger.Log.Error().Err(completeErr).Str("event_id", event.ID).
			Msg("Failed to mark webhook event as completed (event was processed successfully)")
	}

	response.Success(c, http.StatusOK, gin.H{"received": true})
}

func (h *WebhookHandler) handleCheckoutCompleted(raw json.RawMessage) error {
	var session checkoutSession
	if err := json.Unmarshal(raw, &session); err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to parse checkout session")
		return fmt.Errorf("parse checkout session: %w", err)
	}

	if session.PaymentStatus != "paid" {
		return nil
	}

	// Check if our DB has this session at all (skip unknown sessions gracefully)
	txnRepo := h.premiumService.GetTransactionRepo()
	if _, err := txnRepo.FindByStripeSessionID(session.ID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil // Not our session, skip gracefully
		}
		return fmt.Errorf("find transaction: %w", err)
	}

	// Build metadata opts from the webhook payload
	opts := service.LicenseCreationOpts{
		AmountCents: session.AmountTotal,
		Currency:    strings.ToUpper(session.Currency),
	}
	if session.Customer != "" {
		opts.StripeCustomerID = &session.Customer
	}
	if session.Subscription != "" {
		opts.StripeSubscriptionID = &session.Subscription
	}
	if session.PaymentIntent != "" {
		opts.StripePaymentIntentID = &session.PaymentIntent
	}
	if session.CustomerDetails != nil && session.CustomerDetails.Email != "" {
		// Normalize at write side — Stripe preserves user-typed casing
		// ("John.Smith@Gmail.com") but our FindActiveByEmail lookup expects
		// lowercase. Without this normalize, every Stripe-purchased license
		// silently fails restore (Round 4 ultra-review catch). Use the shared
		// service.NormalizeEmail helper for consistency across write sites.
		normalized := service.NormalizeEmail(session.CustomerDetails.Email)
		opts.ContactEmail = &normalized
	}

	// Use the shared deduped method — prevents race with VerifyPayment
	_, _, err := h.premiumService.FindOrCreateLicenseForSession(session.ID, opts)
	if err != nil {
		logger.Log.Error().Err(err).Str("session_id", session.ID).Msg("Failed to find/create license from webhook")
		return fmt.Errorf("find or create license: %w", err)
	}

	return nil
}

func (h *WebhookHandler) handleInvoicePaid(raw json.RawMessage) error {
	var invoice stripeInvoice
	if err := json.Unmarshal(raw, &invoice); err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to parse invoice")
		return fmt.Errorf("parse invoice: %w", err)
	}

	// Multi-tenant filter: same Stripe account serves SSvid + VidCombo + legacy
	// products. Skip events whose price ID is not one of ours so we never persist
	// or attribute revenue from products owned by other backends.
	if _, ok := h.cfg.BrandFromPriceID(invoice.firstPriceID()); !ok {
		return nil
	}

	if invoice.Subscription == "" {
		return nil
	}

	licenseRepo := h.premiumService.GetLicenseRepo()
	license, err := licenseRepo.FindByStripeSubscriptionID(invoice.Subscription)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil // Not our subscription, skip gracefully
		}
		logger.Log.Error().Err(err).Str("subscription", invoice.Subscription).Msg("DB error finding license for renewal")
		return fmt.Errorf("find license: %w", err)
	}

	// Business-key idempotency for the LICENSE EXTENSION only (not for the
	// invoice record, which is upserted unconditionally below).
	//
	// handleInvoicePaid extends license.ExpiresAt via AddBillingCycleToTime —
	// a calendar INCREMENT, not a set. If a previous attempt crashed between
	// licenseRepo.Update and persistInvoiceRecord (or before MarkCompleted),
	// the next stale-reclaim retry would otherwise re-extend the license.
	//
	// Use license.ExpiresAt vs invoice.PeriodEnd as the idempotency signal
	// rather than invoice.PaidAt, because PaidAt is set only AFTER license
	// mutation — leaving a crash window. ExpiresAt is the mutation itself:
	// if it already covers this invoice's period, the period was already
	// applied. Lifetime plans (cycle = sentinel far-future) trivially cover
	// every invoice period and are skipped via IsLifetimePlan separately.
	alreadyCoversInvoice := false
	if invoice.PeriodEnd > 0 {
		periodEnd := time.Unix(invoice.PeriodEnd, 0)
		alreadyCoversInvoice = !license.ExpiresAt.Before(periodEnd)
	}

	// Skip-or-extend decision: layered guards from BOTH correctness improvements.
	//
	//   - Lifetime plans never renew (sentinel cycle covers every period).
	//   - subscription_create: Stripe fires invoice.paid immediately after
	//     checkout.session.completed; the initial billing period was already
	//     granted by FindOrCreateLicenseForSession. Extending again would
	//     double durations (yearly → 2y, semiannual → 12mo, etc.).
	//   - alreadyCoversInvoice: crash-retry idempotency — license.ExpiresAt
	//     already past invoice.PeriodEnd means a prior attempt already applied
	//     this period; skip the increment.
	//   - default: real renewal — extend the license.
	//
	// Entitlement mutation (Tier/IsAutoRenew/ExpiresAt/ContactEmail backfill +
	// licenseRepo.Update) MUST stay inside the default branch. Unconditional
	// mutation would resurrect refunded/cancelled licenses via a replayed
	// invoice.paid event.
	switch {
	case service.IsLifetimePlan(license.BillingCycle):
		// Lifetime plans don't renew. Still persist the invoice record below
		// (revenue dashboard needs it for one-off lifetime payments).
	case invoice.BillingReason == "subscription_create":
		// Initial subscription invoice — checkout.session.completed already
		// granted the first billing period. Skip extension to avoid doubling.
		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Str("stripe_invoice_id", invoice.ID).
			Msg("Skipping expiry extension for initial subscription invoice")
	case alreadyCoversInvoice:
		// License already extended past this invoice's period — retry after
		// crash; skip the increment. Still persist the invoice record below.
		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Str("stripe_invoice_id", invoice.ID).
			Time("license_expires_at", license.ExpiresAt).
			Msg("Invoice period already covered by license — skipping duplicate extend")
	default:
		// Calendar-based renewal via single source of truth.
		// Previously this had a 2-branch monthly/else=year if/else that silently
		// gave VidCombo semiannual renewals 12 months instead of 6, drifting the
		// license expiry off Stripe's actual billing cadence each cycle.
		if time.Now().After(license.ExpiresAt) {
			// Expired — renew from now
			license.ExpiresAt = service.AddBillingCycleToTime(time.Now(), license.BillingCycle)
		} else {
			// Still active — extend from current expiry (preserves unused time)
			license.ExpiresAt = service.AddBillingCycleToTime(license.ExpiresAt, license.BillingCycle)
		}
		// Restore premium tier in case the expiry scheduler already downgraded it
		license.Tier = "premium"
		license.IsAutoRenew = true
		// Reset expiry notification flag so it can fire again for the new period
		license.ExpiryNotifiedAt = nil
		// Backfill contact email from invoice if missing. Normalize via the
		// shared helper — Stripe preserves user-typed casing but our lookups
		// expect lowercase.
		if license.ContactEmail == nil && invoice.CustomerEmail != "" {
			normalized := service.NormalizeEmail(invoice.CustomerEmail)
			license.ContactEmail = &normalized
		}
		if err := licenseRepo.Update(license); err != nil {
			logger.Log.Error().Err(err).Msg("Failed to update license renewal")
			return fmt.Errorf("update license renewal: %w", err)
		}

		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Time("new_expiry", license.ExpiresAt).
			Msg("License renewed via invoice")
	}

	// Persist invoice record for admin dashboard. UNCONDITIONAL — revenue and
	// dashboard tracking apply to lifetime/skipped/renewed alike; no entitlement
	// effect, so safe outside the entitlement switch.
	h.persistInvoiceRecord(invoice, &license.ID, h.resolveBrandFromDevice(license.DeviceID))

	return nil
}

func (h *WebhookHandler) handleSubscriptionDeleted(raw json.RawMessage) error {
	var sub stripeSubscription
	if err := json.Unmarshal(raw, &sub); err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to parse subscription")
		return fmt.Errorf("parse subscription: %w", err)
	}

	licenseRepo := h.premiumService.GetLicenseRepo()
	license, err := licenseRepo.FindByStripeSubscriptionID(sub.ID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil // Not our subscription, skip gracefully
		}
		logger.Log.Error().Err(err).Str("subscription", sub.ID).Msg("DB error finding license for cancellation")
		return fmt.Errorf("find license: %w", err)
	}

	// Business-key idempotency: if already cancelled, no-op so a retried
	// subscription.deleted event doesn't overwrite the original CancelledAt
	// timestamp with a later "now".
	if license.CancelledAt != nil {
		return nil
	}

	now := time.Now()
	license.CancelledAt = &now
	license.IsAutoRenew = false
	if err := licenseRepo.Update(license); err != nil {
		logger.Log.Error().Err(err).Msg("Failed to cancel license")
		return fmt.Errorf("cancel license: %w", err)
	}

	logger.Log.Info().
		Str("license_key", license.LicenseKey).
		Msg("Subscription cancelled via webhook")
	return nil
}

// Stripe event structs (minimal — no stripe-go dependency)

type stripeEvent struct {
	ID   string          `json:"id"`
	Type string          `json:"type"`
	Data stripeEventData `json:"data"`
}

type stripeEventData struct {
	Raw json.RawMessage `json:"object"`
}

type checkoutSession struct {
	ID              string                  `json:"id"`
	PaymentStatus   string                  `json:"payment_status"`
	Customer        string                  `json:"customer"`
	Subscription    string                  `json:"subscription"`
	PaymentIntent   string                  `json:"payment_intent"`
	AmountTotal     int                     `json:"amount_total"`
	Currency        string                  `json:"currency"`
	CustomerDetails *checkoutCustomerDetails `json:"customer_details"`
}

type checkoutCustomerDetails struct {
	Email string `json:"email"`
}

type stripeInvoice struct {
	ID               string                `json:"id"`
	Subscription     string                `json:"subscription"`
	CustomerEmail    string                `json:"customer_email"`
	Status           string                `json:"status"`
	AmountDue        int                   `json:"amount_due"`
	AmountPaid       int                   `json:"amount_paid"`
	Currency         string                `json:"currency"`
	BillingReason    string                `json:"billing_reason"`
	InvoicePDF       string                `json:"invoice_pdf"`
	HostedInvoiceURL string                `json:"hosted_invoice_url"`
	PeriodStart      int64                 `json:"period_start,omitempty"`
	PeriodEnd        int64                 `json:"period_end,omitempty"`
	Lines            stripeInvoiceLines    `json:"lines"`
	PaymentIntent    string                `json:"payment_intent,omitempty"` // legacy top-level shape
	Payments         stripeInvoicePayments `json:"payments,omitempty"`       // current Invoice Payments shape
}

// stripeInvoicePayments mirrors invoice.payments.data[].payment.payment_intent
// from newer Stripe API versions. Top-level invoice.payment_intent was the
// legacy shape and is still emitted on most active webhooks; the nested form
// is what Stripe surfaces once an account opts into the Invoice Payments object.
// We accept both so a forced API-version upgrade doesn't silently break the
// W1.4 refund fallback chain.
type stripeInvoicePayments struct {
	Data []stripeInvoicePayment `json:"data"`
}

type stripeInvoicePayment struct {
	Payment stripeInvoicePaymentRef `json:"payment"`
}

type stripeInvoicePaymentRef struct {
	PaymentIntent string `json:"payment_intent"`
}

// effectivePaymentIntent returns the PaymentIntent for this invoice, preferring
// the legacy top-level field (current production shape) and falling back to
// the first nested invoice payment record. Returns "" if neither is set.
func (inv stripeInvoice) effectivePaymentIntent() string {
	if inv.PaymentIntent != "" {
		return inv.PaymentIntent
	}
	for _, p := range inv.Payments.Data {
		if p.Payment.PaymentIntent != "" {
			return p.Payment.PaymentIntent
		}
	}
	return ""
}

// stripeInvoiceLines mirrors invoice.lines.data[].price.id from Stripe payloads.
// Subscription invoices always have at least one line; we use the first line's
// price ID to attribute the invoice to a brand via StripeConfig.BrandFromPriceID.
type stripeInvoiceLines struct {
	Data []stripeInvoiceLine `json:"data"`
}

type stripeInvoiceLine struct {
	Price stripeInvoicePrice `json:"price"`
}

type stripeInvoicePrice struct {
	ID string `json:"id"`
}

// firstPriceID returns the price ID of the first line item, or "" if none.
func (inv stripeInvoice) firstPriceID() string {
	if len(inv.Lines.Data) == 0 {
		return ""
	}
	return inv.Lines.Data[0].Price.ID
}

type stripeSubscription struct {
	ID                 string `json:"id"`
	Status             string `json:"status"`
	Customer           string `json:"customer"`
	CancelAtPeriodEnd  bool   `json:"cancel_at_period_end"`
}

type stripeCharge struct {
	ID             string `json:"id"`
	PaymentIntent  string `json:"payment_intent"`
	Refunded       bool   `json:"refunded"`
	Amount         int    `json:"amount"`          // Total charge amount in cents
	AmountRefunded int    `json:"amount_refunded"` // Total refunded amount in cents
}

func (h *WebhookHandler) handleChargeRefunded(raw json.RawMessage) error {
	var charge stripeCharge
	if err := json.Unmarshal(raw, &charge); err != nil {
		return fmt.Errorf("parse charge: %w", err)
	}

	if charge.PaymentIntent == "" {
		return nil // No payment intent, skip
	}

	// Partial refund detection: only revoke license on full refund
	if charge.Amount > 0 && charge.AmountRefunded > 0 && charge.AmountRefunded < charge.Amount {
		logger.Log.Info().
			Str("charge_id", charge.ID).
			Int("amount", charge.Amount).
			Int("amount_refunded", charge.AmountRefunded).
			Msg("Partial refund detected — license retained")
		return nil
	}

	if err := h.revokeWithInvoiceFallback(charge.PaymentIntent, "refund"); err != nil {
		return fmt.Errorf("revoke license on refund: %w", err)
	}

	logger.Log.Info().
		Str("charge_id", charge.ID).
		Str("payment_intent", charge.PaymentIntent).
		Msg("License revoked due to full Stripe refund")
	return nil
}

// revokeWithInvoiceFallback runs the W1.4 lookup chain for refund-class events:
// transactions table first, invoices table second (resolving via license_id
// directly, or via subscription_id for orphan rows). Returns nil for the
// "neither path knew this charge" case (silently dropped — Stripe will not
// retry, and a refund on a non-tracked charge is a legitimate no-op).
// Propagates real DB errors so Stripe retries.
func (h *WebhookHandler) revokeWithInvoiceFallback(paymentIntent, reason string) error {
	err := h.premiumService.RevokeLicenseByPaymentIntent(paymentIntent, reason)
	if err == nil {
		return nil
	}
	if !errors.Is(err, service.ErrTransactionNotFound) {
		// ErrLicenseNotFound (txn exists but license_id is nil/missing) is
		// terminal — not "look elsewhere". Same for any wrapped DB error.
		if errors.Is(err, service.ErrLicenseNotFound) {
			return nil
		}
		return err
	}
	// Transaction-keyed path missed → try invoice-keyed path.
	err = h.premiumService.RevokeLicenseByInvoicePaymentIntent(paymentIntent, reason)
	if err == nil {
		return nil
	}
	if errors.Is(err, service.ErrLicenseNotFound) {
		return nil // genuinely not ours
	}
	return err
}

// restoreWithInvoiceFallback is the won-dispute mirror of
// revokeWithInvoiceFallback. Same fallback chain, opposite mutation.
func (h *WebhookHandler) restoreWithInvoiceFallback(paymentIntent, reason string) error {
	err := h.premiumService.RestoreLicenseByPaymentIntent(paymentIntent, reason)
	if err == nil {
		return nil
	}
	if !errors.Is(err, service.ErrTransactionNotFound) {
		if errors.Is(err, service.ErrLicenseNotFound) {
			return nil
		}
		return err
	}
	err = h.premiumService.RestoreLicenseByInvoicePaymentIntent(paymentIntent, reason)
	if err == nil {
		return nil
	}
	if errors.Is(err, service.ErrLicenseNotFound) {
		return nil
	}
	return err
}

// handleInvoicePaymentFailed handles failed subscription renewal payments.
// Marks the license as no longer auto-renewing so the expiry scheduler can downgrade it.
func (h *WebhookHandler) handleInvoicePaymentFailed(raw json.RawMessage) error {
	var invoice stripeInvoice
	if err := json.Unmarshal(raw, &invoice); err != nil {
		return fmt.Errorf("parse invoice: %w", err)
	}

	// Multi-tenant filter (see handleInvoicePaid).
	if _, ok := h.cfg.BrandFromPriceID(invoice.firstPriceID()); !ok {
		return nil
	}

	if invoice.Subscription == "" {
		return nil
	}

	licenseRepo := h.premiumService.GetLicenseRepo()
	license, err := licenseRepo.FindByStripeSubscriptionID(invoice.Subscription)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return fmt.Errorf("find license for failed invoice: %w", err)
	}

	// Disable auto-renew — the expiry scheduler will handle downgrade after grace period
	license.IsAutoRenew = false
	if err := licenseRepo.Update(license); err != nil {
		return fmt.Errorf("update license on payment failure: %w", err)
	}

	logger.Log.Warn().
		Str("license_key", license.LicenseKey).
		Str("subscription", invoice.Subscription).
		Msg("Subscription payment failed — auto-renew disabled")

	// Persist failed invoice record for admin dashboard
	h.persistInvoiceRecord(invoice, &license.ID, h.resolveBrandFromDevice(license.DeviceID))

	return nil
}

// handleInvoiceStatusChange handles invoice.finalized, invoice.voided, invoice.marked_uncollectible.
// Persists or updates the invoice record in our DB for admin visibility.
//
// The brand is resolved from the invoice line's price_id — NOT from the device
// or a hardcoded default. The same Stripe account serves multiple products
// (SSvid desktop, VidCombo desktop, legacy ssvid.net, legacy VidCombo PHP),
// and the previous "default to ssvid" behavior caused every unrelated invoice
// in the account to inflate the SSvid revenue dashboard.
func (h *WebhookHandler) handleInvoiceStatusChange(raw json.RawMessage) error {
	var invoice stripeInvoice
	if err := json.Unmarshal(raw, &invoice); err != nil {
		return fmt.Errorf("parse invoice: %w", err)
	}

	brand, ok := h.cfg.BrandFromPriceID(invoice.firstPriceID())
	if !ok {
		return nil
	}

	// Link to license if we have one for this subscription. License may not
	// exist yet when invoice.finalized fires before checkout.session.completed
	// is processed — that's fine, we still persist the invoice with the brand
	// from the price_id and link the license later when handleInvoicePaid runs.
	var licenseID *uuid.UUID
	if invoice.Subscription != "" {
		licenseRepo := h.premiumService.GetLicenseRepo()
		license, err := licenseRepo.FindByStripeSubscriptionID(invoice.Subscription)
		if err == nil && license != nil {
			licenseID = &license.ID
		}
	}

	h.persistInvoiceRecord(invoice, licenseID, brand)
	return nil
}

// resolveBrandFromDevice looks up the brand for a device by ID. Returns "ssvid" as default.
func (h *WebhookHandler) resolveBrandFromDevice(deviceID uuid.UUID) string {
	if deviceID == uuid.Nil || h.db == nil {
		return "ssvid"
	}
	var device struct{ Brand string }
	if err := h.db.Raw("SELECT brand FROM devices WHERE id = ?", deviceID).Scan(&device).Error; err == nil && device.Brand != "" {
		return device.Brand
	}
	return "ssvid"
}

// persistInvoiceRecord creates or updates an Invoice DB record from a Stripe invoice webhook.
// Non-fatal: errors are logged but don't block webhook processing.
func (h *WebhookHandler) persistInvoiceRecord(inv stripeInvoice, licenseID *uuid.UUID, brand string) {
	invoiceRepo := h.premiumService.GetInvoiceRepo()
	if invoiceRepo == nil {
		return
	}

	// Map Stripe status to our status (Stripe uses: draft, open, paid, void, uncollectible)
	status := inv.Status
	if status == "" {
		status = "open"
	}

	currency := inv.Currency
	if currency == "" {
		currency = "usd"
	}

	if brand == "" {
		brand = "ssvid"
	}

	record := &model.Invoice{
		StripeInvoiceID:  inv.ID,
		LicenseID:        licenseID,
		Brand:            brand,
		// Normalize email at write side so admin search by email is
		// consistent (Round 4 ultra-review catch). Use the shared
		// service.NormalizeEmail helper for parity with other write sites.
		ContactEmail:     service.NormalizeEmail(inv.CustomerEmail),
		Status:           status,
		AmountDueCents:   inv.AmountDue,
		AmountPaidCents:  inv.AmountPaid,
		Currency:         strings.ToLower(currency),
		BillingReason:    inv.BillingReason,
		InvoicePDFURL:    inv.InvoicePDF,
		HostedInvoiceURL: inv.HostedInvoiceURL,
	}

	// W1.4 refund/dispute fallback fingerprints. Both legs of the lookup chain
	// (invoice→PI, invoice→subscription→license) depend on these being set on
	// every persisted row, including the renewal-only invoices that bypass our
	// checkout flow.
	if pi := inv.effectivePaymentIntent(); pi != "" {
		record.StripePaymentIntentID = &pi
	}
	if inv.Subscription != "" {
		sub := inv.Subscription
		record.StripeSubscriptionID = &sub
	}

	if inv.PeriodStart > 0 {
		t := time.Unix(inv.PeriodStart, 0)
		record.PeriodStart = &t
	}
	if inv.PeriodEnd > 0 {
		t := time.Unix(inv.PeriodEnd, 0)
		record.PeriodEnd = &t
	}
	if status == "paid" {
		now := time.Now()
		record.PaidAt = &now
	}

	// Upsert: update if exists, create if new
	existing, err := invoiceRepo.FindByStripeInvoiceID(inv.ID)
	if err == nil && existing != nil {
		// Update existing record
		existing.Status = record.Status
		existing.AmountPaidCents = record.AmountPaidCents
		existing.InvoicePDFURL = record.InvoicePDFURL
		existing.HostedInvoiceURL = record.HostedInvoiceURL
		existing.PaidAt = record.PaidAt
		if existing.ContactEmail == "" && record.ContactEmail != "" {
			// record.ContactEmail already normalized above. Safe to copy.
			existing.ContactEmail = record.ContactEmail
		}
		// Backfill fallback fingerprints if a later event finally surfaces them
		// (e.g. invoice.finalized arrived with empty PI, invoice.paid carries it).
		if existing.StripePaymentIntentID == nil && record.StripePaymentIntentID != nil {
			existing.StripePaymentIntentID = record.StripePaymentIntentID
		}
		if existing.StripeSubscriptionID == nil && record.StripeSubscriptionID != nil {
			existing.StripeSubscriptionID = record.StripeSubscriptionID
		}
		if err := invoiceRepo.Update(existing); err != nil {
			logger.Log.Warn().Err(err).Str("stripe_invoice_id", inv.ID).Msg("Failed to update invoice record")
		}
	} else {
		// Create new record
		if err := invoiceRepo.Create(record); err != nil {
			logger.Log.Warn().Err(err).Str("stripe_invoice_id", inv.ID).Msg("Failed to create invoice record")
		}
	}
}

func (h *WebhookHandler) handleChargeDispute(raw json.RawMessage) error {
	// Dispute event wraps a dispute object with a charge field
	var dispute struct {
		ID            string `json:"id"`
		PaymentIntent string `json:"payment_intent"`
		Charge        string `json:"charge"`
	}
	if err := json.Unmarshal(raw, &dispute); err != nil {
		return fmt.Errorf("parse dispute: %w", err)
	}

	// Per Stripe docs, dispute.payment_intent CAN be null when the dispute
	// is on a charge-only object (legacy Charges API or certain payment
	// methods). Resolve via charge.Retrieve so the revoke path still works.
	pi := dispute.PaymentIntent
	if pi == "" {
		if dispute.Charge == "" {
			return fmt.Errorf("dispute %s has empty payment_intent AND empty charge", dispute.ID)
		}
		resolved, err := chargeResolver(dispute.Charge)
		if err != nil {
			return fmt.Errorf("resolve charge %s for empty-PI dispute: %w", dispute.Charge, err)
		}
		if resolved == "" {
			return fmt.Errorf("charge %s resolves to empty payment_intent for dispute %s", dispute.Charge, dispute.ID)
		}
		pi = resolved
	}

	if err := h.revokeWithInvoiceFallback(pi, "chargeback"); err != nil {
		return fmt.Errorf("revoke license on dispute: %w", err)
	}

	logger.Log.Warn().
		Str("dispute_id", dispute.ID).
		Str("payment_intent", pi).
		Msg("License revoked due to chargeback — investigate immediately")
	return nil
}

// handleSubscriptionUpdated handles subscription changes like cancellation scheduling or reactivation.
// Updates IsAutoRenew based on cancel_at_period_end and subscription status.
func (h *WebhookHandler) handleSubscriptionUpdated(raw json.RawMessage) error {
	var sub stripeSubscription
	if err := json.Unmarshal(raw, &sub); err != nil {
		return fmt.Errorf("parse subscription: %w", err)
	}

	licenseRepo := h.premiumService.GetLicenseRepo()
	license, err := licenseRepo.FindByStripeSubscriptionID(sub.ID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil // Not our subscription, skip gracefully
		}
		return fmt.Errorf("find license for subscription update: %w", err)
	}

	updated := false

	// User scheduled cancellation at period end
	if sub.CancelAtPeriodEnd && license.IsAutoRenew {
		license.IsAutoRenew = false
		updated = true
		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Str("subscription", sub.ID).
			Msg("Subscription scheduled for cancellation at period end — auto-renew disabled")
	}

	// User reactivated subscription (un-cancelled before period end)
	if !sub.CancelAtPeriodEnd && sub.Status == "active" && !license.IsAutoRenew {
		license.IsAutoRenew = true
		updated = true
		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Str("subscription", sub.ID).
			Msg("Subscription reactivated — auto-renew re-enabled")
	}

	// Dunning: payment past due
	if sub.Status == "past_due" {
		logger.Log.Warn().
			Str("license_key", license.LicenseKey).
			Str("subscription", sub.ID).
			Str("customer", sub.Customer).
			Msg("Subscription entered dunning (past_due) — monitor for payment recovery")
	}

	if updated {
		if err := licenseRepo.Update(license); err != nil {
			return fmt.Errorf("update license on subscription change: %w", err)
		}
	}

	return nil
}

// handleDisputeClosed handles the resolution of a charge dispute.
// If we won the dispute, restores the license. If lost, just logs (already revoked on dispute.created).
func (h *WebhookHandler) handleDisputeClosed(raw json.RawMessage) error {
	var dispute struct {
		ID            string `json:"id"`
		Status        string `json:"status"`
		PaymentIntent string `json:"payment_intent"`
		Charge        string `json:"charge"`
	}
	if err := json.Unmarshal(raw, &dispute); err != nil {
		return fmt.Errorf("parse dispute: %w", err)
	}

	if dispute.Status == "won" {
		// We won the dispute — restore the license through the same fallback
		// chain the W1.4 revoke path uses, so renewal-only invoices that were
		// revoked on dispute.created actually get restored here.
		pi := dispute.PaymentIntent
		if pi == "" && dispute.Charge != "" {
			resolved, err := chargeResolver(dispute.Charge)
			if err != nil {
				return fmt.Errorf("resolve charge %s for won-dispute restore: %w", dispute.Charge, err)
			}
			pi = resolved
		}
		if pi == "" {
			logger.Log.Warn().Str("dispute_id", dispute.ID).Msg("Won dispute has no payment_intent (charge resolver returned empty), cannot restore license")
			return nil
		}

		if err := h.restoreWithInvoiceFallback(pi, "dispute_won"); err != nil {
			return fmt.Errorf("restore license after won dispute: %w", err)
		}

		logger.Log.Info().
			Str("dispute_id", dispute.ID).
			Str("payment_intent", pi).
			Msg("License restored — dispute won")
	} else if dispute.Status == "lost" {
		logger.Log.Warn().
			Str("dispute_id", dispute.ID).
			Str("payment_intent", dispute.PaymentIntent).
			Msg("Dispute lost — license remains revoked")
	}

	return nil
}

// verifyStripeSignature verifies the Stripe webhook signature using HMAC-SHA256.
// Also rejects replayed events older than 5 minutes.
func verifyStripeSignature(payload []byte, header, secret string) bool {
	if header == "" {
		return false
	}

	var timestamp, signature string
	for _, part := range strings.Split(header, ",") {
		kv := strings.SplitN(part, "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "t":
			timestamp = kv[1]
		case "v1":
			signature = kv[1]
		}
	}

	if timestamp == "" || signature == "" {
		return false
	}

	// Replay protection: reject events older than 5 minutes
	ts, err := strconv.ParseInt(timestamp, 10, 64)
	if err != nil {
		return false
	}
	if time.Since(time.Unix(ts, 0)) > 5*time.Minute {
		return false
	}

	signedPayload := timestamp + "." + string(payload)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signedPayload))
	expected := hex.EncodeToString(mac.Sum(nil))

	return hmac.Equal([]byte(expected), []byte(signature))
}
