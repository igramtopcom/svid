package dto

import (
	"github.com/snakeloader/backend/internal/analytics/model"
)

// --- Requests ---

type TrackEventRequest struct {
	EventType string `json:"event_type" binding:"required,max=50"`
	EventData string `json:"event_data" binding:"max=500000"`
}

type TrackEventsRequest struct {
	Events []TrackEventRequest `json:"events" binding:"required,min=1,max=50"`
}

// --- Responses ---

type EventResponse struct {
	ID         string `json:"id"`
	DeviceID   string `json:"device_id"`
	EventType  string `json:"event_type"`
	EventData  string `json:"event_data,omitempty"`
	AppVersion string `json:"app_version,omitempty"`
	OS         string `json:"os,omitempty"`
	CreatedAt  string `json:"created_at"`
}

type DailyStatsResponse struct {
	Date       string `json:"date"`
	MetricName string `json:"metric_name"`
	Value      int64  `json:"value"`
	Dimensions string `json:"dimensions,omitempty"`
}

type AnalyticsOverview struct {
	TotalEvents       int64            `json:"total_events"`
	EventsToday       int64            `json:"events_today"`
	ActiveDevicesToday int64           `json:"active_devices_today"`
	ByOS              map[string]int64 `json:"by_os"`
	ByVersion         map[string]int64 `json:"by_version"`
}

// Download analytics aggregation
type DownloadStatsResponse struct {
	TotalDownloads  int64                  `json:"total_downloads"`
	SuccessCount    int64                  `json:"success_count"`
	ErrorCount      int64                  `json:"error_count"`
	SuccessRate     float64                `json:"success_rate"` // 0-100 percentage
	ByPlatform      []PlatformStats        `json:"by_platform"`
	ByOS            map[string]int64       `json:"by_os"`
	DailyTrend      []DailyDownloadStats   `json:"daily_trend"`
}

type PlatformStats struct {
	Platform     string  `json:"platform"` // youtube, tiktok, instagram, etc.
	Total        int64   `json:"total"`
	Success      int64   `json:"success"`
	Errors       int64   `json:"errors"`
	SuccessRate  float64 `json:"success_rate"`
}

type DailyDownloadStats struct {
	Date    string `json:"date"`
	Total   int64  `json:"total"`
	Success int64  `json:"success"`
	Errors  int64  `json:"errors"`
}

// --- Mappers ---

func EventToResponse(e *model.AnalyticsEvent) EventResponse {
	return EventResponse{
		ID:         e.ID.String(),
		DeviceID:   e.DeviceID.String(),
		EventType:  e.EventType,
		EventData:  e.EventData,
		AppVersion: e.AppVersion,
		OS:         e.OS,
		CreatedAt:  e.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}

func EventsToResponse(events []model.AnalyticsEvent) []EventResponse {
	result := make([]EventResponse, len(events))
	for i := range events {
		result[i] = EventToResponse(&events[i])
	}
	return result
}

func DailyStatsToResponse(s *model.DailyStats) DailyStatsResponse {
	return DailyStatsResponse{
		Date:       s.Date.Format("2006-01-02"),
		MetricName: s.MetricName,
		Value:      s.Value,
		Dimensions: s.Dimensions,
	}
}

func DailyStatsListToResponse(stats []model.DailyStats) []DailyStatsResponse {
	result := make([]DailyStatsResponse, len(stats))
	for i := range stats {
		result[i] = DailyStatsToResponse(&stats[i])
	}
	return result
}
