package dto

import (
	"time"

	"github.com/snakeloader/backend/internal/bugs/model"
)

// Requests

type UpdateCrashGroupRequest struct {
	Status     *string `json:"status,omitempty" binding:"omitempty,oneof=new investigating fixing resolved wont_fix"`
	Severity   *string `json:"severity,omitempty" binding:"omitempty,oneof=critical high medium low"`
	AdminNotes *string `json:"admin_notes,omitempty"`
	AssignedTo *string `json:"assigned_to,omitempty"`
}

type MergeCrashGroupsRequest struct {
	TargetID  string   `json:"target_id" binding:"required"`
	SourceIDs []string `json:"source_ids" binding:"required,min=1"`
}

type BackfillCrashGroupMergesRequest struct {
	ScanLimit       int   `json:"scan_limit,omitempty"`
	IncludeResolved bool  `json:"include_resolved,omitempty"`
	MaxCandidates   int   `json:"max_candidates,omitempty"`
	MaxGroupCount   int   `json:"max_group_count,omitempty"`
	DryRun          *bool `json:"dry_run,omitempty"`
}

// Responses

type CrashGroupMergeCandidateResponse struct {
	NormalizedTitle  string               `json:"normalized_title"`
	PlatformKey      string               `json:"platform_key"`
	Target           CrashGroupResponse   `json:"target"`
	Sources          []CrashGroupResponse `json:"sources"`
	GroupCount       int                  `json:"group_count"`
	TotalCrashCount  int64                `json:"total_crash_count"`
	TotalDeviceCount int64                `json:"total_device_count"`
	Reason           string               `json:"reason"`
}

type CrashGroupBackfillMergeResultResponse struct {
	Status           string   `json:"status"`
	NormalizedTitle  string   `json:"normalized_title"`
	PlatformKey      string   `json:"platform_key"`
	TargetID         string   `json:"target_id"`
	SourceIDs        []string `json:"source_ids"`
	GroupCount       int      `json:"group_count"`
	TotalCrashCount  int64    `json:"total_crash_count"`
	TotalDeviceCount int64    `json:"total_device_count"`
	Reason           string   `json:"reason,omitempty"`
	Error            string   `json:"error,omitempty"`
}

type CrashGroupBackfillMergeReportResponse struct {
	DryRun         bool                                    `json:"dry_run"`
	ScanLimit      int                                     `json:"scan_limit"`
	CandidateCount int                                     `json:"candidate_count"`
	SelectedCount  int                                     `json:"selected_count"`
	AppliedCount   int                                     `json:"applied_count"`
	OversizedCount int                                     `json:"oversized_count"`
	DeferredCount  int                                     `json:"deferred_count"`
	ErrorCount     int                                     `json:"error_count"`
	Results        []CrashGroupBackfillMergeResultResponse `json:"results"`
}

type CrashGroupResponse struct {
	ID          string  `json:"id"`
	Fingerprint string  `json:"fingerprint"`
	Title       string  `json:"title"`
	Status      string  `json:"status"`
	Severity    string  `json:"severity"`
	FirstSeenAt string  `json:"first_seen_at"`
	LastSeenAt  string  `json:"last_seen_at"`
	CrashCount  int64   `json:"crash_count"`
	DeviceCount int64   `json:"device_count"`
	Versions    string  `json:"versions"`
	Platforms   string  `json:"platforms"`
	AdminNotes  string  `json:"admin_notes"`
	AssignedTo  string  `json:"assigned_to"`
	ResolvedAt  *string `json:"resolved_at,omitempty"`
	CreatedAt   string  `json:"created_at"`
	UpdatedAt   string  `json:"updated_at"`
}

type CrashGroupStatsResponse struct {
	TotalGroups  int64            `json:"total_groups"`
	ActiveGroups int64            `json:"active_groups"`
	ByStatus     map[string]int64 `json:"by_status"`
	BySeverity   map[string]int64 `json:"by_severity"`
}

func CrashGroupToResponse(g *model.CrashGroup) CrashGroupResponse {
	resp := CrashGroupResponse{
		ID:          g.ID.String(),
		Fingerprint: g.Fingerprint,
		Title:       g.Title,
		Status:      g.Status,
		Severity:    g.Severity,
		FirstSeenAt: g.FirstSeenAt.Format(time.RFC3339),
		LastSeenAt:  g.LastSeenAt.Format(time.RFC3339),
		CrashCount:  g.CrashCount,
		DeviceCount: g.DeviceCount,
		Versions:    g.Versions,
		Platforms:   g.Platforms,
		AdminNotes:  g.AdminNotes,
		AssignedTo:  g.AssignedTo,
		CreatedAt:   g.CreatedAt.Format(time.RFC3339),
		UpdatedAt:   g.UpdatedAt.Format(time.RFC3339),
	}
	if g.ResolvedAt != nil {
		s := g.ResolvedAt.Format(time.RFC3339)
		resp.ResolvedAt = &s
	}
	return resp
}

func CrashGroupsToResponse(groups []model.CrashGroup) []CrashGroupResponse {
	result := make([]CrashGroupResponse, len(groups))
	for i, g := range groups {
		result[i] = CrashGroupToResponse(&g)
	}
	return result
}
