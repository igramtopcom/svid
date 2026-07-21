package jobs

import (
	"context"
	"fmt"
	"strings"
	"time"

	alertsvc "github.com/snakeloader/backend/internal/alerts/service"
	"github.com/snakeloader/backend/internal/notifications"
	"github.com/snakeloader/backend/internal/pkg/email"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"github.com/snakeloader/backend/internal/premium/model"
	"gorm.io/gorm"
)

type Scheduler struct {
	db           *gorm.DB
	email        *email.Service
	alertService *alertsvc.AlertService
	notifier     *notifications.TelegramNotifier
	ctx          context.Context
	cancel       context.CancelFunc
}

func NewScheduler(db *gorm.DB, emailService *email.Service, alertService *alertsvc.AlertService, notifier *notifications.TelegramNotifier) *Scheduler {
	ctx, cancel := context.WithCancel(context.Background())
	return &Scheduler{db: db, email: emailService, alertService: alertService, notifier: notifier, ctx: ctx, cancel: cancel}
}

func (s *Scheduler) Start() {
	logger.Log.Info().Msg("Background job scheduler started")

	// License expiry check — every 24 hours
	go s.runEvery("license-expiry", 24*time.Hour, true, s.checkLicenseExpiry)

	// License expiry warning emails — every 24 hours
	go s.runEvery("license-expiry-notify", 24*time.Hour, true, s.sendExpiryWarnings)

	// Stale session cleanup — every 6 hours
	go s.runEvery("session-cleanup", 6*time.Hour, true, s.cleanupStaleSessions)

	// Analytics daily aggregation — every 1 hour
	go s.runEvery("analytics-aggregate", 1*time.Hour, true, s.aggregateAnalytics)

	// Alert threshold checking — every 5 minutes
	go s.runEvery("alert-check", 5*time.Minute, true, s.checkAlerts)

	// Abandoned transaction cleanup — every 1 hour
	go s.runEvery("txn-cleanup", 1*time.Hour, true, s.cleanupAbandonedTransactions)

	// S1.2: Daily digest to Telegram — every 24 hours, but never immediately on boot.
	go s.runEvery("daily-digest", 24*time.Hour, false, s.sendDailyDigest)

	// Webhook event table cleanup — every 24 hours
	go s.runEvery("webhook-event-cleanup", 24*time.Hour, true, s.cleanupOldWebhookEvents)

	// Idle API key revocation — every 24 hours
	go s.runEvery("idle-key-revoke", 24*time.Hour, true, s.revokeIdleAPIKeys)
}

func (s *Scheduler) Stop() {
	s.cancel()
	logger.Log.Info().Msg("Background job scheduler stopped")
}

func (s *Scheduler) runEvery(name string, interval time.Duration, runImmediately bool, job func()) {
	logger.Log.Info().Str("job", name).Dur("interval", interval).Msg("Job registered")
	if runImmediately {
		s.safeRun(name, job)
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			logger.Log.Debug().Str("job", name).Msg("Running scheduled job")
			s.safeRun(name, job)
		}
	}
}

// safeRun executes a job with panic recovery to prevent a single panic from killing the goroutine.
func (s *Scheduler) safeRun(name string, job func()) {
	defer func() {
		if r := recover(); r != nil {
			logger.Log.Error().
				Str("job", name).
				Interface("panic", r).
				Msg("CRITICAL: Background job panicked — recovered, will retry on next tick")
		}
	}()
	job()
}

func (s *Scheduler) checkLicenseExpiry() {
	// Collect exact IDs to downgrade FIRST, then update and cleanup in one pass.
	// This eliminates the race condition of a time-based window — only licenses
	// identified at the start of this run are affected.
	lifetimeExclude := []string{"lifetime", "lifetime1", "lifetime2", "lifetime3"}

	// Phase 1: Find expired active licenses (7-day grace for Stripe retries).
	var expiredActiveIDs []string
	if err := s.db.Raw(`
		SELECT id FROM premium_licenses
		WHERE tier = 'premium'
		AND expires_at < NOW() - INTERVAL '7 days'
		AND cancelled_at IS NULL
		AND billing_cycle NOT IN ?
	`, lifetimeExclude).Scan(&expiredActiveIDs).Error; err != nil {
		logger.Log.Error().Err(err).Msg("License expiry check failed (query active)")
		return
	}

	// Phase 2: Find cancelled subscriptions past expiry (no grace period).
	var expiredCancelledIDs []string
	if err := s.db.Raw(`
		SELECT id FROM premium_licenses
		WHERE tier = 'premium'
		AND cancelled_at IS NOT NULL
		AND expires_at < NOW()
		AND billing_cycle NOT IN ?
	`, lifetimeExclude).Scan(&expiredCancelledIDs).Error; err != nil {
		logger.Log.Error().Err(err).Msg("License expiry check failed (query cancelled)")
		return
	}

	// Merge all IDs to downgrade
	allIDs := append(expiredActiveIDs, expiredCancelledIDs...)
	if len(allIDs) == 0 {
		return
	}

	// Phase 3: Downgrade + cleanup in a transaction (atomic).
	tx := s.db.Begin()
	if tx.Error != nil {
		logger.Log.Error().Err(tx.Error).Msg("License expiry: failed to begin transaction")
		return
	}

	// Downgrade to free
	result := tx.Exec(`
		UPDATE premium_licenses
		SET tier = 'free', is_auto_renew = false, updated_at = NOW()
		WHERE id IN ?
	`, allIDs)
	if result.Error != nil {
		tx.Rollback()
		logger.Log.Error().Err(result.Error).Msg("License expiry: downgrade failed")
		return
	}

	// Free device slots for exactly these licenses
	resultDevices := tx.Exec(`DELETE FROM license_devices WHERE license_id IN ?`, allIDs)
	if resultDevices.Error != nil {
		tx.Rollback()
		logger.Log.Error().Err(resultDevices.Error).Msg("License expiry: device cleanup failed")
		return
	}

	if err := tx.Commit().Error; err != nil {
		logger.Log.Error().Err(err).Msg("License expiry: commit failed")
		return
	}

	if len(expiredActiveIDs) > 0 {
		logger.Log.Info().Int("count", len(expiredActiveIDs)).Msg("Expired active licenses downgraded")
	}
	if len(expiredCancelledIDs) > 0 {
		logger.Log.Info().Int("count", len(expiredCancelledIDs)).Msg("Expired cancelled licenses downgraded")
	}
	if resultDevices.RowsAffected > 0 {
		logger.Log.Info().Int64("count", resultDevices.RowsAffected).Msg("Device slots freed from expired licenses")
	}
}

func (s *Scheduler) cleanupStaleSessions() {
	// Delete chat sessions older than 90 days with no messages
	result := s.db.Exec(`
		DELETE FROM chat_sessions
		WHERE updated_at < NOW() - INTERVAL '90 days'
		AND id NOT IN (SELECT DISTINCT session_id FROM chat_messages)
	`)
	if result.Error != nil {
		logger.Log.Error().Err(result.Error).Msg("Stale session cleanup failed")
		return
	}
	if result.RowsAffected > 0 {
		logger.Log.Info().Int64("count", result.RowsAffected).Msg("Stale sessions cleaned up")
	}
}

func (s *Scheduler) sendExpiryWarnings() {
	now := time.Now()
	from := now.Add(6 * 24 * time.Hour) // 6 days from now
	to := now.Add(8 * 24 * time.Hour)   // 8 days from now

	var licenses []model.PremiumLicense
	err := s.db.Where(
		"tier = 'premium' AND expires_at BETWEEN ? AND ? AND cancelled_at IS NULL AND contact_email IS NOT NULL AND expiry_notified_at IS NULL",
		from, to,
	).Find(&licenses).Error
	if err != nil {
		logger.Log.Error().Err(err).Msg("Failed to query licenses for expiry warning")
		return
	}

	if len(licenses) == 0 {
		return
	}

	for _, license := range licenses {
		daysRemaining := int(time.Until(license.ExpiresAt).Hours() / 24)
		if daysRemaining < 1 {
			daysRemaining = 1
		}

		// Mask license key: show first and last segments only
		maskedKey := maskLicenseKey(license.LicenseKey)

		autoRenew := "Disabled"
		if license.IsAutoRenew {
			autoRenew = "Enabled"
		}

		subject := fmt.Sprintf("Your SSvid Premium expires in %d days", daysRemaining)
		err := s.email.Send(*license.ContactEmail, subject, "license_expiry_warning", map[string]string{
			"DaysRemaining": fmt.Sprintf("%d", daysRemaining),
			"LicenseKey":    maskedKey,
			"ExpiresAt":     license.ExpiresAt.Format("January 2, 2006"),
			"AutoRenew":     autoRenew,
		})
		if err != nil {
			logger.Log.Error().Err(err).Str("license_key", license.LicenseKey).Msg("Failed to send expiry warning email")
			continue
		}

		// Mark as notified to prevent duplicates
		notifiedAt := time.Now()
		license.ExpiryNotifiedAt = &notifiedAt
		if err := s.db.Save(&license).Error; err != nil {
			logger.Log.Error().Err(err).Str("license_key", license.LicenseKey).Msg("Failed to update expiry_notified_at")
		}
	}

	logger.Log.Info().Int("count", len(licenses)).Msg("Expiry warning emails processed")
}

// maskLicenseKey masks the middle segments of a license key.
// SSVID-abcd-efgh-...-wxyz    → SSVID-abcd-****-...-****-wxyz
// VIDCOMBO-abcd-efgh-...-wxyz → VIDCOMBO-a-****-...-****-wxyz
func maskLicenseKey(key string) string {
	parts := strings.Split(key, "-")
	if len(parts) < 4 {
		return key
	}
	// Show prefix + first hex group and last hex group, mask everything in between
	masked := parts[0] + "-" + parts[1]
	for i := 2; i < len(parts)-1; i++ {
		masked += "-****"
	}
	masked += "-" + parts[len(parts)-1]
	return masked
}

func (s *Scheduler) aggregateAnalytics() {
	now := time.Now().UTC()
	todayStart, tomorrow := timeutil.UTCDayBounds(now)
	active7dStart := now.AddDate(0, 0, -7)
	active30dStart := now.AddDate(0, 0, -30)
	var failCount int

	queries := []struct {
		name string
		sql  string
		args []interface{}
	}{
		{"total_events", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'total_events', COUNT(*), NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2 AND created_at < $3
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"download_success", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'download_success', COUNT(*), NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2 AND created_at < $3 AND event_type = 'download_complete'
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"download_error", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'download_error', COUNT(*), NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2 AND created_at < $3 AND event_type = 'download_error'
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"active_devices", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'active_devices', COUNT(DISTINCT device_id), NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2 AND created_at < $3
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"download_success_rate", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'download_success_rate',
				CASE WHEN COUNT(*) FILTER (WHERE event_type IN ('download_complete','download_error')) > 0
					THEN (COUNT(*) FILTER (WHERE event_type = 'download_complete') * 100 /
						COUNT(*) FILTER (WHERE event_type IN ('download_complete','download_error')))
					ELSE 0 END,
				NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2 AND created_at < $3
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"active_devices_7d", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'active_devices_7d', COUNT(DISTINCT device_id), NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, active7dStart}},
		{"active_devices_30d", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'active_devices_30d', COUNT(DISTINCT device_id), NOW(), NOW()
			FROM analytics_events WHERE created_at >= $2
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, active30dStart}},
		{"crash_count", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'crash_count', COUNT(*), NOW(), NOW()
			FROM crash_reports WHERE created_at >= $2 AND created_at < $3
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"download_errors_structured", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'download_errors_structured', COUNT(*), NOW(), NOW()
			FROM download_errors WHERE created_at >= $2 AND created_at < $3
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart, todayStart, tomorrow}},
		{"crash_groups_active", `INSERT INTO daily_stats (id, date, metric_name, value, created_at, updated_at)
			SELECT gen_random_uuid(), $1, 'crash_groups_active', COUNT(*), NOW(), NOW()
			FROM crash_groups WHERE status NOT IN ('resolved', 'wont_fix')
			ON CONFLICT (date, metric_name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, []interface{}{todayStart}},
	}

	for _, q := range queries {
		if err := s.db.Exec(q.sql, q.args...).Error; err != nil {
			logger.Log.Error().Err(err).Str("metric", q.name).Msg("Analytics aggregation failed")
			failCount++
		}
	}
	if failCount > 0 {
		logger.Log.Warn().Int("failed", failCount).Int("total", len(queries)).Msg("Some analytics aggregations failed")
	}
}

func (s *Scheduler) checkAlerts() {
	if s.alertService == nil {
		return
	}
	s.alertService.CheckAlerts()
}

// cleanupAbandonedTransactions marks old pending transactions as cancelled.
// Stripe Checkout sessions expire after 24h, so pending transactions older than 48h are stale.
func (s *Scheduler) cleanupAbandonedTransactions() {
	result := s.db.Exec(`
		UPDATE payment_transactions
		SET status = 'cancelled', updated_at = NOW()
		WHERE status = 'pending'
		AND created_at < NOW() - INTERVAL '48 hours'
	`)
	if result.Error != nil {
		logger.Log.Error().Err(result.Error).Msg("Abandoned transaction cleanup failed")
		return
	}
	if result.RowsAffected > 0 {
		logger.Log.Info().Int64("count", result.RowsAffected).Msg("Abandoned pending transactions cleaned up")
	}
}

// cleanupOldWebhookEvents removes processed webhook events older than 30 days.
func (s *Scheduler) cleanupOldWebhookEvents() {
	result := s.db.Exec(`
		DELETE FROM webhook_events
		WHERE processed_at < NOW() - INTERVAL '30 days'
	`)
	if result.Error != nil {
		logger.Log.Error().Err(result.Error).Msg("Webhook event cleanup failed")
		return
	}
	if result.RowsAffected > 0 {
		logger.Log.Info().Int64("count", result.RowsAffected).Msg("Old webhook events cleaned up")
	}
}

// revokeIdleAPIKeys revokes API keys for devices that haven't been seen in 90+ days.
// Prevents zombie keys from accumulating — devices must re-register on next use.
func (s *Scheduler) revokeIdleAPIKeys() {
	result := s.db.Exec(`
		UPDATE api_keys SET is_revoked = true, updated_at = NOW()
		WHERE is_revoked = false
		AND device_id IN (
			SELECT id FROM devices WHERE last_seen_at < NOW() - INTERVAL '90 days'
		)
	`)
	if result.Error != nil {
		logger.Log.Error().Err(result.Error).Msg("Idle API key revocation failed")
		return
	}
	if result.RowsAffected > 0 {
		logger.Log.Info().Int64("count", result.RowsAffected).Msg("Idle API keys revoked (90+ days inactive)")
	}
}

// sendDailyDigest aggregates system stats and sends a Telegram digest (S1.2).
func (s *Scheduler) sendDailyDigest() {
	if s.notifier == nil {
		return
	}

	now := time.Now().UTC()
	todayStart, tomorrow := timeutil.UTCDayBounds(now)
	stats := notifications.DailyDigestStats{}

	// Devices
	s.db.Raw("SELECT COUNT(*) FROM devices").Scan(&stats.TotalDevices)
	s.db.Raw("SELECT COUNT(*) FROM devices WHERE created_at >= ? AND created_at < ?", todayStart, tomorrow).Scan(&stats.NewDevicesToday)
	s.db.Raw("SELECT COUNT(*) FROM devices WHERE last_seen_at >= ?", now.AddDate(0, 0, -7)).Scan(&stats.ActiveDevices7d)
	s.db.Raw("SELECT COUNT(*) FROM devices WHERE last_seen_at >= ?", now.AddDate(0, 0, -30)).Scan(&stats.ActiveDevices30d)

	// Bugs
	s.db.Raw("SELECT COUNT(*) FROM bug_reports WHERE status IN ('new','triaging','in_progress')").Scan(&stats.OpenBugs)
	s.db.Raw("SELECT COUNT(*) FROM bug_reports WHERE created_at >= ? AND created_at < ?", todayStart, tomorrow).Scan(&stats.NewBugsToday)

	// Crashes
	s.db.Raw("SELECT COUNT(*) FROM crash_reports WHERE created_at >= ? AND created_at < ?", todayStart, tomorrow).Scan(&stats.CrashesToday)

	// Tickets
	s.db.Raw("SELECT COUNT(*) FROM tickets WHERE status IN ('open','in_progress')").Scan(&stats.OpenTickets)
	s.db.Raw("SELECT COUNT(*) FROM tickets WHERE created_at >= ? AND created_at < ?", todayStart, tomorrow).Scan(&stats.NewTicketsToday)

	// Downloads
	var totalDL, successDL int64
	s.db.Raw("SELECT COUNT(*) FROM analytics_events WHERE created_at >= ? AND created_at < ? AND event_type IN ('download_complete','download_error')", todayStart, tomorrow).Scan(&totalDL)
	s.db.Raw("SELECT COUNT(*) FROM analytics_events WHERE created_at >= ? AND created_at < ? AND event_type = 'download_complete'", todayStart, tomorrow).Scan(&successDL)
	if totalDL > 0 {
		stats.DownloadSuccessRate = int(successDL * 100 / totalDL)
	}
	s.db.Raw("SELECT COUNT(*) FROM analytics_events WHERE created_at >= ? AND created_at < ? AND event_type IN ('download_start','download_complete','download_error')", todayStart, tomorrow).Scan(&stats.DownloadsToday)

	// Ratings
	s.db.Raw("SELECT COALESCE(AVG(rating), 0) FROM app_ratings").Scan(&stats.RatingAverage)
	s.db.Raw("SELECT COUNT(*) FROM app_ratings").Scan(&stats.TotalRatings)

	// Revenue (from invoices — real Stripe payments)
	s.db.Raw("SELECT COALESCE(SUM(amount_paid_cents), 0) FROM invoices WHERE status = 'paid' AND COALESCE(paid_at, created_at) >= ? AND COALESCE(paid_at, created_at) < ?", todayStart, tomorrow).Scan(&stats.RevenueTodayCents)
	s.db.Raw("SELECT COUNT(*) FROM premium_licenses WHERE tier = 'premium'").Scan(&stats.PremiumLicenses)
	s.db.Raw("SELECT COUNT(*) FROM premium_licenses WHERE "+model.ActivePremiumLicenseSQL(""), now).Scan(&stats.ActiveLicenses)

	// Crash groups (Phase 4)
	s.db.Raw("SELECT COUNT(*) FROM crash_groups WHERE status NOT IN ('resolved', 'wont_fix')").Scan(&stats.CrashGroupsActive)
	s.db.Raw("SELECT COUNT(*) FROM crash_groups WHERE first_seen_at >= ? AND first_seen_at < ?", todayStart, tomorrow).Scan(&stats.CrashGroupsNewToday)

	// Download errors (Phase 4 — from structured download_errors table)
	s.db.Raw("SELECT COUNT(*) FROM download_errors WHERE created_at >= ? AND created_at < ?", todayStart, tomorrow).Scan(&stats.DownloadErrorsToday)

	// Top error codes (Phase 4)
	var topCodes []struct{ ErrorCode string }
	s.db.Raw("SELECT error_code FROM download_errors WHERE created_at >= ? AND created_at < ? GROUP BY error_code ORDER BY COUNT(*) DESC LIMIT 3", todayStart, tomorrow).Scan(&topCodes)
	for _, tc := range topCodes {
		stats.TopErrorCodes = append(stats.TopErrorCodes, tc.ErrorCode)
	}

	s.notifier.SendDailyDigest(stats)
	logger.Log.Info().Msg("Daily digest sent to Telegram")
}
