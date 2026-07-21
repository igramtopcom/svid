package dto

import (
	"github.com/snakeloader/backend/internal/feedback/model"
)

// --- Requests ---

type CreateFeatureRequestRequest struct {
	Title       string `json:"title" binding:"required,max=500"`
	Description string `json:"description" binding:"required,max=50000"`
}

type UpdateFeatureRequestRequest struct {
	Status     *string `json:"status" binding:"omitempty,oneof=pending planned in_progress completed declined"`
	AdminNotes *string `json:"admin_notes"`
}

// --- Responses ---

type FeatureRequestResponse struct {
	ID          string `json:"id"`
	DeviceID    string `json:"device_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Status      string `json:"status"`
	Upvotes     int    `json:"upvotes"`
	AdminNotes  string `json:"admin_notes,omitempty"`
	CreatedAt   string `json:"created_at"`
	UpdatedAt   string `json:"updated_at"`
}

type VoteResponse struct {
	FeatureRequestID string `json:"feature_request_id"`
	Upvotes          int    `json:"upvotes"`
	Voted            bool   `json:"voted"`
}

// --- Mappers ---

func FeatureRequestToResponse(f *model.FeatureRequest) FeatureRequestResponse {
	return FeatureRequestResponse{
		ID:          f.ID.String(),
		DeviceID:    f.DeviceID.String(),
		Title:       f.Title,
		Description: f.Description,
		Status:      f.Status,
		Upvotes:     f.Upvotes,
		AdminNotes:  f.AdminNotes,
		CreatedAt:   f.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:   f.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func FeatureRequestsToResponse(requests []model.FeatureRequest) []FeatureRequestResponse {
	result := make([]FeatureRequestResponse, len(requests))
	for i := range requests {
		result[i] = FeatureRequestToResponse(&requests[i])
	}
	return result
}
