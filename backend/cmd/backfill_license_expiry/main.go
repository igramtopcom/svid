// backfill_license_expiry is a one-shot maintenance tool that repairs license
// `expires_at` values inflated by the subscription_create double-extension bug
// fixed in commit ae0867f1.
//
// Background: before the fix, handleInvoicePaid extended every license by one
// billing cycle on receipt of `invoice.paid`, including the very first invoice
// of a new subscription (`billing_reason="subscription_create"`). Stripe always
// fires that event immediately after checkout.session.completed, on top of the
// initial period already granted by FindOrCreateLicenseForSession. Net effect:
// every Stripe-created license received an extra cycle (yearly → 2y,
// semiannual → 12mo, monthly → 2mo).
//
// Renewals (subscription_cycle) were applied correctly. So for licenses that
// have already renewed N times, DB expires_at = stripe.current_period_end + 1
// cycle — independent of N. Reconciling against Stripe's current_period_end
// gives us the canonical truth for both never-renewed AND renewed licenses in
// one shot.
//
// Strategy
//  1. Load every license with stripe_subscription_id set (crypto licenses
//     use a different code path and are unaffected).
//  2. For each, fetch the Stripe subscription. Use `current_period_end` as
//     ground truth for expires_at.
//  3. Compare to DB expires_at:
//     - DB > stripe + tolerance (>1 day later) → FIX, new = stripe period end
//     - DB <= stripe                            → KEEP (already correct or
//       admin-extended)
//     - Stripe 404 / missing                    → MISSING (manual review)
//     - status incomplete / canceled with 0 period_end → SKIP
//  4. Dry-run by default. With --confirm, write JSONL backup, then UPDATE
//     all FIX rows inside a single transaction.
//
// Safety
//   - Default mode does NOT touch the DB.
//   - On --confirm, JSONL backup is written FIRST. If the backup fails the
//     UPDATE never runs.
//   - Stripe API errors → status=ERROR → no fix.
//   - Subscriptions whose Stripe object is missing (404) are NOT fixed —
//     they require manual review.
//   - Rate limit: 100ms between Stripe requests (~10 req/s).
//
// Usage
//   go run ./cmd/backfill_license_expiry            # dry-run, writes report
//   go run ./cmd/backfill_license_expiry --confirm  # apply fixes
//   go run ./cmd/backfill_license_expiry --out /tmp/x  # custom prefix
package main

import (
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/database"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/stripe/stripe-go/v81"
	stripesub "github.com/stripe/stripe-go/v81/subscription"
	"gorm.io/gorm"
)

const (
	statusFix       = "FIX"
	statusKeep      = "KEEP"
	statusMissing   = "MISSING"
	statusIncomplete = "INCOMPLETE"
	statusError     = "ERROR"

	stripeRequestSpacing = 100 * time.Millisecond

	// driftTolerance: DB expires_at within this distance of Stripe's
	// current_period_end is considered correct (clock skew, rounding).
	driftTolerance = 24 * time.Hour
)

type decision struct {
	License           model.PremiumLicense
	Action            string
	StripePeriodEnd   time.Time
	StripeStatus      string
	NewExpiresAt      time.Time
	Note              string
}

func main() {
	var (
		confirm   bool
		outPrefix string
	)
	flag.BoolVar(&confirm, "confirm", false, "actually update FIX rows (default: dry-run)")
	flag.StringVar(&outPrefix, "out", "backfill_license_expiry", "output file prefix")
	flag.Parse()

	logger.Init("info")

	cfg := config.Load()
	if cfg.Stripe.SecretKey == "" {
		logger.Log.Fatal().Msg("STRIPE_SECRET_KEY not set — cannot reconcile against Stripe")
	}
	stripe.Key = cfg.Stripe.SecretKey

	db, err := database.NewPostgresDB(cfg.Database, cfg.Server.GinMode)
	if err != nil {
		logger.Log.Fatal().Err(err).Msg("connect postgres")
	}

	var licenses []model.PremiumLicense
	if err := db.
		Where("stripe_subscription_id IS NOT NULL AND stripe_subscription_id != ''").
		Order("created_at ASC").
		Find(&licenses).Error; err != nil {
		logger.Log.Fatal().Err(err).Msg("read licenses")
	}
	logger.Log.Info().Int("count", len(licenses)).Msg("loaded Stripe-linked licenses")

	timestamp := time.Now().UTC().Format("20060102T150405Z")
	csvPath := fmt.Sprintf("%s_%s.csv", outPrefix, timestamp)
	csvFile, err := os.Create(csvPath)
	if err != nil {
		logger.Log.Fatal().Err(err).Str("path", csvPath).Msg("create csv")
	}
	defer csvFile.Close()
	csvW := csv.NewWriter(csvFile)
	defer csvW.Flush()
	if err := csvW.Write([]string{
		"license_id", "license_key", "brand", "billing_cycle",
		"stripe_subscription_id", "stripe_status",
		"db_expires_at", "stripe_current_period_end", "new_expires_at",
		"delta_days", "action", "note",
	}); err != nil {
		logger.Log.Fatal().Err(err).Msg("write csv header")
	}

	var (
		decisions []decision
		counts    = map[string]int{}
	)

	for i, lic := range licenses {
		if i > 0 {
			time.Sleep(stripeRequestSpacing)
		}

		d := classify(lic)
		counts[d.Action]++
		decisions = append(decisions, d)

		deltaDays := ""
		newExp := ""
		stripeEnd := ""
		if !d.StripePeriodEnd.IsZero() {
			stripeEnd = d.StripePeriodEnd.UTC().Format(time.RFC3339)
			deltaDays = strconv.FormatFloat(lic.ExpiresAt.Sub(d.StripePeriodEnd).Hours()/24, 'f', 2, 64)
		}
		if !d.NewExpiresAt.IsZero() {
			newExp = d.NewExpiresAt.UTC().Format(time.RFC3339)
		}

		if err := csvW.Write([]string{
			lic.ID.String(),
			lic.LicenseKey,
			lic.Brand,
			lic.BillingCycle,
			derefString(lic.StripeSubscriptionID),
			d.StripeStatus,
			lic.ExpiresAt.UTC().Format(time.RFC3339),
			stripeEnd,
			newExp,
			deltaDays,
			d.Action,
			d.Note,
		}); err != nil {
			logger.Log.Error().Err(err).Msg("write csv row")
		}

		if (i+1)%25 == 0 {
			logger.Log.Info().
				Int("scanned", i+1).
				Int("total", len(licenses)).
				Interface("counts", counts).
				Msg("progress")
		}
	}

	csvW.Flush()
	logger.Log.Info().Str("csv", csvPath).Interface("counts", counts).Msg("scan complete")

	if !confirm {
		logger.Log.Info().Msg("DRY-RUN — no rows updated. Re-run with --confirm to apply FIX updates.")
		return
	}

	var toFix []decision
	for _, d := range decisions {
		if d.Action == statusFix {
			toFix = append(toFix, d)
		}
	}
	if len(toFix) == 0 {
		logger.Log.Info().Msg("no FIX rows to update")
		return
	}

	backupPath := fmt.Sprintf("%s_%s_backup.jsonl", outPrefix, timestamp)
	if err := writeBackup(backupPath, toFix); err != nil {
		logger.Log.Fatal().Err(err).Str("path", backupPath).
			Msg("backup failed — refusing to update")
	}
	logger.Log.Info().Str("backup", backupPath).Int("rows", len(toFix)).Msg("backup written")

	if err := db.Transaction(func(tx *gorm.DB) error {
		for _, d := range toFix {
			res := tx.Model(&model.PremiumLicense{}).
				Where("id = ? AND expires_at = ?", d.License.ID, d.License.ExpiresAt).
				Updates(map[string]interface{}{
					"expires_at": d.NewExpiresAt,
					"updated_at": time.Now(),
				})
			if res.Error != nil {
				return fmt.Errorf("update license %s: %w", d.License.ID, res.Error)
			}
			if res.RowsAffected != 1 {
				return fmt.Errorf("license %s: expected 1 row updated, got %d (expires_at changed since scan?)",
					d.License.ID, res.RowsAffected)
			}
		}
		return nil
	}); err != nil {
		logger.Log.Fatal().Err(err).Msg("update transaction failed — DB unchanged, backup retained")
	}

	logger.Log.Info().
		Int("updated", len(toFix)).
		Str("backup", backupPath).
		Str("csv", csvPath).
		Msg("backfill complete")
}

func classify(lic model.PremiumLicense) decision {
	d := decision{License: lic}
	subID := derefString(lic.StripeSubscriptionID)
	if subID == "" {
		d.Action = statusKeep
		d.Note = "no stripe_subscription_id"
		return d
	}

	sub, err := stripesub.Get(subID, nil)
	if err != nil {
		stripeErr, ok := err.(*stripe.Error)
		if ok && stripeErr.HTTPStatusCode == 404 {
			d.Action = statusMissing
			d.Note = "stripe 404 — subscription deleted or wrong account"
			return d
		}
		d.Action = statusError
		d.Note = fmt.Sprintf("stripe error: %v", err)
		return d
	}
	d.StripeStatus = string(sub.Status)

	if sub.CurrentPeriodEnd == 0 {
		d.Action = statusIncomplete
		d.Note = fmt.Sprintf("current_period_end=0 (status=%s)", sub.Status)
		return d
	}

	stripeEnd := time.Unix(sub.CurrentPeriodEnd, 0).UTC()
	d.StripePeriodEnd = stripeEnd

	// DB expires_at is in DB local TZ; compare in UTC.
	if lic.ExpiresAt.UTC().Sub(stripeEnd) > driftTolerance {
		d.Action = statusFix
		d.NewExpiresAt = stripeEnd
		d.Note = fmt.Sprintf("over-extended by %.2f days",
			lic.ExpiresAt.UTC().Sub(stripeEnd).Hours()/24)
		return d
	}

	d.Action = statusKeep
	d.Note = "expires_at already <= stripe current_period_end (+drift tolerance)"
	return d
}

func writeBackup(path string, rows []decision) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	for _, d := range rows {
		entry := map[string]interface{}{
			"license_id":             d.License.ID,
			"license_key":            d.License.LicenseKey,
			"brand":                  d.License.Brand,
			"billing_cycle":          d.License.BillingCycle,
			"stripe_subscription_id": derefString(d.License.StripeSubscriptionID),
			"old_expires_at":         d.License.ExpiresAt.UTC(),
			"new_expires_at":         d.NewExpiresAt.UTC(),
			"stripe_current_period_end": d.StripePeriodEnd.UTC(),
			"stripe_status":          d.StripeStatus,
			"backed_up_at":           time.Now().UTC(),
		}
		if err := enc.Encode(entry); err != nil {
			return err
		}
	}
	return nil
}

func derefString(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
