package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/analytics/model"
	"github.com/snakeloader/backend/internal/analytics/repository"
)

// Requests

type TrackDownloadErrorRequest struct {
	URL          string `json:"url" binding:"max=2000"`
	Platform     string `json:"platform" binding:"required,max=50"`
	ErrorCode    string `json:"error_code" binding:"required,max=50"`
	ErrorPhase   string `json:"error_phase" binding:"required,oneof=extraction download conversion merge post_process unknown"`
	ErrorMessage string `json:"error_message" binding:"max=5000"`
	Metadata     string `json:"metadata" binding:"max=50000"` // JSON
}

// Responses

type DownloadErrorResponse struct {
	ID                   string `json:"id"`
	DeviceID             string `json:"device_id"`
	URL                  string `json:"url"`
	Platform             string `json:"platform"`
	ErrorCode            string `json:"error_code"`
	ErrorPhase           string `json:"error_phase"`
	ErrorMessage         string `json:"error_message"`
	DiagnosticErrorCode  string `json:"diagnostic_error_code,omitempty"`
	DiagnosticErrorPhase string `json:"diagnostic_error_phase,omitempty"`
	DiagnosticSignature  string `json:"diagnostic_signature,omitempty"`
	AppVersion           string `json:"app_version"`
	OS                   string `json:"os"`
	OSVersion            string `json:"os_version"`
	Metadata             string `json:"metadata,omitempty"`
	CreatedAt            string `json:"created_at"`
}

type DownloadErrorStatsResponse struct {
	TotalErrors           int64                        `json:"total_errors"`
	ErrorsToday           int64                        `json:"errors_today"`
	ByErrorCode           map[string]int64             `json:"by_error_code"`
	ByDiagnosticErrorCode map[string]int64             `json:"by_diagnostic_error_code,omitempty"`
	DiagnosticRows        int64                        `json:"diagnostic_rows"`
	DiagnosticCoveragePct float64                      `json:"diagnostic_coverage_pct"`
	DiagnosticMode        string                       `json:"diagnostic_mode"`
	ByPhase               map[string]int64             `json:"by_phase"`
	ByPlatform            map[string]int64             `json:"by_platform"`
	TopErrors             []repository.TopError        `json:"top_errors"`
	DailyTrend            []repository.DailyErrorCount `json:"daily_trend"`
}

func DownloadErrorToResponse(e *model.DownloadError) DownloadErrorResponse {
	return DownloadErrorResponse{
		ID:                   e.ID.String(),
		DeviceID:             e.DeviceID.String(),
		URL:                  e.URL,
		Platform:             e.Platform,
		ErrorCode:            e.ErrorCode,
		ErrorPhase:           e.ErrorPhase,
		ErrorMessage:         e.ErrorMessage,
		DiagnosticErrorCode:  e.DiagnosticErrorCode,
		DiagnosticErrorPhase: e.DiagnosticErrorPhase,
		DiagnosticSignature:  e.DiagnosticSignature,
		AppVersion:           e.AppVersion,
		OS:                   e.OS,
		OSVersion:            e.OSVersion,
		Metadata:             e.Metadata,
		CreatedAt:            e.CreatedAt.Format(time.RFC3339),
	}
}

func DownloadErrorsToResponse(errors []model.DownloadError) []DownloadErrorResponse {
	result := make([]DownloadErrorResponse, len(errors))
	for i, e := range errors {
		result[i] = DownloadErrorToResponse(&e)
	}
	return result
}
