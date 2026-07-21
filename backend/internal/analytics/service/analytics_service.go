package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/snakeloader/backend/internal/analytics/dto"
	"github.com/snakeloader/backend/internal/analytics/model"
	"github.com/snakeloader/backend/internal/analytics/repository"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
)

// analyticsCacheTTL bounds how long admin dashboard aggregations may serve
// stale data. 5 minutes is a deliberate trade: it covers the hottest period
// right after a new admin opens the page (multiple chart queries in <30s)
// and survives most "refresh-the-tab" loops, while still updating fast enough
// that an admin investigating an ongoing incident sees fresh numbers within
// a single coffee break. Applied uniformly to all dashboard aggregations
// (overview, top events, download stats) so the picture stays consistent
// across cards on the same render.
const analyticsCacheTTL = 5 * time.Minute

// cachedAggregation is a cache-aside wrapper for analytics aggregations.
// Tries Redis first; on miss it computes via the provided function and
// writes the result back. Falls through directly to compute() when rdb is
// nil or any Redis op fails — the dashboard must keep working when cache
// is unavailable. T must be json-marshalable.
func cachedAggregation[T any](
	rdb *redis.Client,
	cacheKey string,
	ttl time.Duration,
	compute func() (T, error),
) (T, error) {
	if rdb == nil {
		return compute()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	if cached, err := rdb.Get(ctx, cacheKey).Bytes(); err == nil {
		var resp T
		if err := json.Unmarshal(cached, &resp); err == nil {
			return resp, nil
		}
		// Bad payload — drop it and recompute.
		rdb.Del(ctx, cacheKey)
	}

	resp, err := compute()
	if err != nil {
		var zero T
		return zero, err
	}
	if payload, err := json.Marshal(resp); err == nil {
		rdb.Set(ctx, cacheKey, payload, ttl)
	}
	return resp, nil
}

// Known event types — events not in this set are still accepted but logged as unknown.
var knownEventTypes = map[string]string{
	"app_open":                   "lifecycle",
	"app_close":                  "lifecycle",
	"download_start":             "download",
	"download_complete":          "download",
	"download_error":             "download",
	"download_pause":             "download",
	"download_resume":            "download",
	"video_play":                 "playback",
	"quality_selected":           "download",
	"search_performed":           "navigation",
	"url_pasted":                 "navigation",
	"batch_download_started":     "download",
	"settings_changed":           "navigation",
	"error_displayed":            "error",
	"app_crash":                  "error",
	"premium_checkout_started":   "payment",
	"premium_checkout_completed": "payment",
	"premium_cancelled":          "payment",
	"license_verify":             "premium",
	// Update funnel — instrumented in v1.3.7 / v1.6.4 to diagnose
	// adoption stalls (audit 2026-04-27 found ~88% of v1.6.2 active
	// devices did not migrate, with no client-side signal to explain).
	//
	// Funnel order (each event has a distinct semantic):
	//   update_available       → backend returned updateAvailable=true
	//                            (fires in startup before any UI mount —
	//                            does NOT prove user saw the banner).
	//   update_banner_visible  → banner widget rendered on screen (real
	//                            visual exposure, fires from widget
	//                            build cycle).
	//   update_install_clicked → user pressed Update Now on the banner.
	//   update_install_dialog_clicked → same on the modal dialog.
	//   update_install_auto_started   → mandatory auto-flow, no click.
	//   update_download_verified      → installer artifact is present and
	//                                   hash verified.
	//   update_download_failed        → download/hash verification failed.
	//   update_install_started        → app is about to run the installer path.
	//   update_install_handoff_started → platform installer/script launched.
	//   update_install_completed      → app reopened at the target/newer version.
	//   update_install_not_applied    → app reopened but is still older than target.
	//   update_install_failed         → installer handoff failed before exit.
	//   update_banner_dismissed → user pressed X.
	//
	// `update_banner_shown` is kept as an alias of `update_available`
	// for short-term backward compat with v1.3.6/v1.6.3 clients still
	// sending it; aliasEvents() below normalises it.
	"update_available":               "update",
	"update_banner_visible":          "update",
	"update_install_clicked":         "update", // banner click
	"update_install_dialog_clicked":  "update", // dialog click
	"update_install_auto_started":    "update", // mandatory auto-flow
	"update_download_verified":       "update",
	"update_download_failed":         "update",
	"update_install_started":         "update",
	"update_install_handoff_started": "update",
	"update_install_completed":       "update",
	"update_install_not_applied":     "update",
	"update_install_failed":          "update",
	"update_banner_dismissed":        "update",
}

var canonicalEventTypeAliases = map[string]string{
	"download_started":           "download_start",
	"download_completed":         "download_complete",
	"download_failed":            "download_error",
	"premium_checkout_cancelled": "premium_cancelled",
	// v1.3.7 renamed `update_banner_shown` → `update_available` to
	// distinguish "update detected" from "banner actually rendered".
	// Older clients (v1.3.6 / v1.6.3) still in the field will keep
	// emitting the old name until they upgrade; route them to the new
	// canonical so dashboards aggregate cleanly.
	"update_banner_shown": "update_available",
}

// IsKnownEventType checks if an event type is in the known registry.
func IsKnownEventType(eventType string) bool {
	_, ok := knownEventTypes[eventType]
	return ok
}

func NormalizeEventType(eventType string) (string, bool) {
	normalized := strings.ToLower(strings.TrimSpace(eventType))
	if normalized == "" {
		return "", false
	}
	if canonical, ok := canonicalEventTypeAliases[normalized]; ok {
		normalized = canonical
	}
	return normalized, true
}

type AnalyticsService struct {
	repo        *repository.AnalyticsRepository
	dlErrorRepo *repository.DownloadErrorRepository
	rdb         *redis.Client // nil = cache disabled, queries fall through to DB
}

func NewAnalyticsService(repo *repository.AnalyticsRepository, dlErrorRepo *repository.DownloadErrorRepository) *AnalyticsService {
	return &AnalyticsService{repo: repo, dlErrorRepo: dlErrorRepo}
}

// SetRedis wires the shared Redis client for admin dashboard caching.
// Passing nil disables caching — queries go straight to Postgres.
func (s *AnalyticsService) SetRedis(rdb *redis.Client) { s.rdb = rdb }

// TrackEvent records a single analytics event
func (s *AnalyticsService) TrackEvent(deviceID uuid.UUID, os, appVersion string, req dto.TrackEventRequest) error {
	eventType, ok := NormalizeEventType(req.EventType)
	if !ok {
		logger.Log.Warn().
			Str("device_id", deviceID.String()).
			Msg("Skipping analytics event with empty event type")
		return nil
	}

	event := &model.AnalyticsEvent{
		DeviceID:   deviceID,
		EventType:  eventType,
		EventData:  req.EventData,
		AppVersion: appVersion,
		OS:         os,
	}
	if err := s.repo.CreateEvent(event); err != nil {
		return err
	}
	s.maybeBridgeDownloadError(deviceID, os, appVersion, *event)
	return nil
}

// TrackEvents records multiple analytics events with type validation.
func (s *AnalyticsService) TrackEvents(deviceID uuid.UUID, os, appVersion string, req dto.TrackEventsRequest) (int, error) {
	events := make([]model.AnalyticsEvent, 0, len(req.Events))
	for _, e := range req.Events {
		eventType, ok := NormalizeEventType(e.EventType)
		if !ok {
			logger.Log.Warn().
				Str("device_id", deviceID.String()).
				Msg("Skipping analytics event with empty event type")
			continue
		}
		if !IsKnownEventType(eventType) {
			logger.Log.Warn().Str("event_type", eventType).Str("device_id", deviceID.String()).Msg("Unknown event type received — accepted but not in registry")
		}
		events = append(events, model.AnalyticsEvent{
			ID:         uuid.New(),
			DeviceID:   deviceID,
			EventType:  eventType,
			EventData:  e.EventData,
			AppVersion: appVersion,
			OS:         os,
		})
	}

	if len(events) == 0 {
		return 0, nil
	}

	if err := s.repo.CreateEvents(events); err != nil {
		return 0, err
	}
	for _, event := range events {
		s.maybeBridgeDownloadError(deviceID, os, appVersion, event)
	}
	return len(events), nil
}

func (s *AnalyticsService) TrackBootstrapEvent(req dto.TrackBootstrapEventRequest, clientIP, userAgent string) error {
	brand := strings.TrimSpace(strings.ToLower(req.Brand))
	if brand == "" {
		brand = "ssvid"
	}
	event := &model.BootstrapEvent{
		InstallID:    strings.TrimSpace(req.InstallID),
		Brand:        brand,
		OS:           strings.TrimSpace(strings.ToLower(req.OS)),
		OSVersion:    strings.TrimSpace(req.OSVersion),
		AppVersion:   strings.TrimSpace(req.AppVersion),
		Stage:        strings.TrimSpace(strings.ToLower(req.Stage)),
		Status:       strings.TrimSpace(strings.ToLower(req.Status)),
		ErrorCode:    strings.TrimSpace(req.ErrorCode),
		ErrorMessage: strings.TrimSpace(req.ErrorMessage),
		Metadata:     req.Metadata,
		IPAddress:    clientIP,
		UserAgent:    userAgent,
	}
	return s.repo.CreateBootstrapEvent(event)
}

func (s *AnalyticsService) ListBootstrapEvents(page, perPage int, brand, os, appVersion, stage, status, errorCode string, dateFrom, dateTo *time.Time) ([]dto.BootstrapEventResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	events, total, err := s.repo.ListBootstrapEvents(page, perPage, brand, os, appVersion, stage, status, errorCode, dateFrom, dateTo)
	if err != nil {
		return nil, 0, err
	}
	return dto.BootstrapEventsToResponse(events), total, nil
}

// ListEvents lists recent events with filters
func (s *AnalyticsService) ListEvents(page, perPage int, eventType, os, appVersion, brand string) ([]dto.EventResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	events, total, err := s.repo.ListEvents(page, perPage, eventType, os, appVersion, brand)
	if err != nil {
		return nil, 0, err
	}
	return dto.EventsToResponse(events), total, nil
}

// GetOverview returns analytics overview stats, optionally filtered by brand.
// Cached in Redis for analyticsCacheTTL — 3 of the 5 underlying queries are
// unbounded scans on analytics_events (CountEvents, EventsByOS, EventsByVersion).
func (s *AnalyticsService) GetOverview(brand string) (*dto.AnalyticsOverview, error) {
	return cachedAggregation(s.rdb, analyticsOverviewCacheKey(brand), analyticsCacheTTL, func() (*dto.AnalyticsOverview, error) {
		return s.computeOverview(brand)
	})
}

func (s *AnalyticsService) computeOverview(brand string) (*dto.AnalyticsOverview, error) {
	totalEvents, _ := s.repo.CountEvents(brand)
	eventsToday, _ := s.repo.CountEventsToday(brand)
	activeDevices, _ := s.repo.CountActiveDevicesToday(brand)
	byOS, _ := s.repo.EventsByOS(brand)
	byVersion, _ := s.repo.EventsByVersion(brand)

	return &dto.AnalyticsOverview{
		TotalEvents:        totalEvents,
		EventsToday:        eventsToday,
		ActiveDevicesToday: activeDevices,
		ByOS:               byOS,
		ByVersion:          byVersion,
	}, nil
}

func analyticsOverviewCacheKey(brand string) string {
	if brand == "" {
		brand = "_all"
	}
	return fmt.Sprintf("analytics_overview:v1:%s", brand)
}

// GetTopEvents returns the most common event types, optionally filtered by brand.
// Cached — the underlying TopEventTypes runs GROUP BY event_type on the whole
// analytics_events table.
func (s *AnalyticsService) GetTopEvents(limit int, brand string) ([]repository.EventTypeCount, error) {
	if limit < 1 || limit > 50 {
		limit = 10
	}
	return cachedAggregation(s.rdb, topEventsCacheKey(limit, brand), analyticsCacheTTL, func() ([]repository.EventTypeCount, error) {
		return s.repo.TopEventTypes(limit, brand)
	})
}

func topEventsCacheKey(limit int, brand string) string {
	if brand == "" {
		brand = "_all"
	}
	return fmt.Sprintf("top_events:v1:%d:%s", limit, brand)
}

// GetDownloadStats returns aggregated download analytics, optionally filtered by brand.
// Cached in Redis to spare Postgres from re-running 4 aggregation queries on
// every dashboard render.
func (s *AnalyticsService) GetDownloadStats(days int, brand string) (*dto.DownloadStatsResponse, error) {
	if days < 1 || days > 365 {
		days = 30
	}
	return cachedAggregation(s.rdb, downloadStatsCacheKey(days, brand), analyticsCacheTTL, func() (*dto.DownloadStatsResponse, error) {
		return s.computeDownloadStats(days, brand)
	})
}

func downloadStatsCacheKey(days int, brand string) string {
	if brand == "" {
		brand = "_all"
	}
	// v2: success_rate denominator no longer includes `download_start`.
	// Bump on payload-shape or formula changes so old cached values
	// from a previous deploy don't serve through the 5-min TTL window.
	return fmt.Sprintf("download_stats:v2:%d:%s", days, brand)
}

func (s *AnalyticsService) computeDownloadStats(days int, brand string) (*dto.DownloadStatsResponse, error) {
	total, success, errCount, _ := s.repo.CountDownloads(days, brand)
	byOS, _ := s.repo.DownloadsByOS(days, brand)
	platforms, _ := s.repo.DownloadsByPlatform(days, brand)
	trend, _ := s.repo.DailyDownloadTrend(days, brand)

	var successRate float64
	if total > 0 {
		successRate = float64(success) / float64(total) * 100
	}

	byPlatform := make([]dto.PlatformStats, len(platforms))
	for i, p := range platforms {
		var rate float64
		if p.Total > 0 {
			rate = float64(p.Success) / float64(p.Total) * 100
		}
		byPlatform[i] = dto.PlatformStats{
			Platform:    p.Platform,
			Total:       p.Total,
			Success:     p.Success,
			Errors:      p.Errors,
			SuccessRate: rate,
		}
	}

	dailyTrend := make([]dto.DailyDownloadStats, len(trend))
	for i, d := range trend {
		dailyTrend[i] = dto.DailyDownloadStats{
			Date:    d.Date,
			Total:   d.Total,
			Success: d.Success,
			Errors:  d.Errors,
		}
	}

	return &dto.DownloadStatsResponse{
		TotalDownloads: total,
		SuccessCount:   success,
		ErrorCount:     errCount,
		SuccessRate:    successRate,
		ByPlatform:     byPlatform,
		ByOS:           byOS,
		DailyTrend:     dailyTrend,
	}, nil
}

// GetDailyStats returns daily stats for a date range
func (s *AnalyticsService) GetDailyStats(startDate, endDate time.Time, metricName string) ([]dto.DailyStatsResponse, error) {
	stats, err := s.repo.GetDailyStats(startDate, endDate, metricName)
	if err != nil {
		return nil, err
	}
	return dto.DailyStatsListToResponse(stats), nil
}

// ==================== Download Error Intelligence ====================

// TrackDownloadError records a structured download error.
func (s *AnalyticsService) TrackDownloadError(deviceID uuid.UUID, os, osVersion, appVersion string, req dto.TrackDownloadErrorRequest) error {
	diagnostic := diagnoseDownloadError(req.ErrorCode, req.ErrorPhase, req.ErrorMessage, req.Metadata)
	dlErr := &model.DownloadError{
		DeviceID:             deviceID,
		URL:                  req.URL,
		Platform:             req.Platform,
		ErrorCode:            req.ErrorCode,
		ErrorPhase:           req.ErrorPhase,
		ErrorMessage:         req.ErrorMessage,
		DiagnosticErrorCode:  diagnostic.Code,
		DiagnosticErrorPhase: diagnostic.Phase,
		DiagnosticSignature:  diagnostic.Signature,
		AppVersion:           appVersion,
		OS:                   os,
		OSVersion:            osVersion,
		Metadata:             req.Metadata,
	}
	if err := s.persistDownloadError(dlErr); err != nil {
		return err
	}
	logger.Log.Info().
		Str("device_id", deviceID.String()).
		Str("platform", req.Platform).
		Str("error_code", req.ErrorCode).
		Str("phase", req.ErrorPhase).
		Msg("Download error tracked")
	return nil
}

func (s *AnalyticsService) maybeBridgeDownloadError(deviceID uuid.UUID, os, appVersion string, event model.AnalyticsEvent) {
	dlErr, ok := structuredDownloadErrorFromEvent(deviceID, os, appVersion, event)
	if !ok {
		return
	}
	if err := s.persistDownloadError(dlErr); err != nil {
		logger.Log.Warn().
			Err(err).
			Str("device_id", deviceID.String()).
			Str("event_type", event.EventType).
			Msg("Failed to bridge structured download error from analytics event")
	}
}

func (s *AnalyticsService) persistDownloadError(dlErr *model.DownloadError) error {
	if s.dlErrorRepo == nil {
		return nil
	}

	duplicate, err := s.dlErrorRepo.HasRecentFingerprint(
		dlErr.DeviceID,
		dlErr.Platform,
		dlErr.ErrorCode,
		dlErr.ErrorPhase,
		dlErr.ErrorMessage,
		time.Now().Add(-downloadErrorDedupWindow),
	)
	if err != nil {
		return err
	}
	if duplicate {
		return nil
	}
	return s.dlErrorRepo.Create(dlErr)
}

// ListDownloadErrors returns paginated download errors with filters.
func (s *AnalyticsService) ListDownloadErrors(page, perPage int, errorCode, errorPhase, diagnosticErrorCode, platform, os, appVersion, brand string, dateFrom, dateTo *time.Time) ([]dto.DownloadErrorResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	errors, total, err := s.dlErrorRepo.List(page, perPage, errorCode, errorPhase, diagnosticErrorCode, platform, os, appVersion, brand, dateFrom, dateTo)
	if err != nil {
		return nil, 0, err
	}

	return dto.DownloadErrorsToResponse(errors), total, nil
}

// GetDownloadErrorStats returns aggregate download error statistics, optionally filtered by brand.
func (s *AnalyticsService) GetDownloadErrorStats(days int, brand string) (*dto.DownloadErrorStatsResponse, error) {
	if days < 1 || days > 365 {
		days = 30
	}

	totalErrors, _ := s.dlErrorRepo.CountAll(brand)
	errorsToday, _ := s.dlErrorRepo.CountToday(brand)
	byErrorCode, _ := s.dlErrorRepo.CountByErrorCode(brand)
	byDiagnosticErrorCode, _ := s.dlErrorRepo.CountByDiagnosticErrorCode(brand)
	diagnosticRows, _ := s.dlErrorRepo.CountWithDiagnostic(brand)
	byPhase, _ := s.dlErrorRepo.CountByPhase(brand)
	byPlatform, _ := s.dlErrorRepo.CountByPlatform(brand)
	topErrors, _ := s.dlErrorRepo.TopErrors(10, days, brand)
	dailyTrend, _ := s.dlErrorRepo.DailyTrend(days, brand)
	diagnosticCoveragePct := 0.0
	if totalErrors > 0 {
		diagnosticCoveragePct = float64(diagnosticRows) * 100 / float64(totalErrors)
	}

	return &dto.DownloadErrorStatsResponse{
		TotalErrors:           totalErrors,
		ErrorsToday:           errorsToday,
		ByErrorCode:           byErrorCode,
		ByDiagnosticErrorCode: byDiagnosticErrorCode,
		DiagnosticRows:        diagnosticRows,
		DiagnosticCoveragePct: diagnosticCoveragePct,
		DiagnosticMode:        "stored_new_rows_only",
		ByPhase:               byPhase,
		ByPlatform:            byPlatform,
		TopErrors:             topErrors,
		DailyTrend:            dailyTrend,
	}, nil
}
