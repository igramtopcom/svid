package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/product/model"
	"gorm.io/gorm"
)

type RemoteConfigRepository struct {
	db *gorm.DB
}

func NewRemoteConfigRepository(db *gorm.DB) *RemoteConfigRepository {
	return &RemoteConfigRepository{db: db}
}

func (r *RemoteConfigRepository) Create(cfg *model.RemoteConfig) error {
	return r.db.Create(cfg).Error
}

func (r *RemoteConfigRepository) FindByID(id uuid.UUID) (*model.RemoteConfig, error) {
	var cfg model.RemoteConfig
	if err := r.db.Where("id = ?", id).First(&cfg).Error; err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (r *RemoteConfigRepository) FindByKey(key string) (*model.RemoteConfig, error) {
	var cfg model.RemoteConfig
	if err := r.db.Where("key = ?", key).First(&cfg).Error; err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (r *RemoteConfigRepository) List() ([]model.RemoteConfig, error) {
	var configs []model.RemoteConfig
	if err := r.db.Order("key ASC").Find(&configs).Error; err != nil {
		return nil, err
	}
	return configs, nil
}

func (r *RemoteConfigRepository) Update(cfg *model.RemoteConfig) error {
	return r.db.Save(cfg).Error
}

func (r *RemoteConfigRepository) Delete(id uuid.UUID) error {
	return r.db.Delete(&model.RemoteConfig{}, "id = ?", id).Error
}

func (r *RemoteConfigRepository) CountAll() (int64, error) {
	var count int64
	err := r.db.Model(&model.RemoteConfig{}).Count(&count).Error
	return count, err
}
