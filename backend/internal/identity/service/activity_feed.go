package service

import (
	"fmt"
	"strings"
	"time"

	"github.com/snakeloader/backend/internal/identity/dto"
	"gorm.io/gorm"
)

// ActivityFeedService aggregates recent system-wide events into a unified feed.
// Used by the admin dashboard to show "what's happening right now" across all modules.
type ActivityFeedService struct {
	db *gorm.DB
}

func NewActivityFeedService(db *gorm.DB) *ActivityFeedService {
	return &ActivityFeedService{db: db}
}

// GetRecentActivity returns the most recent N events across the system,
// brand-filtered when brand is non-empty.
//
// Query plan (Postgres): 7-way UNION ALL wrapped in a ranking CTE, sort, and
// limit. We intentionally interleave event types via ROW_NUMBER() so bursty
// device registrations do not drown out payments, crashes, or tickets in the
// admin dashboard feed. Each sub-query is expected to hit an index on
// `created_at DESC` or similar:
//   - devices:              idx_devices_created_at
//   - payment_transactions: idx_payment_transactions_completed_at_paid (partial)
//   - bug_reports:          idx_bug_reports_device_id (JOIN) + seq scan on created_at
//   - tickets:              idx_tickets_device_id (JOIN) + seq scan
//   - crash_reports:        idx_crash_reports_severity (WHERE filter)
//   - app_ratings:          seq scan (small table)
//   - premium_licenses:     idx_premium_licenses_created_at
//
// Run `EXPLAIN ANALYZE` against the produced SQL to verify index usage if
// this endpoint becomes a hot-path bottleneck.
func (s *ActivityFeedService) GetRecentActivity(limit int, brand string) (*dto.ActivityFeedResponse, error) {
	pageSQL, args := buildActivityFeedQuery(limit, brand)

	var rows []struct {
		Type      string    `gorm:"column:type"`
		Timestamp time.Time `gorm:"column:timestamp"`
		Title     string    `gorm:"column:title"`
		Severity  string    `gorm:"column:severity"`
		RelatedID string    `gorm:"column:related_id"`
		Metadata  string    `gorm:"column:metadata"`
	}
	if err := s.db.Raw(pageSQL, args...).Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("failed to query activity feed: %w", err)
	}

	events := make([]dto.TimelineEvent, len(rows))
	for i, r := range rows {
		events[i] = dto.TimelineEvent{
			Type:        r.Type,
			Timestamp:   r.Timestamp.Format(time.RFC3339),
			Title:       r.Title,
			Description: descriptionForType(r.Type),
			Severity:    r.Severity,
			RelatedID:   r.RelatedID,
			Metadata:    r.Metadata,
		}
	}

	return &dto.ActivityFeedResponse{Events: events}, nil
}

// buildActivityFeedQuery assembles the UNION ALL SQL + args for GetRecentActivity.
// Extracted as a pure function so the SQL builder can be unit-tested without a DB
// — verifies placeholder count matches arg count, which is the #1 regression risk
// when someone edits the query fragments.
func buildActivityFeedQuery(limit int, brand string) (string, []interface{}) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	// Build UNION ALL query across event-producing tables.
	// All sub-queries select the same columns: type, timestamp, title, severity, related_id, metadata.
	var unionParts []string
	var args []interface{}

	// Brand filter fragments
	brandJoinDevices := ""
	brandWhereDirect := ""
	if brand != "" {
		brandJoinDevices = "JOIN devices d ON d.id = src.device_id AND d.brand = ?"
		brandWhereDirect = "AND src.brand = ?"
	}

	// 1. Device registrations
	{
		q := `SELECT 'device_registered' AS type, src.created_at AS timestamp,
			CONCAT('New device: ', COALESCE(NULLIF(src.device_name, ''), src.hardware_id)) AS title,
			'info' AS severity,
			src.id::text AS related_id,
			CONCAT(src.os, ' · ', src.brand) AS metadata
			FROM devices src WHERE 1=1`
		if brand != "" {
			q += " AND src.brand = ?"
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	// 2. Successful transactions (paid)
	{
		q := `SELECT 'transaction' AS type, src.completed_at AS timestamp,
			CONCAT('$', ROUND(src.amount_cents::numeric / 100, 2), ' · ', src.billing_cycle) AS title,
			'success' AS severity,
			src.id::text AS related_id,
			COALESCE(src.payment_method, '') AS metadata
			FROM payment_transactions src
			WHERE src.status = 'completed' AND src.completed_at IS NOT NULL`
		if brand != "" {
			q += " AND src.brand = ?"
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	// 3. New bug reports
	{
		q := `SELECT 'bug_report' AS type, src.created_at AS timestamp,
			src.title AS title,
			COALESCE(NULLIF(src.priority, ''), 'medium') AS severity,
			src.id::text AS related_id,
			COALESCE(src.status, '') AS metadata
			FROM bug_reports src ` + brandJoinDevices + ` WHERE 1=1`
		if brand != "" {
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	// 4. New tickets
	{
		q := `SELECT 'ticket' AS type, src.created_at AS timestamp,
			src.subject AS title,
			CASE WHEN src.priority = 'urgent' THEN 'high' ELSE COALESCE(NULLIF(src.priority, ''), 'low') END AS severity,
			src.id::text AS related_id,
			COALESCE(src.status, '') AS metadata
			FROM tickets src ` + brandJoinDevices + ` WHERE 1=1`
		if brand != "" {
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	// 5. Critical/high crashes only (avoid noise from low-severity)
	{
		q := `SELECT 'crash' AS type, src.created_at AS timestamp,
			COALESCE(NULLIF(src.error_message, ''), 'Crash report') AS title,
			COALESCE(NULLIF(src.severity, ''), 'medium') AS severity,
			src.id::text AS related_id,
			COALESCE(src.app_version, '') AS metadata
			FROM crash_reports src ` + brandJoinDevices + `
			WHERE src.severity IN ('critical', 'high')`
		if brand != "" {
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	// 6. New ratings (with content)
	{
		q := `SELECT 'rating' AS type, src.created_at AS timestamp,
			CONCAT(src.rating, '★ ', LEFT(COALESCE(src.review, ''), 60)) AS title,
			CASE WHEN src.rating <= 2 THEN 'high' WHEN src.rating = 3 THEN 'medium' ELSE 'info' END AS severity,
			src.id::text AS related_id,
			COALESCE(src.app_version, '') AS metadata
			FROM app_ratings src ` + brandJoinDevices + ` WHERE 1=1`
		if brand != "" {
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	// 7. New licenses (admin-created or webhook-created)
	{
		q := `SELECT 'license' AS type, src.created_at AS timestamp,
			CONCAT('License: ', src.tier, ' · ', src.billing_cycle) AS title,
			'info' AS severity,
			src.id::text AS related_id,
			COALESCE(src.payment_method, '') AS metadata
			FROM premium_licenses src WHERE 1=1 ` + brandWhereDirect
		if brand != "" {
			args = append(args, brand)
		}
		unionParts = append(unionParts, q)
	}

	unionQuery := strings.Join(unionParts, " UNION ALL ")
	pageSQL := fmt.Sprintf(`
		WITH raw_feed AS (%s),
		ranked_feed AS (
			SELECT type, timestamp, title, severity, related_id, metadata,
				ROW_NUMBER() OVER (PARTITION BY type ORDER BY timestamp DESC) AS type_rank
			FROM raw_feed
		)
		SELECT type, timestamp, title, severity, related_id, metadata
		FROM ranked_feed
		ORDER BY type_rank ASC, timestamp DESC
		LIMIT ?`, unionQuery)
	args = append(args, limit)

	return pageSQL, args
}
