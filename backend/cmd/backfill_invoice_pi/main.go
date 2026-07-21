// backfill_invoice_pi populates the W1.4 refund-fallback fingerprints
// (stripe_payment_intent_id, stripe_subscription_id) on historical Invoice
// rows that were persisted before W1.4 added those columns. Without this
// backfill, the new charge.refunded / charge.dispute.* invoice-fallback chain
// can only recover invoices written AFTER the W1.4 deploy.
//
// Strategy:
//  1. Load every Invoice row where stripe_payment_intent_id IS NULL OR
//     stripe_subscription_id IS NULL.
//  2. For each, fetch the Stripe invoice via Stripe API. Read:
//     - invoice.payment_intent (top-level legacy shape) OR
//       invoice.payments.data[0].payment.payment_intent (new shape)
//     - invoice.subscription
//  3. Dry-run by default. With --confirm, write JSONL backup first, then
//     apply UPDATE for the rows that need it inside a single transaction.
//
// Safety:
//   - Default mode never touches the DB.
//   - JSONL backup written FIRST on --confirm; if it fails, no UPDATE runs.
//   - Rate limit: 100ms between Stripe requests (~10 req/s, well under
//     Stripe's 100 req/s limit).
//   - Idempotent: re-running after a partial run only touches still-NULL rows.
//   - Stripe 404 / missing → row marked MISSING, not updated.
//
// Usage:
//   go run ./cmd/backfill_invoice_pi             # dry-run, writes CSV report
//   go run ./cmd/backfill_invoice_pi --confirm   # apply updates
//   go run ./cmd/backfill_invoice_pi --out /tmp/x # custom prefix
package main

import (
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/database"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/stripe/stripe-go/v81"
	stripeinvoice "github.com/stripe/stripe-go/v81/invoice"
	"gorm.io/gorm"
)

const (
	actionFix     = "FIX"
	actionKeep    = "KEEP"
	actionMissing = "MISSING"
	actionError   = "ERROR"

	stripeRequestSpacing = 100 * time.Millisecond
)

type decision struct {
	Invoice           model.Invoice
	Action            string
	NewPaymentIntent  string
	NewSubscriptionID string
	Note              string
}

func main() {
	var (
		confirm   bool
		outPrefix string
	)
	flag.BoolVar(&confirm, "confirm", false, "actually update FIX rows (default: dry-run)")
	flag.StringVar(&outPrefix, "out", "backfill_invoice_pi", "output file prefix")
	flag.Parse()

	logger.Init("info")

	cfg := config.Load()
	if cfg.Stripe.SecretKey == "" {
		logger.Log.Fatal().Msg("STRIPE_SECRET_KEY not set — cannot resolve invoices against Stripe")
	}
	stripe.Key = cfg.Stripe.SecretKey

	db, err := database.NewPostgresDB(cfg.Database, cfg.Server.GinMode)
	if err != nil {
		logger.Log.Fatal().Err(err).Msg("connect postgres")
	}

	var invoices []model.Invoice
	if err := db.
		Where("stripe_payment_intent_id IS NULL OR stripe_subscription_id IS NULL").
		Order("created_at ASC").
		Find(&invoices).Error; err != nil {
		logger.Log.Fatal().Err(err).Msg("read invoices")
	}
	logger.Log.Info().Int("count", len(invoices)).Msg("loaded invoices missing fingerprint(s)")

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
		"invoice_id", "stripe_invoice_id", "license_id", "brand",
		"old_pi", "new_pi", "old_sub", "new_sub", "action", "note",
	}); err != nil {
		logger.Log.Fatal().Err(err).Msg("write csv header")
	}

	var (
		decisions []decision
		counts    = map[string]int{}
	)
	for i, inv := range invoices {
		if i > 0 {
			time.Sleep(stripeRequestSpacing)
		}
		d := classify(inv)
		counts[d.Action]++
		decisions = append(decisions, d)

		licID := ""
		if inv.LicenseID != nil {
			licID = inv.LicenseID.String()
		}
		if err := csvW.Write([]string{
			inv.ID.String(),
			inv.StripeInvoiceID,
			licID,
			inv.Brand,
			derefStr(inv.StripePaymentIntentID),
			d.NewPaymentIntent,
			derefStr(inv.StripeSubscriptionID),
			d.NewSubscriptionID,
			d.Action,
			d.Note,
		}); err != nil {
			logger.Log.Error().Err(err).Msg("write csv row")
		}

		if (i+1)%25 == 0 {
			logger.Log.Info().
				Int("scanned", i+1).
				Int("total", len(invoices)).
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
		if d.Action == actionFix {
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
			updates := map[string]interface{}{
				"updated_at": time.Now(),
			}
			if d.NewPaymentIntent != "" && d.Invoice.StripePaymentIntentID == nil {
				pi := d.NewPaymentIntent
				updates["stripe_payment_intent_id"] = &pi
			}
			if d.NewSubscriptionID != "" && d.Invoice.StripeSubscriptionID == nil {
				sub := d.NewSubscriptionID
				updates["stripe_subscription_id"] = &sub
			}
			if len(updates) <= 1 {
				continue // only updated_at — nothing new to set
			}
			res := tx.Model(&model.Invoice{}).
				Where("id = ?", d.Invoice.ID).
				Updates(updates)
			if res.Error != nil {
				return fmt.Errorf("update invoice %s: %w", d.Invoice.ID, res.Error)
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

func classify(inv model.Invoice) decision {
	d := decision{Invoice: inv}
	if inv.StripeInvoiceID == "" {
		d.Action = actionKeep
		d.Note = "no stripe_invoice_id (manual invoice?)"
		return d
	}
	si, err := stripeinvoice.Get(inv.StripeInvoiceID, nil)
	if err != nil {
		stripeErr, ok := err.(*stripe.Error)
		if ok && stripeErr.HTTPStatusCode == 404 {
			d.Action = actionMissing
			d.Note = "stripe 404 — invoice deleted or wrong account"
			return d
		}
		d.Action = actionError
		d.Note = fmt.Sprintf("stripe error: %v", err)
		return d
	}

	if si.PaymentIntent != nil && si.PaymentIntent.ID != "" {
		d.NewPaymentIntent = si.PaymentIntent.ID
	}
	if si.Subscription != nil && si.Subscription.ID != "" {
		d.NewSubscriptionID = si.Subscription.ID
	}

	needsPI := inv.StripePaymentIntentID == nil && d.NewPaymentIntent != ""
	needsSub := inv.StripeSubscriptionID == nil && d.NewSubscriptionID != ""
	if needsPI || needsSub {
		d.Action = actionFix
		switch {
		case needsPI && needsSub:
			d.Note = "missing both PI and subscription"
		case needsPI:
			d.Note = "missing PI"
		default:
			d.Note = "missing subscription"
		}
		return d
	}
	d.Action = actionKeep
	d.Note = "fingerprints already present or unavailable upstream"
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
			"invoice_id":          d.Invoice.ID,
			"stripe_invoice_id":   d.Invoice.StripeInvoiceID,
			"license_id":          d.Invoice.LicenseID,
			"brand":               d.Invoice.Brand,
			"old_payment_intent":  derefStr(d.Invoice.StripePaymentIntentID),
			"new_payment_intent":  d.NewPaymentIntent,
			"old_subscription":    derefStr(d.Invoice.StripeSubscriptionID),
			"new_subscription":    d.NewSubscriptionID,
			"backed_up_at":        time.Now().UTC(),
		}
		if err := enc.Encode(entry); err != nil {
			return err
		}
	}
	return nil
}

func derefStr(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
