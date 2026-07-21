package repository

import (
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/analytics/model"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"gorm.io/gorm"
)

type DownloadErrorRepository struct {
	db *gorm.DB
}

func NewDownloadErrorRepository(db *gorm.DB) *DownloadErrorRepository {
	return &DownloadErrorRepository{db: db}
}

func (r *DownloadErrorRepository) Create(err *model.DownloadError) error {
	return r.db.Create(err).Error
}

func (r *DownloadErrorRepository) HasRecentFingerprint(deviceID uuid.UUID, platform, errorCode, errorPhase, errorMessage string, since time.Time) (bool, error) {
	var count int64
	err := r.db.Model(&model.DownloadError{}).
		Where("device_id = ? AND platform = ? AND error_code = ? AND error_phase = ? AND error_message = ? AND created_at >= ?",
			deviceID, platform, errorCode, errorPhase, errorMessage, since).
		Count(&count).Error
	return count > 0, err
}

func (r *DownloadErrorRepository) CreateBatch(errors []model.DownloadError) error {
	return r.db.Create(&errors).Error
}

func (r *DownloadErrorRepository) List(page, perPage int, errorCode, errorPhase, diagnosticErrorCode, platform, os, appVersion, brand string, dateFrom, dateTo *time.Time) ([]model.DownloadError, int64, error) {
	var errors []model.DownloadError
	var total int64

	query := r.db.Model(&model.DownloadError{})

	if errorCode != "" {
		query = query.Where("error_code = ?", errorCode)
	}
	if errorPhase != "" {
		query = query.Where("error_phase = ?", errorPhase)
	}
	if diagnosticErrorCode != "" {
		query = query.Where("diagnostic_error_code = ?", diagnosticErrorCode)
	}
	if platform != "" {
		query = query.Where("platform = ?", platform)
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
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&errors).Error; err != nil {
		return nil, 0, err
	}

	return errors, total, nil
}

func (r *DownloadErrorRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.DownloadError{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *DownloadErrorRepository) CountToday(brand string) (int64, error) {
	var count int64
	today, tomorrow := timeutil.UTCDayBounds(time.Now())
	query := r.db.Model(&model.DownloadError{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Where("created_at >= ? AND created_at < ?", today, tomorrow).Count(&count).Error
	return count, err
}

func (r *DownloadErrorRepository) CountByErrorCode(brand string) (map[string]int64, error) {
	type result struct {
		ErrorCode string
		Count     int64
	}
	var results []result
	query := r.db.Model(&model.DownloadError{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("error_code, count(*) as count").
		Group("error_code").Order("count DESC").
		Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.ErrorCode] = r.Count
	}
	return m, nil
}

func (r *DownloadErrorRepository) CountByDiagnosticErrorCode(brand string) (map[string]int64, error) {
	type result struct {
		DiagnosticErrorCode string
		Count               int64
	}
	var results []result
	query := r.db.Model(&model.DownloadError{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Where("COALESCE(diagnostic_error_code, '') <> ''").
		Select("diagnostic_error_code, count(*) as count").
		Group("diagnostic_error_code").Order("count DESC").
		Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.DiagnosticErrorCode] = r.Count
	}
	return m, nil
}

func (r *DownloadErrorRepository) CountWithDiagnostic(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.DownloadError{}).Where("COALESCE(diagnostic_error_code, '') <> ''")
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *DownloadErrorRepository) CountByPhase(brand string) (map[string]int64, error) {
	type result struct {
		ErrorPhase string
		Count      int64
	}
	var results []result
	query := r.db.Model(&model.DownloadError{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("error_phase, count(*) as count").
		Group("error_phase").Order("count DESC").
		Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.ErrorPhase] = r.Count
	}
	return m, nil
}

func (r *DownloadErrorRepository) CountByPlatform(brand string) (map[string]int64, error) {
	type result struct {
		Platform string
		Count    int64
	}
	var results []result
	query := r.db.Model(&model.DownloadError{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("platform, count(*) as count").
		Group("platform").Order("count DESC").
		Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.Platform] = r.Count
	}
	return m, nil
}

type DailyErrorCount struct {
	Date  string `json:"date"`
	Count int64  `json:"count"`
}

func (r *DownloadErrorRepository) DailyTrend(days int, brand string) ([]DailyErrorCount, error) {
	var results []DailyErrorCount
	start := timeutil.UTCStartOfDay(time.Now()).AddDate(0, 0, -days)
	sql := `SELECT DATE(created_at AT TIME ZONE 'UTC') as date, COUNT(*) as count
		FROM download_errors
		WHERE created_at >= $1`
	args := []interface{}{start}
	if brand != "" {
		sql += ` AND device_id IN (SELECT id FROM devices WHERE brand = $2)`
		args = append(args, brand)
	}
	sql += ` GROUP BY DATE(created_at AT TIME ZONE 'UTC') ORDER BY date ASC`
	err := r.db.Raw(sql, args...).Scan(&results).Error
	return results, err
}

type TopError struct {
	ErrorCode string `json:"error_code"`
	Platform  string `json:"platform"`
	Count     int64  `json:"count"`
}

func (r *DownloadErrorRepository) TopErrors(limit, days int, brand string) ([]TopError, error) {
	var results []TopError
	start := timeutil.UTCStartOfDay(time.Now()).AddDate(0, 0, -days)
	sql := `SELECT error_code, platform, COUNT(*) as count
		FROM download_errors
		WHERE created_at >= $1`
	args := []interface{}{start, limit}
	if brand != "" {
		sql += ` AND device_id IN (SELECT id FROM devices WHERE brand = $3)`
		args = append(args, brand)
	}
	sql += ` GROUP BY error_code, platform
		ORDER BY count DESC
		LIMIT $2`
	err := r.db.Raw(sql, args...).Scan(&results).Error
	return results, err
}

func (r *DownloadErrorRepository) ListByDeviceID(deviceID uuid.UUID, page, perPage int) ([]model.DownloadError, int64, error) {
	var errors []model.DownloadError
	var total int64

	query := r.db.Model(&model.DownloadError{}).Where("device_id = ?", deviceID)

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&errors).Error; err != nil {
		return nil, 0, err
	}

	return errors, total, nil
}

// CountInWindow counts download errors in the last N minutes (for alert system).
func (r *DownloadErrorRepository) CountInWindow(windowMins int) (int, error) {
	var count int64
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)
	err := r.db.Model(&model.DownloadError{}).Where("created_at >= ?", since).Count(&count).Error
	return int(count), err
}
