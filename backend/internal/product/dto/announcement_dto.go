package dto

import (
	"github.com/snakeloader/backend/internal/product/model"
)

// --- Requests ---

type CreateAnnouncementRequest struct {
	Title           string  `json:"title" binding:"required,max=500"`
	Content         string  `json:"content" binding:"required"`
	Type            string  `json:"type" binding:"required,oneof=info warning critical maintenance"`
	TargetTiers     string  `json:"target_tiers"`     // JSON array string
	TargetPlatforms string  `json:"target_platforms"` // JSON array string
	StartsAt        *string `json:"starts_at"`        // RFC3339
	ExpiresAt       *string `json:"expires_at"`       // RFC3339
	IsActive        bool    `json:"is_active"`
}

type UpdateAnnouncementRequest struct {
	Title           *string `json:"title" binding:"omitempty,max=500"`
	Content         *string `json:"content"`
	Type            *string `json:"type" binding:"omitempty,oneof=info warning critical maintenance"`
	TargetTiers     *string `json:"target_tiers"`
	TargetPlatforms *string `json:"target_platforms"`
	StartsAt        *string `json:"starts_at"`
	ExpiresAt       *string `json:"expires_at"`
	IsActive        *bool   `json:"is_active"`
}

// --- Responses ---

type AnnouncementResponse struct {
	ID              string  `json:"id"`
	Title           string  `json:"title"`
	Content         string  `json:"content"`
	Type            string  `json:"type"`
	TargetTiers     string  `json:"target_tiers,omitempty"`
	TargetPlatforms string  `json:"target_platforms,omitempty"`
	StartsAt        *string `json:"starts_at,omitempty"`
	ExpiresAt       *string `json:"expires_at,omitempty"`
	IsActive        bool    `json:"is_active"`
	CreatedAt       string  `json:"created_at"`
	UpdatedAt       string  `json:"updated_at"`
}

// DeviceAnnouncementResponse is a slim response for device-facing API
type DeviceAnnouncementResponse struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Content   string  `json:"content"`
	Type      string  `json:"type"`
	StartsAt  *string `json:"starts_at,omitempty"`
	ExpiresAt *string `json:"expires_at,omitempty"`
	CreatedAt string  `json:"created_at"`
}

// --- Mappers ---

func AnnouncementToResponse(a *model.Announcement) AnnouncementResponse {
	resp := AnnouncementResponse{
		ID:              a.ID.String(),
		Title:           a.Title,
		Content:         a.Content,
		Type:            a.Type,
		TargetTiers:     a.TargetTiers,
		TargetPlatforms: a.TargetPlatforms,
		IsActive:        a.IsActive,
		CreatedAt:       a.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:       a.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
	if a.StartsAt != nil {
		t := a.StartsAt.Format("2006-01-02T15:04:05Z07:00")
		resp.StartsAt = &t
	}
	if a.ExpiresAt != nil {
		t := a.ExpiresAt.Format("2006-01-02T15:04:05Z07:00")
		resp.ExpiresAt = &t
	}
	return resp
}

func AnnouncementsToResponse(announcements []model.Announcement) []AnnouncementResponse {
	result := make([]AnnouncementResponse, len(announcements))
	for i := range announcements {
		result[i] = AnnouncementToResponse(&announcements[i])
	}
	return result
}

func AnnouncementToDeviceResponse(a *model.Announcement) DeviceAnnouncementResponse {
	resp := DeviceAnnouncementResponse{
		ID:        a.ID.String(),
		Title:     a.Title,
		Content:   a.Content,
		Type:      a.Type,
		CreatedAt: a.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
	if a.StartsAt != nil {
		t := a.StartsAt.Format("2006-01-02T15:04:05Z07:00")
		resp.StartsAt = &t
	}
	if a.ExpiresAt != nil {
		t := a.ExpiresAt.Format("2006-01-02T15:04:05Z07:00")
		resp.ExpiresAt = &t
	}
	return resp
}

func AnnouncementsToDeviceResponse(announcements []model.Announcement) []DeviceAnnouncementResponse {
	result := make([]DeviceAnnouncementResponse, len(announcements))
	for i := range announcements {
		result[i] = AnnouncementToDeviceResponse(&announcements[i])
	}
	return result
}
