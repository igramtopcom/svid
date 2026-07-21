package dto

import (
	"github.com/snakeloader/backend/internal/product/model"
)

// --- Requests ---

type CreateAppReleaseRequest struct {
	Version      string `json:"version" binding:"required,max=20"`
	Platform     string `json:"platform" binding:"required,oneof=macos windows linux android"`
	Channel      string `json:"channel" binding:"required,oneof=stable beta alpha"`
	Brand        string `json:"brand" binding:"omitempty,oneof=ssvid vidcombo"`
	ReleaseNotes string `json:"release_notes"`
	DownloadURL  string `json:"download_url"`
	FileSize     int64  `json:"file_size"`
	Checksum     string `json:"checksum" binding:"max=64"`
	IsMandatory  bool   `json:"is_mandatory"`
	IsActive     bool   `json:"is_active"`
	Publish      bool   `json:"publish"` // If true, set published_at to now
}

type UpdateAppReleaseRequest struct {
	ReleaseNotes *string `json:"release_notes"`
	DownloadURL  *string `json:"download_url"`
	FileSize     *int64  `json:"file_size"`
	Checksum     *string `json:"checksum" binding:"omitempty,max=64"`
	IsMandatory  *bool   `json:"is_mandatory"`
	IsActive     *bool   `json:"is_active"`
	Publish      *bool   `json:"publish"` // If true, set published_at to now
}

type CheckUpdateRequest struct {
	Platform   string `form:"platform" binding:"required,oneof=macos windows linux"`
	Version    string `form:"version" binding:"required"`
	Channel    string `form:"channel" binding:"omitempty,oneof=stable beta alpha"`
}

// CIReleasePlatformData represents a single platform's release data from CI pipeline.
type CIReleasePlatformData struct {
	DownloadURL string `json:"download_url" binding:"required"`
	Checksum    string `json:"checksum"`
	FileSize    int64  `json:"file_size"`
}

// CIReleaseRequest is the batch release registration payload from CI.
type CIReleaseRequest struct {
	Version      string                           `json:"version" binding:"required,max=20"`
	Channel      string                           `json:"channel" binding:"omitempty,oneof=stable beta alpha"`
	Brand        string                           `json:"brand" binding:"omitempty,oneof=ssvid vidcombo"`
	ReleaseNotes string                           `json:"release_notes"`
	IsMandatory  bool                             `json:"is_mandatory"`
	Platforms    map[string]CIReleasePlatformData `json:"platforms" binding:"required"`
}

// --- Responses ---

type AppReleaseResponse struct {
	ID           string  `json:"id"`
	Version      string  `json:"version"`
	Platform     string  `json:"platform"`
	Channel      string  `json:"channel"`
	Brand        string  `json:"brand"`
	ReleaseNotes string  `json:"release_notes,omitempty"`
	DownloadURL  string  `json:"download_url,omitempty"`
	FileSize     int64   `json:"file_size"`
	Checksum     string  `json:"checksum,omitempty"`
	IsMandatory  bool    `json:"is_mandatory"`
	IsActive     bool    `json:"is_active"`
	PublishedAt  *string `json:"published_at,omitempty"`
	CreatedAt    string  `json:"created_at"`
	UpdatedAt    string  `json:"updated_at"`
}

type UpdateCheckResponse struct {
	UpdateAvailable bool    `json:"update_available"`
	LatestVersion   string  `json:"latest_version,omitempty"`
	CurrentVersion  string  `json:"current_version"`
	IsMandatory     bool    `json:"is_mandatory"`
	ReleaseNotes    string  `json:"release_notes,omitempty"`
	DownloadURL     string  `json:"download_url,omitempty"`
	FileSize        int64   `json:"file_size,omitempty"`
	Checksum        string  `json:"checksum,omitempty"`
	PublishedAt     *string `json:"published_at,omitempty"`
}

// --- Mappers ---

func AppReleaseToResponse(r *model.AppRelease) AppReleaseResponse {
	resp := AppReleaseResponse{
		ID:           r.ID.String(),
		Version:      r.Version,
		Platform:     r.Platform,
		Channel:      r.Channel,
		Brand:        r.Brand,
		ReleaseNotes: r.ReleaseNotes,
		DownloadURL:  r.DownloadURL,
		FileSize:     r.FileSize,
		Checksum:     r.Checksum,
		IsMandatory:  r.IsMandatory,
		IsActive:     r.IsActive,
		CreatedAt:    r.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:    r.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
	if r.PublishedAt != nil {
		t := r.PublishedAt.Format("2006-01-02T15:04:05Z07:00")
		resp.PublishedAt = &t
	}
	return resp
}

func AppReleasesToResponse(releases []model.AppRelease) []AppReleaseResponse {
	result := make([]AppReleaseResponse, len(releases))
	for i := range releases {
		result[i] = AppReleaseToResponse(&releases[i])
	}
	return result
}
