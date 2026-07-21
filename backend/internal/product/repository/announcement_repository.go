package repository

import (
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/product/model"
	"gorm.io/gorm"
)

type AnnouncementRepository struct {
	db *gorm.DB
}

func NewAnnouncementRepository(db *gorm.DB) *AnnouncementRepository {
	return &AnnouncementRepository{db: db}
}

func (r *AnnouncementRepository) Create(ann *model.Announcement) error {
	return r.db.Create(ann).Error
}

func (r *AnnouncementRepository) FindByID(id uuid.UUID) (*model.Announcement, error) {
	var ann model.Announcement
	if err := r.db.Where("id = ?", id).First(&ann).Error; err != nil {
		return nil, err
	}
	return &ann, nil
}

func (r *AnnouncementRepository) List(page, perPage int, annType string, activeOnly bool) ([]model.Announcement, int64, error) {
	var announcements []model.Announcement
	var total int64

	query := r.db.Model(&model.Announcement{})

	if annType != "" {
		query = query.Where("type = ?", annType)
	}
	if activeOnly {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&announcements).Error; err != nil {
		return nil, 0, err
	}

	return announcements, total, nil
}

// ListActive returns active announcements that are within their time window
func (r *AnnouncementRepository) ListActive() ([]model.Announcement, error) {
	var announcements []model.Announcement
	now := time.Now()

	query := r.db.Where("is_active = ?", true)
	query = query.Where("starts_at IS NULL OR starts_at <= ?", now)
	query = query.Where("expires_at IS NULL OR expires_at > ?", now)

	if err := query.Order("created_at DESC").Limit(50).Find(&announcements).Error; err != nil {
		return nil, err
	}

	return announcements, nil
}

func (r *AnnouncementRepository) Update(ann *model.Announcement) error {
	return r.db.Save(ann).Error
}

func (r *AnnouncementRepository) Delete(id uuid.UUID) error {
	return r.db.Delete(&model.Announcement{}, "id = ?", id).Error
}

func (r *AnnouncementRepository) CountAll() (int64, error) {
	var count int64
	err := r.db.Model(&model.Announcement{}).Count(&count).Error
	return count, err
}

func (r *AnnouncementRepository) CountActive() (int64, error) {
	var count int64
	now := time.Now()
	err := r.db.Model(&model.Announcement{}).
		Where("is_active = ? AND (starts_at IS NULL OR starts_at <= ?) AND (expires_at IS NULL OR expires_at > ?)", true, now, now).
		Count(&count).Error
	return count, err
}
