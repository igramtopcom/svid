package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/identity/model"
)

type RegisterResponse struct {
	DeviceID string `json:"device_id"`
	ApiKey   string `json:"api_key"`
	IsNew    bool   `json:"is_new"`
}

type HeartbeatResponse struct {
	ServerTime string `json:"server_time"`
}

type DeviceResponse struct {
	ID         string `json:"id"`
	HardwareID string `json:"hardware_id"`
	Brand      string `json:"brand"`
	OS         string `json:"os"`
	OSVersion  string `json:"os_version"`
	AppVersion string `json:"app_version"`
	DeviceName string `json:"device_name"`
	Tier       string `json:"tier"`
	IsActive   bool   `json:"is_active"`
	CreatedAt  string `json:"created_at"`
	LastSeenAt string `json:"last_seen_at"`
}

func DeviceToResponse(d *model.Device) DeviceResponse {
	return DeviceResponse{
		ID:         d.ID.String(),
		HardwareID: d.HardwareID,
		Brand:      d.Brand,
		OS:         d.OS,
		OSVersion:  d.OSVersion,
		AppVersion: d.AppVersion,
		DeviceName: d.DeviceName,
		Tier:       d.Tier,
		IsActive:   d.IsActive,
		CreatedAt:  d.CreatedAt.Format(time.RFC3339),
		LastSeenAt: d.LastSeenAt.Format(time.RFC3339),
	}
}

func DevicesToResponse(devices []model.Device) []DeviceResponse {
	result := make([]DeviceResponse, len(devices))
	for i, d := range devices {
		result[i] = DeviceToResponse(&d)
	}
	return result
}
