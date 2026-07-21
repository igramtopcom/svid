package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/bugs/model"
)

// Requests

type SubmitBugRequest struct {
	Title         string `json:"title" binding:"required,max=500"`
	Description   string `json:"description" binding:"required,max=50000"`
	Steps         string `json:"steps" binding:"max=50000"`
	AppVersion    string `json:"app_version" binding:"required,max=20"`
	OS            string `json:"os" binding:"required,oneof=macos windows linux"`
	OSVersion     string `json:"os_version" binding:"max=50"`
	DiagnosticLog string `json:"diagnostic_log" binding:"max=500000"` // last ~200 lines of app log
}

type UpdateBugRequest struct {
	Status     *string `json:"status,omitempty" binding:"omitempty,oneof=new triaging in_progress resolved closed"`
	Priority   *string `json:"priority,omitempty" binding:"omitempty,oneof=critical high medium low"`
	AdminNotes *string `json:"admin_notes,omitempty"`
}

// Responses

type BugResponse struct {
	ID          string               `json:"id"`
	DeviceID    string               `json:"device_id"`
	Title       string               `json:"title"`
	Description string               `json:"description"`
	Steps       string               `json:"steps,omitempty"`
	AppVersion  string               `json:"app_version"`
	OS          string               `json:"os"`
	OSVersion   string               `json:"os_version"`
	Status      string               `json:"status"`
	Priority    string               `json:"priority"`
	AdminNotes  string               `json:"admin_notes,omitempty"`
	ResolvedAt  string               `json:"resolved_at,omitempty"`
	CreatedAt   string               `json:"created_at"`
	UpdatedAt   string               `json:"updated_at"`
	Attachments    []AttachmentResponse `json:"attachments,omitempty"`
	HasDiagnostics bool                 `json:"has_diagnostics"`
}

type DiagnosticLogResponse struct {
	ID         string `json:"id"`
	ReportType string `json:"report_type"`
	ReportID   string `json:"report_id"`
	Content    string `json:"content"`
	LineCount  int    `json:"line_count"`
	SizeBytes  int    `json:"size_bytes"`
	CreatedAt  string `json:"created_at"`
}

type AttachmentResponse struct {
	ID       string `json:"id"`
	FileName string `json:"file_name"`
	FileURL  string `json:"file_url"`
	FileType string `json:"file_type"`
	FileSize int64  `json:"file_size"`
}

type BugStatsResponse struct {
	TotalBugs  int64            `json:"total_bugs"`
	OpenToday  int64            `json:"open_today"`
	ByStatus   map[string]int64 `json:"by_status"`
}

func BugToResponse(b *model.BugReport) BugResponse {
	resp := BugResponse{
		ID:          b.ID.String(),
		DeviceID:    b.DeviceID.String(),
		Title:       b.Title,
		Description: b.Description,
		Steps:       b.Steps,
		AppVersion:  b.AppVersion,
		OS:          b.OS,
		OSVersion:   b.OSVersion,
		Status:      b.Status,
		Priority:    b.Priority,
		AdminNotes:  b.AdminNotes,
		CreatedAt:   b.CreatedAt.Format(time.RFC3339),
		UpdatedAt:   b.UpdatedAt.Format(time.RFC3339),
	}
	if b.ResolvedAt != nil {
		resp.ResolvedAt = b.ResolvedAt.Format(time.RFC3339)
	}
	for _, a := range b.Attachments {
		resp.Attachments = append(resp.Attachments, AttachmentResponse{
			ID:       a.ID.String(),
			FileName: a.FileName,
			FileURL:  a.FileURL,
			FileType: a.FileType,
			FileSize: a.FileSize,
		})
	}
	return resp
}

func BugsToResponse(bugs []model.BugReport) []BugResponse {
	result := make([]BugResponse, len(bugs))
	for i, b := range bugs {
		result[i] = BugToResponse(&b)
	}
	return result
}
