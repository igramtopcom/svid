package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/assistant/model"
	"gorm.io/gorm"
)

type KnowledgeRepository struct {
	db *gorm.DB
}

func NewKnowledgeRepository(db *gorm.DB) *KnowledgeRepository {
	return &KnowledgeRepository{db: db}
}

func (r *KnowledgeRepository) Create(kb *model.KnowledgeBase) error {
	return r.db.Create(kb).Error
}

func (r *KnowledgeRepository) FindByID(id uuid.UUID) (*model.KnowledgeBase, error) {
	var kb model.KnowledgeBase
	if err := r.db.Where("id = ?", id).First(&kb).Error; err != nil {
		return nil, err
	}
	return &kb, nil
}

func (r *KnowledgeRepository) Update(kb *model.KnowledgeBase) error {
	return r.db.Save(kb).Error
}

func (r *KnowledgeRepository) Delete(id uuid.UUID) error {
	return r.db.Delete(&model.KnowledgeBase{}, "id = ?", id).Error
}

func (r *KnowledgeRepository) List(page, perPage int, category string, activeOnly bool) ([]model.KnowledgeBase, int64, error) {
	var entries []model.KnowledgeBase
	var total int64

	query := r.db.Model(&model.KnowledgeBase{})
	if category != "" {
		query = query.Where("category = ?", category)
	}
	if activeOnly {
		query = query.Where("is_active = ?", true)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * perPage
	if err := query.Order("category ASC, title ASC").Offset(offset).Limit(perPage).Find(&entries).Error; err != nil {
		return nil, 0, err
	}

	return entries, total, nil
}

func (r *KnowledgeRepository) ListActive() ([]model.KnowledgeBase, error) {
	var entries []model.KnowledgeBase
	if err := r.db.Where("is_active = ?", true).Find(&entries).Error; err != nil {
		return nil, err
	}
	return entries, nil
}

// Search finds knowledge base entries matching a query (case-insensitive)
func (r *KnowledgeRepository) Search(query string) ([]model.KnowledgeBase, error) {
	var entries []model.KnowledgeBase
	searchPattern := "%" + query + "%"
	if err := r.db.Where("is_active = ? AND (title ILIKE ? OR content ILIKE ? OR tags ILIKE ?)",
		true, searchPattern, searchPattern, searchPattern).
		Limit(5).Find(&entries).Error; err != nil {
		return nil, err
	}
	return entries, nil
}

func (r *KnowledgeRepository) CountAll() (int64, error) {
	var count int64
	err := r.db.Model(&model.KnowledgeBase{}).Count(&count).Error
	return count, err
}

func (r *KnowledgeRepository) CountActive() (int64, error) {
	var count int64
	err := r.db.Model(&model.KnowledgeBase{}).Where("is_active = ?", true).Count(&count).Error
	return count, err
}
