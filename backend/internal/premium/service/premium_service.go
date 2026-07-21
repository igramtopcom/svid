package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/dto"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/stripe/stripe-go/v81"
	checkoutsession "github.com/stripe/stripe-go/v81/checkout/session"
	"github.com/stripe/stripe-go/v81/refund"
	"github.com/stripe/stripe-go/v81/subscription"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	MaxDevicesPerLicense = 3
	MonthlyDurationDays  = 30
	YearlyDurationDays   = 365
	PostExpiryGraceDays  = 7
)

// IsLifetimePlan returns true if the billing cycle is a lifetime plan.
func IsLifetimePlan(billingCycle string) bool {
	return model.IsLifetimeBillingCycle(billingCycle)
}

// AddBillingCycleToTime returns t advanced by one billing period for the given cycle.
// Used for both initial license expiration (base = time.Now()) and renewal extensions
// (base = current ExpiresAt, when renewing before the previous period ends).
//
// This is the single source of truth for license duration math. Previously the
// expiration calculation was inlined in 5 places and 4 of them were missing the
// `semiannual` branch — VidCombo semiannual subscribers ($29.34 / 6 months) silently
// got 365 days of premium, drifting their license expiry off Stripe's renewal cadence
// every billing cycle. Calling sites: CreateLicense, FindOrCreateLicenseForSession,
// FindOrCreateLicenseForCryptoInvoice, webhook handleInvoicePaid (renew + extend).
func AddBillingCycleToTime(t time.Time, billingCycle string) time.Time {
	switch billingCycle {
	case "lifetime", "lifetime1", "lifetime2", "lifetime3":
		return t.AddDate(100, 0, 0) // 100 years — effectively never expires
	case "monthly":
		return t.AddDate(0, 1, 0)
	case "semiannual":
		return t.AddDate(0, 6, 0)
	case "yearly":
		return t.AddDate(1, 0, 0)
	default:
		// Fail-safe: unknown cycles get 1 year. DTO validation already restricts
		// billing_cycle to known values, so this branch should be unreachable in
		// production — but we prefer "user keeps premium" over "user loses access"
		// if validation is ever bypassed (admin tools, tests, future cycles).
		return t.AddDate(1, 0, 0)
	}
}

// MaxDevicesForPlan returns the device limit for a given plan.
func MaxDevicesForPlan(billingCycle string) int {
	switch billingCycle {
	case "monthly", "semiannual", "lifetime", "lifetime1", "lifetime2", "lifetime3":
		return 5
	case "yearly":
		return 5
	default:
		return MaxDevicesPerLicense
	}
}

var (
	ErrLicenseNotFound     = errors.New("license not found")
	ErrLicenseExpired      = errors.New("license expired")
	ErrAlreadyCancelled    = errors.New("already cancelled")
	ErrDeviceLimitReached  = errors.New("device limit exceeded")
	ErrInvalidLicenseKey   = errors.New("invalid license key")
	ErrDuplicatePayment    = errors.New("duplicate payment")
	ErrDeviceNotFound      = errors.New("device not found on license")
	ErrCannotRemoveSelf    = errors.New("cannot remove your own device")
	ErrTransactionNotFound = errors.New("transaction not found")
	ErrNotRefundable       = errors.New("only completed transactions can be refunded")
)

type PremiumService struct {
	licenseRepo *repository.LicenseRepository
	txnRepo     *repository.TransactionRepository
	invoiceRepo *repository.InvoiceRepository
	jwtSecret   string
	stripe      *StripeService
	crypto      *CryptoService
}

func NewPremiumService(
	licenseRepo *repository.LicenseRepository,
	txnRepo *repository.TransactionRepository,
	jwtSecret string,
	stripe *StripeService,
	crypto *CryptoService,
) *PremiumService {
	return &PremiumService{
		licenseRepo: licenseRepo,
		txnRepo:     txnRepo,
		jwtSecret:   jwtSecret,
		stripe:      stripe,
		crypto:      crypto,
	}
}

// SetInvoiceRepo injects the invoice repository (avoids changing constructor signature for backward compat).
func (s *PremiumService) SetInvoiceRepo(repo *repository.InvoiceRepository) {
	s.invoiceRepo = repo
}

// VerifyLicense verifies a license key and registers the device if needed.
var legacyPhpKeyPattern = regexp.MustCompile(`^[0-9A-Z]{32}$`)

func (s *PremiumService) VerifyLicense(licenseKey string, deviceID uuid.UUID) (*dto.LicenseVerifyResponse, error) {
	license, err := s.licenseRepo.FindByKey(licenseKey)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			if legacyPhpKeyPattern.MatchString(licenseKey) {
				return s.verifyViaPhpCheckKey(licenseKey, deviceID)
			}
			return nil, ErrInvalidLicenseKey
		}
		return nil, err
	}

	// Lifetime plans never expire
	if !IsLifetimePlan(license.BillingCycle) {
		// Check expiry (with grace period)
		graceDeadline := license.ExpiresAt.Add(time.Duration(PostExpiryGraceDays) * 24 * time.Hour)
		if time.Now().After(graceDeadline) {
			return &dto.LicenseVerifyResponse{
				IsValid:      false,
				Tier:         license.Tier,
				BillingCycle: license.BillingCycle,
				ExpiresAt:    license.ExpiresAt.Format(time.RFC3339),
				IsAutoRenew:  license.IsAutoRenew,
			}, ErrLicenseExpired
		}
	}

	maxDevices := MaxDevicesForPlan(license.BillingCycle)

	// Try to register this device (atomic count+insert to prevent TOCTOU race)
	existing, findErr := s.licenseRepo.FindLicenseDevice(license.ID, deviceID)
	if findErr != nil && errors.Is(findErr, gorm.ErrRecordNotFound) {
		// New device — atomically check limit and register within a transaction
		ld := &model.LicenseDevice{
			LicenseID: license.ID,
			DeviceID:  deviceID,
		}
		if err := s.licenseRepo.RegisterDeviceWithLimit(ld, maxDevices); err != nil {
			if err.Error() == "device limit exceeded" {
				deviceCount, _ := s.licenseRepo.CountDevices(license.ID)
				return &dto.LicenseVerifyResponse{
					IsValid:      false,
					Tier:         license.Tier,
					DeviceCount:  int(deviceCount),
					MaxDevices:   maxDevices,
					BillingCycle: license.BillingCycle,
					ExpiresAt:    license.ExpiresAt.Format(time.RFC3339),
					IsAutoRenew:  license.IsAutoRenew,
				}, ErrDeviceLimitReached
			}
			return nil, err
		}
		logger.Log.Info().Str("license", licenseKey).Str("device", deviceID.String()).Msg("Device registered to license")

		// Sync device tier to match the license tier
		if license.Tier == "premium" {
			db := s.txnRepo.GetDB()
			if err := db.Table("devices").Where("id = ?", deviceID).Update("tier", "premium").Error; err != nil {
				logger.Log.Warn().Err(err).Str("device_id", deviceID.String()).Msg("Failed to sync device tier to premium")
			}
		}
	} else if findErr == nil {
		// Existing device — update verification time
		existing.LastVerifiedAt = time.Now()
		_ = s.licenseRepo.UpdateLicenseDevice(existing)
	}

	deviceCount, _ := s.licenseRepo.CountDevices(license.ID)
	isValid := license.Tier == "premium" && (IsLifetimePlan(license.BillingCycle) || time.Now().Before(license.ExpiresAt))

	return &dto.LicenseVerifyResponse{
		IsValid:      isValid,
		Tier:         license.Tier,
		DeviceCount:  int(deviceCount),
		MaxDevices:   maxDevices,
		BillingCycle: license.BillingCycle,
		ExpiresAt:    license.ExpiresAt.Format(time.RFC3339),
		IsAutoRenew:  license.IsAutoRenew,
	}, nil
}

// CreateLicense creates a premium license for a device after successful payment.
func (s *PremiumService) CreateLicense(deviceID uuid.UUID, billingCycle, paymentMethod string) (*model.PremiumLicense, error) {
	expiresAt := AddBillingCycleToTime(time.Now(), billingCycle)

	// Resolve brand from device
	brand := "ssvid"
	if deviceID != uuid.Nil {
		var deviceBrand struct{ Brand string }
		if err := s.txnRepo.GetDB().Raw("SELECT brand FROM devices WHERE id = ?", deviceID).Scan(&deviceBrand).Error; err == nil && deviceBrand.Brand != "" {
			brand = deviceBrand.Brand
		}
	}

	license := &model.PremiumLicense{
		DeviceID:      deviceID,
		Brand:         brand,
		LicenseKey:    model.GenerateLicenseKey(s.jwtSecret, brand),
		Tier:          "premium",
		BillingCycle:  billingCycle,
		PaymentMethod: paymentMethod,
		IsAutoRenew:   !IsLifetimePlan(billingCycle),
		ExpiresAt:     expiresAt,
	}

	if err := s.licenseRepo.Create(license); err != nil {
		return nil, err
	}

	// Register the purchasing device
	ld := &model.LicenseDevice{
		LicenseID: license.ID,
		DeviceID:  deviceID,
	}
	if err := s.licenseRepo.RegisterDevice(ld); err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to register device to new license")
	}

	// Sync device tier to "premium" in the devices table
	if deviceID != uuid.Nil {
		db := s.txnRepo.GetDB()
		if err := db.Table("devices").Where("id = ?", deviceID).Update("tier", "premium").Error; err != nil {
			logger.Log.Warn().Err(err).Str("device_id", deviceID.String()).Msg("Failed to sync device tier to premium")
		}
	}

	logger.Log.Info().
		Str("license_key", license.LicenseKey).
		Str("device_id", deviceID.String()).
		Str("billing_cycle", billingCycle).
		Str("brand", brand).
		Msg("Premium license created")

	return license, nil
}

// FindOrCreateLicenseForSession is the single entry point for creating a license
// from a completed Stripe checkout session. Both VerifyPayment and the webhook
// call this method, which uses a FOR UPDATE lock on the transaction row to prevent
// duplicate license creation from concurrent calls.
//
// Returns the license (existing or newly created) and whether a new one was created.
func (s *PremiumService) FindOrCreateLicenseForSession(stripeSessionID string, opts LicenseCreationOpts) (*model.PremiumLicense, bool, error) {
	var license *model.PremiumLicense
	created := false

	db := s.txnRepo.GetDB()
	err := db.Transaction(func(dbTx *gorm.DB) error {
		// Lock the transaction row to serialize concurrent webhook + verify calls
		var txn model.PaymentTransaction
		if err := dbTx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("stripe_session_id = ?", stripeSessionID).First(&txn).Error; err != nil {
			return fmt.Errorf("find transaction: %w", err)
		}

		// If license already created, return it — but backfill ContactEmail
		// if opts carries one and the stored row is still null/empty.
		// Pre-fix rows (verify-path created licenses before email was added
		// to opts) had ContactEmail=NULL forever, breaking restore-by-email
		// for lifetime buyers. Broad ultra-review Round 8 catch.
		if txn.LicenseID != nil {
			var existing model.PremiumLicense
			if err := dbTx.First(&existing, "id = ?", *txn.LicenseID).Error; err != nil {
				return fmt.Errorf("find existing license: %w", err)
			}
			if opts.ContactEmail != nil && *opts.ContactEmail != "" &&
				(existing.ContactEmail == nil || *existing.ContactEmail == "") {
				existing.ContactEmail = opts.ContactEmail
				if err := dbTx.Save(&existing).Error; err != nil {
					return fmt.Errorf("backfill contact email: %w", err)
				}
			}
			license = &existing
			return nil
		}

		// Create the license inside the same transaction
		expiresAt := AddBillingCycleToTime(time.Now(), txn.BillingCycle)

		// Resolve brand from device
		licenseBrand := "ssvid"
		if txn.DeviceID != uuid.Nil {
			var deviceBrand struct{ Brand string }
			if err := dbTx.Raw("SELECT brand FROM devices WHERE id = ?", txn.DeviceID).Scan(&deviceBrand).Error; err == nil && deviceBrand.Brand != "" {
				licenseBrand = deviceBrand.Brand
			}
		}

		newLicense := model.PremiumLicense{
			DeviceID:             txn.DeviceID,
			Brand:                licenseBrand,
			LicenseKey:           model.GenerateLicenseKey(s.jwtSecret, licenseBrand),
			Tier:                 "premium",
			BillingCycle:         txn.BillingCycle,
			PaymentMethod:        "stripe",
			IsAutoRenew:          !IsLifetimePlan(txn.BillingCycle),
			ExpiresAt:            expiresAt,
			StripeCustomerID:     opts.StripeCustomerID,
			StripeSubscriptionID: opts.StripeSubscriptionID,
			ContactEmail:         opts.ContactEmail,
		}
		// BeforeCreate hook sets ID if nil
		if err := dbTx.Create(&newLicense).Error; err != nil {
			return fmt.Errorf("create license: %w", err)
		}

		// Register purchasing device (inside same transaction)
		if txn.DeviceID != uuid.Nil {
			ld := model.LicenseDevice{
				LicenseID: newLicense.ID,
				DeviceID:  txn.DeviceID,
			}
			if err := dbTx.Create(&ld).Error; err != nil {
				logger.Log.Warn().Err(err).Msg("Failed to register device to new license")
			}
		}

		// Update transaction: mark completed, link license, store payment metadata
		now := time.Now()
		updates := map[string]interface{}{
			"status":       "completed",
			"license_id":   newLicense.ID,
			"completed_at": now,
		}
		if opts.AmountCents > 0 {
			updates["amount_cents"] = opts.AmountCents
		}
		if opts.Currency != "" {
			updates["currency"] = opts.Currency
		}
		if opts.StripePaymentIntentID != nil {
			updates["stripe_payment_intent_id"] = *opts.StripePaymentIntentID
		}
		if err := dbTx.Model(&txn).Updates(updates).Error; err != nil {
			return fmt.Errorf("update transaction: %w", err)
		}

		license = &newLicense
		created = true
		return nil
	})

	if err != nil {
		return nil, false, err
	}

	if created {
		// Sync device tier to "premium" in the devices table
		if license.DeviceID != uuid.Nil {
			if err := db.Table("devices").Where("id = ?", license.DeviceID).Update("tier", "premium").Error; err != nil {
				logger.Log.Warn().Err(err).Str("device_id", license.DeviceID.String()).Msg("Failed to sync device tier to premium")
			}
		}

		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Str("session_id", stripeSessionID).
			Str("device_id", license.DeviceID.String()).
			Msg("License created for Stripe session (deduped)")
	}

	return license, created, nil
}

// LicenseCreationOpts holds optional metadata to attach to the license and transaction
// when creating via FindOrCreateLicenseForSession.
type LicenseCreationOpts struct {
	StripeCustomerID      *string
	StripeSubscriptionID  *string
	ContactEmail          *string
	StripePaymentIntentID *string
	AmountCents           int
	Currency              string
}

// FindOrCreateLicenseForCryptoInvoice is the single entry point for creating a license
// from a completed crypto (BTCPay) invoice. Uses a FOR UPDATE lock on the transaction
// row to prevent duplicate license creation from concurrent polling calls.
//
// Returns the license (existing or newly created) and whether a new one was created.
func (s *PremiumService) FindOrCreateLicenseForCryptoInvoice(cryptoInvoiceID string, deviceID uuid.UUID) (*model.PremiumLicense, bool, error) {
	var license *model.PremiumLicense
	created := false

	db := s.txnRepo.GetDB()
	err := db.Transaction(func(dbTx *gorm.DB) error {
		// Lock the transaction row to serialize concurrent poll calls
		var txn model.PaymentTransaction
		if err := dbTx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("crypto_invoice_id = ?", cryptoInvoiceID).First(&txn).Error; err != nil {
			return fmt.Errorf("find transaction: %w", err)
		}

		// Validate device ownership
		if txn.DeviceID != deviceID {
			return errors.New("invoice not found")
		}

		// If license already created, return it. Crypto path has no opts,
		// no email backfill needed here (crypto doesn't capture email).
		if txn.LicenseID != nil {
			var existing model.PremiumLicense
			if err := dbTx.First(&existing, "id = ?", *txn.LicenseID).Error; err != nil {
				return fmt.Errorf("find existing license: %w", err)
			}
			license = &existing
			return nil
		}

		// Only create license if status is completed
		if txn.Status != "completed" {
			return nil
		}

		// Create the license inside the same transaction
		expiresAt := AddBillingCycleToTime(time.Now(), txn.BillingCycle)

		// Resolve brand from device
		cryptoBrand := "ssvid"
		if txn.DeviceID != uuid.Nil {
			var deviceBrand struct{ Brand string }
			if err := dbTx.Raw("SELECT brand FROM devices WHERE id = ?", txn.DeviceID).Scan(&deviceBrand).Error; err == nil && deviceBrand.Brand != "" {
				cryptoBrand = deviceBrand.Brand
			}
		}

		newLicense := model.PremiumLicense{
			DeviceID:      txn.DeviceID,
			Brand:         cryptoBrand,
			LicenseKey:    model.GenerateLicenseKey(s.jwtSecret, cryptoBrand),
			Tier:          "premium",
			BillingCycle:  txn.BillingCycle,
			PaymentMethod: "crypto",
			IsAutoRenew:   false, // Crypto payments are always one-time
			ExpiresAt:     expiresAt,
		}
		if err := dbTx.Create(&newLicense).Error; err != nil {
			return fmt.Errorf("create license: %w", err)
		}

		// Register purchasing device (inside same transaction)
		if txn.DeviceID != uuid.Nil {
			ld := model.LicenseDevice{
				LicenseID: newLicense.ID,
				DeviceID:  txn.DeviceID,
			}
			if err := dbTx.Create(&ld).Error; err != nil {
				logger.Log.Warn().Err(err).Msg("Failed to register device to new crypto license")
			}
		}

		// Update transaction: mark completed, link license
		now := time.Now()
		updates := map[string]interface{}{
			"license_id":   newLicense.ID,
			"completed_at": now,
		}
		if err := dbTx.Model(&txn).Updates(updates).Error; err != nil {
			return fmt.Errorf("update transaction: %w", err)
		}

		license = &newLicense
		created = true
		return nil
	})

	if err != nil {
		return nil, false, err
	}

	if created {
		// Sync device tier to "premium" in the devices table
		if license.DeviceID != uuid.Nil {
			if err := db.Table("devices").Where("id = ?", license.DeviceID).Update("tier", "premium").Error; err != nil {
				logger.Log.Warn().Err(err).Str("device_id", license.DeviceID.String()).Msg("Failed to sync device tier to premium")
			}
		}

		logger.Log.Info().
			Str("license_key", license.LicenseKey).
			Str("invoice_id", cryptoInvoiceID).
			Str("device_id", license.DeviceID.String()).
			Msg("License created for crypto invoice (deduped)")
	}

	return license, created, nil
}

// CancelLicense cancels a license's auto-renewal.
func (s *PremiumService) CancelLicense(licenseKey string) error {
	license, err := s.licenseRepo.FindByKey(licenseKey)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrLicenseNotFound
		}
		return err
	}

	if license.CancelledAt != nil {
		return ErrAlreadyCancelled
	}

	now := time.Now()
	license.CancelledAt = &now
	license.IsAutoRenew = false

	return s.licenseRepo.Update(license)
}

// GetStripeService returns the Stripe service.
func (s *PremiumService) GetStripeService() *StripeService {
	return s.stripe
}

// GetCryptoService returns the crypto service.
func (s *PremiumService) GetCryptoService() *CryptoService {
	return s.crypto
}

// GetTransactionRepo returns the transaction repository.
func (s *PremiumService) GetTransactionRepo() *repository.TransactionRepository {
	return s.txnRepo
}

// GetLicenseRepo returns the license repository.
func (s *PremiumService) GetLicenseRepo() *repository.LicenseRepository {
	return s.licenseRepo
}

// GetInvoiceRepo returns the invoice repository (may be nil).
func (s *PremiumService) GetInvoiceRepo() *repository.InvoiceRepository {
	return s.invoiceRepo
}

// --- User-facing methods ---

// GetMyTransactions returns paginated transactions for a device.
func (s *PremiumService) GetMyTransactions(deviceID uuid.UUID, page, perPage int) ([]dto.TransactionResponse, int64, error) {
	txns, total, err := s.txnRepo.FindByDeviceID(deviceID, page, perPage)
	if err != nil {
		return nil, 0, err
	}
	return dto.TransactionsToResponse(txns), total, nil
}

// GetLicenseInfo returns the active license info for a device, including device list.
func (s *PremiumService) GetLicenseInfo(deviceID uuid.UUID) (*dto.LicenseInfoResponse, error) {
	license, err := s.licenseRepo.FindByDeviceID(deviceID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}

	deviceCount, _ := s.licenseRepo.CountDevices(license.ID)

	resp := &dto.LicenseInfoResponse{
		Tier:          license.Tier,
		ExpiresAt:     license.ExpiresAt.Format(time.RFC3339),
		IsAutoRenew:   license.IsAutoRenew,
		BillingCycle:  license.BillingCycle,
		PaymentMethod: license.PaymentMethod,
		DeviceCount:   int(deviceCount),
		MaxDevices:    MaxDevicesForPlan(license.BillingCycle),
		LicenseKey:    license.LicenseKey,
	}
	if license.CancelledAt != nil {
		s := license.CancelledAt.Format(time.RFC3339)
		resp.CancelledAt = &s
	}

	return resp, nil
}

// GetMyDevices returns the device list for the license associated with a device,
// enriched with device metadata (name, OS, app version) from the identity table.
func (s *PremiumService) GetMyDevices(deviceID uuid.UUID) ([]dto.LicenseDeviceResponse, error) {
	license, err := s.licenseRepo.FindByDeviceID(deviceID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}

	devices, err := s.licenseRepo.ListDevices(license.ID)
	if err != nil {
		return nil, err
	}

	// Enrich with device metadata from identity table
	result := dto.LicenseDevicesToResponse(devices)
	if len(devices) > 0 {
		deviceIDs := make([]uuid.UUID, len(devices))
		for i, d := range devices {
			deviceIDs[i] = d.DeviceID
		}

		type deviceMeta struct {
			ID         uuid.UUID
			DeviceName string
			OS         string
			OSVersion  string
			AppVersion string
		}
		var metas []deviceMeta
		s.txnRepo.GetDB().Raw(
			"SELECT id, device_name, os, os_version, app_version FROM devices WHERE id IN ?",
			deviceIDs,
		).Scan(&metas)

		metaMap := make(map[string]deviceMeta, len(metas))
		for _, m := range metas {
			metaMap[m.ID.String()] = m
		}

		for i := range result {
			if m, ok := metaMap[result[i].DeviceID]; ok {
				result[i].DeviceName = m.DeviceName
				result[i].OS = m.OS
				result[i].OSVersion = m.OSVersion
				result[i].AppVersion = m.AppVersion
			}
		}
	}

	return result, nil
}

// RefundTransaction processes a refund for a completed transaction.
// For Stripe payments, it calls the Stripe Refund API before marking DB as refunded.
// For crypto payments, it marks the transaction as "refund_pending" (manual process).
func (s *PremiumService) RefundTransaction(txnID uuid.UUID, cancelLicense bool) (*dto.TransactionResponse, error) {
	txn, err := s.txnRepo.FindByID(txnID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTransactionNotFound
		}
		return nil, err
	}

	if txn.Status != "completed" {
		return nil, ErrNotRefundable
	}

	if txn.PaymentMethod == "stripe" {
		// Resolve PaymentIntent ID: prefer stored value, fallback to Stripe session lookup
		var paymentIntentID string
		if txn.StripePaymentIntentID != nil && *txn.StripePaymentIntentID != "" {
			paymentIntentID = *txn.StripePaymentIntentID
		} else if txn.StripeSessionID != nil && *txn.StripeSessionID != "" {
			session, err := checkoutsession.Get(*txn.StripeSessionID, &stripe.CheckoutSessionParams{})
			if err != nil {
				logger.Log.Error().Err(err).
					Str("session_id", *txn.StripeSessionID).
					Msg("Failed to retrieve Stripe session for refund")
				return nil, fmt.Errorf("failed to retrieve Stripe session: %w", err)
			}
			if session.PaymentIntent == nil || session.PaymentIntent.ID == "" {
				return nil, fmt.Errorf("no payment intent found for session %s", *txn.StripeSessionID)
			}
			paymentIntentID = session.PaymentIntent.ID
		} else {
			return nil, fmt.Errorf("no Stripe payment reference found for transaction %s", txnID.String())
		}

		// Issue refund via Stripe API
		_, err = refund.New(&stripe.RefundParams{
			PaymentIntent: stripe.String(paymentIntentID),
		})
		if err != nil {
			logger.Log.Error().Err(err).
				Str("payment_intent", paymentIntentID).
				Msg("Stripe refund failed")
			return nil, fmt.Errorf("stripe refund failed: %w", err)
		}

		logger.Log.Info().
			Str("payment_intent", paymentIntentID).
			Str("transaction_id", txnID.String()).
			Msg("Stripe refund issued successfully")

		// Mark transaction as refunded
		txn.Status = "refunded"
		if err := s.txnRepo.Update(txn); err != nil {
			return nil, err
		}
	} else if txn.PaymentMethod == "crypto" {
		// Crypto refunds are manual — mark as pending
		txn.Status = "refund_pending"
		if err := s.txnRepo.Update(txn); err != nil {
			return nil, err
		}

		logger.Log.Info().
			Str("transaction_id", txnID.String()).
			Msg("Crypto transaction marked as refund_pending (manual process)")
	} else {
		// Unknown or no external payment — just mark as refunded
		txn.Status = "refunded"
		if err := s.txnRepo.Update(txn); err != nil {
			return nil, err
		}
	}

	// Optionally cancel the associated license
	if cancelLicense && txn.LicenseID != nil {
		license, err := s.licenseRepo.FindByID(*txn.LicenseID)
		if err == nil {
			// Cancel Stripe subscription immediately (not just at period end — refund means stop now)
			if license.StripeSubscriptionID != nil && *license.StripeSubscriptionID != "" {
				_, subErr := subscription.Cancel(*license.StripeSubscriptionID, nil)
				if subErr != nil {
					logger.Log.Error().Err(subErr).
						Str("subscription_id", *license.StripeSubscriptionID).
						Str("license_id", license.ID.String()).
						Msg("Failed to cancel Stripe subscription after refund — subscription may still bill")
				} else {
					logger.Log.Info().
						Str("subscription_id", *license.StripeSubscriptionID).
						Str("license_id", license.ID.String()).
						Msg("Stripe subscription cancelled after refund")
				}
			}

			now := time.Now()
			license.Tier = "free"
			license.IsAutoRenew = false
			license.CancelledAt = &now
			if updateErr := s.licenseRepo.Update(license); updateErr != nil {
				logger.Log.Error().Err(updateErr).
					Str("license_id", license.ID.String()).
					Str("transaction_id", txnID.String()).
					Msg("CRITICAL: License downgrade failed after refund issued — user retains premium access")
			}

			logger.Log.Info().
				Str("license_id", license.ID.String()).
				Str("transaction_id", txnID.String()).
				Msg("License downgraded to free due to refund")
		}
	}

	logger.Log.Info().
		Str("transaction_id", txnID.String()).
		Str("device_id", txn.DeviceID.String()).
		Msg("Transaction refunded")

	resp := dto.TransactionToResponse(txn)
	return &resp, nil
}

// --- Admin methods ---

// GetLicense returns a license by ID.
func (s *PremiumService) GetLicense(id uuid.UUID) (*dto.LicenseResponse, error) {
	license, err := s.licenseRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}
	resp := dto.LicenseToResponse(license)
	return &resp, nil
}

// ListLicenses returns paginated licenses for admin.
func (s *PremiumService) ListLicenses(page, perPage int, tier, paymentMethod, search, sortBy, sortDir, brand string) ([]dto.LicenseResponse, int64, error) {
	licenses, total, err := s.licenseRepo.List(page, perPage, tier, paymentMethod, search, sortBy, sortDir, brand)
	if err != nil {
		return nil, 0, err
	}
	return dto.LicensesToResponse(licenses), total, nil
}

// UpdateLicense updates a license for admin with audit trail.
func (s *PremiumService) UpdateLicense(id uuid.UUID, req dto.AdminUpdateLicenseRequest, adminID uuid.UUID) (*dto.LicenseResponse, error) {
	license, err := s.licenseRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}

	if req.Tier != nil {
		license.Tier = *req.Tier
	}
	if req.IsAutoRenew != nil {
		license.IsAutoRenew = *req.IsAutoRenew
	}
	if req.ExpiresAt != nil {
		t, err := time.Parse(time.RFC3339, *req.ExpiresAt)
		if err == nil {
			// Lifetime plans must not have a past expiry date
			if IsLifetimePlan(license.BillingCycle) && t.Before(time.Now()) {
				return nil, fmt.Errorf("lifetime plans cannot have an expiry date in the past")
			}
			license.ExpiresAt = t
		}
	}
	if req.CancelledAt != nil {
		if *req.CancelledAt == "" {
			license.CancelledAt = nil
		} else {
			t, err := time.Parse(time.RFC3339, *req.CancelledAt)
			if err == nil {
				license.CancelledAt = &t
			}
		}
	}

	// Audit trail: record which admin made the change
	license.UpdatedBy = adminID.String()

	if err := s.licenseRepo.Update(license); err != nil {
		return nil, err
	}

	resp := dto.LicenseToResponse(license)
	return &resp, nil
}

// ListTransactions returns paginated transactions for admin.
func (s *PremiumService) ListTransactions(page, perPage int, status, paymentMethod string) ([]dto.TransactionResponse, int64, error) {
	txns, total, err := s.txnRepo.List(page, perPage, status, paymentMethod)
	if err != nil {
		return nil, 0, err
	}
	return dto.TransactionsToResponse(txns), total, nil
}

// GetPremiumStats returns aggregate premium stats for admin dashboard.
func (s *PremiumService) GetPremiumStats(brand string) (*dto.PremiumStatsResponse, error) {
	totalLicenses, _ := s.licenseRepo.CountAll(brand)
	activeLicenses, _ := s.licenseRepo.CountActive(brand)
	expiredLicenses, _ := s.licenseRepo.CountExpired(brand)
	cancelledCount, _ := s.licenseRepo.CountCancelled(brand)
	stripeCount, _ := s.licenseRepo.CountByPaymentMethod("stripe", brand)
	cryptoCount, _ := s.licenseRepo.CountByPaymentMethod("crypto", brand)
	totalRevenue, _ := s.txnRepo.TotalRevenue(brand)
	monthlyRevenue, _ := s.txnRepo.RevenueByBillingCycle("monthly")
	yearlyRevenue, _ := s.txnRepo.RevenueByBillingCycle("yearly")

	var churnRate float64
	if totalLicenses > 0 {
		churnRate = float64(cancelledCount) / float64(totalLicenses)
	}

	return &dto.PremiumStatsResponse{
		TotalLicenses:   totalLicenses,
		ActiveLicenses:  activeLicenses,
		ExpiredLicenses: expiredLicenses,
		CancelledCount:  cancelledCount,
		TotalRevenue:    totalRevenue,
		MonthlyRevenue:  monthlyRevenue,
		YearlyRevenue:   yearlyRevenue,
		StripeCount:     stripeCount,
		CryptoCount:     cryptoCount,
		ChurnRate:       churnRate,
	}, nil

}

// RemoveDevice allows a user to remove a target device from their license.
// The current device must share the same license as the target device.
func (s *PremiumService) RemoveDevice(currentDeviceID, targetDeviceID uuid.UUID) error {
	// Find the license associated with the current device
	license, err := s.licenseRepo.FindByDeviceID(currentDeviceID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrLicenseNotFound
		}
		return err
	}

	// Prevent self-removal — user cannot remove their own device
	if currentDeviceID == targetDeviceID {
		return ErrCannotRemoveSelf
	}

	// Verify current device is registered to this license
	_, err = s.licenseRepo.FindLicenseDevice(license.ID, currentDeviceID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrLicenseNotFound
		}
		return err
	}

	// Delete the target device from the license
	if err := s.licenseRepo.DeleteDevice(license.ID, targetDeviceID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrDeviceNotFound
		}
		return err
	}

	logger.Log.Info().
		Str("license_id", license.ID.String()).
		Str("removed_device", targetDeviceID.String()).
		Str("by_device", currentDeviceID.String()).
		Msg("Device removed from license")

	return nil
}

// AdminListDevices returns all devices registered to a license (admin).
func (s *PremiumService) AdminListDevices(licenseID uuid.UUID) ([]dto.LicenseDeviceResponse, error) {
	// Verify license exists
	_, err := s.licenseRepo.FindByID(licenseID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLicenseNotFound
		}
		return nil, err
	}

	devices, err := s.licenseRepo.ListDevices(licenseID)
	if err != nil {
		return nil, err
	}

	return dto.LicenseDevicesToResponse(devices), nil
}

// AdminRemoveDevice removes a device from a license (admin).
func (s *PremiumService) AdminRemoveDevice(licenseID, deviceID uuid.UUID) error {
	// Verify license exists
	_, err := s.licenseRepo.FindByID(licenseID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrLicenseNotFound
		}
		return err
	}

	if err := s.licenseRepo.DeleteDevice(licenseID, deviceID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrDeviceNotFound
		}
		return err
	}

	logger.Log.Info().
		Str("license_id", licenseID.String()).
		Str("device_id", deviceID.String()).
		Msg("Admin removed device from license")

	return nil
}

// RestoreLicense finds an active license by email and returns it.
// Requires deviceID to prevent email enumeration — the device must have been
// previously registered on the license.
func (s *PremiumService) RestoreLicense(email, brand string, deviceID uuid.UUID) (*dto.RestoreResponse, error) {
	license, err := s.licenseRepo.FindActiveByEmail(email, brand)
	if err != nil {
		return nil, ErrLicenseNotFound
	}

	// Check validity BEFORE registering device — don't consume a device slot
	// on an expired license that the user can't use.
	isValid := license.Tier == "premium" && (IsLifetimePlan(license.BillingCycle) || time.Now().Before(license.ExpiresAt))
	if !isValid {
		return nil, ErrLicenseNotFound
	}

	// Auto-register device on first restore (respecting device limit).
	if deviceID != uuid.Nil {
		_, deviceErr := s.licenseRepo.FindLicenseDevice(license.ID, deviceID)
		if deviceErr != nil {
			ld := &model.LicenseDevice{LicenseID: license.ID, DeviceID: deviceID}
			if regErr := s.licenseRepo.RegisterDeviceWithLimit(ld, MaxDevicesForPlan(license.BillingCycle)); regErr != nil {
				logger.Log.Warn().
					Str("license_key", license.LicenseKey).
					Str("device_id", deviceID.String()).
					Str("error", regErr.Error()).
					Msg("Restore: device registration failed (limit reached?)")
				return nil, ErrDeviceLimitReached
			}
			logger.Log.Info().
				Str("license_key", license.LicenseKey).
				Str("device_id", deviceID.String()).
				Msg("Restore: new device registered to license")
		}
	}

	return &dto.RestoreResponse{
		LicenseKey:   license.LicenseKey,
		BillingCycle: license.BillingCycle,
		ExpiresAt:    license.ExpiresAt.Format(time.RFC3339),
	}, nil
}

// RevokeLicenseByPaymentIntent revokes a license associated with a Stripe payment intent.
// Used by webhook handlers for charge.refunded and charge.dispute.created.
//
// Error contract (W1.4 hardening): only gorm.ErrRecordNotFound is translated
// to ErrTransactionNotFound / ErrLicenseNotFound so callers can branch into
// the invoice-fallback chain. Every other repo error is propagated wrapped so
// the webhook returns 500 and Stripe retries — silently swallowing a DB error
// here previously masked real revocation failures.
func (s *PremiumService) RevokeLicenseByPaymentIntent(paymentIntentID, reason string) error {
	txn, err := s.txnRepo.FindByStripePaymentIntentID(paymentIntentID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrTransactionNotFound
	}
	if err != nil {
		return fmt.Errorf("find transaction by payment intent: %w", err)
	}

	if txn.LicenseID == nil {
		return ErrLicenseNotFound
	}

	if err := s.revokeLicenseByID(*txn.LicenseID, paymentIntentID, reason); err != nil {
		return err
	}

	txn.Status = "refunded"
	if err := s.txnRepo.Update(txn); err != nil {
		logger.Log.Error().Err(err).Msg("Failed to update transaction status after " + reason)
	}
	return nil
}

// RevokeLicenseByInvoicePaymentIntent is the W1.4 fallback lookup path: when
// payment_transactions has no row for a refunded/disputed PaymentIntent
// (typical for renewal invoices created by Stripe's billing engine rather
// than our checkout flow), resolve the license via the Invoice row instead.
//
// Lookup chain:
//  1. invoices.stripe_payment_intent_id → invoice.license_id (direct)
//  2. if license_id is nil (orphan invoice — finalized before checkout
//     completed): invoices.stripe_subscription_id → license via
//     licenseRepo.FindByStripeSubscriptionID.
//
// Returns ErrLicenseNotFound if both legs fail to resolve a license.
// Real DB errors propagate unwrapped so the caller can retry.
func (s *PremiumService) RevokeLicenseByInvoicePaymentIntent(paymentIntentID, reason string) error {
	if s.invoiceRepo == nil {
		return ErrLicenseNotFound
	}
	inv, err := s.invoiceRepo.FindByStripePaymentIntentID(paymentIntentID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrLicenseNotFound
	}
	if err != nil {
		return fmt.Errorf("find invoice by payment intent: %w", err)
	}

	if inv.LicenseID != nil {
		return s.revokeLicenseByID(*inv.LicenseID, paymentIntentID, reason)
	}

	if inv.StripeSubscriptionID == nil || *inv.StripeSubscriptionID == "" {
		// Orphan invoice without subscription anchor — nothing to revoke.
		return ErrLicenseNotFound
	}

	license, err := s.licenseRepo.FindByStripeSubscriptionID(*inv.StripeSubscriptionID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrLicenseNotFound
	}
	if err != nil {
		return fmt.Errorf("find license by subscription: %w", err)
	}
	return s.revokeLicenseByID(license.ID, paymentIntentID, reason)
}

// revokeLicenseByID is the shared mutation used by both the transaction-keyed
// and the invoice-keyed revocation paths. Single source of truth for the
// "make this license free + clear auto-renew + stamp cancelled_at" sequence.
func (s *PremiumService) revokeLicenseByID(licenseID uuid.UUID, paymentIntentID, reason string) error {
	license, err := s.licenseRepo.FindByID(licenseID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrLicenseNotFound
	}
	if err != nil {
		return fmt.Errorf("find license by id: %w", err)
	}

	now := time.Now()
	license.Tier = "free"
	license.IsAutoRenew = false
	license.CancelledAt = &now
	if err := s.licenseRepo.Update(license); err != nil {
		logger.Log.Error().Err(err).
			Str("license_id", license.ID.String()).
			Str("payment_intent", paymentIntentID).
			Msg("CRITICAL: Failed to revoke license after " + reason)
		return fmt.Errorf("update license on revoke: %w", err)
	}

	logger.Log.Info().
		Str("license_id", license.ID.String()).
		Str("license_key", license.LicenseKey).
		Str("payment_intent", paymentIntentID).
		Str("reason", reason).
		Msg("License revoked due to payment reversal")
	return nil
}

// RestoreLicenseByPaymentIntent re-enables a license whose revocation should
// be reversed (e.g. dispute.closed status=won). Mirror of the revoke chain —
// transaction lookup first, invoice fallback second.
func (s *PremiumService) RestoreLicenseByPaymentIntent(paymentIntentID, reason string) error {
	txn, err := s.txnRepo.FindByStripePaymentIntentID(paymentIntentID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrTransactionNotFound
	}
	if err != nil {
		return fmt.Errorf("find transaction by payment intent: %w", err)
	}
	if txn.LicenseID == nil {
		return ErrLicenseNotFound
	}
	return s.restoreLicenseByID(*txn.LicenseID, paymentIntentID, reason)
}

// RestoreLicenseByInvoicePaymentIntent is the invoice-fallback variant for
// the won-dispute restoration path. Same lookup chain as
// RevokeLicenseByInvoicePaymentIntent.
func (s *PremiumService) RestoreLicenseByInvoicePaymentIntent(paymentIntentID, reason string) error {
	if s.invoiceRepo == nil {
		return ErrLicenseNotFound
	}
	inv, err := s.invoiceRepo.FindByStripePaymentIntentID(paymentIntentID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrLicenseNotFound
	}
	if err != nil {
		return fmt.Errorf("find invoice by payment intent: %w", err)
	}
	if inv.LicenseID != nil {
		return s.restoreLicenseByID(*inv.LicenseID, paymentIntentID, reason)
	}
	if inv.StripeSubscriptionID == nil || *inv.StripeSubscriptionID == "" {
		return ErrLicenseNotFound
	}
	license, err := s.licenseRepo.FindByStripeSubscriptionID(*inv.StripeSubscriptionID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrLicenseNotFound
	}
	if err != nil {
		return fmt.Errorf("find license by subscription: %w", err)
	}
	return s.restoreLicenseByID(license.ID, paymentIntentID, reason)
}

func (s *PremiumService) restoreLicenseByID(licenseID uuid.UUID, paymentIntentID, reason string) error {
	license, err := s.licenseRepo.FindByID(licenseID)
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrLicenseNotFound
	}
	if err != nil {
		return fmt.Errorf("find license by id: %w", err)
	}
	license.Tier = "premium"
	license.CancelledAt = nil
	// Restore auto-renew for Stripe subscriptions (lifetime plans don't renew).
	// Without this, a license revoked by dispute.created and restored on
	// dispute.closed=won would silently stop renewing — Stripe would keep
	// charging but our auto-renew flag would stay false from the revoke.
	if license.StripeSubscriptionID != nil && *license.StripeSubscriptionID != "" && !IsLifetimePlan(license.BillingCycle) {
		license.IsAutoRenew = true
	}
	if err := s.licenseRepo.Update(license); err != nil {
		return fmt.Errorf("restore license: %w", err)
	}
	logger.Log.Info().
		Str("license_id", license.ID.String()).
		Str("license_key", license.LicenseKey).
		Str("payment_intent", paymentIntentID).
		Str("reason", reason).
		Msg("License restored after payment reversal")
	return nil
}

// AdminCreateLicense creates a manual/comp license (no payment required).
// Used by admin to issue complimentary licenses, test licenses, or replacements.
func (s *PremiumService) AdminCreateLicense(req dto.AdminCreateLicenseRequest, adminID uuid.UUID) (*dto.LicenseResponse, error) {
	// Use the canonical cycle→duration helper so semiannual gets +6mo (not +12),
	// and any new cycles introduced later automatically work here too.
	now := time.Now()
	expiresAt := AddBillingCycleToTime(now, req.BillingCycle)

	// Default brand to "ssvid" for admin-created licenses
	brand := "ssvid"
	if req.Brand != "" {
		brand = req.Brand
	}

	// Normalize email at write side so case-sensitive WHERE in
	// FindActiveByEmail matches what RestoreLicense sends after lowercasing.
	// Shared helper from email_util.go (W1 magic-link convergence).
	license := &model.PremiumLicense{
		DeviceID:      uuid.Nil, // No device yet — will be registered on first verify
		Brand:         brand,
		LicenseKey:    model.GenerateLicenseKey(s.jwtSecret, brand),
		Tier:          "premium",
		BillingCycle:  req.BillingCycle,
		PaymentMethod: "manual",
		IsAutoRenew:   false, // Manual licenses don't auto-renew
		ExpiresAt:     expiresAt,
		ContactEmail:  normalizeContactEmailPtr(req.ContactEmail),
		CreatedBy:     adminID.String(),
	}

	if err := s.licenseRepo.Create(license); err != nil {
		return nil, err
	}

	logger.Log.Info().
		Str("license_key", license.LicenseKey).
		Str("billing_cycle", req.BillingCycle).
		Str("admin_id", adminID.String()).
		Str("notes", req.Notes).
		Msg("Manual license created by admin")

	resp := dto.LicenseToResponse(license)
	return &resp, nil
}

// AdminImportLegacyLicense imports a pre-existing PHP-issued license into the
// Go backend. One-shot γ-ETL migration from quantri.vidcombo.com →
// api.ssvid.app to close the "Restore by Email" gap for ~4,240 legacy
// VidCombo subscribers whose data only lived in MySQL.
//
// Contract:
//   - LicenseKey PRESERVED VERBATIM (no key generation) — user already has
//     this 32-hex key from the original purchase email.
//   - Brand LOCKED to "vidcombo" by DTO binding + service guard.
//   - PaymentMethod = "stripe_legacy" so admin dashboard can distinguish
//     PHP-origin records from in-app Stripe purchases.
//   - IsAutoRenew = false (legacy users manage renewal via vidcombo.net).
//   - DeviceID = uuid.Nil (bound on first /premium/restore call).
//   - Idempotent: re-run is safe — updates mutable fields, never touches
//     immutable origin facts.
//
// Safety rails (ultra-review Round 1):
//   - Atomic upsert via clause.OnConflict — race-safe under concurrent ETL.
//   - Refuses to update a row already revoked / refunded / downgraded
//     (CancelledAt != nil OR Tier != "premium"): an admin's manual revoke
//     must NOT be silently undone by a re-run.
//   - Refuses to overwrite a row of a different brand: blocks the case
//     where a PHP 32-hex key collides with a brand=ssvid row (data drift /
//     manual seed) and the update would silently corrupt an SSvid license.
//   - Rejects zero-value ExpiresAt and ExpiresAt > 1 year in the past
//     (Gin's `required` binding tag treats time.Time{} as present).
//   - Rejects unknown plan values explicitly — no silent default that would
//     grant the wrong tier (revenue loss).
//
// Errors map to sentinel types so the handler can return clean status codes
// without leaking raw GORM messages.
func (s *PremiumService) AdminImportLegacyLicense(req dto.AdminImportLegacyLicenseRequest, adminID uuid.UUID) (*dto.LicenseResponse, error) {
	// 0. Status guard (service-level defense-in-depth). Gin binding
	// `oneof=active trialing` on the DTO already rejects other values at
	// the HTTP boundary, but any future internal caller (CSV bulk variant,
	// admin tooling, service-to-service) that bypasses Gin would otherwise
	// silently resurrect refunded / cancelled / past_due rows as premium.
	// Keep this guard even if it duplicates the binding — contract beats
	// implicit trust. Broad ultra-review Round 9.
	if req.Status != "active" && req.Status != "trialing" {
		return nil, ErrLegacyImportInvalidStatus
	}

	// 1. Map PHP plan → Go billing_cycle. Unknown plan = reject (no fallback).
	billingCycle, ok := mapLegacyPlanToBillingCycle(req.Plan)
	if !ok {
		return nil, ErrLegacyImportInvalidPlan
	}

	// 2. Reject zero / absurdly-past ExpiresAt. Gin `required` on time.Time
	// treats the zero value as present, so we re-check here.
	if req.ExpiresAt.IsZero() {
		return nil, ErrLegacyImportInvalidExpiresAt
	}
	if !model.IsLifetimeBillingCycle(billingCycle) &&
		req.ExpiresAt.Before(time.Now().Add(-365*24*time.Hour)) {
		// More than a year in the past — almost certainly a parse error
		// upstream. Lifetime plans get a 100-year sentinel and are exempt.
		return nil, ErrLegacyImportInvalidExpiresAt
	}

	// 3. Normalize license key to uppercase to match canonical PHP output
	// (strtoupper(bin2hex(random_bytes(16)))). The tx below uses an
	// `UPPER(license_key) = ?` predicate so a row stored lowercase by a
	// prior (manual) seeding tool is still found and de-duplicated.
	normalizedKey := strings.ToUpper(req.LicenseKey)

	// Email normalization mirrors RestoreLicense's lowercase + trim so
	// case-sensitive WHERE in FindActiveByEmail matches imported rows.
	normalizedEmail := strings.ToLower(strings.TrimSpace(req.Email))

	// 4. Atomic upsert. Wraps the read-then-write in a transaction with row
	// locking + ON CONFLICT (license_key) so concurrent ETL processes or a
	// re-run that overlaps with the first run cannot duplicate-insert or
	// race past each other.
	var result *model.PremiumLicense
	var wasUpdate bool
	db := s.txnRepo.GetDB()
	txErr := db.Transaction(func(tx *gorm.DB) error {
		var existing model.PremiumLicense
		findErr := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("UPPER(license_key) = ?", normalizedKey).
			First(&existing).Error

		if findErr == nil {
			// Existing row — apply guards before any field write.
			// Guard A: brand must match. Blocks cross-brand overwrite.
			if existing.Brand != req.Brand {
				return ErrLegacyImportBrandMismatch
			}
			// Guard B: row must still be a non-revoked premium. Refuses to
			// resurrect a row an admin previously cancelled, refunded, or
			// downgraded to free.
			if existing.CancelledAt != nil || existing.Tier != "premium" {
				return ErrLegacyImportRowRevoked
			}
			// Guard C: payment_method must remain stripe_legacy. Refuses to
			// rewrite the origin of a Go-native Stripe / crypto / manual
			// record even on a key collision.
			if existing.PaymentMethod != "stripe_legacy" {
				return ErrLegacyImportPaymentMethodMismatch
			}

			// Update ONLY mutable bookkeeping fields. License key, brand,
			// payment method, created_by, device_id, tier — all immutable.
			existing.ExpiresAt = req.ExpiresAt
			emailCopy := normalizedEmail
			existing.ContactEmail = &emailCopy
			existing.StripeCustomerID = req.StripeCustomerID
			existing.StripeSubscriptionID = req.StripeSubscriptionID
			existing.UpdatedBy = adminID.String()
			if err := tx.Save(&existing).Error; err != nil {
				return fmt.Errorf("save legacy license: %w", err)
			}
			result = &existing
			wasUpdate = true
			return nil
		}

		if !errors.Is(findErr, gorm.ErrRecordNotFound) {
			return fmt.Errorf("lookup legacy license: %w", findErr)
		}

		// New row insert.
		emailCopy := normalizedEmail
		license := &model.PremiumLicense{
			DeviceID:             uuid.Nil, // Bound on first /premium/restore
			Brand:                req.Brand,
			LicenseKey:           normalizedKey,
			Tier:                 "premium",
			BillingCycle:         billingCycle,
			PaymentMethod:        "stripe_legacy",
			StripeCustomerID:     req.StripeCustomerID,
			StripeSubscriptionID: req.StripeSubscriptionID,
			IsAutoRenew:          false,
			ExpiresAt:            req.ExpiresAt,
			ContactEmail:         &emailCopy,
			CreatedBy:            adminID.String(),
		}
		// ON CONFLICT DO NOTHING — if a concurrent ETL beat us, no error.
		// We re-fetch to return the canonical row.
		if err := tx.Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "license_key"}},
			DoNothing: true,
		}).Create(license).Error; err != nil {
			return fmt.Errorf("create legacy license: %w", err)
		}
		// Re-fetch to handle the DoNothing branch (RowsAffected may be 0).
		if err := tx.Where("UPPER(license_key) = ?", normalizedKey).
			First(license).Error; err != nil {
			return fmt.Errorf("re-fetch legacy license: %w", err)
		}
		result = license
		return nil
	})
	if txErr != nil {
		return nil, txErr
	}

	// 5. Log without the raw license_key (PII at scale). The first 8 chars
	// are enough to triage; the full key is in the audit_logs middleware
	// table (which itself MUST redact — covered in audit middleware).
	keyTag := normalizedKey
	if len(keyTag) > 8 {
		keyTag = keyTag[:8] + "..."
	}
	logger.Log.Info().
		Str("license_key_prefix", keyTag).
		Str("brand", req.Brand).
		Str("plan", req.Plan).
		Str("billing_cycle", billingCycle).
		Bool("was_update", wasUpdate).
		Str("admin_id", adminID.String()).
		Msg("Legacy PHP license imported into Go backend")

	resp := dto.LicenseToResponse(result)
	return &resp, nil
}

// Sentinel errors for [AdminImportLegacyLicense]. Handler maps each to a
// distinct HTTP status + error code so callers can distinguish "client
// fixable" (plan unknown, brand mismatch) from "operator action required"
// (row revoked) without inspecting raw error strings.
var (
	ErrLegacyImportInvalidPlan            = errors.New("legacy import: unsupported plan")
	ErrLegacyImportInvalidExpiresAt       = errors.New("legacy import: missing or absurdly-past expires_at")
	ErrLegacyImportInvalidStatus          = errors.New("legacy import: status must be active or trialing")
	ErrLegacyImportBrandMismatch          = errors.New("legacy import: license key collides with row of different brand")
	ErrLegacyImportRowRevoked             = errors.New("legacy import: row already revoked / refunded / downgraded — refusing to resurrect")
	ErrLegacyImportPaymentMethodMismatch  = errors.New("legacy import: license key collides with row of different payment_method")
)

// mapLegacyPlanToBillingCycle converts a PHP `subscriptions.plan` column
// value to the Go canonical billing cycle. Returns (cycle, true) on success
// or ("", false) for unknown plans — caller MUST reject unknowns rather than
// silently defaulting (a wrong tier mapping = free premium time = revenue loss).
func mapLegacyPlanToBillingCycle(plan string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(plan)) {
	case "plan1":
		return "monthly", true
	case "plan2":
		return "semiannual", true
	case "plan3":
		return "yearly", true
	case "lifetime":
		return "lifetime", true
	default:
		return "", false
	}
}

// AmountCentsForBillingCycle returns price in USD cents, brand-aware.
func AmountCentsForBillingCycle(cycle, brand string) int {
	if brand == "vidcombo" {
		switch cycle {
		case "monthly":
			return 699 // $6.99
		case "semiannual":
			return 2934 // $29.34
		case "yearly":
			return 4188 // $41.88
		default:
			return 0
		}
	}
	// SSvid (default)
	switch cycle {
	case "monthly":
		return 799 // $7.99
	case "yearly":
		return 2999 // $29.99
	case "lifetime", "lifetime1", "lifetime2", "lifetime3":
		return 8999 // $89.99
	default:
		return 0
	}
}

// --- Business Dashboard Methods ---

// GetTransaction returns a single transaction by ID.
func (s *PremiumService) GetTransaction(id uuid.UUID) (*dto.EnhancedTransactionResponse, error) {
	txn, err := s.txnRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrTransactionNotFound
		}
		return nil, err
	}

	base := dto.TransactionToResponse(txn)
	resp := &dto.EnhancedTransactionResponse{TransactionResponse: base}

	// Enrich with license data
	if txn.LicenseID != nil {
		license, err := s.licenseRepo.FindByID(*txn.LicenseID)
		if err == nil {
			resp.ContactEmail = license.ContactEmail
			resp.LicenseKey = &license.LicenseKey
		}
	}

	return resp, nil
}

// ListTransactionsEnhanced returns paginated transactions with license data.
func (s *PremiumService) ListTransactionsEnhanced(page, perPage int, status, paymentMethod, search, dateFrom, dateTo, sortBy, sortDir, brand string) ([]dto.EnhancedTransactionResponse, int64, error) {
	txns, total, err := s.txnRepo.ListEnhanced(page, perPage, status, paymentMethod, search, dateFrom, dateTo, sortBy, sortDir, brand)
	if err != nil {
		return nil, 0, err
	}

	result := make([]dto.EnhancedTransactionResponse, len(txns))
	for i, t := range txns {
		base := dto.TransactionToResponse(&t.PaymentTransaction)
		result[i] = dto.EnhancedTransactionResponse{
			TransactionResponse: base,
			ContactEmail:        t.ContactEmail,
			LicenseKey:          t.LicenseKey,
		}
	}

	return result, total, nil
}

// GetTransactionStats returns aggregate transaction statistics.
func (s *PremiumService) GetTransactionStats(brand string) (*dto.TransactionStatsResponse, error) {
	totalTxns, _ := s.txnRepo.CountAll(brand)
	totalRevenue, _ := s.txnRepo.TotalRevenue(brand)
	revenueToday, _ := s.txnRepo.RevenueToday(brand)
	revenueMonth, _ := s.txnRepo.RevenueThisMonth(brand)
	statusCounts, _ := s.txnRepo.CountByStatus(brand)

	byStatus := make(map[string]int64)
	for _, sc := range statusCounts {
		byStatus[sc.Status] = sc.Count
	}

	return &dto.TransactionStatsResponse{
		TotalTransactions: totalTxns,
		TotalRevenue:      totalRevenue,
		RevenueToday:      revenueToday,
		RevenueThisMonth:  revenueMonth,
		ByStatus:          byStatus,
	}, nil
}

// ListSubscriptions returns paginated subscription view of licenses.
func (s *PremiumService) ListSubscriptions(page, perPage int, status, search, sortBy, sortDir, brand string) ([]dto.SubscriptionResponse, int64, error) {
	licenses, total, err := s.licenseRepo.ListSubscriptions(page, perPage, status, search, sortBy, sortDir, brand)
	if err != nil {
		return nil, 0, err
	}

	result := make([]dto.SubscriptionResponse, len(licenses))
	for i, l := range licenses {
		base := dto.LicenseToResponse(&l)
		deviceCount, _ := s.licenseRepo.CountDevices(l.ID)

		subStatus := "active"
		if l.CancelledAt != nil {
			subStatus = "cancelled"
		} else if time.Now().After(l.ExpiresAt) {
			subStatus = "expired"
		}

		result[i] = dto.SubscriptionResponse{
			LicenseResponse: base,
			Status:          subStatus,
			DeviceCount:     int(deviceCount),
			MaxDevices:      MaxDevicesForPlan(l.BillingCycle),
		}
	}

	return result, total, nil
}

// GetSubscriptionStats returns aggregate subscription statistics.
func (s *PremiumService) GetSubscriptionStats(brand string) (*dto.SubscriptionStatsResponse, error) {
	active, _ := s.licenseRepo.CountActive(brand)
	cancelled, _ := s.licenseRepo.CountCancelled(brand)
	expired, _ := s.licenseRepo.CountExpired(brand)
	mrr, _ := s.licenseRepo.CalculateMRR(brand)

	total := active + cancelled + expired
	var churnRate float64
	if total > 0 {
		churnRate = float64(cancelled) / float64(total)
	}

	return &dto.SubscriptionStatsResponse{
		ActiveCount:    active,
		CancelledCount: cancelled,
		ExpiredCount:   expired,
		TotalCount:     total,
		MRR:            mrr,
		ChurnRate:      churnRate,
	}, nil
}

// ListCustomers returns paginated customer aggregates.
func (s *PremiumService) ListCustomers(page, perPage int, search, sortBy, sortDir, brand string) ([]dto.CustomerResponse, int64, error) {
	customers, total, err := s.licenseRepo.ListCustomers(page, perPage, search, sortBy, sortDir, brand)
	if err != nil {
		return nil, 0, err
	}

	result := make([]dto.CustomerResponse, len(customers))
	for i, c := range customers {
		result[i] = dto.CustomerResponse{
			ContactEmail:     c.ContactEmail,
			StripeCustomerID: c.StripeCustomerID,
			LicenseCount:     c.LicenseCount,
			ActiveLicenses:   c.ActiveLicenses,
			TotalSpentCents:  c.TotalSpentCents,
			FirstPurchase:    c.FirstPurchase.Format(time.RFC3339),
			LastPurchase:     c.LastPurchase.Format(time.RFC3339),
		}
	}

	return result, total, nil
}

// GetCustomer returns detailed customer data including licenses and transactions.
func (s *PremiumService) GetCustomer(email string) (*dto.CustomerDetailResponse, error) {
	licenses, err := s.licenseRepo.FindByEmail(email)
	if err != nil || len(licenses) == 0 {
		return nil, ErrLicenseNotFound
	}

	// Build customer aggregate
	var stripeID *string
	for _, l := range licenses {
		if l.StripeCustomerID != nil {
			stripeID = l.StripeCustomerID
			break
		}
	}

	totalSpent, err := s.txnRepo.TotalRevenueByEmail(email)
	if err != nil {
		logger.Log.Warn().Err(err).Str("email", email).Msg("GetCustomer: failed to get total revenue")
	}
	activeLicenses := int64(0)
	now := time.Now().UTC()
	for _, l := range licenses {
		if model.IsLicenseActiveAt(&l, now) {
			activeLicenses++
		}
	}

	licenseResponses := dto.LicensesToResponse(licenses)

	// Get transactions for this customer
	enhancedTxns, _, err := s.txnRepo.FindByEmail(email, 1, 50)
	if err != nil {
		logger.Log.Warn().Err(err).Str("email", email).Msg("GetCustomer: failed to get transactions")
	}
	txnResponses := make([]dto.EnhancedTransactionResponse, len(enhancedTxns))
	for i, t := range enhancedTxns {
		base := dto.TransactionToResponse(&t.PaymentTransaction)
		txnResponses[i] = dto.EnhancedTransactionResponse{
			TransactionResponse: base,
			ContactEmail:        t.ContactEmail,
			LicenseKey:          t.LicenseKey,
		}
	}

	return &dto.CustomerDetailResponse{
		CustomerResponse: dto.CustomerResponse{
			ContactEmail:     email,
			StripeCustomerID: stripeID,
			LicenseCount:     int64(len(licenses)),
			ActiveLicenses:   activeLicenses,
			TotalSpentCents:  totalSpent,
			FirstPurchase:    licenses[len(licenses)-1].CreatedAt.Format(time.RFC3339),
			LastPurchase:     licenses[0].CreatedAt.Format(time.RFC3339),
		},
		Licenses:     licenseResponses,
		Transactions: txnResponses,
	}, nil
}

// GetCustomerStats returns aggregate customer statistics.
func (s *PremiumService) GetCustomerStats(brand string) (*dto.CustomerStatsResponse, error) {
	totalCustomers, err := s.licenseRepo.CountCustomers(brand)
	if err != nil {
		return nil, fmt.Errorf("count customers: %w", err)
	}
	totalRevenue, err := s.txnRepo.TotalRevenue(brand)
	if err != nil {
		return nil, fmt.Errorf("total revenue: %w", err)
	}

	var avgRevenue int64
	if totalCustomers > 0 {
		avgRevenue = totalRevenue / totalCustomers
	}

	return &dto.CustomerStatsResponse{
		TotalCustomers: totalCustomers,
		TotalRevenue:   totalRevenue,
		AvgRevenue:     avgRevenue,
	}, nil
}

// GetRevenueReport returns comprehensive revenue data for the report page.
// Uses invoices table (real Stripe webhook data) as the source of truth for revenue.
func (s *PremiumService) GetRevenueReport(days int, brand string) (*dto.RevenueReportResponse, error) {
	if days <= 0 {
		days = 30
	}

	// Revenue from invoices (paid Stripe invoices = real money)
	totalRevenue, _ := s.invoiceRepo.TotalPaid(brand)
	revenueToday, _ := s.invoiceRepo.RevenueToday(brand)
	revenueMonth, _ := s.invoiceRepo.RevenueThisMonth(brand)

	// Refunds still tracked via transactions (Stripe refund events)
	totalRefunded, _ := s.txnRepo.TotalRefunded(brand)
	refundCount, _ := s.txnRepo.RefundCount(brand)

	// Breakdown by billing reason (subscription_cycle, subscription_create, etc.)
	byReason, _ := s.invoiceRepo.RevenueByBillingReason(brand)

	// Daily trend from invoices
	dailyRevenue, _ := s.invoiceRepo.RevenueByDay(days, brand)

	resp := &dto.RevenueReportResponse{
		TotalRevenue:     totalRevenue,
		RevenueToday:     revenueToday,
		RevenueThisMonth: revenueMonth,
		TotalRefunded:    totalRefunded,
		RefundCount:      refundCount,
		NetRevenue:       totalRevenue - totalRefunded,
	}

	for _, r := range byReason {
		resp.ByCycle = append(resp.ByCycle, dto.RevenueCycleBreakdown{
			BillingCycle: r.BillingReason,
			AmountCents:  r.AmountCents,
			Count:        r.Count,
		})
	}

	for _, d := range dailyRevenue {
		resp.DailyRevenue = append(resp.DailyRevenue, dto.DailyRevenuePoint{
			Date:        d.Date,
			AmountCents: d.AmountCents,
			Count:       d.Count,
		})
	}

	// Breakdown by payment method (stripe, crypto, etc.)
	byMethod, _ := s.txnRepo.RevenueGroupedByMethod(brand)
	for _, m := range byMethod {
		resp.ByMethod = append(resp.ByMethod, dto.RevenueMethodBreakdown{
			PaymentMethod: m.PaymentMethod,
			AmountCents:   m.AmountCents,
			Count:         m.Count,
		})
	}

	return resp, nil
}

// GlobalSearch searches across licenses, transactions, and customers.
func (s *PremiumService) GlobalSearch(query string, limit int) (*dto.GlobalSearchResponse, error) {
	if limit <= 0 {
		limit = 5
	}

	resp := &dto.GlobalSearchResponse{}

	// Search licenses (non-fatal: partial results on error)
	licenses, _, err := s.licenseRepo.List(1, limit, "", "", query, "", "", "")
	if err != nil {
		logger.Log.Warn().Err(err).Str("query", query).Msg("GlobalSearch: license search failed")
	}
	resp.Licenses = dto.LicensesToResponse(licenses)

	// Search transactions (non-fatal: partial results on error)
	txns, _, err := s.txnRepo.ListEnhanced(1, limit, "", "", query, "", "", "", "", "")
	if err != nil {
		logger.Log.Warn().Err(err).Str("query", query).Msg("GlobalSearch: transaction search failed")
	}
	for _, t := range txns {
		base := dto.TransactionToResponse(&t.PaymentTransaction)
		resp.Transactions = append(resp.Transactions, dto.EnhancedTransactionResponse{
			TransactionResponse: base,
			ContactEmail:        t.ContactEmail,
			LicenseKey:          t.LicenseKey,
		})
	}

	// Search customers (non-fatal: partial results on error)
	customers, _, err := s.licenseRepo.ListCustomers(1, limit, query, "", "", "")
	if err != nil {
		logger.Log.Warn().Err(err).Str("query", query).Msg("GlobalSearch: customer search failed")
	}
	for _, c := range customers {
		resp.Customers = append(resp.Customers, dto.CustomerResponse{
			ContactEmail:     c.ContactEmail,
			StripeCustomerID: c.StripeCustomerID,
			LicenseCount:     c.LicenseCount,
			ActiveLicenses:   c.ActiveLicenses,
			TotalSpentCents:  c.TotalSpentCents,
			FirstPurchase:    c.FirstPurchase.Format(time.RFC3339),
			LastPurchase:     c.LastPurchase.Format(time.RFC3339),
		})
	}

	return resp, nil
}

// --- Invoice Methods ---

// ListInvoices returns paginated invoices.
func (s *PremiumService) ListInvoices(page, perPage int, status, search, sortBy, sortDir, brand string) ([]dto.InvoiceResponse, int64, error) {
	if s.invoiceRepo == nil {
		return nil, 0, fmt.Errorf("invoice repository not configured")
	}
	invoices, total, err := s.invoiceRepo.List(page, perPage, status, search, sortBy, sortDir, brand)
	if err != nil {
		return nil, 0, err
	}
	return dto.InvoicesToResponse(invoices), total, nil
}

// GetInvoiceStats returns aggregate invoice statistics.
func (s *PremiumService) GetInvoiceStats(brand string) (*dto.InvoiceStatsResponse, error) {
	if s.invoiceRepo == nil {
		return nil, fmt.Errorf("invoice repository not configured")
	}

	totalCount, err := s.invoiceRepo.CountAll(brand)
	if err != nil {
		return nil, err
	}

	totalPaid, err := s.invoiceRepo.TotalPaid(brand)
	if err != nil {
		return nil, err
	}

	statusCounts, err := s.invoiceRepo.CountByStatus(brand)
	if err != nil {
		return nil, err
	}

	byStatus := make(map[string]int64)
	for _, sc := range statusCounts {
		byStatus[sc.Status] = sc.Count
	}

	return &dto.InvoiceStatsResponse{
		TotalInvoices: totalCount,
		TotalPaid:     totalPaid,
		ByStatus:      byStatus,
	}, nil
}

// GetMRRTrend returns monthly recurring revenue over the last N months.
func (s *PremiumService) GetMRRTrend(months int, brand string) ([]dto.MRRPoint, error) {
	if s.invoiceRepo == nil {
		return nil, fmt.Errorf("invoice repository not configured")
	}
	if months <= 0 {
		months = 12
	}

	points, err := s.invoiceRepo.MRRByMonth(months, brand)
	if err != nil {
		return nil, err
	}

	result := make([]dto.MRRPoint, len(points))
	for i, p := range points {
		result[i] = dto.MRRPoint{
			Month:       p.Month,
			AmountCents: p.AmountCents,
			Count:       int(p.Count),
		}
	}
	return result, nil
}

// GetInvoice returns a single invoice by ID.
func (s *PremiumService) GetInvoice(id uuid.UUID) (*dto.InvoiceResponse, error) {
	if s.invoiceRepo == nil {
		return nil, fmt.Errorf("invoice repository not configured")
	}
	invoice, err := s.invoiceRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, fmt.Errorf("invoice not found")
		}
		return nil, err
	}
	resp := dto.InvoiceToResponse(invoice)
	return &resp, nil
}

// verifyViaPhpCheckKey proxies a 32-hex legacy license key to the VidCombo PHP
// backend's checkkey.php and translates the response into LicenseVerifyResponse.
func (s *PremiumService) verifyViaPhpCheckKey(licenseKey string, deviceID uuid.UUID) (*dto.LicenseVerifyResponse, error) {
	phpURL := fmt.Sprintf(
		"https://api.vidcombo.net/checkkey.php?license_key=%s&device_id=%s&app_name=appVidcombo",
		licenseKey, deviceID.String(),
	)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(phpURL)
	if err != nil {
		logger.Log.Warn().Err(err).Msg("PHP checkkey.php proxy failed")
		return nil, ErrInvalidLicenseKey
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, ErrInvalidLicenseKey
	}

	var phpResp struct {
		LicenseKey string `json:"license_key"`
		Status     string `json:"status"`
		EndDate    string `json:"end_date"`
		Lever      string `json:"lever"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&phpResp); err != nil {
		logger.Log.Warn().Err(err).Msg("PHP checkkey.php returned invalid JSON")
		return nil, ErrInvalidLicenseKey
	}

	if phpResp.Status != "active" {
		return &dto.LicenseVerifyResponse{
			IsValid: false,
			Tier:    "free",
			Reason:  "php_key_" + phpResp.Status,
		}, ErrLicenseExpired
	}

	billingCycle := "semiannual"
	switch phpResp.Lever {
	case "plan1":
		billingCycle = "monthly"
	case "plan2":
		billingCycle = "semiannual"
	case "plan3":
		billingCycle = "yearly"
	case "lifetime":
		billingCycle = "lifetime"
	}

	expiresAt := ""
	if phpResp.EndDate != "" {
		if t, err := time.Parse("2006-01-02", phpResp.EndDate); err == nil {
			expiresAt = t.Format(time.RFC3339)
		}
	}

	return &dto.LicenseVerifyResponse{
		IsValid:      true,
		Tier:         "premium",
		BillingCycle: billingCycle,
		ExpiresAt:    expiresAt,
		MaxDevices:   MaxDevicesForPlan(billingCycle),
		IsAutoRenew:  true,
	}, nil
}
