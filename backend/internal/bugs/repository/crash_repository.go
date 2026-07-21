package repository

import (
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/model"
	"github.com/snakeloader/backend/internal/pkg/timeutil"
	"gorm.io/gorm"
)

type CrashRepository struct {
	db *gorm.DB
}

func NewCrashRepository(db *gorm.DB) *CrashRepository {
	return &CrashRepository{db: db}
}

func (r *CrashRepository) Create(crash *model.CrashReport) error {
	return r.db.Create(crash).Error
}

func (r *CrashRepository) FindByID(id uuid.UUID) (*model.CrashReport, error) {
	var crash model.CrashReport
	err := r.db.Where("id = ?", id).First(&crash).Error
	if err != nil {
		return nil, err
	}
	return &crash, nil
}

func (r *CrashRepository) List(page, perPage int, severity, appVersion, os, brand, deviceID string) ([]model.CrashReport, int64, error) {
	var crashes []model.CrashReport
	var total int64

	query := r.db.Model(&model.CrashReport{})

	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	if severity != "" {
		query = query.Where("severity = ?", severity)
	}
	if appVersion != "" {
		query = query.Where("app_version = ?", appVersion)
	}
	if os != "" {
		query = query.Where("os = ?", os)
	}
	// device_id filter — was missing before, so `?device_id=X` silently
	// returned all crashes. Caller is expected to pass a valid UUID
	// string; non-UUID values yield an empty result via GORM's coercion
	// rather than a 500.
	if deviceID != "" {
		query = query.Where("device_id = ?", deviceID)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&crashes).Error; err != nil {
		return nil, 0, err
	}

	return crashes, total, nil
}

func (r *CrashRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.CrashReport{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *CrashRepository) CountToday(brand string) (int64, error) {
	var count int64
	today, tomorrow := timeutil.UTCDayBounds(time.Now())
	query := r.db.Model(&model.CrashReport{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Where("created_at >= ? AND created_at < ?", today, tomorrow).Count(&count).Error
	return count, err
}

func (r *CrashRepository) CountBySeverity(brand string) (map[string]int64, error) {
	type result struct {
		Severity string
		Count    int64
	}
	var results []result
	query := r.db.Model(&model.CrashReport{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.
		Select("severity, count(*) as count").
		Group("severity").Scan(&results).Error
	if err != nil {
		return nil, err
	}
	m := make(map[string]int64)
	for _, r := range results {
		m[r.Severity] = r.Count
	}
	return m, nil
}

func (r *CrashRepository) ListByGroupID(groupID uuid.UUID, page, perPage int) ([]model.CrashReport, int64, error) {
	var crashes []model.CrashReport
	var total int64

	query := r.db.Model(&model.CrashReport{}).Where("crash_group_id = ?", groupID)

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&crashes).Error; err != nil {
		return nil, 0, err
	}

	return crashes, total, nil
}

func (r *CrashRepository) CountByGroupID(groupID uuid.UUID) (int64, error) {
	var count int64
	err := r.db.Model(&model.CrashReport{}).Where("crash_group_id = ?", groupID).Count(&count).Error
	return count, err
}

func (r *CrashRepository) UpdateFields(id uuid.UUID, fields map[string]interface{}) error {
	return r.db.Model(&model.CrashReport{}).Where("id = ?", id).Updates(fields).Error
}

func (r *CrashRepository) ListByDeviceID(deviceID uuid.UUID, page, perPage int) ([]model.CrashReport, int64, error) {
	var crashes []model.CrashReport
	var total int64

	query := r.db.Model(&model.CrashReport{}).Where("device_id = ?", deviceID)

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&crashes).Error; err != nil {
		return nil, 0, err
	}

	return crashes, total, nil
}
