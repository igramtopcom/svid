package service

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/dto"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/stripe/stripe-go/v81"
	billingportalsession "github.com/stripe/stripe-go/v81/billingportal/session"
	checkoutsession "github.com/stripe/stripe-go/v81/checkout/session"
	"github.com/stripe/stripe-go/v81/subscription"
	"gorm.io/gorm"
)

const (
	CheckoutSessionExpiry = 30 * time.Minute
)

var (
	ErrPaymentNotConfigured = errors.New("payment not configured")
	ErrInvalidBillingCycle   = errors.New("invalid billing cycle")
	ErrStripeError           = errors.New("stripe error")
	ErrNoStripeCustomer      = errors.New("no Stripe customer associated with this license")
)

type StripeService struct {
	cfg            *config.StripeConfig
	db             *gorm.DB
	licenseRepo    *repository.LicenseRepository
	txnRepo        *repository.TransactionRepository
	jwtSecret      string
	premiumService *PremiumService // back-reference, set after construction to break circular init
}

func NewStripeService(
	cfg *config.StripeConfig,
	db *gorm.DB,
	licenseRepo *repository.LicenseRepository,
	txnRepo *repository.TransactionRepository,
	jwtSecret string,
) *StripeService {
	return &StripeService{
		cfg:         cfg,
		db:          db,
		licenseRepo: licenseRepo,
		txnRepo:     txnRepo,
		jwtSecret:   jwtSecret,
	}
}

// SetPremiumService sets the back-reference to PremiumService.
// Called after both services are constructed to break circular init.
func (s *StripeService) SetPremiumService(ps *PremiumService) {
	s.premiumService = ps
}

// IsConfigured returns true if Stripe keys are set.
func (s *StripeService) IsConfigured() bool {
	return s.cfg.SecretKey != ""
}

// Config returns the StripeConfig. Used by maintenance tooling (InvoiceAudit)
// that needs the brand whitelist. Regular callers should use higher-level
// service methods.
func (s *StripeService) Config() *config.StripeConfig {
	return s.cfg
}

// CreateCheckoutSession creates a Stripe Checkout session.
// brand selects the correct Stripe price IDs and pricing ("svid" or "vidcombo").
func (s *StripeService) CreateCheckoutSession(deviceID uuid.UUID, req dto.CheckoutRequest, brand string) (*dto.CheckoutResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}

	// Check for duplicate idempotency key
	existing, err := s.txnRepo.FindByIdempotencyKey(req.IdempotencyKey)
	if err == nil && existing != nil {
		return nil, ErrDuplicatePayment
	}

	// Determine price ID based on brand
	priceID := s.resolvePriceID(req.BillingCycle, brand)
	if priceID == "" {
		return nil, ErrInvalidBillingCycle
	}

	// Lifetime = one-time payment, subscription = recurring
	mode := stripe.CheckoutSessionModeSubscription
	if IsLifetimePlan(req.BillingCycle) {
		mode = stripe.CheckoutSessionModePayment
	}

	// Create real Stripe Checkout session
	params := &stripe.CheckoutSessionParams{
		Mode: stripe.String(string(mode)),
		LineItems: []*stripe.CheckoutSessionLineItemParams{
			{
				Price:    stripe.String(priceID),
				Quantity: stripe.Int64(1),
			},
		},
		Metadata: map[string]string{
			"device_id":     deviceID.String(),
			"billing_cycle": req.BillingCycle,
			"brand":         brand,
		},
	}
	successURL := s.cfg.SuccessURL
	cancelURL := s.cfg.CancelURL
	if brand == "vidcombo" && s.cfg.VidComboSuccessURL != "" && s.cfg.VidComboCancelURL != "" {
		successURL = s.cfg.VidComboSuccessURL
		cancelURL = s.cfg.VidComboCancelURL
	}
	params.SuccessURL = stripe.String(successURL + "?session_id={CHECKOUT_SESSION_ID}")
	params.CancelURL = stripe.String(cancelURL)
	params.IdempotencyKey = stripe.String(req.IdempotencyKey)

	session, err := checkoutsession.New(params)
	if err != nil {
		logger.Log.Error().Err(err).Msg("Stripe checkout session creation failed")
		return nil, fmt.Errorf("%w: %v", ErrStripeError, err)
	}

	sessionID := session.ID
	expiresAt := time.Unix(session.ExpiresAt, 0)

	// Record pending transaction
	txn := &model.PaymentTransaction{
		DeviceID:        deviceID,
		Brand:           brand,
		IdempotencyKey:  req.IdempotencyKey,
		PaymentMethod:   "stripe",
		BillingCycle:    req.BillingCycle,
		AmountCents:     AmountCentsForBillingCycle(req.BillingCycle, brand),
		Currency:        "USD",
		Status:          "pending",
		StripeSessionID: &sessionID,
	}
	if err := s.txnRepo.Create(txn); err != nil {
		return nil, err
	}

	logger.Log.Info().
		Str("session_id", sessionID).
		Str("device_id", deviceID.String()).
		Str("billing_cycle", req.BillingCycle).
		Str("brand", brand).
		Msg("Stripe checkout session created")

	return &dto.CheckoutResponse{
		SessionID:   sessionID,
		CheckoutURL: session.URL,
		ExpiresAt:   expiresAt.Format(time.RFC3339),
	}, nil
}

// resolvePriceID returns the Stripe price ID for a given billing cycle and brand.
func (s *StripeService) resolvePriceID(billingCycle, brand string) string {
	if brand == "vidcombo" {
		switch billingCycle {
		case "monthly":
			return s.cfg.VidComboPriceMonthly
		case "semiannual":
			return s.cfg.VidComboPriceSemiannual
		case "yearly":
			return s.cfg.VidComboPriceYearly
		default:
			return ""
		}
	}
	// Svid (default)
	switch billingCycle {
	case "monthly":
		return s.cfg.PriceMonthly
	case "yearly":
		return s.cfg.PriceYearly
	case "lifetime", "lifetime1", "lifetime2", "lifetime3":
		return s.cfg.PriceLifetime
	default:
		return ""
	}
}

// CreateWebCheckoutSession creates a Stripe Checkout session from the public website.
// No device auth required — device_id is set to a nil UUID (web purchase).
// The user receives a license key after payment and activates it in the app.
// brand defaults to "svid" for web checkout (landing page is svid.app).
func (s *StripeService) CreateWebCheckoutSession(req dto.WebCheckoutRequest) (*dto.CheckoutResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}

	// Web checkout defaults to Svid (svid.app landing page)
	brand := "svid"

	priceID := s.resolvePriceID(req.BillingCycle, brand)
	if priceID == "" {
		return nil, ErrInvalidBillingCycle
	}

	mode := stripe.CheckoutSessionModeSubscription
	if IsLifetimePlan(req.BillingCycle) {
		mode = stripe.CheckoutSessionModePayment
	}

	params := &stripe.CheckoutSessionParams{
		Mode: stripe.String(string(mode)),
		LineItems: []*stripe.CheckoutSessionLineItemParams{
			{
				Price:    stripe.String(priceID),
				Quantity: stripe.Int64(1),
			},
		},
		SuccessURL: stripe.String(s.cfg.SuccessURL + "?session_id={CHECKOUT_SESSION_ID}"),
		CancelURL:  stripe.String(s.cfg.CancelURL),
		Metadata: map[string]string{
			"source":        "web",
			"billing_cycle": req.BillingCycle,
			"brand":         brand,
		},
	}

	session, err := checkoutsession.New(params)
	if err != nil {
		logger.Log.Error().Err(err).Msg("Stripe web checkout session creation failed")
		return nil, fmt.Errorf("%w: %v", ErrStripeError, err)
	}

	sessionID := session.ID

	// Record pending transaction so the webhook can find it and create a license.
	// Use uuid.Nil as device_id for web purchases (no device auth).
	txn := &model.PaymentTransaction{
		DeviceID:        uuid.Nil,
		Brand:           brand,
		IdempotencyKey:  uuid.New().String(),
		PaymentMethod:   "stripe",
		BillingCycle:    req.BillingCycle,
		AmountCents:     AmountCentsForBillingCycle(req.BillingCycle, brand),
		Currency:        "USD",
		Status:          "pending",
		StripeSessionID: &sessionID,
	}
	if err := s.txnRepo.Create(txn); err != nil {
		logger.Log.Error().Err(err).Msg("Failed to record web checkout transaction")
		return nil, err
	}

	logger.Log.Info().
		Str("session_id", sessionID).
		Str("billing_cycle", req.BillingCycle).
		Str("source", "web").
		Msg("Stripe web checkout session created")

	return &dto.CheckoutResponse{
		SessionID:   sessionID,
		CheckoutURL: session.URL,
		ExpiresAt:   time.Unix(session.ExpiresAt, 0).Format(time.RFC3339),
	}, nil
}

// WebVerifyPayment checks the status of a checkout session (no device auth required).
// Works for both web purchases (device_id = uuid.Nil) and app purchases (device_id set).
func (s *StripeService) WebVerifyPayment(sessionID string) (*dto.PaymentResultResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}

	txn, err := s.txnRepo.FindByStripeSessionID(sessionID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("session not found")
		}
		return nil, err
	}

	resp := &dto.PaymentResultResponse{
		Status:        txn.Status,
		SessionID:     sessionID,
		PaymentMethod: "stripe",
		BillingCycle:  txn.BillingCycle,
		CreatedAt:     txn.CreatedAt.Format(time.RFC3339),
	}

	if txn.Status == "completed" && txn.LicenseID != nil {
		license, err := s.licenseRepo.FindByID(*txn.LicenseID)
		if err == nil {
			resp.LicenseKey = license.LicenseKey
			resp.ExpiresAt = license.ExpiresAt.Format(time.RFC3339)
		}
	}

	return resp, nil
}

// VerifyPayment checks the status of a Stripe Checkout session.
func (s *StripeService) VerifyPayment(sessionID string, deviceID uuid.UUID) (*dto.PaymentResultResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}

	txn, err := s.txnRepo.FindByStripeSessionID(sessionID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("session not found")
		}
		return nil, err
	}

	// Validate device ownership
	if txn.DeviceID != deviceID {
		return nil, errors.New("session not found")
	}

	// Query Stripe for real-time session status
	var stripeSession *stripe.CheckoutSession
	session, err := checkoutsession.Get(sessionID, nil)
	if err != nil {
		logger.Log.Warn().Err(err).Str("session_id", sessionID).Msg("Failed to fetch Stripe session, using local status")
	} else {
		stripeSession = session
		// Update local transaction status based on Stripe
		switch session.PaymentStatus {
		case stripe.CheckoutSessionPaymentStatusPaid:
			// Use the shared deduped method — prevents race with webhook
			opts := LicenseCreationOpts{
				AmountCents: int(session.AmountTotal),
				Currency:    strings.ToUpper(string(session.Currency)),
			}
			if session.Customer != nil {
				opts.StripeCustomerID = &session.Customer.ID
			}
			if session.Subscription != nil {
				opts.StripeSubscriptionID = &session.Subscription.ID
			}
			if session.PaymentIntent != nil {
				opts.StripePaymentIntentID = &session.PaymentIntent.ID
			}
			// Persist customer email so restore-by-email works even when the
			// verify-poll wins the race vs the webhook delivery.
			// Lifetime plans never receive invoice.paid (no renewal), so
			// without this, lifetime buyers permanently lose restore-by-email
			// if verify-path created the license. Normalize at write side
			// per Round 4 ultra-review.
			if session.CustomerDetails != nil && session.CustomerDetails.Email != "" {
				normalized := strings.ToLower(strings.TrimSpace(session.CustomerDetails.Email))
				opts.ContactEmail = &normalized
			}

			license, _, fErr := s.premiumService.FindOrCreateLicenseForSession(sessionID, opts)
			if fErr != nil {
				logger.Log.Error().Err(fErr).Str("session_id", sessionID).
					Msg("Failed to find/create license in verify payment")
			} else {
				txn.Status = "completed"
				txn.LicenseID = &license.ID
			}
		case stripe.CheckoutSessionPaymentStatusUnpaid:
			if session.Status == stripe.CheckoutSessionStatusExpired {
				txn.Status = "cancelled"
				if err := s.txnRepo.Update(txn); err != nil {
					logger.Log.Error().Err(err).
						Str("session_id", sessionID).
						Msg("Failed to mark transaction as cancelled")
				}
			}
		}
	}

	resp := &dto.PaymentResultResponse{
		Status:        txn.Status,
		SessionID:     sessionID,
		PaymentMethod: "stripe",
		BillingCycle:  txn.BillingCycle,
		CreatedAt:     txn.CreatedAt.Format(time.RFC3339),
	}

	// Populate TransactionID from the Stripe payment intent
	if stripeSession != nil && stripeSession.PaymentIntent != nil {
		resp.TransactionID = stripeSession.PaymentIntent.ID
	}

	// Populate ErrorMessage for failed/cancelled payments
	if txn.Status == "failed" || txn.Status == "cancelled" {
		if stripeSession != nil && stripeSession.PaymentIntent != nil &&
			stripeSession.PaymentIntent.LastPaymentError != nil {
			resp.ErrorMessage = stripeSession.PaymentIntent.LastPaymentError.Msg
		} else if txn.Status == "cancelled" {
			resp.ErrorMessage = "Payment session expired"
		}
	}

	// If completed, include license info
	if txn.Status == "completed" && txn.LicenseID != nil {
		license, err := s.licenseRepo.FindByID(*txn.LicenseID)
		if err == nil {
			resp.LicenseKey = license.LicenseKey
			resp.ExpiresAt = license.ExpiresAt.Format(time.RFC3339)
		}
	}

	return resp, nil
}

// CancelSubscription cancels a Stripe subscription.
// deviceID is used to verify the requesting device is registered to the license.
func (s *StripeService) CancelSubscription(licenseKey string, deviceID uuid.UUID) error {
	if !s.IsConfigured() {
		return ErrPaymentNotConfigured
	}

	license, err := s.licenseRepo.FindByKey(licenseKey)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrLicenseNotFound
		}
		return err
	}

	// Verify the requesting device is registered to this license
	_, err = s.licenseRepo.FindLicenseDevice(license.ID, deviceID)
	if err != nil {
		return ErrLicenseNotFound
	}

	if license.CancelledAt != nil {
		return ErrAlreadyCancelled
	}

	// Set cancel_at_period_end instead of immediate cancellation.
	// The user keeps premium access until the current billing period ends.
	if license.StripeSubscriptionID != nil && *license.StripeSubscriptionID != "" {
		params := &stripe.SubscriptionParams{
			CancelAtPeriodEnd: stripe.Bool(true),
		}
		_, err := subscription.Update(*license.StripeSubscriptionID, params)
		if err != nil {
			logger.Log.Error().Err(err).
				Str("subscription_id", *license.StripeSubscriptionID).
				Msg("Failed to set cancel_at_period_end on Stripe subscription")
			return fmt.Errorf("%w: %v", ErrStripeError, err)
		}
	}

	// cancel_at_period_end semantics: user retains premium until ExpiresAt.
	// We MUST NOT set CancelledAt now — the canonical ActivePremiumLicenseSQL
	// + IsLicenseActiveAt predicates treat CancelledAt != nil as "fully
	// cancelled, restore should fail". User paid through end of period and
	// should still pass restore/portal checks. CancelledAt gets set by
	// handleSubscriptionDeleted webhook AT actual period end.
	// Broad ultra-review Round 8 catch (Codex 2026-05-21).
	license.IsAutoRenew = false

	if err := s.licenseRepo.Update(license); err != nil {
		return err
	}

	logger.Log.Info().
		Str("license_key", licenseKey).
		Msg("Stripe subscription cancel scheduled at period end")

	return nil
}

// CreatePortalSession creates a Stripe Billing Portal session.
// The portal allows users to manage their subscription: change plan, update
// payment method, view invoices, and cancel — all hosted by Stripe.
func (s *StripeService) CreatePortalSession(deviceID uuid.UUID, brand string) (*dto.PortalSessionResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}

	// Find the license for this device
	license, err := s.licenseRepo.FindByDeviceID(deviceID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}

	if license.StripeCustomerID == nil || *license.StripeCustomerID == "" {
		return nil, ErrNoStripeCustomer
	}

	// Determine return URL based on brand
	returnURL := s.cfg.SuccessURL
	if returnURL == "" {
		if brand == "vidcombo" {
			returnURL = "https://vidcombo.com"
		} else {
			returnURL = "https://svid.app"
		}
	}

	params := &stripe.BillingPortalSessionParams{
		Customer:  license.StripeCustomerID,
		ReturnURL: stripe.String(returnURL),
	}

	session, err := billingportalsession.New(params)
	if err != nil {
		logger.Log.Error().Err(err).
			Str("customer_id", *license.StripeCustomerID).
			Msg("Failed to create Stripe Billing Portal session")
		return nil, fmt.Errorf("%w: %v", ErrStripeError, err)
	}

	logger.Log.Info().
		Str("device_id", deviceID.String()).
		Str("customer_id", *license.StripeCustomerID).
		Msg("Stripe Billing Portal session created")

	return &dto.PortalSessionResponse{URL: session.URL}, nil
}

// CreatePortalSessionForLicense creates a Stripe Billing Portal session for a
// known license ID. Used by the W1.2/W1.3 magic-link redemption path after
// the token's identity claims have been verified — the license is already
// authenticated by the signed token, so this skips the device/email lookup
// that the other two variants need.
func (s *StripeService) CreatePortalSessionForLicense(licenseID uuid.UUID) (*dto.PortalSessionResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}
	license, err := s.licenseRepo.FindByID(licenseID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}
	if license.StripeCustomerID == nil || *license.StripeCustomerID == "" {
		return nil, ErrNoStripeCustomer
	}

	returnURL := "https://svid.app/account"
	if license.Brand == "vidcombo" {
		returnURL = "https://vidcombo.com"
	}
	params := &stripe.BillingPortalSessionParams{
		Customer:  license.StripeCustomerID,
		ReturnURL: stripe.String(returnURL),
	}
	session, err := billingportalsession.New(params)
	if err != nil {
		logger.Log.Error().Err(err).
			Str("customer_id", *license.StripeCustomerID).
			Msg("Failed to create Stripe Billing Portal session (magic-link)")
		return nil, fmt.Errorf("%w: %v", ErrStripeError, err)
	}
	logger.Log.Info().
		Str("license_id", licenseID.String()).
		Str("customer_id", *license.StripeCustomerID).
		Msg("Stripe Billing Portal session created (magic-link)")
	return &dto.PortalSessionResponse{URL: session.URL}, nil
}

// CreatePortalSessionByEmail creates a Stripe Billing Portal session using email lookup.
// Used by the landing page where device auth is not available.
func (s *StripeService) CreatePortalSessionByEmail(email string) (*dto.PortalSessionResponse, error) {
	if !s.IsConfigured() {
		return nil, ErrPaymentNotConfigured
	}

	// Stripe portal lookup is brand-agnostic: any license with a
	// Stripe customer_id can manage the underlying subscription, regardless
	// of which brand stamped the record. So we pass empty brand here.
	license, err := s.licenseRepo.FindActiveByEmail(email, "")
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}

	if license.StripeCustomerID == nil || *license.StripeCustomerID == "" {
		return nil, ErrNoStripeCustomer
	}

	returnURL := "https://svid.app/account"
	if license.Brand == "vidcombo" {
		returnURL = "https://vidcombo.com"
	}

	params := &stripe.BillingPortalSessionParams{
		Customer:  license.StripeCustomerID,
		ReturnURL: stripe.String(returnURL),
	}

	session, err := billingportalsession.New(params)
	if err != nil {
		logger.Log.Error().Err(err).
			Str("customer_id", *license.StripeCustomerID).
			Msg("Failed to create Stripe Billing Portal session (web)")
		return nil, fmt.Errorf("%w: %v", ErrStripeError, err)
	}

	logger.Log.Info().
		Str("email", email).
		Str("customer_id", *license.StripeCustomerID).
		Msg("Stripe Billing Portal session created (web)")

	return &dto.PortalSessionResponse{URL: session.URL}, nil
}
