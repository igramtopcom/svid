package repository

import (
	"errors"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/feedback/model"
	"gorm.io/gorm"
)

type RatingRepository struct {
	db *gorm.DB
}

func NewRatingRepository(db *gorm.DB) *RatingRepository {
	return &RatingRepository{db: db}
}

func (r *RatingRepository) Upsert(rating *model.AppRating) error {
	// Try to find existing rating by device
	var existing model.AppRating
	err := r.db.Where("device_id = ?", rating.DeviceID).First(&existing).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return err // Real DB error, fail fast
	}
	if err == nil {
		// Update existing
		existing.Rating = rating.Rating
		existing.Review = rating.Review
		existing.AppVersion = rating.AppVersion
		return r.db.Save(&existing).Error
	}
	// Create new
	return r.db.Create(rating).Error
}

func (r *RatingRepository) FindByDeviceID(deviceID uuid.UUID) (*model.AppRating, error) {
	var rating model.AppRating
	if err := r.db.Where("device_id = ?", deviceID).First(&rating).Error; err != nil {
		return nil, err
	}
	return &rating, nil
}

func (r *RatingRepository) List(page, perPage int, rating int, sort, brand string) ([]model.AppRating, int64, error) {
	var ratings []model.AppRating
	var total int64

	query := r.db.Model(&model.AppRating{})

	if rating > 0 {
		query = query.Where("rating = ?", rating)
	}
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	orderClause := "created_at DESC"
	switch sort {
	case "rating_desc":
		orderClause = "rating DESC, created_at DESC"
	case "rating_asc":
		orderClause = "rating ASC, created_at DESC"
	}

	offset := (page - 1) * perPage
	if err := query.Order(orderClause).Offset(offset).Limit(perPage).Find(&ratings).Error; err != nil {
		return nil, 0, err
	}

	return ratings, total, nil
}

func (r *RatingRepository) CountAll(brand string) (int64, error) {
	var count int64
	query := r.db.Model(&model.AppRating{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Count(&count).Error
	return count, err
}

func (r *RatingRepository) AverageRating(brand string) (float64, error) {
	var avg float64
	query := r.db.Model(&model.AppRating{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Select("COALESCE(AVG(rating), 0)").Scan(&avg).Error
	return avg, err
}

func (r *RatingRepository) Distribution(brand string) (map[int]int64, error) {
	type result struct {
		Rating int
		Count  int64
	}
	var results []result
	query := r.db.Model(&model.AppRating{})
	if brand != "" {
		query = query.Where("device_id IN (SELECT id FROM devices WHERE brand = ?)", brand)
	}
	err := query.Select("rating, count(*) as count").Group("rating").Order("rating").Find(&results).Error
	if err != nil {
		return nil, err
	}
	dist := make(map[int]int64)
	for _, r := range results {
		dist[r.Rating] = r.Count
	}
	return dist, nil
}
