package service

import (
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/dto"
	"github.com/snakeloader/backend/internal/bugs/model"
	"gorm.io/gorm"
)

type crashGroupMergeCluster struct {
	normalizedTitle string
	platformTokens  []string
	groups          []model.CrashGroup
}

type crashGroupMergeBackfillConfig struct {
	scanLimit       int
	includeResolved bool
	maxCandidates   int
	maxGroupCount   int
	dryRun          bool
}

const (
	defaultCrashGroupMergeScanLimit     = 200
	defaultCrashGroupMergeMaxCandidates = 20
	defaultCrashGroupMergeMaxGroupCount = 4
)

func normalizeCrashGroupMergeBackfillConfig(req dto.BackfillCrashGroupMergesRequest) crashGroupMergeBackfillConfig {
	cfg := crashGroupMergeBackfillConfig{
		scanLimit:       defaultCrashGroupMergeScanLimit,
		maxCandidates:   defaultCrashGroupMergeMaxCandidates,
		maxGroupCount:   defaultCrashGroupMergeMaxGroupCount,
		includeResolved: req.IncludeResolved,
		dryRun:          true,
	}
	if req.ScanLimit > 0 {
		cfg.scanLimit = req.ScanLimit
	}
	if cfg.scanLimit > 500 {
		cfg.scanLimit = 500
	}
	if req.MaxCandidates > 0 {
		cfg.maxCandidates = req.MaxCandidates
	}
	if cfg.maxCandidates > 100 {
		cfg.maxCandidates = 100
	}
	if req.MaxGroupCount > 0 {
		cfg.maxGroupCount = req.MaxGroupCount
	}
	if cfg.maxGroupCount > 10 {
		cfg.maxGroupCount = 10
	}
	if req.DryRun != nil {
		cfg.dryRun = *req.DryRun
	}
	return cfg
}

// ListCrashGroupMergeCandidates returns likely duplicate crash-group clusters
// so admin/orchestrators can backfill historical merges without inspecting raw
// crash rows manually.
func (s *BugService) ListCrashGroupMergeCandidates(limit int, includeResolved bool) ([]dto.CrashGroupMergeCandidateResponse, error) {
	groups, err := s.crashGroupRepo.ListForMergeReview(limit, includeResolved)
	if err != nil {
		return nil, err
	}

	return buildCrashGroupMergeCandidates(groups, func(groupIDs []uuid.UUID) (int64, int64, error) {
		return s.crashGroupRepo.AggregateForGroupIDs(groupIDs)
	})
}

// BackfillCrashGroupMerges scans for historical duplicate crash-group clusters
// and optionally applies bounded batch merges. Dry-run is the default mode.
func (s *BugService) BackfillCrashGroupMerges(req dto.BackfillCrashGroupMergesRequest) (*dto.CrashGroupBackfillMergeReportResponse, error) {
	cfg := normalizeCrashGroupMergeBackfillConfig(req)
	candidates, err := s.ListCrashGroupMergeCandidates(cfg.scanLimit, cfg.includeResolved)
	if err != nil {
		return nil, err
	}

	report := executeCrashGroupMergeBackfillCandidates(candidates, cfg, func(targetID uuid.UUID, sourceIDs []uuid.UUID) error {
		return s.MergeCrashGroups(targetID, sourceIDs)
	})
	return &report, nil
}

func buildCrashGroupMergeCandidates(
	groups []model.CrashGroup,
	aggregateFor func(groupIDs []uuid.UUID) (int64, int64, error),
) ([]dto.CrashGroupMergeCandidateResponse, error) {
	clusters := clusterCrashGroupsForMerge(groups)
	candidates := make([]dto.CrashGroupMergeCandidateResponse, 0, len(clusters))

	for _, cluster := range clusters {
		if len(cluster.groups) < 2 {
			continue
		}

		sort.Slice(cluster.groups, func(i, j int) bool {
			return preferCrashGroupMergeTarget(cluster.groups[i], cluster.groups[j])
		})

		target := cluster.groups[0]
		sources := append([]model.CrashGroup(nil), cluster.groups[1:]...)
		groupIDs := make([]uuid.UUID, 0, len(cluster.groups))
		for _, group := range cluster.groups {
			groupIDs = append(groupIDs, group.ID)
		}

		totalCrashCount, totalDeviceCount := aggregateCountsFromGroups(cluster.groups)
		if aggregateFor != nil {
			crashCount, deviceCount, err := aggregateFor(groupIDs)
			if err != nil {
				return nil, err
			}
			totalCrashCount = crashCount
			totalDeviceCount = deviceCount
		}

		candidates = append(candidates, dto.CrashGroupMergeCandidateResponse{
			NormalizedTitle:  cluster.normalizedTitle,
			PlatformKey:      joinPlatformTokens(cluster.platformTokens),
			Target:           dto.CrashGroupToResponse(&target),
			Sources:          dto.CrashGroupsToResponse(sources),
			GroupCount:       len(cluster.groups),
			TotalCrashCount:  totalCrashCount,
			TotalDeviceCount: totalDeviceCount,
			Reason:           "same normalized title and overlapping platform footprint",
		})
	}

	sort.Slice(candidates, func(i, j int) bool {
		if candidates[i].TotalCrashCount != candidates[j].TotalCrashCount {
			return candidates[i].TotalCrashCount > candidates[j].TotalCrashCount
		}
		if candidates[i].GroupCount != candidates[j].GroupCount {
			return candidates[i].GroupCount > candidates[j].GroupCount
		}
		return candidates[i].Target.LastSeenAt > candidates[j].Target.LastSeenAt
	})

	return candidates, nil
}

func executeCrashGroupMergeBackfillCandidates(
	candidates []dto.CrashGroupMergeCandidateResponse,
	cfg crashGroupMergeBackfillConfig,
	apply func(targetID uuid.UUID, sourceIDs []uuid.UUID) error,
) dto.CrashGroupBackfillMergeReportResponse {
	report := dto.CrashGroupBackfillMergeReportResponse{
		DryRun:         cfg.dryRun,
		ScanLimit:      cfg.scanLimit,
		CandidateCount: len(candidates),
		Results:        make([]dto.CrashGroupBackfillMergeResultResponse, 0),
	}

	for _, candidate := range candidates {
		if cfg.maxGroupCount > 0 && candidate.GroupCount > cfg.maxGroupCount {
			report.OversizedCount++
			report.Results = append(report.Results, dto.CrashGroupBackfillMergeResultResponse{
				Status:           "skipped_oversized",
				NormalizedTitle:  candidate.NormalizedTitle,
				PlatformKey:      candidate.PlatformKey,
				TargetID:         candidate.Target.ID,
				SourceIDs:        crashGroupSourceIDs(candidate),
				GroupCount:       candidate.GroupCount,
				TotalCrashCount:  candidate.TotalCrashCount,
				TotalDeviceCount: candidate.TotalDeviceCount,
				Reason:           fmt.Sprintf("group_count=%d exceeds max_group_count=%d", candidate.GroupCount, cfg.maxGroupCount),
			})
			continue
		}

		if cfg.maxCandidates > 0 && report.SelectedCount >= cfg.maxCandidates {
			report.DeferredCount++
			continue
		}

		report.SelectedCount++
		result := dto.CrashGroupBackfillMergeResultResponse{
			NormalizedTitle:  candidate.NormalizedTitle,
			PlatformKey:      candidate.PlatformKey,
			TargetID:         candidate.Target.ID,
			SourceIDs:        crashGroupSourceIDs(candidate),
			GroupCount:       candidate.GroupCount,
			TotalCrashCount:  candidate.TotalCrashCount,
			TotalDeviceCount: candidate.TotalDeviceCount,
		}

		if cfg.dryRun {
			result.Status = "dry_run"
			result.Reason = "candidate selected for dry-run only"
			report.Results = append(report.Results, result)
			continue
		}

		targetID, sourceIDs, err := crashGroupCandidateIDs(candidate)
		if err != nil {
			report.ErrorCount++
			result.Status = "error"
			result.Error = err.Error()
			report.Results = append(report.Results, result)
			continue
		}

		if err := apply(targetID, sourceIDs); err != nil {
			report.ErrorCount++
			result.Status = "error"
			result.Error = err.Error()
			report.Results = append(report.Results, result)
			continue
		}

		report.AppliedCount++
		result.Status = "applied"
		report.Results = append(report.Results, result)
	}

	return report
}

func clusterCrashGroupsForMerge(groups []model.CrashGroup) []crashGroupMergeCluster {
	titleBuckets := make(map[string][]model.CrashGroup)
	for _, group := range groups {
		normalizedTitle := NormalizeCrashTitle(group.Title)
		if normalizedTitle == "" {
			continue
		}
		titleBuckets[normalizedTitle] = append(titleBuckets[normalizedTitle], group)
	}

	clusters := make([]crashGroupMergeCluster, 0)
	for normalizedTitle, bucket := range titleBuckets {
		sort.Slice(bucket, func(i, j int) bool {
			return bucket[i].LastSeenAt.After(bucket[j].LastSeenAt)
		})

		titleClusters := make([]crashGroupMergeCluster, 0, len(bucket))
		for _, group := range bucket {
			platformTokens := normalizePlatformTokens(group.Platforms)
			assigned := false

			for i := range titleClusters {
				if platformTokensOverlap(titleClusters[i].platformTokens, platformTokens) {
					titleClusters[i].groups = append(titleClusters[i].groups, group)
					titleClusters[i].platformTokens = mergePlatformTokens(titleClusters[i].platformTokens, platformTokens)
					assigned = true
					break
				}
			}

			if assigned {
				continue
			}

			titleClusters = append(titleClusters, crashGroupMergeCluster{
				normalizedTitle: normalizedTitle,
				platformTokens:  platformTokens,
				groups:          []model.CrashGroup{group},
			})
		}

		clusters = append(clusters, titleClusters...)
	}

	return clusters
}

func preferCrashGroupMergeTarget(a, b model.CrashGroup) bool {
	if statusRank(a.Status) != statusRank(b.Status) {
		return statusRank(a.Status) > statusRank(b.Status)
	}
	if a.CrashCount != b.CrashCount {
		return a.CrashCount > b.CrashCount
	}
	if !a.LastSeenAt.Equal(b.LastSeenAt) {
		return a.LastSeenAt.After(b.LastSeenAt)
	}
	if severityRank(a.Severity) != severityRank(b.Severity) {
		return severityRank(a.Severity) > severityRank(b.Severity)
	}
	if !a.FirstSeenAt.Equal(b.FirstSeenAt) {
		return a.FirstSeenAt.Before(b.FirstSeenAt)
	}
	return a.ID.String() < b.ID.String()
}

func buildCrashGroupMergeUpdateFields(target model.CrashGroup, sources []model.CrashGroup) map[string]interface{} {
	all := append([]model.CrashGroup{target}, sources...)

	status, resolvedAt := mergedCrashGroupStatus(target, sources)
	title := strings.TrimSpace(target.Title)
	if title == "" {
		title = selectCrashGroupMergeTitle(all)
	}

	fields := map[string]interface{}{
		"title":    title,
		"severity": mergedCrashGroupSeverity(all),
		"status":   status,
	}
	if resolvedAt != nil {
		fields["resolved_at"] = *resolvedAt
	} else {
		fields["resolved_at"] = nil
	}
	return fields
}

func mergedCrashGroupSeverity(groups []model.CrashGroup) string {
	bestSeverity := "medium"
	bestRank := severityRank(bestSeverity)
	for _, group := range groups {
		rank := severityRank(group.Severity)
		if rank > bestRank {
			bestSeverity = group.Severity
			bestRank = rank
		}
	}
	return bestSeverity
}

func mergedCrashGroupStatus(target model.CrashGroup, sources []model.CrashGroup) (string, *time.Time) {
	if isCrashGroupActiveStatus(target.Status) {
		return target.Status, nil
	}

	for _, source := range sources {
		if isCrashGroupActiveStatus(source.Status) {
			return source.Status, nil
		}
	}

	status := strings.TrimSpace(target.Status)
	if status != "" {
		return status, target.ResolvedAt
	}

	for _, source := range sources {
		status = strings.TrimSpace(source.Status)
		if status != "" {
			return status, source.ResolvedAt
		}
	}

	return "new", nil
}

func selectCrashGroupMergeTitle(groups []model.CrashGroup) string {
	best := "Unknown crash"
	for _, group := range groups {
		title := strings.TrimSpace(group.Title)
		if title == "" {
			continue
		}
		if best == "Unknown crash" || len(title) > len(best) {
			best = title
		}
	}
	return best
}

func normalizePlatformTokens(platforms string) []string {
	if strings.TrimSpace(platforms) == "" {
		return nil
	}

	seen := make(map[string]struct{})
	tokens := make([]string, 0)
	for _, token := range strings.Split(platforms, ",") {
		normalized := strings.ToLower(strings.TrimSpace(token))
		if normalized == "" {
			continue
		}
		if _, ok := seen[normalized]; ok {
			continue
		}
		seen[normalized] = struct{}{}
		tokens = append(tokens, normalized)
	}
	sort.Strings(tokens)
	return tokens
}

func mergePlatformTokens(left, right []string) []string {
	if len(left) == 0 {
		return append([]string(nil), right...)
	}
	if len(right) == 0 {
		return append([]string(nil), left...)
	}

	seen := make(map[string]struct{}, len(left)+len(right))
	merged := make([]string, 0, len(left)+len(right))
	for _, token := range append(append([]string(nil), left...), right...) {
		if _, ok := seen[token]; ok {
			continue
		}
		seen[token] = struct{}{}
		merged = append(merged, token)
	}
	sort.Strings(merged)
	return merged
}

func platformTokensOverlap(left, right []string) bool {
	if len(left) == 0 || len(right) == 0 {
		return len(left) == 0 && len(right) == 0
	}

	seen := make(map[string]struct{}, len(left))
	for _, token := range left {
		seen[token] = struct{}{}
	}
	for _, token := range right {
		if _, ok := seen[token]; ok {
			return true
		}
	}
	return false
}

func joinPlatformTokens(tokens []string) string {
	if len(tokens) == 0 {
		return "unknown"
	}
	return strings.Join(tokens, ",")
}

func aggregateCountsFromGroups(groups []model.CrashGroup) (int64, int64) {
	var crashCount int64
	var deviceCount int64
	for _, group := range groups {
		crashCount += group.CrashCount
		deviceCount += group.DeviceCount
	}
	return crashCount, deviceCount
}

func crashGroupSourceIDs(candidate dto.CrashGroupMergeCandidateResponse) []string {
	ids := make([]string, 0, len(candidate.Sources))
	for _, source := range candidate.Sources {
		ids = append(ids, source.ID)
	}
	return ids
}

func crashGroupCandidateIDs(candidate dto.CrashGroupMergeCandidateResponse) (uuid.UUID, []uuid.UUID, error) {
	targetID, err := uuid.Parse(candidate.Target.ID)
	if err != nil {
		return uuid.Nil, nil, fmt.Errorf("parse target id: %w", err)
	}

	sourceIDs := make([]uuid.UUID, 0, len(candidate.Sources))
	for _, source := range candidate.Sources {
		sourceID, err := uuid.Parse(source.ID)
		if err != nil {
			return uuid.Nil, nil, fmt.Errorf("parse source id %q: %w", source.ID, err)
		}
		sourceIDs = append(sourceIDs, sourceID)
	}

	return targetID, sourceIDs, nil
}

func statusRank(status string) int {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "fixing":
		return 5
	case "investigating":
		return 4
	case "new":
		return 3
	case "resolved":
		return 2
	case "wont_fix":
		return 1
	default:
		return 0
	}
}

func isCrashGroupActiveStatus(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "new", "investigating", "fixing":
		return true
	default:
		return false
	}
}

func sanitizeCrashGroupMergeSources(targetID uuid.UUID, sourceIDs []uuid.UUID) []uuid.UUID {
	seen := make(map[uuid.UUID]struct{}, len(sourceIDs))
	result := make([]uuid.UUID, 0, len(sourceIDs))
	for _, sourceID := range sourceIDs {
		if sourceID == uuid.Nil || sourceID == targetID {
			continue
		}
		if _, ok := seen[sourceID]; ok {
			continue
		}
		seen[sourceID] = struct{}{}
		result = append(result, sourceID)
	}
	return result
}

func (s *BugService) loadCrashGroupsForMerge(targetID uuid.UUID, sourceIDs []uuid.UUID) (model.CrashGroup, []model.CrashGroup, error) {
	target, err := s.crashGroupRepo.FindByID(targetID)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return model.CrashGroup{}, nil, ErrCrashGroupNotFound
		}
		return model.CrashGroup{}, nil, err
	}

	sourceIDs = sanitizeCrashGroupMergeSources(targetID, sourceIDs)
	if len(sourceIDs) == 0 {
		return *target, nil, nil
	}

	sources, err := s.crashGroupRepo.FindByIDs(sourceIDs)
	if err != nil {
		return model.CrashGroup{}, nil, err
	}
	if len(sources) != len(sourceIDs) {
		return model.CrashGroup{}, nil, ErrCrashGroupNotFound
	}

	return *target, sources, nil
}
