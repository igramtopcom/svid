package service

import (
	"strings"
	"testing"
)

// TestBuildActivityFeedQuery_NoBrand verifies the UNION ALL query without brand filter.
// Expected: 7 sub-queries, no brand args, final arg = limit.
func TestBuildActivityFeedQuery_NoBrand(t *testing.T) {
	sql, args := buildActivityFeedQuery(50, "")

	// #1 regression guard: placeholder count must match arg count.
	placeholders := strings.Count(sql, "?")
	if placeholders != len(args) {
		t.Fatalf("placeholder/arg mismatch: %d placeholders vs %d args\nSQL: %s\nargs: %v",
			placeholders, len(args), sql, args)
	}

	// Without brand, only the LIMIT placeholder should exist.
	if len(args) != 1 {
		t.Errorf("expected 1 arg (limit), got %d: %v", len(args), args)
	}
	if args[len(args)-1] != 50 {
		t.Errorf("expected last arg to be limit=50, got %v", args[len(args)-1])
	}

	// All 7 sub-queries must appear.
	requiredTypes := []string{
		"'device_registered'",
		"'transaction'",
		"'bug_report'",
		"'ticket'",
		"'crash'",
		"'rating'",
		"'license'",
	}
	for _, typ := range requiredTypes {
		if !strings.Contains(sql, typ) {
			t.Errorf("SQL missing sub-query for type %s", typ)
		}
	}

	// UNION ALL must appear 6 times (7 sub-queries).
	unionCount := strings.Count(sql, "UNION ALL")
	if unionCount != 6 {
		t.Errorf("expected 6 UNION ALL, got %d", unionCount)
	}

	// Outer ranking order + limit on the aggregated feed.
	if !strings.Contains(sql, "ROW_NUMBER() OVER (PARTITION BY type ORDER BY timestamp DESC)") {
		t.Error("SQL missing per-type row_number ranking")
	}
	if !strings.Contains(sql, "ORDER BY type_rank ASC, timestamp DESC") {
		t.Error("SQL missing interleaved type_rank ordering")
	}
	if !strings.Contains(sql, "LIMIT ?") {
		t.Error("SQL missing outer LIMIT ?")
	}

	// Brand-specific fragments must NOT appear when brand is empty.
	if strings.Contains(sql, "JOIN devices d ON d.id = src.device_id AND d.brand") {
		t.Error("SQL should not contain brand JOIN when brand is empty")
	}
}

// TestBuildActivityFeedQuery_WithBrand verifies brand filter injects the correct
// number of ? placeholders (7 brand args, one per sub-query) + LIMIT.
func TestBuildActivityFeedQuery_WithBrand(t *testing.T) {
	sql, args := buildActivityFeedQuery(30, "ssvid")

	// #1 regression guard.
	placeholders := strings.Count(sql, "?")
	if placeholders != len(args) {
		t.Fatalf("placeholder/arg mismatch: %d placeholders vs %d args\nSQL: %s\nargs: %v",
			placeholders, len(args), sql, args)
	}

	// Expected: 7 brand args (one per sub-query) + 1 LIMIT = 8 total.
	const expectedArgCount = 8
	if len(args) != expectedArgCount {
		t.Errorf("expected %d args (7 brand + 1 limit), got %d: %v",
			expectedArgCount, len(args), args)
	}

	// First 7 args must all be the brand string.
	for i := 0; i < 7; i++ {
		if args[i] != "ssvid" {
			t.Errorf("args[%d] expected 'ssvid', got %v", i, args[i])
		}
	}

	// Last arg must be the limit.
	if args[len(args)-1] != 30 {
		t.Errorf("expected last arg to be limit=30, got %v", args[len(args)-1])
	}

	// Brand JOIN must appear (used by bug_reports, tickets, crash_reports, app_ratings).
	if !strings.Contains(sql, "JOIN devices d ON d.id = src.device_id AND d.brand = ?") {
		t.Error("SQL should contain brand JOIN fragment when brand is set")
	}

	// Direct brand filter must appear (used by devices, transactions, licenses).
	if !strings.Contains(sql, "src.brand = ?") {
		t.Error("SQL should contain direct src.brand = ? filter when brand is set")
	}
}

// TestBuildActivityFeedQuery_LimitClamping verifies out-of-range limits are clamped.
func TestBuildActivityFeedQuery_LimitClamping(t *testing.T) {
	tests := []struct {
		name     string
		input    int
		expected int
	}{
		{"zero → 50", 0, 50},
		{"negative → 50", -5, 50},
		{"above max → 50", 500, 50},
		{"valid 10", 10, 10},
		{"valid 200 (boundary)", 200, 200},
		{"201 → 50", 201, 50},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, args := buildActivityFeedQuery(tt.input, "")
			if len(args) == 0 {
				t.Fatal("expected at least the limit arg")
			}
			got := args[len(args)-1]
			if got != tt.expected {
				t.Errorf("buildActivityFeedQuery(%d, \"\") limit arg = %v, want %d",
					tt.input, got, tt.expected)
			}
		})
	}
}

// TestBuildActivityFeedQuery_LimitPositionIsLast verifies LIMIT arg is always last.
// This is critical because gorm binds ? positionally and a misordered arg
// would mean LIMIT gets a brand string (runtime error) and vice versa.
func TestBuildActivityFeedQuery_LimitPositionIsLast(t *testing.T) {
	// Without brand
	_, args := buildActivityFeedQuery(25, "")
	if _, ok := args[len(args)-1].(int); !ok {
		t.Errorf("last arg should be int (limit), got %T", args[len(args)-1])
	}

	// With brand
	_, args = buildActivityFeedQuery(25, "vidcombo")
	if _, ok := args[len(args)-1].(int); !ok {
		t.Errorf("last arg should be int (limit), got %T", args[len(args)-1])
	}
}
