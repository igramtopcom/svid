package repository

import (
	"time"

	"github.com/snakeloader/backend/internal/analytics/model"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type AnalyticsRepository struct {
	db *gorm.DB
}

func NewAnalyticsRepository(db *gorm.DB) *AnalyticsRepository {
	return &AnalyticsRepository{db: db}
}

// ==================== Events ====================

func (r *AnalyticsRepository) CreateEvent(event *model.AnalyticsEvent) error {
	return r.db.Create(event).Error
}

func (r *AnalyticsRepository) CreateEvents(events []model.AnalyticsEvent) error {
	return r.db.Create(&events).Error
}

func (r *AnalyticsRepository) CreateBootstrapEvent(event *model.BootstrapEvent) error {
	return r.db.Create(event).Error
}

func (r *AnalyticsRepository) ListBootstrapEvents(page, perPage int, brand, os, appVersion, stage, status, errorCode string, dateFrom, dateTo *time.Time) ([]model.BootstrapEvent, int64, error) {
	var events []model.BootstrapEvent
	var total int64

	query := r.db.Model(&model.BootstrapEvent{})
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	if os != "" {
		query = query.Where("os = ?", os)
	}
	if appVersion != "" {
		query = query.Where("app_version = ?", appVersion)
	}
	if stage != "" {
		query = query.Where("stage = ?", stage)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if errorCode != "" {
		query = query.Where("error_code = ?", errorCode)
	}
	if dateFrom != nil {
		query = query.Where("created_at >= ?", *dateFrom)
	}
	if dateTo != nil {
		query = query.Where("created_at <= ?", *dateTo)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&events).Error; err != nil {
		return nil, 0, err
	}

	return events, total, nil
}

func (r *AnalyticsRepository) ListEvents(page, perPage int, eventType, os, appVersion, brand string) ([]model.AnalyticsEvent, int64, error) {
	var events []model.AnalyticsEvent
	var total int64

	query := r.db.Model(&model.AnalyticsEvent{})
	if eventType != "" {
		query = query.Where("event_type = ?", eventType)
	}
	if os != "" {
		query = query.Where("os = ?", os)
	}
	if appVersion != "" {
		query = query.Where("app_version = ?", appVersion)
	}
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&events).Error; err != nil {
		return nil, 0, err
	}

	return events, total, nil
}

func (r *AnalyticsRepository) CountEvents(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.AnalyticsEvent{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *AnalyticsRepository) CountEventsToday(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.AnalyticsEvent{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	start, end := timeutil.UTCDayBounds(time.Now())
	err := query.Where("created_at >= ? AND created_at < ?", start, end).Count(&count).Error
	return count, err
}

func (r *AnalyticsRepository) CountActiveDevicesToday(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.AnalyticsEvent{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	start, end := timeutil.UTCDayBounds(time.Now())
	err := query.
		Where("created_at >= ? AND created_at < ?", start, end).
		Select("COUNT(DISTINCT device_id)").
		Scan(&count).Error
	return count, err
}

func (r *AnalyticsRepository) TopEventTypes(limit int, brand string) ([]EventTypeCount, error) {
	var results []EventTypeCount
	query := r.db.Model(&model.AnalyticsEvent{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("event_type, count(*) as count").
		Group("event_type").
		Order("count DESC").
		Limit(limit).
		Find(&results).Error
	return results, err
}

type EventTypeCount struct {
	EventType string `json:"event_type"`
	Count     int64  `json:"count"`
}

func (r *AnalyticsRepository) EventsByOS(brand string) (map[string]int64, error) {
	type result struct {
		OS    string
		Count int64
	}
	var results []result
	query := r.db.Model(&model.AnalyticsEvent{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("os, count(*) as count").
		Group("os").
		Find(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.OS] = r.Count
	}
	return m, nil
}

func (r *AnalyticsRepository) EventsByVersion(brand string) (map[string]int64, error) {
	type result struct {
		AppVersion string
		Count      int64
	}
	var results []result
	query := r.db.Model(&model.AnalyticsEvent{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("app_version, count(*) as count").
		Group("app_version").
		Find(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.AppVersion] = r.Count
	}
	return m, nil
}

// ==================== Download Analytics ====================

type PlatformDownloadCount struct {
	Platform string `json:"platform"`
	Total    int64  `json:"total"`
	Success  int64  `json:"success"`
	Errors   int64  `json:"errors"`
}

type DailyDownloadCount struct {
	Date    string `json:"date"`
	Total   int64  `json:"total"`
	Success int64  `json:"success"`
	Errors  int64  `json:"errors"`
}

// downloadWindowStart returns the inclusive lower bound for download aggregations.
// `days` is normalized by the service layer (1..365); callers must not pass <= 0.
func downloadWindowStart(days int) time.Time {
	return timeutil.UTCStartOfDay(time.Now()).AddDate(0, 0, -days)
}

// CountDownloads counts download outcomes within the last `days` window.
//
// "Total" here means resolved downloads (success + error). `download_start`
// is intentionally excluded so success_rate = success / total has the
// correct denominator — every download fires `download_start` once and
// later exactly one of `download_complete` / `download_error`, so including
// starts would roughly halve the rate.
func (r *AnalyticsRepository) CountDownloads(days int, brand string) (total, success, errors int64, err error) {
	var result struct {
		Total   int64
		Success int64
		Errors  int64
	}
	query := r.db.Model(&model.AnalyticsEvent{}).
		Where("created_at >= ?", downloadWindowStart(days))
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err = query.
		Where("event_type IN ?", []string{"download_complete", "download_error"}).
		Select(`
			COUNT(*) as total,
			COUNT(*) FILTER (WHERE event_type = 'download_complete') as success,
			COUNT(*) FILTER (WHERE event_type = 'download_error') as errors
		`).Scan(&result).Error
	return result.Total, result.Success, result.Errors, err
}

// DownloadsByOS returns resolved download counts grouped by OS, within the last `days` window.
// `download_start` is excluded so per-OS totals match (success + error) and stay consistent
// with the summary card. See CountDownloads for the rationale.
func (r *AnalyticsRepository) DownloadsByOS(days int, brand string) (map[string]int64, error) {
	type result struct {
		OS    string
		Count int64
	}
	var results []result
	query := r.db.Model(&model.AnalyticsEvent{}).
		Where("created_at >= ?", downloadWindowStart(days))
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Where("event_type IN ?", []string{"download_complete", "download_error"}).
		Select("os, count(*) as count").Group("os").Find(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.OS] = r.Count
	}
	return m, nil
}

// DownloadsByPlatform aggregates resolved downloads by platform extracted from event_data JSON,
// within the last `days` window. event_data is expected to contain {"platform": "youtube"} or
// similar. `download_start` is excluded so per-platform success_rate has the correct
// denominator. See CountDownloads for the rationale.
func (r *AnalyticsRepository) DownloadsByPlatform(days int, brand string) ([]PlatformDownloadCount, error) {
	var results []PlatformDownloadCount
	sql := `
		SELECT
			COALESCE(event_data::json->>'platform', 'unknown') as platform,
			COUNT(*) as total,
			COUNT(*) FILTER (WHERE event_type = 'download_complete') as success,
			COUNT(*) FILTER (WHERE event_type = 'download_error') as errors
		FROM analytics_events
		WHERE event_type IN ('download_complete', 'download_error')
		  AND created_at >= $1`
	args := []interface{}{downloadWindowStart(days)}
	if brand != "" {
		sql += ` AND device_id IN (SELECT id FROM devices WHERE brand = $2)`
		args = append(args, brand)
	}
	sql += `
		GROUP BY COALESCE(event_data::json->>'platform', 'unknown')
		ORDER BY total DESC
		LIMIT 20`
	err := r.db.Raw(sql, args...).Scan(&results).Error
	return results, err
}

// DailyDownloadTrend returns daily resolved-download counts for the last N days.
// `download_start` is excluded so each day's `total` equals `success + errors`
// and stays consistent with the summary / platform aggregations.
func (r *AnalyticsRepository) DailyDownloadTrend(days int, brand string) ([]DailyDownloadCount, error) {
	var results []DailyDownloadCount
	start := timeutil.UTCStartOfDay(time.Now()).AddDate(0, 0, -days)
	sql := `
		SELECT
			DATE(created_at AT TIME ZONE 'UTC') as date,
			COUNT(*) as total,
			COUNT(*) FILTER (WHERE event_type = 'download_complete') as success,
			COUNT(*) FILTER (WHERE event_type = 'download_error') as errors
		FROM analytics_events
		WHERE event_type IN ('download_complete', 'download_error')
		AND created_at >= $1`
	args := []interface{}{start}
	if brand != "" {
		sql += ` AND device_id IN (SELECT id FROM devices WHERE brand = $2)`
		args = append(args, brand)
	}
	sql += `
		GROUP BY DATE(created_at AT TIME ZONE 'UTC')
		ORDER BY date ASC`
	err := r.db.Raw(sql, args...).Scan(&results).Error
	return results, err
}

// ==================== Daily Stats ====================

func (r *AnalyticsRepository) UpsertDailyStats(date time.Time, metricName string, value int64, dimensions string) error {
	stats := model.DailyStats{
		Date:       date,
		MetricName: metricName,
		Value:      value,
		Dimensions: dimensions,
	}

	return r.db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "date"}, {Name: "metric_name"}},
		DoUpdates: clause.AssignmentColumns([]string{"value", "dimensions"}),
	}).Create(&stats).Error
}

func (r *AnalyticsRepository) GetDailyStats(startDate, endDate time.Time, metricName string) ([]model.DailyStats, error) {
	var stats []model.DailyStats
	query := r.db.Where("date >= ? AND date <= ?", startDate, endDate)
	if metricName != "" {
		query = query.Where("metric_name = ?", metricName)
	}
	if err := query.Order("date ASC, metric_name ASC").Find(&stats).Error; err != nil {
		return nil, err
	}
	return stats, nil
}
