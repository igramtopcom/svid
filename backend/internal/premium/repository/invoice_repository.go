package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"github.com/snakeloader/backend/internal/premium/model"
	"gorm.io/gorm"
	"time"
)

type InvoiceRepository struct {
	db *gorm.DB
}

func NewInvoiceRepository(db *gorm.DB) *InvoiceRepository {
	return &InvoiceRepository{db: db}
}

// DB returns the underlying gorm.DB handle. Used by maintenance tooling
// (e.g. InvoiceAudit) that needs transactional access outside the standard
// repository methods. Regular callers should use the typed methods below.
func (r *InvoiceRepository) DB() *gorm.DB {
	return r.db
}

func (r *InvoiceRepository) Create(invoice *model.Invoice) error {
	return r.db.Create(invoice).Error
}

func (r *InvoiceRepository) Update(invoice *model.Invoice) error {
	return r.db.Save(invoice).Error
}

func (r *InvoiceRepository) FindByID(id uuid.UUID) (*model.Invoice, error) {
	var invoice model.Invoice
	err := r.db.Where("id = ?", id).First(&invoice).Error
	if err != nil {
		return nil, err
	}
	return &invoice, nil
}

func (r *InvoiceRepository) FindByStripeInvoiceID(stripeID string) (*model.Invoice, error) {
	var invoice model.Invoice
	err := r.db.Where("stripe_invoice_id = ?", stripeID).First(&invoice).Error
	if err != nil {
		return nil, err
	}
	return &invoice, nil
}

// FindByStripePaymentIntentID is the first leg of the W1.4 refund/dispute
// fallback chain: locate an invoice by its underlying PaymentIntent so we can
// resolve the license to revoke even when payment_transactions has no row.
// Returns gorm.ErrRecordNotFound on miss.
func (r *InvoiceRepository) FindByStripePaymentIntentID(piID string) (*model.Invoice, error) {
	var invoice model.Invoice
	err := r.db.Where("stripe_payment_intent_id = ?", piID).First(&invoice).Error
	if err != nil {
		return nil, err
	}
	return &invoice, nil
}

// List returns paginated invoices with optional filters.
func (r *InvoiceRepository) List(page, perPage int, status, search, sortBy, sortDir, brand string) ([]model.Invoice, int64, error) {
	var invoices []model.Invoice
	var total int64

	query := r.db.Model(&model.Invoice{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}

	if status != "" {
		query = query.Where("status = ?", status)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where("(contact_email ILIKE ? OR stripe_invoice_id ILIKE ?)", like, like)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "created_at DESC"
	if sortBy != "" {
		allowed := map[string]bool{
			"contact_email": true, "status": true, "amount_due_cents": true,
			"amount_paid_cents": true, "paid_at": true, "created_at": true,
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
	if err := query.Order(orderClause).Offset(offset).Limit(perPage).Find(&invoices).Error; err != nil {
		return nil, 0, err
	}

	return invoices, total, nil
}

// InvoiceStatusCount holds a status and its count.
type InvoiceStatusCount struct {
	Status string `gorm:"column:status"`
	Count  int64  `gorm:"column:count"`
}

// CountByStatus returns invoice counts grouped by status.
func (r *InvoiceRepository) CountByStatus(brand string) ([]InvoiceStatusCount, error) {
	var results []InvoiceStatusCount
	query := r.db.Model(&model.Invoice{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("status, COUNT(*) as count").
		Group("status").
		Find(&results).Error
	return results, err
}

// CountAll returns total number of invoices.
func (r *InvoiceRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.Invoice{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

// TotalPaid returns total paid amount.
func (r *InvoiceRepository) TotalPaid(brand string) (int64, error) {
	var total int64
	query := r.db.Model(&model.Invoice{}).Where("status = 'paid'")
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("COALESCE(SUM(amount_paid_cents), 0)").
		Scan(&total).Error
	return total, err
}

// RevenueToday returns paid revenue for today.
func (r *InvoiceRepository) RevenueToday(brand string) (int64, error) {
	var total int64
	start, end := timeutil.UTCDayBounds(time.Now())
	query := r.db.Model(&model.Invoice{}).
		Where("status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?", start, end)
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("COALESCE(SUM(amount_paid_cents), 0)").
		Scan(&total).Error
	return total, err
}

// RevenueThisMonth returns paid revenue for the current month.
func (r *InvoiceRepository) RevenueThisMonth(brand string) (int64, error) {
	var total int64
	start, end := timeutil.UTCMonthBounds(time.Now())
	query := r.db.Model(&model.Invoice{}).
		Where("status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?", start, end)
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("COALESCE(SUM(amount_paid_cents), 0)").
		Scan(&total).Error
	return total, err
}

// InvoiceDailyRevenue holds daily revenue data from invoices.
type InvoiceDailyRevenue struct {
	Date        string `gorm:"column:date"`
	AmountCents int64  `gorm:"column:amount_cents"`
	Count       int64  `gorm:"column:count"`
}

// RevenueByDay returns daily revenue for paid invoices within the last N days.
func (r *InvoiceRepository) RevenueByDay(days int, brand string) ([]InvoiceDailyRevenue, error) {
	var results []InvoiceDailyRevenue
	start := timeutil.UTCStartOfDay(time.Now()).AddDate(0, 0, -days)
	query := r.db.Model(&model.Invoice{}).
		Where("status = 'paid' AND COALESCE(paid_at, created_at) >= ?", start)
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("DATE(COALESCE(paid_at, created_at) AT TIME ZONE 'UTC') as date, COALESCE(SUM(amount_paid_cents), 0) as amount_cents, COUNT(*) as count").
		Group("DATE(COALESCE(paid_at, created_at) AT TIME ZONE 'UTC')").
		Order("date ASC").
		Find(&results).Error
	return results, err
}

// InvoiceMRRPoint holds monthly revenue data from paid invoices.
type InvoiceMRRPoint struct {
	Month       string `gorm:"column:month"`
	AmountCents int64  `gorm:"column:amount_cents"`
	Count       int64  `gorm:"column:count"`
}

// MRRByMonth returns monthly revenue grouped by month for the last N months.
func (r *InvoiceRepository) MRRByMonth(months int, brand string) ([]InvoiceMRRPoint, error) {
	var results []InvoiceMRRPoint
	now := time.Now().UTC()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC).AddDate(0, -(months - 1), 0)
	query := r.db.Model(&model.Invoice{}).
		Where("status = 'paid' AND COALESCE(paid_at, created_at) >= ?", monthStart)
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("TO_CHAR(DATE_TRUNC('month', COALESCE(paid_at, created_at) AT TIME ZONE 'UTC'), 'YYYY-MM') as month, COALESCE(SUM(amount_paid_cents), 0) as amount_cents, COUNT(*) as count").
		Group("month").
		Order("month ASC").
		Find(&results).Error
	return results, err
}

// InvoiceRevenueByReason holds revenue grouped by billing reason.
type InvoiceRevenueByReason struct {
	BillingReason string `gorm:"column:billing_reason"`
	AmountCents   int64  `gorm:"column:amount_cents"`
	Count         int64  `gorm:"column:count"`
}

// RevenueByBillingReason returns revenue grouped by billing reason (subscription_cycle, subscription_create, etc.).
func (r *InvoiceRepository) RevenueByBillingReason(brand string) ([]InvoiceRevenueByReason, error) {
	var results []InvoiceRevenueByReason
	query := r.db.Model(&model.Invoice{}).Where("status = 'paid'")
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.
		Select("COALESCE(billing_reason, 'unknown') as billing_reason, COALESCE(SUM(amount_paid_cents), 0) as amount_cents, COUNT(*) as count").
		Group("billing_reason").
		Find(&results).Error
	return results, err
}
