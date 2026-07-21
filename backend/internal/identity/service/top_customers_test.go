package service

import (
	"strings"
	"testing"
)

// TestBuildTopCustomersQuery_NoBrand verifies the base query without brand filter.
func TestBuildTopCustomersQuery_NoBrand(t *testing.T) {
	sql, args := buildTopCustomersQuery(10, "")

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
	if args[0] != 10 {
		t.Errorf("expected limit arg = 10, got %v", args[0])
	}

	// Required SQL elements.
	requiredSubstrings := []string{
		"FROM premium_licenses pl",
		"LEFT JOIN payment_transactions pt",
		"ON pt.license_id = pl.id AND pt.status = 'completed'",
		"pl.contact_email IS NOT NULL",
		"GROUP BY pl.contact_email",
		// Regression guard: without HAVING, $0 admin-created free licenses
		// would pollute the leaderboard. See top_customers.go comments.
		"HAVING COALESCE(SUM(pt.amount_cents), 0) > 0",
		"ORDER BY total_spent_cents DESC",
		"LIMIT ?",
	}
	for _, s := range requiredSubstrings {
		if !strings.Contains(sql, s) {
			t.Errorf("SQL missing required fragment: %q", s)
		}
	}

	// Brand filter must NOT appear.
	if strings.Contains(sql, "pl.brand = ?") {
		t.Error("SQL should not contain brand filter when brand is empty")
	}
}

// TestBuildTopCustomersQuery_WithBrand verifies brand filter injection.
func TestBuildTopCustomersQuery_WithBrand(t *testing.T) {
	sql, args := buildTopCustomersQuery(25, "vidcombo")

	// #1 regression guard.
	placeholders := strings.Count(sql, "?")
	if placeholders != len(args) {
		t.Fatalf("placeholder/arg mismatch: %d placeholders vs %d args\nSQL: %s\nargs: %v",
			placeholders, len(args), sql, args)
	}

	// Expected: brand + limit = 2 args.
	if len(args) != 2 {
		t.Errorf("expected 2 args (brand + limit), got %d: %v", len(args), args)
	}
	if args[0] != "vidcombo" {
		t.Errorf("args[0] expected 'vidcombo', got %v", args[0])
	}
	if args[1] != 25 {
		t.Errorf("args[1] expected limit=25, got %v", args[1])
	}

	// Brand filter fragment.
	if !strings.Contains(sql, "AND pl.brand = ?") {
		t.Error("SQL should contain brand filter when brand is set")
	}

	// HAVING clause must still be present (not clobbered by brand injection).
	if !strings.Contains(sql, "HAVING COALESCE(SUM(pt.amount_cents), 0) > 0") {
		t.Error("HAVING clause missing — $0 licenses would pollute leaderboard")
	}
}

// TestBuildTopCustomersQuery_LimitClamping verifies out-of-range limits are clamped.
func TestBuildTopCustomersQuery_LimitClamping(t *testing.T) {
	tests := []struct {
		name     string
		input    int
		expected int
	}{
		{"zero → 10", 0, 10},
		{"negative → 10", -1, 10},
		{"above max → 10", 500, 10},
		{"valid 5", 5, 5},
		{"valid 100 (boundary)", 100, 100},
		{"101 → 10", 101, 10},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, args := buildTopCustomersQuery(tt.input, "")
			if len(args) == 0 {
				t.Fatal("expected at least the limit arg")
			}
			got := args[len(args)-1]
			if got != tt.expected {
				t.Errorf("buildTopCustomersQuery(%d, \"\") limit arg = %v, want %d",
					tt.input, got, tt.expected)
			}
		})
	}
}

// TestBuildTopCustomersQuery_ArgOrder verifies that args are in the same order
// as the ? placeholders appear in the SQL string (gorm binds positionally).
func TestBuildTopCustomersQuery_ArgOrder(t *testing.T) {
	sql, args := buildTopCustomersQuery(50, "svid")

	// Find position of brand filter ? and LIMIT ?.
	brandPos := strings.Index(sql, "AND pl.brand = ?")
	limitPos := strings.Index(sql, "LIMIT ?")

	if brandPos == -1 {
		t.Fatal("brand placeholder not found")
	}
	if limitPos == -1 {
		t.Fatal("LIMIT placeholder not found")
	}
	if brandPos >= limitPos {
		t.Errorf("brand placeholder should come before LIMIT: brand@%d limit@%d",
			brandPos, limitPos)
	}

	// Args must be in the same order.
	if _, ok := args[0].(string); !ok {
		t.Errorf("args[0] should be brand string, got %T", args[0])
	}
	if _, ok := args[1].(int); !ok {
		t.Errorf("args[1] should be limit int, got %T", args[1])
	}
}
