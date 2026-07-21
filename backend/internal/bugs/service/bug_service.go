package service

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/dto"
	"github.com/snakeloader/backend/internal/bugs/model"
	"github.com/snakeloader/backend/internal/bugs/repository"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/pkg/pagination"
	"gorm.io/gorm"
)

var (
	ErrBugNotFound        = errors.New("bug report not found")
	ErrBugAccessDenied    = errors.New("bug report access denied")
	ErrCrashNotFound      = errors.New("crash report not found")
	ErrCrashAccessDenied  = errors.New("crash report access denied")
	ErrCrashGroupNotFound = errors.New("crash group not found")
	ErrLogNotFound        = errors.New("diagnostic log not found")
)

// EventNotifier is an optional hook for sending event notifications (Telegram, etc.)
type EventNotifier interface {
	NotifyNewBug(bugID, title, os, appVersion, priority string)
	NotifyNewCrash(crashID, errorMessage, severity, os, appVersion string)
}

// BugTriager is an optional AI auto-triage hook.
type BugTriager interface {
	AutoTriageBug(bugID uuid.UUID, title, description, steps, os, appVersion string) *BugTriageResult
}

// BugTriageResult holds AI triage output.
type BugTriageResult struct {
	Priority string
	Category string
	Summary  string
}

type BugService struct {
	bugRepo        *repository.BugRepository
	crashRepo      *repository.CrashRepository
	crashGroupRepo *repository.CrashGroupRepository
	notifier       EventNotifier // nil = no notifications
	triager        BugTriager    // nil = no auto-triage
}

func NewBugService(bugRepo *repository.BugRepository, crashRepo *repository.CrashRepository, crashGroupRepo *repository.CrashGroupRepository) *BugService {
	return &BugService{bugRepo: bugRepo, crashRepo: crashRepo, crashGroupRepo: crashGroupRepo}
}

// SetNotifier wires the event notifier (called after construction to avoid circular deps).
func (s *BugService) SetNotifier(n EventNotifier) { s.notifier = n }

// SetTriager wires the AI auto-triage agent.
func (s *BugService) SetTriager(t BugTriager) { s.triager = t }

// SubmitCrash creates a new crash report from a device, with automatic crash group assignment.
func (s *BugService) SubmitCrash(deviceID uuid.UUID, req dto.SubmitCrashRequest) (*dto.CrashResponse, error) {
	crash := &model.CrashReport{
		DeviceID:     deviceID,
		StackTrace:   req.StackTrace,
		ErrorMessage: req.ErrorMessage,
		AppVersion:   req.AppVersion,
		OS:           req.OS,
		OSVersion:    req.OSVersion,
		Severity:     req.Severity,
		Metadata:     req.Metadata,
	}

	// Crash group fingerprinting
	if s.crashGroupRepo != nil {
		fingerprint := ComputeFingerprint(req.ErrorMessage, req.StackTrace)
		legacyFingerprint := ComputeLegacyFingerprint(req.StackTrace)
		normalizedTitle := NormalizeCrashTitle(ExtractTitle(req.ErrorMessage, req.StackTrace))

		group, promoteFingerprint, err := s.findMatchingCrashGroup(fingerprint, legacyFingerprint, normalizedTitle, req.OS)
		switch {
		case err == nil:
			crash.CrashGroupID = &group.ID
			if promoteFingerprint {
				if updateErr := s.crashGroupRepo.UpdateFields(group.ID, map[string]interface{}{"fingerprint": fingerprint}); updateErr != nil {
					logger.Log.Warn().Err(updateErr).Str("group_id", group.ID.String()).Msg("Failed to promote crash group fingerprint")
				}
			}
			// Promote severity if new crash is more severe
			if severityRank(req.Severity) > severityRank(group.Severity) {
				s.crashGroupRepo.UpdateFields(group.ID, map[string]interface{}{"severity": req.Severity})
			}
		case errors.Is(err, gorm.ErrRecordNotFound):
			// Group doesn't exist — create it
			now := time.Now()
			title := ExtractTitle(req.ErrorMessage, req.StackTrace)
			severity := req.Severity
			if severity == "" {
				severity = "medium"
			}
			group = &model.CrashGroup{
				Fingerprint: fingerprint,
				Title:       title,
				Severity:    severity,
				FirstSeenAt: now,
				LastSeenAt:  now,
				CrashCount:  0,
				DeviceCount: 0,
				Versions:    req.AppVersion,
				Platforms:   req.OS,
			}
			if createErr := s.crashGroupRepo.Create(group); createErr != nil {
				logger.Log.Warn().Err(createErr).Msg("Failed to create crash group, continuing without grouping")
			} else {
				crash.CrashGroupID = &group.ID
			}
		default:
			logger.Log.Warn().Err(err).Msg("Failed to match crash group, continuing without grouping")
		}

		if err := s.crashRepo.Create(crash); err != nil {
			return nil, err
		}

		// Update group counts after crash is created
		if crash.CrashGroupID != nil {
			if incErr := s.crashGroupRepo.IncrementCounts(*crash.CrashGroupID, deviceID, req.AppVersion, req.OS); incErr != nil {
				logger.Log.Warn().Err(incErr).Msg("Failed to increment crash group counts")
			}
		}
	} else {
		if err := s.crashRepo.Create(crash); err != nil {
			return nil, err
		}
	}

	// Store diagnostic log if provided
	if req.DiagnosticLog != "" {
		s.saveDiagnosticLog("crash", crash.ID, req.DiagnosticLog)
	}

	logger.Log.Info().Str("crash_id", crash.ID.String()).Str("severity", crash.Severity).Msg("Crash report submitted")

	// S1.1: Telegram notification
	if s.notifier != nil {
		s.notifier.NotifyNewCrash(crash.ID.String(), crash.ErrorMessage, crash.Severity, crash.OS, crash.AppVersion)
	}

	resp := dto.CrashToResponse(crash)
	resp.HasDiagnostics = req.DiagnosticLog != ""
	return &resp, nil
}

func (s *BugService) findMatchingCrashGroup(primaryFingerprint, legacyFingerprint, normalizedTitle, os string) (*model.CrashGroup, bool, error) {
	candidates := uniqueNonEmptyStrings(primaryFingerprint, legacyFingerprint)
	if len(candidates) > 0 {
		group, err := s.crashGroupRepo.FindByFingerprints(candidates)
		if err == nil {
			return group, group.Fingerprint != primaryFingerprint && primaryFingerprint != "", nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, false, err
		}
	}

	if normalizedTitle == "" {
		return nil, false, gorm.ErrRecordNotFound
	}

	groups, err := s.crashGroupRepo.ListRecentActiveByPlatform(os, 100)
	if err != nil {
		return nil, false, err
	}
	for i := range groups {
		if NormalizeCrashTitle(groups[i].Title) == normalizedTitle {
			return &groups[i], groups[i].Fingerprint != primaryFingerprint && primaryFingerprint != "", nil
		}
	}

	return nil, false, gorm.ErrRecordNotFound
}

func uniqueNonEmptyStrings(values ...string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

// severityRank returns a numeric rank for severity comparison (higher = more severe).
func severityRank(severity string) int {
	switch strings.ToLower(severity) {
	case "critical":
		return 4
	case "high":
		return 3
	case "medium":
		return 2
	case "low":
		return 1
	default:
		return 2 // default medium
	}
}

// SubmitBug creates a new bug report from a device.
func (s *BugService) SubmitBug(deviceID uuid.UUID, req dto.SubmitBugRequest) (*dto.BugResponse, error) {
	bug := &model.BugReport{
		DeviceID:    deviceID,
		Title:       req.Title,
		Description: req.Description,
		Steps:       req.Steps,
		AppVersion:  req.AppVersion,
		OS:          req.OS,
		OSVersion:   req.OSVersion,
	}

	if err := s.bugRepo.Create(bug); err != nil {
		return nil, err
	}

	// Store diagnostic log if provided
	if req.DiagnosticLog != "" {
		s.saveDiagnosticLog("bug", bug.ID, req.DiagnosticLog)
	}

	logger.Log.Info().Str("bug_id", bug.ID.String()).Str("title", bug.Title).Msg("Bug report submitted")

	// S2.2: AI auto-triage (runs in background, updates bug priority/notes)
	// Copy values to avoid sharing the *model.BugReport pointer with the goroutine.
	if s.triager != nil {
		bugID := bug.ID
		title := bug.Title
		description := bug.Description
		steps := bug.Steps
		osName := bug.OS
		appVersion := bug.AppVersion
		go func() {
			result := s.triager.AutoTriageBug(bugID, title, description, steps, osName, appVersion)
			if result != nil {
				fields := map[string]interface{}{
					"priority": result.Priority,
				}
				if result.Summary != "" {
					fields["admin_notes"] = "[AI Triage] " + result.Summary
				}
				if err := s.bugRepo.UpdateFields(bugID, fields); err != nil {
					logger.Log.Warn().Err(err).Str("bug_id", bugID.String()).Msg("AI triage update failed")
				} else {
					logger.Log.Info().Str("bug_id", bugID.String()).Str("priority", result.Priority).Str("category", result.Category).Msg("AI auto-triage applied")
				}
			}
		}()
	}

	// S1.1: Telegram notification
	if s.notifier != nil {
		s.notifier.NotifyNewBug(bug.ID.String(), bug.Title, bug.OS, bug.AppVersion, bug.Priority)
	}

	resp := dto.BugToResponse(bug)
	resp.HasDiagnostics = req.DiagnosticLog != ""
	return &resp, nil
}

// GetBug returns a bug report by ID (admin use — no ownership check).
func (s *BugService) GetBug(id uuid.UUID) (*dto.BugResponse, error) {
	bug, err := s.bugRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrBugNotFound
		}
		return nil, err
	}
	resp := dto.BugToResponse(bug)
	resp.HasDiagnostics = s.bugRepo.HasDiagnosticLog("bug", id)
	return &resp, nil
}

// GetDeviceBug returns a bug report by ID, verifying it belongs to the requesting device.
func (s *BugService) GetDeviceBug(id, deviceID uuid.UUID) (*dto.BugResponse, error) {
	bug, err := s.bugRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrBugNotFound
		}
		return nil, err
	}
	if bug.DeviceID != deviceID {
		return nil, ErrBugAccessDenied
	}
	resp := dto.BugToResponse(bug)
	resp.HasDiagnostics = s.bugRepo.HasDiagnosticLog("bug", id)
	return &resp, nil
}

// GetCrash returns a crash report by ID.
func (s *BugService) GetCrash(id uuid.UUID) (*dto.CrashResponse, error) {
	crash, err := s.crashRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrCrashNotFound
		}
		return nil, err
	}
	resp := dto.CrashToResponse(crash)
	resp.HasDiagnostics = s.bugRepo.HasDiagnosticLog("crash", id)
	return &resp, nil
}

// GetDiagnosticLog retrieves the diagnostic log for a bug or crash report.
func (s *BugService) GetDiagnosticLog(reportType string, reportID uuid.UUID) (*dto.DiagnosticLogResponse, error) {
	log, err := s.bugRepo.FindDiagnosticLog(reportType, reportID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrLogNotFound
		}
		return nil, err
	}
	return &dto.DiagnosticLogResponse{
		ID:         log.ID.String(),
		ReportType: log.ReportType,
		ReportID:   log.ReportID.String(),
		Content:    log.Content,
		LineCount:  log.LineCount,
		SizeBytes:  log.SizeBytes,
		CreatedAt:  log.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}, nil
}

// saveDiagnosticLog stores a diagnostic log entry.
func (s *BugService) saveDiagnosticLog(reportType string, reportID uuid.UUID, content string) {
	lineCount := strings.Count(content, "\n") + 1
	log := &model.DiagnosticLog{
		ReportType: reportType,
		ReportID:   reportID,
		Content:    content,
		LineCount:  lineCount,
		SizeBytes:  len(content),
	}
	if err := s.bugRepo.CreateDiagnosticLog(log); err != nil {
		logger.Log.Error().Err(err).Str("report_type", reportType).Str("report_id", reportID.String()).Msg("Failed to save diagnostic log")
	}
}

// UpdateBug updates a bug report's status, priority, or admin notes.
func (s *BugService) UpdateBug(id uuid.UUID, req dto.UpdateBugRequest) (*dto.BugResponse, error) {
	bug, err := s.bugRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrBugNotFound
		}
		return nil, err
	}

	if req.Status != nil {
		bug.Status = *req.Status
		if *req.Status == "resolved" || *req.Status == "closed" {
			now := time.Now()
			bug.ResolvedAt = &now
		}
	}
	if req.Priority != nil {
		bug.Priority = *req.Priority
	}
	if req.AdminNotes != nil {
		bug.AdminNotes = *req.AdminNotes
	}

	if err := s.bugRepo.Update(bug); err != nil {
		return nil, err
	}

	resp := dto.BugToResponse(bug)
	return &resp, nil
}

// ListBugs returns paginated bug reports with filters.
func (s *BugService) ListBugs(page, perPage int, status, priority, os, appVersion, search, brand, deviceID string) ([]dto.BugResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	bugs, total, err := s.bugRepo.List(page, perPage, status, priority, os, appVersion, search, brand, deviceID)
	if err != nil {
		return nil, 0, err
	}

	return dto.BugsToResponse(bugs), total, nil
}

// ListCrashes returns paginated crash reports with filters.
func (s *BugService) ListCrashes(page, perPage int, severity, appVersion, os, brand, deviceID string) ([]dto.CrashResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	crashes, total, err := s.crashRepo.List(page, perPage, severity, appVersion, os, brand, deviceID)
	if err != nil {
		return nil, 0, err
	}

	return dto.CrashesToResponse(crashes), total, nil
}

// ListDeviceBugs returns bugs for a specific device.
func (s *BugService) ListDeviceBugs(deviceID uuid.UUID) ([]dto.BugResponse, error) {
	bugs, err := s.bugRepo.ListByDevice(deviceID)
	if err != nil {
		return nil, err
	}
	return dto.BugsToResponse(bugs), nil
}

// ==================== Crash Group Methods ====================

// ListCrashGroups returns paginated crash groups with filters.
func (s *BugService) ListCrashGroups(page, perPage int, status, severity, search, brand string) ([]dto.CrashGroupResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	groups, total, err := s.crashGroupRepo.List(page, perPage, status, severity, search, brand)
	if err != nil {
		return nil, 0, err
	}

	return dto.CrashGroupsToResponse(groups), total, nil
}

// GetCrashGroup returns a crash group by ID.
func (s *BugService) GetCrashGroup(id uuid.UUID) (*dto.CrashGroupResponse, error) {
	group, err := s.crashGroupRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrCrashGroupNotFound
		}
		return nil, err
	}
	resp := dto.CrashGroupToResponse(group)
	return &resp, nil
}

// UpdateCrashGroup updates a crash group's status, severity, admin_notes, or assigned_to.
func (s *BugService) UpdateCrashGroup(id uuid.UUID, req dto.UpdateCrashGroupRequest) (*dto.CrashGroupResponse, error) {
	group, err := s.crashGroupRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrCrashGroupNotFound
		}
		return nil, err
	}

	fields := make(map[string]interface{})
	if req.Status != nil {
		fields["status"] = *req.Status
		if *req.Status == "resolved" || *req.Status == "wont_fix" {
			now := time.Now()
			fields["resolved_at"] = &now
		}
	}
	if req.Severity != nil {
		fields["severity"] = *req.Severity
	}
	if req.AdminNotes != nil {
		fields["admin_notes"] = *req.AdminNotes
	}
	if req.AssignedTo != nil {
		fields["assigned_to"] = *req.AssignedTo
	}

	if len(fields) > 0 {
		if err := s.crashGroupRepo.UpdateFields(id, fields); err != nil {
			return nil, err
		}
		// Re-fetch to get updated values
		group, err = s.crashGroupRepo.FindByID(id)
		if err != nil {
			return nil, err
		}
	}

	resp := dto.CrashGroupToResponse(group)
	return &resp, nil
}

// MergeCrashGroups merges source crash groups into a target group.
func (s *BugService) MergeCrashGroups(targetID uuid.UUID, sourceIDs []uuid.UUID) error {
	target, sources, err := s.loadCrashGroupsForMerge(targetID, sourceIDs)
	if err != nil {
		return err
	}

	sourceIDs = sanitizeCrashGroupMergeSources(targetID, sourceIDs)
	if len(sourceIDs) == 0 {
		return nil
	}

	mergedFields := buildCrashGroupMergeUpdateFields(target, sources)
	return s.crashGroupRepo.Merge(targetID, sourceIDs, mergedFields)
}

// ListGroupCrashes returns individual crashes within a crash group.
func (s *BugService) ListGroupCrashes(groupID uuid.UUID, page, perPage int) ([]dto.CrashResponse, int64, error) {
	page, perPage = pagination.Normalize(page, perPage, 20)

	crashes, total, err := s.crashRepo.ListByGroupID(groupID, page, perPage)
	if err != nil {
		return nil, 0, err
	}

	return dto.CrashesToResponse(crashes), total, nil
}

// UpdateCrash updates admin notes on an individual crash report.
func (s *BugService) UpdateCrash(id uuid.UUID, req dto.UpdateCrashRequest) (*dto.CrashResponse, error) {
	crash, err := s.crashRepo.FindByID(id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrCrashNotFound
		}
		return nil, err
	}

	fields := make(map[string]interface{})
	if req.AdminNotes != nil {
		fields["admin_notes"] = *req.AdminNotes
	}

	if len(fields) > 0 {
		if err := s.crashRepo.UpdateFields(id, fields); err != nil {
			return nil, err
		}
		crash, err = s.crashRepo.FindByID(id)
		if err != nil {
			return nil, err
		}
	}

	resp := dto.CrashToResponse(crash)
	resp.HasDiagnostics = s.bugRepo.HasDiagnosticLog("crash", id)
	return &resp, nil
}

// GetCrashGroupStats returns aggregate crash group statistics, optionally filtered by brand.
func (s *BugService) GetCrashGroupStats(brand string) (*dto.CrashGroupStatsResponse, error) {
	totalGroups, err := s.crashGroupRepo.CountAll(brand)
	if err != nil {
		return nil, err
	}
	activeGroups, err := s.crashGroupRepo.CountActive(brand)
	if err != nil {
		return nil, err
	}
	byStatus, err := s.crashGroupRepo.CountByStatus(brand)
	if err != nil {
		return nil, err
	}
	bySeverity, err := s.crashGroupRepo.CountBySeverity(brand)
	if err != nil {
		return nil, err
	}

	return &dto.CrashGroupStatsResponse{
		TotalGroups:  totalGroups,
		ActiveGroups: activeGroups,
		ByStatus:     byStatus,
		BySeverity:   bySeverity,
	}, nil
}

// GetBugStats returns aggregate bug/crash stats, optionally filtered by brand.
func (s *BugService) GetBugStats(brand string) (*dto.BugStatsResponse, *dto.CrashStatsResponse, error) {
	totalBugs, err := s.bugRepo.CountAll(brand)
	if err != nil {
		return nil, nil, err
	}
	openToday, err := s.bugRepo.CountOpenToday(brand)
	if err != nil {
		return nil, nil, err
	}
	byStatus, err := s.bugRepo.CountByStatus(brand)
	if err != nil {
		return nil, nil, err
	}

	totalCrashes, err := s.crashRepo.CountAll(brand)
	if err != nil {
		return nil, nil, err
	}
	crashesToday, err := s.crashRepo.CountToday(brand)
	if err != nil {
		return nil, nil, err
	}
	bySeverity, err := s.crashRepo.CountBySeverity(brand)
	if err != nil {
		return nil, nil, err
	}

	bugStats := &dto.BugStatsResponse{
		TotalBugs: totalBugs,
		OpenToday: openToday,
		ByStatus:  byStatus,
	}
	crashStats := &dto.CrashStatsResponse{
		TotalCrashes: totalCrashes,
		CrashesToday: crashesToday,
		BySeverity:   bySeverity,
	}

	return bugStats, crashStats, nil
}
