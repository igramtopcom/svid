package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/product/model"
	"gorm.io/gorm"
)

type FeatureFlagRepository struct {
	db *gorm.DB
}

func NewFeatureFlagRepository(db *gorm.DB) *FeatureFlagRepository {
	return &FeatureFlagRepository{db: db}
}

func (r *FeatureFlagRepository) Create(flag *model.FeatureFlag) error {
	return r.db.Create(flag).Error
}

func (r *FeatureFlagRepository) FindByID(id uuid.UUID) (*model.FeatureFlag, error) {
	var flag model.FeatureFlag
	if err := r.db.Where("id = ?", id).First(&flag).Error; err != nil {
		return nil, err
	}
	return &flag, nil
}

func (r *FeatureFlagRepository) FindByKey(key string) (*model.FeatureFlag, error) {
	var flag model.FeatureFlag
	if err := r.db.Where("key = ?", key).First(&flag).Error; err != nil {
		return nil, err
	}
	return &flag, nil
}

func (r *FeatureFlagRepository) List() ([]model.FeatureFlag, error) {
	var flags []model.FeatureFlag
	if err := r.db.Order("key ASC").Find(&flags).Error; err != nil {
		return nil, err
	}
	return flags, nil
}

func (r *FeatureFlagRepository) ListEnabled() ([]model.FeatureFlag, error) {
	var flags []model.FeatureFlag
	if err := r.db.Where("enabled = ?", true).Order("key ASC").Find(&flags).Error; err != nil {
		return nil, err
	}
	return flags, nil
}

func (r *FeatureFlagRepository) Update(flag *model.FeatureFlag) error {
	return r.db.Save(flag).Error
}

func (r *FeatureFlagRepository) Delete(id uuid.UUID) error {
	return r.db.Delete(&model.FeatureFlag{}, "id = ?", id).Error
}

func (r *FeatureFlagRepository) CountAll() (int64, error) {
	var count int64
	err := r.db.Model(&model.FeatureFlag{}).Count(&count).Error
	return count, err
}

func (r *FeatureFlagRepository) CountEnabled() (int64, error) {
	var count int64
	err := r.db.Model(&model.FeatureFlag{}).Where("enabled = ?", true).Count(&count).Error
	return count, err
}
