package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/bugs/model"
)

// Requests

type SubmitCrashRequest struct {
	StackTrace   string `json:"stack_trace" binding:"required,max=500000"`
	ErrorMessage string `json:"error_message" binding:"max=50000"`
	AppVersion   string `json:"app_version" binding:"required,max=20"`
	OS           string `json:"os" binding:"required,oneof=macos windows linux"`
	OSVersion    string `json:"os_version" binding:"max=50"`
	Severity      string `json:"severity" binding:"omitempty,oneof=critical high medium low"`
	Metadata      string `json:"metadata" binding:"max=500000"`       // JSON string
	DiagnosticLog string `json:"diagnostic_log" binding:"max=500000"` // last ~200 lines of app log
}

type UpdateCrashRequest struct {
	AdminNotes *string `json:"admin_notes,omitempty"`
}

// Responses

type CrashResponse struct {
	ID           string  `json:"id"`
	DeviceID     string  `json:"device_id"`
	CrashGroupID *string `json:"crash_group_id,omitempty"`
	StackTrace   string  `json:"stack_trace"`
	ErrorMessage string  `json:"error_message"`
	AppVersion   string  `json:"app_version"`
	OS           string  `json:"os"`
	OSVersion    string  `json:"os_version"`
	Severity     string  `json:"severity"`
	Metadata       string `json:"metadata,omitempty"`
	AdminNotes     string `json:"admin_notes,omitempty"`
	CreatedAt      string `json:"created_at"`
	HasDiagnostics bool   `json:"has_diagnostics"`
}

type CrashStatsResponse struct {
	TotalCrashes  int64            `json:"total_crashes"`
	CrashesToday  int64            `json:"crashes_today"`
	BySeverity    map[string]int64 `json:"by_severity"`
}

func CrashToResponse(c *model.CrashReport) CrashResponse {
	resp := CrashResponse{
		ID:           c.ID.String(),
		DeviceID:     c.DeviceID.String(),
		StackTrace:   c.StackTrace,
		ErrorMessage: c.ErrorMessage,
		AppVersion:   c.AppVersion,
		OS:           c.OS,
		OSVersion:    c.OSVersion,
		Severity:     c.Severity,
		Metadata:     c.Metadata,
		AdminNotes:   c.AdminNotes,
		CreatedAt:    c.CreatedAt.Format(time.RFC3339),
	}
	if c.CrashGroupID != nil {
		s := c.CrashGroupID.String()
		resp.CrashGroupID = &s
	}
	return resp
}

func CrashesToResponse(crashes []model.CrashReport) []CrashResponse {
	result := make([]CrashResponse, len(crashes))
	for i, c := range crashes {
		result[i] = CrashToResponse(&c)
	}
	return result
}
