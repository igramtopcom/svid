package service

import (
	"fmt"
	"time"

	"github.com/snakeloader/backend/internal/identity/dto"
	"gorm.io/gorm"
)

// TopCustomersService returns the highest-revenue customers (grouped by contact_email).
type TopCustomersService struct {
	db *gorm.DB
}

func NewTopCustomersService(db *gorm.DB) *TopCustomersService {
	return &TopCustomersService{db: db}
}

// GetTopCustomers returns the top-N customers by total revenue, grouped by contact_email.
// A customer is identified by their email across all their licenses/transactions.
// Brand filter applies to the underlying licenses when non-empty.
//
// Query plan (Postgres):
//   - Scan premium_licenses via idx_premium_licenses_contact_email (or seq scan if small)
//   - Nested-loop join to payment_transactions via idx_payment_transactions_status_created
//     (the ON clause filters status='completed' so index helps)
//   - HashAggregate on contact_email, HAVING filters out $0 admin-created free licenses
//   - Sort + Limit
//
// Run `EXPLAIN ANALYZE` against the produced SQL to verify index usage.
func (s *TopCustomersService) GetTopCustomers(limit int, brand string) (*dto.TopCustomersResponse, error) {
	q, args := buildTopCustomersQuery(limit, brand)

	var rows []struct {
		ContactEmail    string     `gorm:"column:contact_email"`
		LicenseCount    int64      `gorm:"column:license_count"`
		TotalSpentCents int64      `gorm:"column:total_spent_cents"`
		LastPurchase    *time.Time `gorm:"column:last_purchase"`
	}
	if err := s.db.Raw(q, args...).Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("failed to query top customers: %w", err)
	}

	customers := make([]dto.TopCustomerSummary, len(rows))
	for i, r := range rows {
		lastPurchase := ""
		if r.LastPurchase != nil {
			lastPurchase = r.LastPurchase.Format(time.RFC3339)
		}
		customers[i] = dto.TopCustomerSummary{
			ContactEmail:    r.ContactEmail,
			LicenseCount:    r.LicenseCount,
			TotalSpentCents: r.TotalSpentCents,
			LastPurchase:    lastPurchase,
		}
	}

	return &dto.TopCustomersResponse{Customers: customers}, nil
}

// buildTopCustomersQuery assembles the SQL + args for GetTopCustomers.
// Extracted as a pure function so the SQL builder can be unit-tested without a DB
// — verifies placeholder count matches arg count, HAVING clause is present (filters
// $0 free licenses), and LIMIT is always the final arg.
func buildTopCustomersQuery(limit int, brand string) (string, []interface{}) {
	if limit <= 0 || limit > 100 {
		limit = 10
	}

	// We join premium_licenses (which holds contact_email) with payment_transactions
	// on license_id, and group by email. Customers without email are excluded.
	q := `
		SELECT pl.contact_email AS contact_email,
			COUNT(DISTINCT pl.id) AS license_count,
			COALESCE(SUM(pt.amount_cents), 0) AS total_spent_cents,
			MAX(pt.completed_at) AS last_purchase
		FROM premium_licenses pl
		LEFT JOIN payment_transactions pt
			ON pt.license_id = pl.id AND pt.status = 'completed'
		WHERE pl.contact_email IS NOT NULL AND pl.contact_email <> ''
	`
	args := []interface{}{}
	if brand != "" {
		q += " AND pl.brand = ?"
		args = append(args, brand)
	}
	q += `
		GROUP BY pl.contact_email
		HAVING COALESCE(SUM(pt.amount_cents), 0) > 0
		ORDER BY total_spent_cents DESC, license_count DESC
		LIMIT ?
	`
	args = append(args, limit)

	return q, args
}
