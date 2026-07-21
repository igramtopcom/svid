package repository

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"github.com/snakeloader/backend/internal/premium/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type TransactionRepository struct {
	db *gorm.DB
}

func NewTransactionRepository(db *gorm.DB) *TransactionRepository {
	return &TransactionRepository{db: db}
}

func (r *TransactionRepository) GetDB() *gorm.DB {
	return r.db
}

func (r *TransactionRepository) Create(txn *model.PaymentTransaction) error {
	return r.db.Create(txn).Error
}

func (r *TransactionRepository) Update(txn *model.PaymentTransaction) error {
	return r.db.Save(txn).Error
}

func (r *TransactionRepository) FindByID(id uuid.UUID) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := r.db.Where("id = ?", id).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

func (r *TransactionRepository) FindByIdempotencyKey(key string) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := r.db.Where("idempotency_key = ?", key).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

func (r *TransactionRepository) FindByStripeSessionID(sessionID string) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := r.db.Where("stripe_session_id = ?", sessionID).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

// FindByStripeSessionIDForUpdate acquires a row-level lock on the transaction record.
// Must be called within an existing GORM transaction (dbTx).
func (r *TransactionRepository) FindByStripeSessionIDForUpdate(dbTx *gorm.DB, sessionID string) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := dbTx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("stripe_session_id = ?", sessionID).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

func (r *TransactionRepository) FindByCryptoInvoiceID(invoiceID string) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := r.db.Where("crypto_invoice_id = ?", invoiceID).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

// FindByCryptoInvoiceIDForUpdate acquires a row-level lock on the transaction record.
// Must be called within an existing GORM transaction (dbTx).
func (r *TransactionRepository) FindByCryptoInvoiceIDForUpdate(dbTx *gorm.DB, invoiceID string) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := dbTx.Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("crypto_invoice_id = ?", invoiceID).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

// FindByStripePaymentIntentID finds a transaction by its Stripe PaymentIntent ID.
func (r *TransactionRepository) FindByStripePaymentIntentID(piID string) (*model.PaymentTransaction, error) {
	var txn model.PaymentTransaction
	err := r.db.Where("stripe_payment_intent_id = ?", piID).First(&txn).Error
	if err != nil {
		return nil, err
	}
	return &txn, nil
}

func (r *TransactionRepository) List(page, perPage int, status, paymentMethod string) ([]model.PaymentTransaction, int64, error) {
	var txns []model.PaymentTransaction
	var total int64

	query := r.db.Model(&model.PaymentTransaction{})

	if status != "" {
		query = query.Where("status = ?", status)
	}
	if paymentMethod != "" {
		query = query.Where("payment_method = ?", paymentMethod)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&txns).Error; err != nil {
		return nil, 0, err
	}

	return txns, total, nil
}

// FindByDeviceID returns paginated transactions for a specific device.
func (r *TransactionRepository) FindByDeviceID(deviceID uuid.UUID, page, perPage int) ([]model.PaymentTransaction, int64, error) {
	var txns []model.PaymentTransaction
	var total int64

	query := r.db.Model(&model.PaymentTransaction{}).Where("device_id = ?", deviceID)

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&txns).Error; err != nil {
		return nil, 0, err
	}

	return txns, total, nil
}

// TotalRevenue returns the sum of amount_cents for completed transactions.
func (r *TransactionRepository) TotalRevenue(brand string) (int64, error) {
	var total int64
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Where("status = 'completed'").
		Select("COALESCE(SUM(amount_cents), 0)").
		Scan(&total).Error
	return total, err
}

// RevenueByBillingCycle returns revenue for a specific billing cycle.
func (r *TransactionRepository) RevenueByBillingCycle(cycle string) (int64, error) {
	var total int64
	err := r.db.Model(&model.PaymentTransaction{}).
		Where("status = 'completed' AND billing_cycle = ?", cycle).
		Select("COALESCE(SUM(amount_cents), 0)").
		Scan(&total).Error
	return total, err
}

// EnhancedTransaction is a transaction joined with license data for admin views.
type EnhancedTransaction struct {
	model.PaymentTransaction
	ContactEmail *string `gorm:"column:contact_email"`
	LicenseKey   *string `gorm:"column:license_key"`
}

// ListEnhanced returns paginated transactions with optional date range and search,
// joined with license data for contact_email and license_key.
func (r *TransactionRepository) ListEnhanced(page, perPage int, status, paymentMethod, search, dateFrom, dateTo, sortBy, sortDir, brand string) ([]EnhancedTransaction, int64, error) {
	var txns []EnhancedTransaction
	var total int64

	query := r.db.Model(&model.PaymentTransaction{}).
		Select("payment_transactions.*, premium_licenses.contact_email, premium_licenses.license_key").
		Joins("LEFT JOIN premium_licenses ON premium_licenses.id = payment_transactions.license_id")

	if brand != "" {
		query = query.Where("payment_transactions.brand = ?", brand)
	}
	if status != "" {
		query = query.Where("payment_transactions.status = ?", status)
	}
	if paymentMethod != "" {
		query = query.Where("payment_transactions.payment_method = ?", paymentMethod)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where(
			"(payment_transactions.id::text ILIKE ? OR premium_licenses.contact_email ILIKE ? OR premium_licenses.license_key ILIKE ?)",
			like, like, like,
		)
	}
	if dateFrom != "" {
		query = query.Where("payment_transactions.created_at >= ?", dateFrom)
	}
	if dateTo != "" {
		query = query.Where("payment_transactions.created_at <= ?", dateTo)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "payment_transactions.created_at DESC"
	if sortBy != "" {
		allowed := map[string]string{
			"amount_cents": "payment_transactions.amount_cents",
			"status":       "payment_transactions.status",
			"created_at":   "payment_transactions.created_at",
		}
		if col, ok := allowed[sortBy]; ok {
			dir := "DESC"
			if sortDir == "asc" {
				dir = "ASC"
			}
			orderClause = col + " " + dir
		}
	}

	offset := (page - 1) * perPage
	if err := query.Order(orderClause).Offset(offset).Limit(perPage).Find(&txns).Error; err != nil {
		return nil, 0, err
	}

	return txns, total, nil
}

// TransactionStatusCount holds a status and its count.
type TransactionStatusCount struct {
	Status string `gorm:"column:status"`
	Count  int64  `gorm:"column:count"`
}

// CountByStatus returns counts grouped by status.
func (r *TransactionRepository) CountByStatus(brand string) ([]TransactionStatusCount, error) {
	var results []TransactionStatusCount
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("status, COUNT(*) as count").
		Group("status").
		Find(&results).Error
	return results, err
}

// RevenueToday returns total completed revenue for today (UTC).
func (r *TransactionRepository) RevenueToday(brand string) (int64, error) {
	var total int64
	start, end := timeutil.UTCDayBounds(time.Now())
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Where("status = 'completed' AND completed_at >= ? AND completed_at < ?", start, end).
		Select("COALESCE(SUM(amount_cents), 0)").
		Scan(&total).Error
	return total, err
}

// RevenueThisMonth returns total completed revenue for the current month (UTC).
func (r *TransactionRepository) RevenueThisMonth(brand string) (int64, error) {
	var total int64
	start, end := timeutil.UTCMonthBounds(time.Now())
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Where("status = 'completed' AND completed_at >= ? AND completed_at < ?", start, end).
		Select("COALESCE(SUM(amount_cents), 0)").
		Scan(&total).Error
	return total, err
}

// CountAll returns total number of transactions.
func (r *TransactionRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

// FindByEmail returns transactions linked to licenses with a given contact email.
func (r *TransactionRepository) FindByEmail(email string, page, perPage int) ([]EnhancedTransaction, int64, error) {
	var txns []EnhancedTransaction
	var total int64

	// Case-insensitive + trim-insensitive lookup. Matches the predicate
	// used by LicenseRepository.FindByEmail (Round 4 defense-in-depth) so
	// admin customer-detail revenue/txn lists stay consistent with the
	// license list regardless of input casing or pre-migration data.
	normalized := strings.ToLower(strings.TrimSpace(email))
	query := r.db.Model(&model.PaymentTransaction{}).
		Select("payment_transactions.*, premium_licenses.contact_email, premium_licenses.license_key").
		Joins("JOIN premium_licenses ON premium_licenses.id = payment_transactions.license_id").
		Where("LOWER(TRIM(premium_licenses.contact_email)) = ?", normalized)

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("payment_transactions.created_at DESC").Offset(offset).Limit(perPage).Find(&txns).Error; err != nil {
		return nil, 0, err
	}

	return txns, total, nil
}

// DailyRevenue holds revenue for a single day.
type DailyRevenue struct {
	Date        string `gorm:"column:date"`
	AmountCents int64  `gorm:"column:amount_cents"`
	Count       int64  `gorm:"column:count"`
}

// RevenueByDay returns daily revenue for completed transactions within a date range.
func (r *TransactionRepository) RevenueByDay(days int, brand string) ([]DailyRevenue, error) {
	var results []DailyRevenue
	start := timeutil.UTCStartOfDay(time.Now()).AddDate(0, 0, -days)
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("DATE(completed_at AT TIME ZONE 'UTC') as date, COALESCE(SUM(amount_cents), 0) as amount_cents, COUNT(*) as count").
		Where("status = 'completed' AND completed_at >= ?", start).
		Group("DATE(completed_at AT TIME ZONE 'UTC')").
		Order("date ASC").
		Find(&results).Error
	return results, err
}

// RevenueByMethod returns revenue grouped by payment method.
type RevenueByMethod struct {
	PaymentMethod string `gorm:"column:payment_method"`
	AmountCents   int64  `gorm:"column:amount_cents"`
	Count         int64  `gorm:"column:count"`
}

func (r *TransactionRepository) RevenueGroupedByMethod(brand string) ([]RevenueByMethod, error) {
	var results []RevenueByMethod
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("payment_method, COALESCE(SUM(amount_cents), 0) as amount_cents, COUNT(*) as count").
		Where("status = 'completed'").
		Group("payment_method").
		Find(&results).Error
	return results, err
}

// RevenueByBillingCycleAll returns revenue grouped by billing cycle.
type RevenueByCycle struct {
	BillingCycle string `gorm:"column:billing_cycle"`
	AmountCents  int64  `gorm:"column:amount_cents"`
	Count        int64  `gorm:"column:count"`
}

func (r *TransactionRepository) RevenueGroupedByCycle(brand string) ([]RevenueByCycle, error) {
	var results []RevenueByCycle
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("billing_cycle, COALESCE(SUM(amount_cents), 0) as amount_cents, COUNT(*) as count").
		Where("status = 'completed'").
		Group("billing_cycle").
		Find(&results).Error
	return results, err
}

// TotalRefunded returns total refunded amount.
func (r *TransactionRepository) TotalRefunded(brand string) (int64, error) {
	var total int64
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Where("status = 'refunded'").
		Select("COALESCE(SUM(amount_cents), 0)").
		Scan(&total).Error
	return total, err
}

// RefundCount returns the number of refunded transactions.
func (r *TransactionRepository) RefundCount(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.PaymentTransaction{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Where("status = 'refunded'").
		Count(&count).Error
	return count, err
}

// TotalRevenueByEmail returns total revenue for a given email.
// Case-insensitive + trim-insensitive — see FindByEmail rationale.
func (r *TransactionRepository) TotalRevenueByEmail(email string) (int64, error) {
	var total int64
	normalized := strings.ToLower(strings.TrimSpace(email))
	err := r.db.Model(&model.PaymentTransaction{}).
		Joins("JOIN premium_licenses ON premium_licenses.id = payment_transactions.license_id").
		Where("payment_transactions.status = 'completed' AND LOWER(TRIM(premium_licenses.contact_email)) = ?", normalized).
		Select("COALESCE(SUM(payment_transactions.amount_cents), 0)").
		Scan(&total).Error
	return total, err
}
