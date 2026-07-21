package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/analytics/model"
)

type TrackBootstrapEventRequest struct {
	InstallID    string `json:"install_id" binding:"required,min=8,max=64"`
	Brand        string `json:"brand" binding:"omitempty,oneof=svid vidcombo"`
	OS           string `json:"os" binding:"required,oneof=macos windows linux unknown"`
	OSVersion    string `json:"os_version" binding:"max=80"`
	AppVersion   string `json:"app_version" binding:"required,max=20"`
	Stage        string `json:"stage" binding:"required,max=50"`
	Status       string `json:"status" binding:"required,oneof=started succeeded failed skipped"`
	ErrorCode    string `json:"error_code" binding:"max=100"`
	ErrorMessage string `json:"error_message" binding:"max=5000"`
	Metadata     string `json:"metadata" binding:"max=50000"` // JSON
}

type BootstrapEventResponse struct {
	ID           string `json:"id"`
	InstallID    string `json:"install_id"`
	Brand        string `json:"brand"`
	OS           string `json:"os"`
	OSVersion    string `json:"os_version,omitempty"`
	AppVersion   string `json:"app_version"`
	Stage        string `json:"stage"`
	Status       string `json:"status"`
	ErrorCode    string `json:"error_code,omitempty"`
	ErrorMessage string `json:"error_message,omitempty"`
	Metadata     string `json:"metadata,omitempty"`
	IPAddress    string `json:"ip_address,omitempty"`
	UserAgent    string `json:"user_agent,omitempty"`
	CreatedAt    string `json:"created_at"`
}

func BootstrapEventToResponse(e *model.BootstrapEvent) BootstrapEventResponse {
	return BootstrapEventResponse{
		ID:           e.ID.String(),
		InstallID:    e.InstallID,
		Brand:        e.Brand,
		OS:           e.OS,
		OSVersion:    e.OSVersion,
		AppVersion:   e.AppVersion,
		Stage:        e.Stage,
		Status:       e.Status,
		ErrorCode:    e.ErrorCode,
		ErrorMessage: e.ErrorMessage,
		Metadata:     e.Metadata,
		IPAddress:    e.IPAddress,
		UserAgent:    e.UserAgent,
		CreatedAt:    e.CreatedAt.Format(time.RFC3339),
	}
}

func BootstrapEventsToResponse(events []model.BootstrapEvent) []BootstrapEventResponse {
	result := make([]BootstrapEventResponse, len(events))
	for i := range events {
		result[i] = BootstrapEventToResponse(&events[i])
	}
	return result
}
