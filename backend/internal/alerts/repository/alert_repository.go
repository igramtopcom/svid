package repository

import (
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/alerts/model"
	"gorm.io/gorm"
)

type AlertRepository struct {
	db *gorm.DB
}

func NewAlertRepository(db *gorm.DB) *AlertRepository {
	return &AlertRepository{db: db}
}

// ==================== AlertConfig ====================

func (r *AlertRepository) CreateConfig(config *model.AlertConfig) error {
	return r.db.Create(config).Error
}

func (r *AlertRepository) FindConfigByID(id uuid.UUID) (*model.AlertConfig, error) {
	var config model.AlertConfig
	err := r.db.Where("id = ?", id).First(&config).Error
	if err != nil {
		return nil, err
	}
	return &config, nil
}

func (r *AlertRepository) UpdateConfig(config *model.AlertConfig) error {
	return r.db.Save(config).Error
}

func (r *AlertRepository) DeleteConfig(id uuid.UUID) error {
	return r.db.Delete(&model.AlertConfig{}, "id = ?", id).Error
}

func (r *AlertRepository) ListConfigs() ([]model.AlertConfig, error) {
	var configs []model.AlertConfig
	err := r.db.Order("created_at DESC").Find(&configs).Error
	return configs, err
}

func (r *AlertRepository) ListEnabledConfigs() ([]model.AlertConfig, error) {
	var configs []model.AlertConfig
	err := r.db.Where("is_enabled = ?", true).Find(&configs).Error
	return configs, err
}

// ==================== AlertLog ====================

func (r *AlertRepository) CreateLog(log *model.AlertLog) error {
	return r.db.Create(log).Error
}

func (r *AlertRepository) ListLogs(page, perPage int, configID *uuid.UUID) ([]model.AlertLog, int64, error) {
	var logs []model.AlertLog
	var total int64

	query := r.db.Model(&model.AlertLog{})
	if configID != nil {
		query = query.Where("alert_config_id = ?", *configID)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&logs).Error; err != nil {
		return nil, 0, err
	}

	return logs, total, nil
}

// ==================== Metric Queries ====================

// CountCrashesInWindow counts crash reports within the last N minutes.
func (r *AlertRepository) CountCrashesInWindow(windowMins int) (int, error) {
	var count int64
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)
	err := r.db.Table("crash_reports").Where("created_at >= ?", since).Count(&count).Error
	return int(count), err
}

// CountErrorEventsInWindow counts analytics events of type 'download_error' within the last N minutes.
func (r *AlertRepository) CountErrorEventsInWindow(windowMins int) (int, error) {
	var count int64
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)
	err := r.db.Table("analytics_events").
		Where("event_type = ? AND created_at >= ?", "download_error", since).
		Count(&count).Error
	return int(count), err
}

// CountDownloadErrorsInWindow counts structured download_errors within the last N minutes.
func (r *AlertRepository) CountDownloadErrorsInWindow(windowMins int) (int, error) {
	var count int64
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)
	err := r.db.Table("download_errors").
		Where("created_at >= ?", since).
		Count(&count).Error
	return int(count), err
}

// CountNewBugsInWindow counts new bug reports within the last N minutes.
func (r *AlertRepository) CountNewBugsInWindow(windowMins int) (int, error) {
	var count int64
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)
	err := r.db.Table("bug_reports").
		Where("created_at >= ?", since).
		Count(&count).Error
	return int(count), err
}

// CountActiveCrashGroups counts crash groups with active status (not resolved/wont_fix).
func (r *AlertRepository) CountActiveCrashGroups() (int, error) {
	var count int64
	err := r.db.Table("crash_groups").
		Where("status NOT IN ?", []string{"resolved", "wont_fix"}).
		Count(&count).Error
	return int(count), err
}

// CountCrashGroupSpikeInWindow counts crashes linked to active crash groups within the last N minutes.
func (r *AlertRepository) CountCrashGroupSpikeInWindow(windowMins int) (int, error) {
	var count int64
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)
	err := r.db.Table("crash_reports").
		Where("crash_group_id IS NOT NULL AND created_at >= ?", since).
		Count(&count).Error
	return int(count), err
}

// DownloadErrorRatePercent returns the download error percentage in the last N minutes.
// Calculated as: download_errors / (download_errors + successful downloads) * 100.
func (r *AlertRepository) DownloadErrorRatePercent(windowMins int) (int, error) {
	since := time.Now().Add(-time.Duration(windowMins) * time.Minute)

	var errorCount int64
	if err := r.db.Table("download_errors").
		Where("created_at >= ?", since).
		Count(&errorCount).Error; err != nil {
		return 0, err
	}

	var successCount int64
	r.db.Table("analytics_events").
		Where("event_type = ? AND created_at >= ?", "download_complete", since).
		Count(&successCount)

	total := errorCount + successCount
	if total == 0 {
		return 0, nil
	}
	return int(errorCount * 100 / total), nil
}
