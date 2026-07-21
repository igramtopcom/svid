package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/alerts/model"
)

// ==================== Requests ====================

type CreateAlertConfigRequest struct {
	Name         string `json:"name" binding:"required,max=100"`
	MetricType   string `json:"metric_type" binding:"required,oneof=crash_rate error_rate"`
	Threshold    int    `json:"threshold" binding:"required,min=1"`
	WindowMins   int    `json:"window_mins" binding:"required,min=5,max=1440"`
	Channel      string `json:"channel" binding:"required,oneof=telegram email"`
	Destination  string `json:"destination" binding:"required,max=500"`
	IsEnabled    *bool  `json:"is_enabled"`
	CooldownMins int    `json:"cooldown_mins" binding:"omitempty,min=5"`
}

type UpdateAlertConfigRequest struct {
	Name         *string `json:"name,omitempty" binding:"omitempty,max=100"`
	Threshold    *int    `json:"threshold,omitempty" binding:"omitempty,min=1"`
	WindowMins   *int    `json:"window_mins,omitempty" binding:"omitempty,min=5,max=1440"`
	Channel      *string `json:"channel,omitempty" binding:"omitempty,oneof=telegram email"`
	Destination  *string `json:"destination,omitempty" binding:"omitempty,max=500"`
	IsEnabled    *bool   `json:"is_enabled,omitempty"`
	CooldownMins *int    `json:"cooldown_mins,omitempty" binding:"omitempty,min=5"`
}

// ==================== Responses ====================

type AlertConfigResponse struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	MetricType   string  `json:"metric_type"`
	Threshold    int     `json:"threshold"`
	WindowMins   int     `json:"window_mins"`
	Channel      string  `json:"channel"`
	Destination  string  `json:"destination"`
	IsEnabled    bool    `json:"is_enabled"`
	CooldownMins int     `json:"cooldown_mins"`
	LastFiredAt  string  `json:"last_fired_at,omitempty"`
	CreatedAt    string  `json:"created_at"`
	UpdatedAt    string  `json:"updated_at"`
}

type AlertLogResponse struct {
	ID            string `json:"id"`
	AlertConfigID string `json:"alert_config_id"`
	MetricValue   int    `json:"metric_value"`
	Message       string `json:"message"`
	Channel       string `json:"channel"`
	Status        string `json:"status"`
	ErrorMessage  string `json:"error_message,omitempty"`
	CreatedAt     string `json:"created_at"`
}

// ==================== Mappers ====================

func AlertConfigToResponse(c *model.AlertConfig) AlertConfigResponse {
	resp := AlertConfigResponse{
		ID:           c.ID.String(),
		Name:         c.Name,
		MetricType:   c.MetricType,
		Threshold:    c.Threshold,
		WindowMins:   c.WindowMins,
		Channel:      c.Channel,
		Destination:  c.Destination,
		IsEnabled:    c.IsEnabled,
		CooldownMins: c.CooldownMins,
		CreatedAt:    c.CreatedAt.Format(time.RFC3339),
		UpdatedAt:    c.UpdatedAt.Format(time.RFC3339),
	}
	if c.LastFiredAt != nil {
		resp.LastFiredAt = c.LastFiredAt.Format(time.RFC3339)
	}
	return resp
}

func AlertConfigsToResponse(configs []model.AlertConfig) []AlertConfigResponse {
	result := make([]AlertConfigResponse, len(configs))
	for i := range configs {
		result[i] = AlertConfigToResponse(&configs[i])
	}
	return result
}

func AlertLogToResponse(l *model.AlertLog) AlertLogResponse {
	return AlertLogResponse{
		ID:            l.ID.String(),
		AlertConfigID: l.AlertConfigID.String(),
		MetricValue:   l.MetricValue,
		Message:       l.Message,
		Channel:       l.Channel,
		Status:        l.Status,
		ErrorMessage:  l.ErrorMessage,
		CreatedAt:     l.CreatedAt.Format(time.RFC3339),
	}
}

func AlertLogsToResponse(logs []model.AlertLog) []AlertLogResponse {
	result := make([]AlertLogResponse, len(logs))
	for i := range logs {
		result[i] = AlertLogToResponse(&logs[i])
	}
	return result
}
