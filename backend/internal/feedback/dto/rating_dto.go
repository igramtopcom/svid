package dto

import (
	"github.com/snakeloader/backend/internal/feedback/model"
)

// --- Requests ---

type SubmitRatingRequest struct {
	Rating     int    `json:"rating" binding:"required,min=1,max=5"`
	Review     string `json:"review"`
	AppVersion string `json:"app_version" binding:"max=20"`
}

// --- Responses ---

type RatingResponse struct {
	ID         string `json:"id"`
	DeviceID   string `json:"device_id"`
	Rating     int    `json:"rating"`
	Review     string `json:"review,omitempty"`
	AppVersion string `json:"app_version,omitempty"`
	CreatedAt  string `json:"created_at"`
	UpdatedAt  string `json:"updated_at"`
}

type RatingStatsResponse struct {
	TotalRatings int64          `json:"total_ratings"`
	Average      float64        `json:"average"`
	Distribution map[int]int64  `json:"distribution"`
}

// --- Mappers ---

func RatingToResponse(r *model.AppRating) RatingResponse {
	return RatingResponse{
		ID:         r.ID.String(),
		DeviceID:   r.DeviceID.String(),
		Rating:     r.Rating,
		Review:     r.Review,
		AppVersion: r.AppVersion,
		CreatedAt:  r.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:  r.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func RatingsToResponse(ratings []model.AppRating) []RatingResponse {
	result := make([]RatingResponse, len(ratings))
	for i := range ratings {
		result[i] = RatingToResponse(&ratings[i])
	}
	return result
}
