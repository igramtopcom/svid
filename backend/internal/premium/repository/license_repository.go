package repository

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/premium/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type LicenseRepository struct {
	db *gorm.DB
}

func NewLicenseRepository(db *gorm.DB) *LicenseRepository {
	return &LicenseRepository{db: db}
}

func (r *LicenseRepository) Create(license *model.PremiumLicense) error {
	return r.db.Create(license).Error
}

func (r *LicenseRepository) Update(license *model.PremiumLicense) error {
	return r.db.Save(license).Error
}

func (r *LicenseRepository) FindByID(id uuid.UUID) (*model.PremiumLicense, error) {
	var license model.PremiumLicense
	err := r.db.Where("id = ?", id).First(&license).Error
	if err != nil {
		return nil, err
	}
	return &license, nil
}

func (r *LicenseRepository) FindByKey(key string) (*model.PremiumLicense, error) {
	var license model.PremiumLicense
	err := r.db.Where("license_key = ?", key).First(&license).Error
	if err != nil {
		return nil, err
	}
	return &license, nil
}

func (r *LicenseRepository) FindByStripeSubscriptionID(subID string) (*model.PremiumLicense, error) {
	var license model.PremiumLicense
	err := r.db.Where("stripe_subscription_id = ?", subID).First(&license).Error
	if err != nil {
		return nil, err
	}
	return &license, nil
}

func (r *LicenseRepository) FindByDeviceID(deviceID uuid.UUID) (*model.PremiumLicense, error) {
	var license model.PremiumLicense
	err := r.db.Joins("JOIN license_devices ON license_devices.license_id = premium_licenses.id").
		Where("license_devices.device_id = ?", deviceID).
		Order("premium_licenses.created_at DESC").
		First(&license).Error
	if err != nil {
		return nil, err
	}
	return &license, nil
}

func (r *LicenseRepository) List(page, perPage int, tier, paymentMethod, search, sortBy, sortDir, brand string) ([]model.PremiumLicense, int64, error) {
	var licenses []model.PremiumLicense
	var total int64

	query := r.db.Model(&model.PremiumLicense{})

	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	if tier != "" {
		query = query.Where("tier = ?", tier)
	}
	if paymentMethod != "" {
		query = query.Where("payment_method = ?", paymentMethod)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where("(license_key ILIKE ? OR contact_email ILIKE ?)", like, like)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "created_at DESC"
	if sortBy != "" {
		allowed := map[string]bool{
			"tier": true, "billing_cycle": true, "payment_method": true,
			"expires_at": true, "created_at": true,
		}
		if allowed[sortBy] {
			dir := "DESC"
			if sortDir == "asc" {
				dir = "ASC"
			}
			orderClause = sortBy + " " + dir
		}
	}

	offset := (page - 1) * perPage
	if err := query.Order(orderClause).Offset(offset).Limit(perPage).Find(&licenses).Error; err != nil {
		return nil, 0, err
	}

	return licenses, total, nil
}

// CountDevices returns how many devices are registered to a license.
func (r *LicenseRepository) CountDevices(licenseID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.Model(&model.LicenseDevice{}).Where("license_id = ?", licenseID).Count(&count).Error
	return count, err
}

// RegisterDevice adds a device to a license's device list.
func (r *LicenseRepository) RegisterDevice(ld *model.LicenseDevice) error {
	return r.db.Create(ld).Error
}

// FindLicenseDevice checks if a device is already registered to a license.
func (r *LicenseRepository) FindLicenseDevice(licenseID, deviceID uuid.UUID) (*model.LicenseDevice, error) {
	var ld model.LicenseDevice
	err := r.db.Where("license_id = ? AND device_id = ?", licenseID, deviceID).First(&ld).Error
	if err != nil {
		return nil, err
	}
	return &ld, nil
}

// UpdateLicenseDevice updates a license device record (e.g., last_verified_at).
func (r *LicenseRepository) UpdateLicenseDevice(ld *model.LicenseDevice) error {
	return r.db.Save(ld).Error
}

// FindActiveByEmail returns the most recent active premium license matching a contact email.
// Compares against the LOWER() of contact_email so a row stored mixed-case from the legacy
// pre-W1.2 path still matches a normalized lookup.
func (r *LicenseRepository) FindActiveByEmail(email, brand string) (*model.PremiumLicense, error) {
	var license model.PremiumLicense
	q := r.db.Where(
		"LOWER(contact_email) = ? AND tier = 'premium' AND cancelled_at IS NULL AND "+
			"(expires_at > ? OR billing_cycle IN ('lifetime','lifetime1','lifetime2','lifetime3'))",
		email, time.Now(),
	)
	if brand != "" {
		q = q.Where("brand = ?", brand)
	}
	err := q.Order("created_at DESC").First(&license).Error
	if err != nil {
		return nil, err
	}
	return &license, nil
}

// FindActiveStripeByEmail returns the most recent active premium license matching a
// contact email AND having a non-empty stripe_customer_id. Used by the magic-link
// portal flow so an email with a newer manual/crypto license + older Stripe license
// still gets a working Billing Portal link (the plain "most recent" lookup would
// hand back the manual row and fail at portal-session creation).
//
// Email comparison is case+trim-insensitive — parity with FindActiveByEmail
// so a mixed-case row stored pre-W1.2 still matches a normalized lookup.
func (r *LicenseRepository) FindActiveStripeByEmail(email string) (*model.PremiumLicense, error) {
	var license model.PremiumLicense
	normalized := strings.ToLower(strings.TrimSpace(email))
	err := r.db.Where("LOWER(TRIM(contact_email)) = LOWER(TRIM(?)) AND tier = 'premium' AND stripe_customer_id IS NOT NULL AND stripe_customer_id != ''", normalized).
		Order("created_at DESC").First(&license).Error
	if err != nil {
		return nil, err
	}
	return &license, nil
}

// Stats methods for admin dashboard.

func (r *LicenseRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PremiumLicense{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *LicenseRepository) CountActive(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PremiumLicense{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Where(model.ActivePremiumLicenseSQL(""), time.Now().UTC()).
		Count(&count).Error
	return count, err
}

func (r *LicenseRepository) CountExpired(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PremiumLicense{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Where(model.ExpiredPremiumLicenseSQL(""), time.Now().UTC()).
		Count(&count).Error
	return count, err
}

func (r *LicenseRepository) CountCancelled(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PremiumLicense{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Where("tier = 'premium' AND cancelled_at IS NOT NULL").
		Count(&count).Error
	return count, err
}

func (r *LicenseRepository) CountByPaymentMethod(method, brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PremiumLicense{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Where("payment_method = ? AND tier = 'premium'", method).
		Count(&count).Error
	return count, err
}

// ListDevices returns all devices registered to a license.
func (r *LicenseRepository) ListDevices(licenseID uuid.UUID) ([]model.LicenseDevice, error) {
	var devices []model.LicenseDevice
	err := r.db.Where("license_id = ?", licenseID).Order("registered_at ASC").Find(&devices).Error
	return devices, err
}

// RegisterDeviceWithLimit atomically checks device count and registers a device within a transaction.
// It uses SELECT ... FOR UPDATE on the license row to prevent concurrent requests from exceeding the limit.
func (r *LicenseRepository) RegisterDeviceWithLimit(ld *model.LicenseDevice, maxDevices int) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		// Lock the license row to prevent concurrent device registrations
		var license model.PremiumLicense
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&license, "id = ?", ld.LicenseID).Error; err != nil {
			return err
		}
		// Count current devices within the same transaction
		var count int64
		if err := tx.Model(&model.LicenseDevice{}).Where("license_id = ?", ld.LicenseID).Count(&count).Error; err != nil {
			return err
		}
		if int(count) >= maxDevices {
			return errors.New("device limit exceeded")
		}
		return tx.Create(ld).Error
	})
}

// ListSubscriptions returns paginated licenses filtered as subscriptions (tier=premium)
// with optional status filter: active, cancelled, expired.
func (r *LicenseRepository) ListSubscriptions(page, perPage int, status, search, sortBy, sortDir, brand string) ([]model.PremiumLicense, int64, error) {
	var licenses []model.PremiumLicense
	var total int64

	query := r.db.Model(&model.PremiumLicense{}).Where("tier = 'premium'")

	if brand != "" {
		query = query.Where("brand = ?", brand)
	}

	now := time.Now()
	switch status {
	case "active":
		query = query.Where(model.ActivePremiumLicenseSQL(""), now.UTC())
	case "cancelled":
		query = query.Where("cancelled_at IS NOT NULL")
	case "expired":
		query = query.Where(model.ExpiredPremiumLicenseSQL(""), now.UTC())
	}

	if search != "" {
		like := "%" + search + "%"
		query = query.Where("(license_key ILIKE ? OR contact_email ILIKE ?)", like, like)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "created_at DESC"
	if sortBy != "" {
		allowed := map[string]bool{
			"contact_email": true, "billing_cycle": true, "status": true,
			"expires_at": true, "created_at": true,
		}
		if allowed[sortBy] {
			dir := "DESC"
			if sortDir == "asc" {
				dir = "ASC"
			}
			orderClause = sortBy + " " + dir
		}
	}

	offset := (page - 1) * perPage
	if err := query.Order(orderClause).Offset(offset).Limit(perPage).Find(&licenses).Error; err != nil {
		return nil, 0, err
	}

	return licenses, total, nil
}

// CalculateMRR returns Monthly Recurring Revenue from active monthly subscriptions.
func (r *LicenseRepository) CalculateMRR(brand string) (int64, error) {
	var total int64
	query := r.db.Model(&model.PaymentTransaction{}).
		Joins("JOIN premium_licenses ON premium_licenses.id = payment_transactions.license_id").
		Where("payment_transactions.status = 'completed' AND premium_licenses.billing_cycle = 'monthly' AND premium_licenses.expires_at > ? AND premium_licenses.cancelled_at IS NULL", time.Now())
	if brand != "" {
		query = query.Where("premium_licenses.brand = ?", brand)
	}
	err := query.Select("COALESCE(SUM(payment_transactions.amount_cents), 0)").
		Scan(&total).Error
	return total, err
}

// CustomerRow represents an aggregate customer view.
type CustomerRow struct {
	ContactEmail     string    `gorm:"column:contact_email"`
	StripeCustomerID *string   `gorm:"column:stripe_customer_id"`
	LicenseCount     int64     `gorm:"column:license_count"`
	ActiveLicenses   int64     `gorm:"column:active_licenses"`
	FirstPurchase    time.Time `gorm:"column:first_purchase"`
	LastPurchase     time.Time `gorm:"column:last_purchase"`
	TotalSpentCents  int64     `gorm:"column:total_spent_cents"`
}

// ListCustomers returns paginated customer aggregates grouped by contact_email.
func (r *LicenseRepository) ListCustomers(page, perPage int, search, sortBy, sortDir, brand string) ([]CustomerRow, int64, error) {
	var customers []CustomerRow
	var total int64

	baseQuery := r.db.Model(&model.PremiumLicense{}).
		Where("contact_email IS NOT NULL AND contact_email != ''")

	if brand != "" {
		baseQuery = baseQuery.Where("brand = ?", brand)
	}
	if search != "" {
		like := "%" + search + "%"
		baseQuery = baseQuery.Where("(contact_email ILIKE ? OR stripe_customer_id ILIKE ?)", like, like)
	}

	// Count distinct emails
	if err := baseQuery.Select("COUNT(DISTINCT contact_email)").Scan(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "last_purchase DESC"
	if sortBy != "" {
		allowed := map[string]bool{
			"total_spent_cents": true, "license_count": true,
			"first_purchase": true, "last_purchase": true,
		}
		if allowed[sortBy] {
			dir := "DESC"
			if sortDir == "asc" {
				dir = "ASC"
			}
			orderClause = sortBy + " " + dir
		}
	}

	offset := (page - 1) * perPage
	now := time.Now().UTC()
	subQuery := r.db.Model(&model.PremiumLicense{}).
		Select(`contact_email,
			MAX(stripe_customer_id) as stripe_customer_id,
			COUNT(*) as license_count,
			COUNT(CASE WHEN `+model.ActivePremiumLicenseSQL("")+` THEN 1 END) as active_licenses,
			MIN(created_at) as first_purchase,
			MAX(created_at) as last_purchase`, now).
		Where("contact_email IS NOT NULL AND contact_email != ''")

	if brand != "" {
		subQuery = subQuery.Where("brand = ?", brand)
	}
	if search != "" {
		like := "%" + search + "%"
		subQuery = subQuery.Where("(contact_email ILIKE ? OR stripe_customer_id ILIKE ?)", like, like)
	}

	subQuery = subQuery.Group("contact_email").
		Order(orderClause).
		Offset(offset).Limit(perPage)

	if err := subQuery.Find(&customers).Error; err != nil {
		return nil, 0, err
	}

	// Enrich with total spent from transactions
	for i, c := range customers {
		var spent int64
		r.db.Model(&model.PaymentTransaction{}).
			Joins("JOIN premium_licenses ON premium_licenses.id = payment_transactions.license_id").
			Where("payment_transactions.status = 'completed' AND premium_licenses.contact_email = ?", c.ContactEmail).
			Select("COALESCE(SUM(payment_transactions.amount_cents), 0)").
			Scan(&spent)
		customers[i].TotalSpentCents = spent
	}

	return customers, total, nil
}

// CountCustomers returns the total number of unique customers (by email).
func (r *LicenseRepository) CountCustomers(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PremiumLicense{}).
		Where("contact_email IS NOT NULL AND contact_email != ''")
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Select("COUNT(DISTINCT contact_email)").
		Scan(&count).Error
	return count, err
}

// FindByEmail returns all licenses for a given contact email. Case- and
// trim-insensitive — see FindActiveByEmail for the defense-in-depth
// rationale.
func (r *LicenseRepository) FindByEmail(email string) ([]model.PremiumLicense, error) {
	var licenses []model.PremiumLicense
	normalized := strings.ToLower(strings.TrimSpace(email))
	err := r.db.Where("LOWER(TRIM(contact_email)) = ?", normalized).
		Order("created_at DESC").Find(&licenses).Error
	return licenses, err
}

// DeleteDevice removes a device registration from a license.
func (r *LicenseRepository) DeleteDevice(licenseID, deviceID uuid.UUID) error {
	result := r.db.Where("license_id = ? AND device_id = ?", licenseID, deviceID).
		Delete(&model.LicenseDevice{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}
