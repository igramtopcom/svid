package dto

import (
	"github.com/snakeloader/backend/internal/product/model"
)

// --- Requests ---

type CreateFeatureFlagRequest struct {
	Key           string `json:"key" binding:"required,max=100"`
	Name          string `json:"name" binding:"required,max=255"`
	Description   string `json:"description"`
	Enabled       bool   `json:"enabled"`
	Tiers         string `json:"tiers"`          // JSON array string
	Platforms     string `json:"platforms"`       // JSON array string
	MinAppVersion string `json:"min_app_version" binding:"max=20"`
	Metadata      string `json:"metadata"`
}

type UpdateFeatureFlagRequest struct {
	Name          *string `json:"name" binding:"omitempty,max=255"`
	Description   *string `json:"description"`
	Enabled       *bool   `json:"enabled"`
	Tiers         *string `json:"tiers"`
	Platforms     *string `json:"platforms"`
	MinAppVersion *string `json:"min_app_version" binding:"omitempty,max=20"`
	Metadata      *string `json:"metadata"`
}

// --- Responses ---

type FeatureFlagResponse struct {
	ID            string `json:"id"`
	Key           string `json:"key"`
	Name          string `json:"name"`
	Description   string `json:"description"`
	Enabled       bool   `json:"enabled"`
	Tiers         string `json:"tiers,omitempty"`
	Platforms     string `json:"platforms,omitempty"`
	MinAppVersion string `json:"min_app_version,omitempty"`
	Metadata      string `json:"metadata,omitempty"`
	CreatedAt     string `json:"created_at"`
	UpdatedAt     string `json:"updated_at"`
}

// DeviceFeatureFlagResponse is a slimmer response for device-facing API
type DeviceFeatureFlagResponse struct {
	Key           string `json:"key"`
	Enabled       bool   `json:"enabled"`
	MinAppVersion string `json:"min_app_version,omitempty"`
	Metadata      string `json:"metadata,omitempty"`
}

// --- Mappers ---

func FeatureFlagToResponse(f *model.FeatureFlag) FeatureFlagResponse {
	return FeatureFlagResponse{
		ID:            f.ID.String(),
		Key:           f.Key,
		Name:          f.Name,
		Description:   f.Description,
		Enabled:       f.Enabled,
		Tiers:         f.Tiers,
		Platforms:     f.Platforms,
		MinAppVersion: f.MinAppVersion,
		Metadata:      f.Metadata,
		CreatedAt:     f.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:     f.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func FeatureFlagsToResponse(flags []model.FeatureFlag) []FeatureFlagResponse {
	result := make([]FeatureFlagResponse, len(flags))
	for i := range flags {
		result[i] = FeatureFlagToResponse(&flags[i])
	}
	return result
}

func FeatureFlagToDeviceResponse(f *model.FeatureFlag) DeviceFeatureFlagResponse {
	return DeviceFeatureFlagResponse{
		Key:           f.Key,
		Enabled:       f.Enabled,
		MinAppVersion: f.MinAppVersion,
		Metadata:      f.Metadata,
	}
}

func FeatureFlagsToDeviceResponse(flags []model.FeatureFlag) []DeviceFeatureFlagResponse {
	result := make([]DeviceFeatureFlagResponse, len(flags))
	for i := range flags {
		result[i] = FeatureFlagToDeviceResponse(&flags[i])
	}
	return result
}
