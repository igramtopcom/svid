package database

import (
	"fmt"
	"time"

	alertmodel "github.com/snakeloader/backend/internal/alerts/model"
	analyticsmodel "github.com/snakeloader/backend/internal/analytics/model"
	assistantmodel "github.com/snakeloader/backend/internal/assistant/model"
	bugmodel "github.com/snakeloader/backend/internal/bugs/model"
	feedbackmodel "github.com/snakeloader/backend/internal/feedback/model"
	"github.com/snakeloader/backend/internal/identity/model"
	"github.com/snakeloader/backend/internal/pkg/crypto"
	"github.com/snakeloader/backend/internal/pkg/logger"
	premiummodel "github.com/snakeloader/backend/internal/premium/model"
	productmodel "github.com/snakeloader/backend/internal/product/model"
	"gorm.io/gorm"
)

func RunMigrations(db *gorm.DB) error {
	logger.Log.Info().Msg("Running database migrations...")

	if err := db.AutoMigrate(
		// Identity
		&model.Device{},
		&model.ApiKey{},
		&model.Admin{},
		// Bugs
		&bugmodel.CrashGroup{},
		&bugmodel.CrashReport{},
		&bugmodel.BugReport{},
		&bugmodel.BugAttachment{},
		// Product Control
		&productmodel.FeatureFlag{},
		&productmodel.RemoteConfig{},
		&productmodel.AppRelease{},
		&productmodel.Announcement{},
		// Feedback
		&feedbackmodel.Ticket{},
		&feedbackmodel.TicketMessage{},
		&feedbackmodel.FeatureRequest{},
		&feedbackmodel.FeatureVote{},
		&feedbackmodel.AppRating{},
		// Assistant
		&assistantmodel.ChatSession{},
		&assistantmodel.ChatMessage{},
		&assistantmodel.KnowledgeBase{},
		// Analytics
		&analyticsmodel.AnalyticsEvent{},
		&analyticsmodel.BootstrapEvent{},
		&analyticsmodel.DailyStats{},
		&analyticsmodel.DownloadError{},
		// Premium
		&premiummodel.PremiumLicense{},
		&premiummodel.PaymentTransaction{},
		&premiummodel.LicenseDevice{},
		&premiummodel.WebhookEvent{},
		&premiummodel.Invoice{},
		// Diagnostic Logs
		&bugmodel.DiagnosticLog{},
		// Alerts
		&alertmodel.AlertConfig{},
		&alertmodel.AlertLog{},
		// Audit
		&model.AuditLog{},
	); err != nil {
		return fmt.Errorf("failed to run migrations: %w", err)
	}

	// Multi-brand migration: drop old hardware_id unique index (now unique per brand+hardware_id)
	// Safe to run repeatedly — ignores error if index doesn't exist.
	db.Exec("DROP INDEX IF EXISTS idx_devices_hardware_id")
	db.Exec("DROP INDEX IF EXISTS uni_devices_hardware_id")

	// Backfill existing devices with default brand
	db.Exec("UPDATE devices SET brand = 'ssvid' WHERE brand IS NULL OR brand = ''")

	// Backfill existing invoices with default brand
	db.Exec("UPDATE invoices SET brand = 'ssvid' WHERE brand IS NULL OR brand = ''")

	// Backfill existing licenses: set brand from device, default to 'ssvid'
	db.Exec(`UPDATE premium_licenses SET brand = COALESCE(
		(SELECT d.brand FROM devices d WHERE d.id = premium_licenses.device_id AND d.brand != ''),
		'ssvid'
	) WHERE brand IS NULL OR brand = ''`)

	// Backfill existing transactions: set brand from device, default to 'ssvid'
	db.Exec(`UPDATE payment_transactions SET brand = COALESCE(
		(SELECT d.brand FROM devices d WHERE d.id = payment_transactions.device_id AND d.brand != ''),
		'ssvid'
	) WHERE brand IS NULL OR brand = ''`)

	// Add performance indexes (idempotent — safe to run repeatedly)
	indexes := []struct {
		table   string
		name    string
		columns string
	}{
		{"crash_reports", "idx_crash_reports_severity", "severity"},
		{"crash_reports", "idx_crash_reports_device_id", "device_id"},
		{"payment_transactions", "idx_payment_transactions_stripe_session_id", "stripe_session_id"},
		{"payment_transactions", "idx_payment_transactions_crypto_invoice_id", "crypto_invoice_id"},
		{"app_releases", "idx_app_releases_platform_channel", "platform, channel"},
		{"knowledge_bases", "idx_knowledge_bases_is_active", "is_active"},
		{"announcements", "idx_announcements_is_active", "is_active"},
		{"analytics_events", "idx_analytics_events_event_type", "event_type"},
		{"analytics_events", "idx_analytics_events_device_id", "device_id"},
		{"analytics_events", "idx_analytics_events_created_at", "created_at"},
		{"bootstrap_events", "idx_bootstrap_events_brand_created", "brand, created_at DESC"},
		{"bootstrap_events", "idx_bootstrap_events_stage_status", "stage, status"},
		{"bootstrap_events", "idx_bootstrap_events_install_id", "install_id"},
		{"bug_reports", "idx_bug_reports_device_id", "device_id"},
		{"bug_reports", "idx_bug_reports_status", "status"},
		{"tickets", "idx_tickets_device_id", "device_id"},
		{"tickets", "idx_tickets_status", "status"},
		{"chat_sessions", "idx_chat_sessions_device_id", "device_id"},
		{"premium_licenses", "idx_premium_licenses_device_id", "device_id"},
		// Security hardening v1.1.3 — compound indexes for common query patterns
		{"ticket_messages", "idx_ticket_messages_ticket_id_created", "ticket_id, created_at ASC"},
		{"chat_messages", "idx_chat_messages_session_id_created", "session_id, created_at ASC"},
		{"feature_requests", "idx_feature_requests_upvotes_created", "upvotes DESC, created_at DESC"},
		{"license_devices", "idx_license_devices_license_id", "license_id"},
		{"payment_transactions", "idx_payment_transactions_status_created", "status, created_at"},
		{"payment_transactions", "idx_payment_transactions_device_id", "device_id"},
		{"premium_licenses", "idx_premium_licenses_contact_email", "contact_email"},
		{"premium_licenses", "idx_premium_licenses_stripe_sub_id", "stripe_subscription_id"},
		// Invoices
		{"invoices", "idx_invoices_status_created", "status, created_at DESC"},
		{"invoices", "idx_invoices_contact_email_created", "contact_email, created_at DESC"},
		// Crash groups
		{"crash_groups", "idx_crash_groups_status_last_seen", "status, last_seen_at DESC"},
		{"crash_groups", "idx_crash_groups_severity", "severity"},
		{"crash_reports", "idx_crash_reports_crash_group_id", "crash_group_id"},
		// Download errors
		{"download_errors", "idx_download_errors_error_code", "error_code"},
		{"download_errors", "idx_download_errors_diagnostic_error_code", "diagnostic_error_code"},
		{"download_errors", "idx_download_errors_diagnostic_signature", "diagnostic_signature"},
		{"download_errors", "idx_download_errors_platform", "platform"},
		{"download_errors", "idx_download_errors_device_id", "device_id"},
		{"download_errors", "idx_download_errors_created_at", "created_at"},
		// Audit logs
		{"audit_logs", "idx_audit_logs_admin_id_created", "admin_id, created_at DESC"},
		{"audit_logs", "idx_audit_logs_resource_type", "resource_type"},
		// Dashboard activity feed + trends + top customers (tier-SSS upgrade)
		// Hot columns for ORDER BY timestamp DESC on 7-table UNION ALL + date-range filters
		{"devices", "idx_devices_created_at", "created_at DESC"},
		{"devices", "idx_devices_last_seen_at", "last_seen_at DESC"},
		{"premium_licenses", "idx_premium_licenses_created_at", "created_at DESC"},
		{"payment_transactions", "idx_payment_transactions_created_at", "created_at DESC"},
	}
	for _, idx := range indexes {
		sql := fmt.Sprintf("CREATE INDEX IF NOT EXISTS %s ON %s (%s)", idx.name, idx.table, idx.columns)
		if err := db.Exec(sql).Error; err != nil {
			logger.Log.Warn().Str("index", idx.name).Err(err).Msg("Failed to create index (may already exist)")
		}
	}

	// Partial index: payment_transactions.completed_at for activity feed + top customers.
	// Only indexes rows where status='completed' AND completed_at IS NOT NULL — the exact
	// filter used by GetRecentActivity() and GetTopCustomers(). Partial indexes are smaller
	// and faster to scan than full indexes on nullable columns.
	if err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_payment_transactions_completed_at_paid
		ON payment_transactions (completed_at DESC)
		WHERE status = 'completed' AND completed_at IS NOT NULL`).Error; err != nil {
		logger.Log.Warn().Err(err).Msg("Failed to create partial index idx_payment_transactions_completed_at_paid")
	}

	// Unique indexes for data integrity
	uniqueIndexes := []struct {
		table   string
		name    string
		columns string
	}{
		{"feature_votes", "idx_feature_votes_unique_vote", "feature_request_id, device_id"},
		{"devices", "idx_devices_brand_hardware_id", "brand, hardware_id"},
	}
	for _, idx := range uniqueIndexes {
		sql := fmt.Sprintf("CREATE UNIQUE INDEX IF NOT EXISTS %s ON %s (%s)", idx.name, idx.table, idx.columns)
		if err := db.Exec(sql).Error; err != nil {
			logger.Log.Warn().Str("index", idx.name).Err(err).Msg("Failed to create unique index (may already exist)")
		}
	}

	// Data cleanup: fix stuck webhook events from early deployment (March 2026)
	// - Set status from "processing" to "processed" for old stuck events
	// - Set created_at to processed_at for events with zero timestamps
	cutoff := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	result := db.Model(&premiummodel.WebhookEvent{}).
		Where("status = ? AND (created_at IS NULL OR created_at < ?)", "processing", cutoff).
		Updates(map[string]interface{}{
			"status":     "processed",
			"created_at": gorm.Expr("COALESCE(processed_at, NOW())"),
		})
	if result.Error != nil {
		logger.Log.Warn().Err(result.Error).Msg("Failed to clean up stuck webhook events")
	} else if result.RowsAffected > 0 {
		logger.Log.Info().Int64("count", result.RowsAffected).Msg("Cleaned up stuck webhook events from early deployment")
	}

	// Email normalization backfill — broad ultra-review 2026-05-21.
	// Pre-Round-4 webhook writes could store mixed-case contact_email.
	// Idempotent: WHERE skips rows already normalized.
	emailNormalize := db.Exec(`
		UPDATE premium_licenses
		SET contact_email = LOWER(TRIM(contact_email)), updated_at = NOW()
		WHERE contact_email IS NOT NULL
		  AND contact_email <> LOWER(TRIM(contact_email))
	`)
	if emailNormalize.Error != nil {
		logger.Log.Warn().Err(emailNormalize.Error).
			Msg("Failed to normalize premium_licenses.contact_email")
	} else if emailNormalize.RowsAffected > 0 {
		logger.Log.Info().Int64("count", emailNormalize.RowsAffected).
			Msg("Normalized premium_licenses.contact_email to lowercase+trim")
	}
	invoiceNormalize := db.Exec(`
		UPDATE invoices
		SET contact_email = LOWER(TRIM(contact_email)), updated_at = NOW()
		WHERE contact_email IS NOT NULL AND contact_email <> ''
		  AND contact_email <> LOWER(TRIM(contact_email))
	`)
	if invoiceNormalize.Error != nil {
		logger.Log.Warn().Err(invoiceNormalize.Error).
			Msg("Failed to normalize invoices.contact_email")
	}

	// Functional indexes for the case-insensitive WHERE predicates in
	// LicenseRepository.FindActiveByEmail / FindByEmail / TransactionRepository
	// — without these, the LOWER(TRIM(...)) lookups seq-scan as table grows.
	// CREATE INDEX IF NOT EXISTS is idempotent.
	indexSQL := []string{
		`CREATE INDEX IF NOT EXISTS idx_premium_licenses_contact_email_lower
		   ON premium_licenses (LOWER(TRIM(contact_email)))
		   WHERE contact_email IS NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_invoices_contact_email_lower
		   ON invoices (LOWER(TRIM(contact_email)))
		   WHERE contact_email IS NOT NULL AND contact_email <> ''`,
	}
	for _, s := range indexSQL {
		if err := db.Exec(s).Error; err != nil {
			logger.Log.Warn().Err(err).Str("sql", s).
				Msg("Failed to create case-insensitive email index")
		}
	}

	logger.Log.Info().Msg("Database migrations completed")
	return nil
}

func SeedAdmin(db *gorm.DB, email, password string) error {
	var count int64
	db.Model(&model.Admin{}).Count(&count)
	if count > 0 {
		logger.Log.Debug().Msg("Admin already exists, skipping seed")
		return nil
	}

	hash, err := crypto.HashPassword(password)
	if err != nil {
		return fmt.Errorf("failed to hash admin password: %w", err)
	}

	admin := model.Admin{
		Email:        email,
		PasswordHash: hash,
		Name:         "Admin",
	}

	if err := db.Create(&admin).Error; err != nil {
		return fmt.Errorf("failed to seed admin: %w", err)
	}

	logger.Log.Info().Str("email", email).Msg("Default admin seeded")
	return nil
}
