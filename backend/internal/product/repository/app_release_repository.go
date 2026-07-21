package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/product/model"
	"gorm.io/gorm"
)

type AppReleaseRepository struct {
	db *gorm.DB
}

func NewAppReleaseRepository(db *gorm.DB) *AppReleaseRepository {
	return &AppReleaseRepository{db: db}
}

func (r *AppReleaseRepository) Create(release *model.AppRelease) error {
	return r.db.Create(release).Error
}

func (r *AppReleaseRepository) FindByID(id uuid.UUID) (*model.AppRelease, error) {
	var release model.AppRelease
	if err := r.db.Where("id = ?", id).First(&release).Error; err != nil {
		return nil, err
	}
	return &release, nil
}

func (r *AppReleaseRepository) FindPublished(platform, channel, brand string) ([]model.AppRelease, error) {
	var releases []model.AppRelease
	query := r.db.Where("is_active = ? AND platform = ? AND channel = ?", true, platform, channel)
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	query = query.Where("published_at IS NOT NULL")
	if err := query.Order("published_at DESC").Limit(100).Find(&releases).Error; err != nil {
		return nil, err
	}
	return releases, nil
}

func (r *AppReleaseRepository) List(page, perPage int, platform, channel string) ([]model.AppRelease, int64, error) {
	var releases []model.AppRelease
	var total int64

	query := r.db.Model(&model.AppRelease{})

	if platform != "" {
		query = query.Where("platform = ?", platform)
	}
	if channel != "" {
		query = query.Where("channel = ?", channel)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("created_at DESC").Offset(offset).Limit(perPage).Find(&releases).Error; err != nil {
		return nil, 0, err
	}

	return releases, total, nil
}

func (r *AppReleaseRepository) Update(release *model.AppRelease) error {
	return r.db.Save(release).Error
}

func (r *AppReleaseRepository) CountAll() (int64, error) {
	var count int64
	err := r.db.Model(&model.AppRelease{}).Count(&count).Error
	return count, err
}

func (r *AppReleaseRepository) CountActive() (int64, error) {
	var count int64
	err := r.db.Model(&model.AppRelease{}).Where("is_active = ?", true).Count(&count).Error
	return count, err
}

// FindByVersionPlatformChannelBrand finds an existing release for deduplication.
func (r *AppReleaseRepository) FindByVersionPlatformChannelBrand(version, platform, channel, brand string) (*model.AppRelease, error) {
	var release model.AppRelease
	query := r.db.Where("version = ? AND platform = ? AND channel = ?", version, platform, channel)
	if brand != "" {
		query = query.Where("brand = ?", brand)
	}
	err := query.First(&release).Error
	if err != nil {
		return nil, err
	}
	return &release, nil
}
