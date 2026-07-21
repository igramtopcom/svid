package repository

import (
	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/feedback/model"
	"gorm.io/gorm"
)

type FeatureRequestRepository struct {
	db *gorm.DB
}

func NewFeatureRequestRepository(db *gorm.DB) *FeatureRequestRepository {
	return &FeatureRequestRepository{db: db}
}

func (r *FeatureRequestRepository) Create(req *model.FeatureRequest) error {
	return r.db.Create(req).Error
}

func (r *FeatureRequestRepository) FindByID(id uuid.UUID) (*model.FeatureRequest, error) {
	var req model.FeatureRequest
	if err := r.db.Where("id = ?", id).First(&req).Error; err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *FeatureRequestRepository) Update(req *model.FeatureRequest) error {
	return r.db.Save(req).Error
}

func (r *FeatureRequestRepository) List(page, perPage int, status, sortBy, brand, search string) ([]model.FeatureRequest, int64, error) {
	var requests []model.FeatureRequest
	var total int64

	query := r.db.Model(&model.FeatureRequest{})

	if status != "" {
		query = query.Where("status = ?", status)
	}
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	if search != "" {
		like := "%" + search + "%"
		query = query.Where("title ILIKE ? OR description ILIKE ?", like, like)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "created_at DESC"
	if sortBy == "upvotes" {
		orderClause = "upvotes DESC, created_at DESC"
	}

	offset := (page - 1) * perPage
	if err := query.Order(orderClause).Offset(offset).Limit(perPage).Find(&requests).Error; err != nil {
		return nil, 0, err
	}

	return requests, total, nil
}

func (r *FeatureRequestRepository) FindVote(featureID, deviceID uuid.UUID) (*model.FeatureVote, error) {
	var vote model.FeatureVote
	if err := r.db.Where("feature_request_id = ? AND device_id = ?", featureID, deviceID).First(&vote).Error; err != nil {
		return nil, err
	}
	return &vote, nil
}

func (r *FeatureRequestRepository) CreateVote(vote *model.FeatureVote) error {
	return r.db.Create(vote).Error
}

func (r *FeatureRequestRepository) IncrementUpvotes(id uuid.UUID) error {
	return r.db.Model(&model.FeatureRequest{}).Where("id = ?", id).
		UpdateColumn("upvotes", gorm.Expr("upvotes + 1")).Error
}

func (r *FeatureRequestRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.FeatureRequest{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *FeatureRequestRepository) CountByStatus(brand string) (map[string]int64, error) {
	type result struct {
		Status string
		Count  int64
	}
	var results []result
	query := r.db.Model(&model.FeatureRequest{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Select("status, count(*) as count").Group("status").Find(&results).Error
	if err != nil {
		return nil, err
	}
	counts := make(map[string]int64)
	for _, r := range results {
		counts[r.Status] = r.Count
	}
	return counts, nil
}
