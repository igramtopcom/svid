package dto

import (
	"github.com/snakeloader/backend/internal/product/model"
)

// --- Requests ---

type CreateRemoteConfigRequest struct {
	Key         string `json:"key" binding:"required,max=100"`
	Value       string `json:"value" binding:"required"`
	ValueType   string `json:"value_type" binding:"required,oneof=string number boolean json"`
	Description string `json:"description"`
}

type UpdateRemoteConfigRequest struct {
	Value       *string `json:"value"`
	ValueType   *string `json:"value_type" binding:"omitempty,oneof=string number boolean json"`
	Description *string `json:"description"`
}

// --- Responses ---

type RemoteConfigResponse struct {
	ID          string `json:"id"`
	Key         string `json:"key"`
	Value       string `json:"value"`
	ValueType   string `json:"value_type"`
	Description string `json:"description"`
	CreatedAt   string `json:"created_at"`
	UpdatedAt   string `json:"updated_at"`
}

// DeviceRemoteConfigResponse is a slim key-value for device-facing API
type DeviceRemoteConfigResponse struct {
	Key       string `json:"key"`
	Value     string `json:"value"`
	ValueType string `json:"value_type"`
}

// --- Mappers ---

func RemoteConfigToResponse(c *model.RemoteConfig) RemoteConfigResponse {
	return RemoteConfigResponse{
		ID:          c.ID.String(),
		Key:         c.Key,
		Value:       c.Value,
		ValueType:   c.ValueType,
		Description: c.Description,
		CreatedAt:   c.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:   c.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func RemoteConfigsToResponse(configs []model.RemoteConfig) []RemoteConfigResponse {
	result := make([]RemoteConfigResponse, len(configs))
	for i := range configs {
		result[i] = RemoteConfigToResponse(&configs[i])
	}
	return result
}

func RemoteConfigToDeviceResponse(c *model.RemoteConfig) DeviceRemoteConfigResponse {
	return DeviceRemoteConfigResponse{
		Key:       c.Key,
		Value:     c.Value,
		ValueType: c.ValueType,
	}
}

func RemoteConfigsToDeviceResponse(configs []model.RemoteConfig) []DeviceRemoteConfigResponse {
	result := make([]DeviceRemoteConfigResponse, len(configs))
	for i := range configs {
		result[i] = RemoteConfigToDeviceResponse(&configs[i])
	}
	return result
}
