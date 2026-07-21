package repository

import (
	"time"

	"github.com/snakeloader/backend/internal/identity/model"
	"gorm.io/gorm"
)

type AuditLogRepository struct {
	db *gorm.DB
}

func NewAuditLogRepository(db *gorm.DB) *AuditLogRepository {
	return &AuditLogRepository{db: db}
}

func (r *AuditLogRepository) Create(log *model.AuditLog) error {
	return r.db.Create(log).Error
}

func (r *AuditLogRepository) List(page, perPage int, adminID, action, resourceType string, dateFrom, dateTo *time.Time) ([]model.AuditLog, int64, error) {
	query := r.db.Model(&model.AuditLog{})

	if adminID != "" {
		query = query.Where("admin_id = ?", adminID)
	}
	if action != "" {
		query = query.Where("action = ?", action)
	}
	if resourceType != "" {
		query = query.Where("resource_type = ?", resourceType)
	}
	if dateFrom != nil {
		query = query.Where("created_at >= ?", dateFrom)
	}
	if dateTo != nil {
		query = query.Where("created_at <= ?", dateTo)
	}

	var total int64
	query.Count(&total)

	var logs []model.AuditLog
	err := query.Order("created_at DESC").
		Offset((page - 1) * perPage).
		Limit(perPage).
		Find(&logs).Error

	return logs, total, err
}
