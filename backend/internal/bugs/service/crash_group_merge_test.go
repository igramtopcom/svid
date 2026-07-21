package service

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/snakeloader/backend/internal/bugs/dto"
	"github.com/snakeloader/backend/internal/bugs/model"
)

func TestBuildCrashGroupMergeCandidates_ClustersByNormalizedTitleAndPlatform(t *testing.T) {
	now := time.Date(2026, 4, 22, 10, 0, 0, 0, time.UTC)

	windowsA := model.CrashGroup{
		ID:          uuid.New(),
		Title:       "Invalid argument(s): No host specified in URI C:/Users/Alice/AppData/Local/Temp/legacy_thumbnails/14.jpg",
		Status:      "new",
		Severity:    "high",
		CrashCount:  100,
		DeviceCount: 4,
		Platforms:   "windows",
		LastSeenAt:  now.Add(-1 * time.Hour),
		FirstSeenAt: now.Add(-72 * time.Hour),
	}
	windowsB := model.CrashGroup{
		ID:          uuid.New(),
		Title:       "Invalid argument(s): No host specified in URI C:/Users/Bob/AppData/Local/Temp/legacy_thumbnails/99.jpg",
		Status:      "fixing",
		Severity:    "critical",
		CrashCount:  40,
		DeviceCount: 2,
		Platforms:   "windows",
		LastSeenAt:  now.Add(-2 * time.Hour),
		FirstSeenAt: now.Add(-48 * time.Hour),
	}
	macos := model.CrashGroup{
		ID:          uuid.New(),
		Title:       "Invalid argument(s): No host specified in URI /Users/alice/Library/Caches/legacy_thumbnails/14.jpg",
		Status:      "new",
		Severity:    "high",
		CrashCount:  20,
		DeviceCount: 1,
		Platforms:   "macos",
		LastSeenAt:  now.Add(-3 * time.Hour),
		FirstSeenAt: now.Add(-24 * time.Hour),
	}
	other := model.CrashGroup{
		ID:          uuid.New(),
		Title:       "Assertion failed: [Player] has been disposed",
		Status:      "investigating",
		Severity:    "medium",
		CrashCount:  51,
		DeviceCount: 6,
		Platforms:   "windows",
		LastSeenAt:  now.Add(-30 * time.Minute),
		FirstSeenAt: now.Add(-24 * time.Hour),
	}

	candidates, err := buildCrashGroupMergeCandidates(
		[]model.CrashGroup{windowsA, windowsB, macos, other},
		func(groupIDs []uuid.UUID) (int64, int64, error) {
			var crashCount int64
			var deviceCount int64
			for _, id := range groupIDs {
				switch id {
				case windowsA.ID:
					crashCount += windowsA.CrashCount
					deviceCount += windowsA.DeviceCount
				case windowsB.ID:
					crashCount += windowsB.CrashCount
					deviceCount += windowsB.DeviceCount
				case macos.ID:
					crashCount += macos.CrashCount
					deviceCount += macos.DeviceCount
				case other.ID:
					crashCount += other.CrashCount
					deviceCount += other.DeviceCount
				}
			}
			return crashCount, deviceCount, nil
		},
	)
	if err != nil {
		t.Fatalf("buildCrashGroupMergeCandidates returned error: %v", err)
	}

	if len(candidates) != 1 {
		t.Fatalf("expected 1 candidate, got %d", len(candidates))
	}

	candidate := candidates[0]
	if candidate.PlatformKey != "windows" {
		t.Fatalf("expected windows candidate, got %q", candidate.PlatformKey)
	}
	if candidate.GroupCount != 2 {
		t.Fatalf("expected 2 grouped crash groups, got %d", candidate.GroupCount)
	}
	if candidate.TotalCrashCount != 140 {
		t.Fatalf("expected 140 crashes in aggregate, got %d", candidate.TotalCrashCount)
	}
	if candidate.TotalDeviceCount != 6 {
		t.Fatalf("expected 6 devices in aggregate, got %d", candidate.TotalDeviceCount)
	}
	if candidate.Target.ID != windowsB.ID.String() {
		t.Fatalf("expected fixing group %s to be preferred as target, got %s", windowsB.ID, candidate.Target.ID)
	}
	if len(candidate.Sources) != 1 || candidate.Sources[0].ID != windowsA.ID.String() {
		t.Fatalf("expected windowsA to remain the only source, got %+v", candidate.Sources)
	}
}

func TestBuildCrashGroupMergeUpdateFields_PreservesActionableStatusAndHighestSeverity(t *testing.T) {
	resolvedAt := time.Date(2026, 4, 20, 8, 0, 0, 0, time.UTC)
	target := model.CrashGroup{
		Title:      "Assertion failed: [Player] has been disposed",
		Status:     "resolved",
		Severity:   "low",
		ResolvedAt: &resolvedAt,
	}
	source := model.CrashGroup{
		Title:    "Assertion failed: [Player] has been disposed",
		Status:   "investigating",
		Severity: "critical",
	}

	fields := buildCrashGroupMergeUpdateFields(target, []model.CrashGroup{source})

	if got, ok := fields["status"].(string); !ok || got != "investigating" {
		t.Fatalf("expected investigating status, got %#v", fields["status"])
	}
	if got, ok := fields["severity"].(string); !ok || got != "critical" {
		t.Fatalf("expected critical severity, got %#v", fields["severity"])
	}
	if fields["resolved_at"] != nil {
		t.Fatalf("expected resolved_at to be cleared when an active source exists, got %#v", fields["resolved_at"])
	}
	if got, ok := fields["title"].(string); !ok || got != target.Title {
		t.Fatalf("expected target title to be preserved, got %#v", fields["title"])
	}
}

func TestSanitizeCrashGroupMergeSources_RemovesTargetDuplicateAndNil(t *testing.T) {
	targetID := uuid.New()
	sourceA := uuid.New()
	sourceB := uuid.New()

	got := sanitizeCrashGroupMergeSources(targetID, []uuid.UUID{uuid.Nil, targetID, sourceA, sourceA, sourceB})
	if len(got) != 2 {
		t.Fatalf("expected 2 source IDs after sanitization, got %d", len(got))
	}
	if got[0] != sourceA || got[1] != sourceB {
		t.Fatalf("unexpected sanitized source IDs: %+v", got)
	}
}

func TestExecuteCrashGroupMergeBackfillCandidates_DryRunAndGuardrails(t *testing.T) {
	targetA := uuid.New()
	sourceA := uuid.New()
	targetB := uuid.New()
	sourceB1 := uuid.New()
	sourceB2 := uuid.New()
	sourceB3 := uuid.New()
	targetC := uuid.New()
	sourceC := uuid.New()

	candidates := []dto.CrashGroupMergeCandidateResponse{
		{
			NormalizedTitle:  "legacy thumbnails",
			PlatformKey:      "windows",
			Target:           dto.CrashGroupResponse{ID: targetA.String()},
			Sources:          []dto.CrashGroupResponse{{ID: sourceA.String()}},
			GroupCount:       2,
			TotalCrashCount:  140,
			TotalDeviceCount: 6,
		},
		{
			NormalizedTitle:  "oversized cluster",
			PlatformKey:      "windows",
			Target:           dto.CrashGroupResponse{ID: targetB.String()},
			Sources:          []dto.CrashGroupResponse{{ID: sourceB1.String()}, {ID: sourceB2.String()}, {ID: sourceB3.String()}},
			GroupCount:       4,
			TotalCrashCount:  200,
			TotalDeviceCount: 8,
		},
		{
			NormalizedTitle:  "player disposed",
			PlatformKey:      "windows",
			Target:           dto.CrashGroupResponse{ID: targetC.String()},
			Sources:          []dto.CrashGroupResponse{{ID: sourceC.String()}},
			GroupCount:       2,
			TotalCrashCount:  51,
			TotalDeviceCount: 6,
		},
	}

	called := 0
	report := executeCrashGroupMergeBackfillCandidates(candidates, crashGroupMergeBackfillConfig{
		scanLimit:     50,
		maxCandidates: 1,
		maxGroupCount: 3,
		dryRun:        true,
	}, func(targetID uuid.UUID, sourceIDs []uuid.UUID) error {
		called++
		return nil
	})

	if called != 0 {
		t.Fatalf("expected no apply calls during dry-run, got %d", called)
	}
	if !report.DryRun {
		t.Fatal("expected dry-run report")
	}
	if report.CandidateCount != 3 || report.SelectedCount != 1 {
		t.Fatalf("unexpected candidate selection counts: %+v", report)
	}
	if report.OversizedCount != 1 {
		t.Fatalf("expected 1 oversized candidate, got %d", report.OversizedCount)
	}
	if report.DeferredCount != 1 {
		t.Fatalf("expected 1 deferred candidate, got %d", report.DeferredCount)
	}
	if len(report.Results) != 2 {
		t.Fatalf("expected 2 result rows (1 dry_run + 1 oversized), got %d", len(report.Results))
	}
	if report.Results[0].Status != "dry_run" {
		t.Fatalf("expected first result to be dry_run, got %q", report.Results[0].Status)
	}
	if report.Results[1].Status != "skipped_oversized" {
		t.Fatalf("expected second result to be skipped_oversized, got %q", report.Results[1].Status)
	}
}

func TestExecuteCrashGroupMergeBackfillCandidates_AppliesAndCapturesErrors(t *testing.T) {
	targetA := uuid.New()
	sourceA := uuid.New()
	targetB := uuid.New()
	sourceB := uuid.New()

	candidates := []dto.CrashGroupMergeCandidateResponse{
		{
			NormalizedTitle:  "legacy thumbnails",
			PlatformKey:      "windows",
			Target:           dto.CrashGroupResponse{ID: targetA.String()},
			Sources:          []dto.CrashGroupResponse{{ID: sourceA.String()}},
			GroupCount:       2,
			TotalCrashCount:  140,
			TotalDeviceCount: 6,
		},
		{
			NormalizedTitle:  "player disposed",
			PlatformKey:      "windows",
			Target:           dto.CrashGroupResponse{ID: targetB.String()},
			Sources:          []dto.CrashGroupResponse{{ID: sourceB.String()}},
			GroupCount:       2,
			TotalCrashCount:  51,
			TotalDeviceCount: 6,
		},
	}

	var applied []string
	report := executeCrashGroupMergeBackfillCandidates(candidates, crashGroupMergeBackfillConfig{
		scanLimit:     50,
		maxCandidates: 10,
		maxGroupCount: 3,
		dryRun:        false,
	}, func(targetID uuid.UUID, sourceIDs []uuid.UUID) error {
		applied = append(applied, targetID.String())
		if targetID == targetB {
			return errors.New("merge failed")
		}
		return nil
	})

	if report.DryRun {
		t.Fatal("expected apply mode report")
	}
	if report.AppliedCount != 1 {
		t.Fatalf("expected 1 applied merge, got %d", report.AppliedCount)
	}
	if report.ErrorCount != 1 {
		t.Fatalf("expected 1 error, got %d", report.ErrorCount)
	}
	if len(applied) != 2 {
		t.Fatalf("expected apply callback for both selected candidates, got %d", len(applied))
	}
	if report.Results[0].Status != "applied" {
		t.Fatalf("expected first result to be applied, got %q", report.Results[0].Status)
	}
	if report.Results[1].Status != "error" || report.Results[1].Error == "" {
		t.Fatalf("expected second result to capture error, got %+v", report.Results[1])
	}
}
