package service

import (
	"strings"
	"testing"
	"time"

	"github.com/snakeloader/backend/internal/identity/dto"
	premiummodel "github.com/snakeloader/backend/internal/premium/model"
)

func TestActivePremiumLicensePredicate_DefaultAndAliased(t *testing.T) {
	base := premiummodel.ActivePremiumLicenseSQL("")
	aliased := premiummodel.ActivePremiumLicenseSQL("pl")

	for _, fragment := range []string{
		"tier = 'premium'",
		"cancelled_at IS NULL",
		"expires_at > ?",
		"billing_cycle IN ('lifetime','lifetime1','lifetime2','lifetime3')",
	} {
		if !strings.Contains(base, fragment) {
			t.Fatalf("base predicate missing fragment %q: %s", fragment, base)
		}
	}

	if strings.Contains(base, "pl.") {
		t.Fatalf("base predicate should not contain alias prefix: %s", base)
	}
	if !strings.Contains(aliased, "pl.tier = 'premium'") ||
		!strings.Contains(aliased, "pl.cancelled_at IS NULL") ||
		!strings.Contains(aliased, "pl.expires_at > ?") {
		t.Fatalf("aliased predicate missing pl. prefixes: %s", aliased)
	}
}

func TestBuildTierDistributionQuery_NoBrand_UsesExistsToAvoidDuplicateDevices(t *testing.T) {
	activeAt := time.Date(2026, 4, 22, 9, 0, 0, 0, time.UTC)

	query, args := buildTierDistributionQuery(activeAt, "")

	if placeholders := strings.Count(query, "?"); placeholders != len(args) {
		t.Fatalf("placeholder/arg mismatch: %d placeholders vs %d args\nSQL: %s\nargs: %v", placeholders, len(args), query, args)
	}
	if len(args) != 1 {
		t.Fatalf("expected only activeAt arg, got %d args: %v", len(args), args)
	}
	if got, ok := args[0].(time.Time); !ok || !got.Equal(activeAt) {
		t.Fatalf("expected args[0] to equal activeAt, got %#v", args[0])
	}

	if !strings.Contains(query, "CASE WHEN EXISTS") {
		t.Fatalf("expected EXISTS-based premium classification, got SQL: %s", query)
	}
	if strings.Contains(query, "LEFT JOIN premium_licenses") {
		t.Fatalf("query should not LEFT JOIN premium_licenses anymore: %s", query)
	}
	if strings.Contains(query, "WHERE d.brand = ?") {
		t.Fatalf("query should not include brand filter when brand is empty: %s", query)
	}
}

func TestBuildTierDistributionQuery_WithBrand_PreservesArgOrder(t *testing.T) {
	activeAt := time.Date(2026, 4, 22, 9, 0, 0, 0, time.UTC)

	query, args := buildTierDistributionQuery(activeAt, "vidcombo")

	if placeholders := strings.Count(query, "?"); placeholders != len(args) {
		t.Fatalf("placeholder/arg mismatch: %d placeholders vs %d args\nSQL: %s\nargs: %v", placeholders, len(args), query, args)
	}
	if len(args) != 2 {
		t.Fatalf("expected activeAt + brand args, got %d args: %v", len(args), args)
	}
	if got, ok := args[0].(time.Time); !ok || !got.Equal(activeAt) {
		t.Fatalf("expected args[0] to equal activeAt, got %#v", args[0])
	}
	if args[1] != "vidcombo" {
		t.Fatalf("expected args[1] to be brand, got %#v", args[1])
	}

	if !strings.Contains(query, "WHERE d.brand = ?") {
		t.Fatalf("expected brand filter in SQL, got: %s", query)
	}
	if strings.Index(query, "expires_at > ?") > strings.Index(query, "WHERE d.brand = ?") {
		t.Fatalf("expected activeAt placeholder to appear before brand placeholder: %s", query)
	}
}

func TestEnsureAndOrderBrandSummaries_SeedsKnownBrandsAndSortsExtras(t *testing.T) {
	brands := make(map[string]*dto.BrandSummary)
	ensureBrandSummary(brands, "VIDCOMBO").RevenueMonth = 2796
	ensureBrandSummary(brands, "beta").TotalDevices = 3
	ensureBrandSummary(brands, "ssvid").TotalDevices = 10

	ordered := orderedBrandSummaries(brands)
	if len(ordered) != 3 {
		t.Fatalf("expected 3 brands, got %d", len(ordered))
	}

	if ordered[0].Brand != "ssvid" {
		t.Fatalf("expected ssvid first, got %+v", ordered)
	}
	if ordered[1].Brand != "vidcombo" {
		t.Fatalf("expected vidcombo second, got %+v", ordered)
	}
	if ordered[2].Brand != "beta" {
		t.Fatalf("expected extra brand beta last, got %+v", ordered)
	}
	if ordered[1].RevenueMonth != 2796 {
		t.Fatalf("expected vidcombo revenue to survive normalization, got %+v", ordered[1])
	}
}
