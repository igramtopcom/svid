package repository

import (
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/model"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"gorm.io/gorm"
)

type BugRepository struct {
	db *gorm.DB
}

func NewBugRepository(db *gorm.DB) *BugRepository {
	return &BugRepository{db: db}
}

func (r *BugRepository) Create(bug *model.BugReport) error {
	return r.db.Create(bug).Error
}

func (r *BugRepository) FindByID(id uuid.UUID) (*model.BugReport, error) {
	var bug model.BugReport
	err := r.db.Preload("Attachments").Where("id = ?", id).First(&bug).Error
	if err != nil {
		return nil, err
	}
	return &bug, nil
}

func (r *BugRepository) Update(bug *model.BugReport) error {
	return r.db.Save(bug).Error
}

// UpdateFields performs a scoped column update on a bug report (safe for concurrent use).
func (r *BugRepository) UpdateFields(id uuid.UUID, fields map[string]interface{}) error {
	return r.db.Model(&model.BugReport{}).Where("id = ?", id).Updates(fields).Error
}

func (r *BugRepository) List(page, perPage int, status, priority, os, appVersion, search, brand, deviceID string) ([]model.BugReport, int64, error) {
	var bugs []model.BugReport
	var total int64

	query := r.db.Model(&model.BugReport{})

	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if priority != "" {
		query = query.Where("priority = ?", priority)
	}
	if os != "" {
		query = query.Where("os = ?", os)
	}
	if appVersion != "" {
		query = query.Where("app_version = ?", appVersion)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where("title ILIKE ? OR description ILIKE ?", like, like)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Preload("Attachments").Order("created_at DESC").Offset(offset).Limit(perPage).Find(&bugs).Error; err != nil {
		return nil, 0, err
	}

	return bugs, total, nil
}

func (r *BugRepository) ListByDevice(deviceID uuid.UUID) ([]model.BugReport, error) {
	var bugs []model.BugReport
	err := r.db.Preload("Attachments").Where("device_id = ?", deviceID).Order("created_at DESC").Limit(50).Find(&bugs).Error
	return bugs, err
}

func (r *BugRepository) CreateAttachment(attachment *model.BugAttachment) error {
	return r.db.Create(attachment).Error
}

func (r *BugRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.BugReport{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *BugRepository) CountByStatus(brand string) (map[string]int64, error) {
	type result struct {
		Status string
		Count  int64
	}
	var results []result
	query := r.db.Model(&model.BugReport{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("status, count(*) as count").
		Group("status").Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.Status] = r.Count
	}
	return m, nil
}

func (r *BugRepository) CountOpenToday(brand string) (int64, error) {
	var count int64
	today, tomorrow := timeutil.UTCDayBounds(time.Now())
	query := r.db.Model(&model.BugReport{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Where("created_at >= ? AND created_at < ? AND status NOT IN ?", today, tomorrow, []string{"resolved", "closed"}).
		Count(&count).Error
	return count, err
}

// ==================== Diagnostic Logs ====================

func (r *BugRepository) CreateDiagnosticLog(log *model.DiagnosticLog) error {
	return r.db.Create(log).Error
}

func (r *BugRepository) FindDiagnosticLog(reportType string, reportID uuid.UUID) (*model.DiagnosticLog, error) {
	var log model.DiagnosticLog
	err := r.db.Where("report_type = ? AND report_id = ?", reportType, reportID).First(&log).Error
	if err != nil {
		return nil, err
	}
	return &log, nil
}

func (r *BugRepository) HasDiagnosticLog(reportType string, reportID uuid.UUID) bool {
	var count int64
	r.db.Model(&model.DiagnosticLog{}).
		Where("report_type = ? AND report_id = ?", reportType, reportID).
		Count(&count)
	return count > 0
}
