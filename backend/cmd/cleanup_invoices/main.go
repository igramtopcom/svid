// cleanup_invoices is a one-shot maintenance tool that audits the invoices
// table against the live Stripe account and removes rows that belong to other
// products on the shared Stripe account (legacy VidCombo PHP, legacy
// ssvid.net, anh Quan's other products, etc.).
//
// Background: prior to the price_id whitelist filter in webhook_handler.go,
// invoice.finalized / invoice.paid events from any product on the shared
// Stripe account were persisted with a hardcoded brand="ssvid" fallback,
// inflating the SSvid revenue dashboard. After the webhook fix no NEW foreign
// invoices are created, but historical pollution remains. This script cleans
// up that history.
//
// Strategy
//   1. Read every row from local `invoices` table.
//   2. For each, fetch the live invoice from Stripe (with line items expanded)
//      and read the first line's price ID.
//   3. Run that price ID through cfg.Stripe.BrandFromPriceID — same logic the
//      webhook now uses. If the price isn't ours → mark FOREIGN.
//   4. Always: write a CSV audit log (KEEP / FOREIGN / STRIPE_MISSING / ERROR).
//   5. Dry-run by default. With --confirm, dump FOREIGN rows to a JSONL backup
//      file and DELETE them inside one transaction.
//
// Safety
//   - Default mode does NOT touch the DB.
//   - On --confirm, the JSONL backup is written FIRST, then the transaction
//     opens. If the backup fails the delete never runs.
//   - Stripe API errors do NOT cause deletion (status=ERROR → KEEP).
//   - Rows whose Stripe invoice no longer exists (404) are NOT deleted —
//      they may still represent real revenue. Status=STRIPE_MISSING for
//      manual review.
//   - Rate limit: 100ms sleep between Stripe requests (~10 req/s, well under
//      the 100/s default limit).
//
// Usage
//   go run ./cmd/cleanup_invoices                 # dry-run, writes report only
//   go run ./cmd/cleanup_invoices --confirm       # actually delete FOREIGN rows
//   go run ./cmd/cleanup_invoices --out /tmp/x    # custom output prefix
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
	stripeinvoice "github.com/stripe/stripe-go/v81/invoice"
	"gorm.io/gorm"
)

const (
	statusKeep           = "KEEP"
	statusForeign        = "FOREIGN"
	statusStripeMissing  = "STRIPE_MISSING"
	statusError          = "ERROR"
	stripeRequestSpacing = 100 * time.Millisecond
)

func main() {
	var (
		confirm   bool
		outPrefix string
	)
	flag.BoolVar(&confirm, "confirm", false, "actually delete FOREIGN rows (default: dry-run)")
	flag.StringVar(&outPrefix, "out", "cleanup_invoices", "output file prefix (timestamp + extension appended)")
	flag.Parse()

	logger.Init("info")

	cfg := config.Load()
	if cfg.Stripe.SecretKey == "" {
		logger.Log.Fatal().Msg("STRIPE_SECRET_KEY not set — cannot verify invoices against Stripe")
	}
	stripe.Key = cfg.Stripe.SecretKey

	db, err := database.NewPostgresDB(cfg.Database, cfg.Server.GinMode)
	if err != nil {
		logger.Log.Fatal().Err(err).Msg("connect postgres")
	}

	var invoices []model.Invoice
	if err := db.Order("created_at ASC").Find(&invoices).Error; err != nil {
		logger.Log.Fatal().Err(err).Msg("read invoices")
	}
	logger.Log.Info().Int("count", len(invoices)).Msg("loaded invoices from DB")

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
		"stripe_invoice_id", "db_brand", "db_status", "db_amount_paid_cents",
		"stripe_price_id", "resolved_brand", "action", "note",
	}); err != nil {
		logger.Log.Fatal().Err(err).Msg("write csv header")
	}

	var (
		toDelete       []invoiceDecision
		counts         = map[string]int{}
		foreignCents   int
		keptCentsPaid  int
	)

	for i, inv := range invoices {
		if i > 0 {
			time.Sleep(stripeRequestSpacing)
		}

		action, priceID, brand, note := classify(inv, cfg.Stripe)
		counts[action]++

		if action == statusForeign {
			toDelete = append(toDelete, invoiceDecision{row: inv, action: action})
			foreignCents += inv.AmountPaidCents
		}
		if action == statusKeep && inv.Status == "paid" {
			keptCentsPaid += inv.AmountPaidCents
		}

		if err := csvW.Write([]string{
			inv.StripeInvoiceID,
			inv.Brand,
			inv.Status,
			strconv.Itoa(inv.AmountPaidCents),
			priceID,
			brand,
			action,
			note,
		}); err != nil {
			logger.Log.Error().Err(err).Msg("write csv row")
		}

		if (i+1)%50 == 0 {
			logger.Log.Info().
				Int("scanned", i+1).
				Int("total", len(invoices)).
				Interface("counts", counts).
				Msg("progress")
		}
	}

	csvW.Flush()
	logger.Log.Info().
		Str("csv", csvPath).
		Interface("counts", counts).
		Int("foreign_paid_cents", foreignCents).
		Int("kept_paid_cents", keptCentsPaid).
		Msg("scan complete")

	if !confirm {
		logger.Log.Info().Msg("DRY-RUN — no rows deleted. Re-run with --confirm to delete FOREIGN rows.")
		return
	}
	if len(toDelete) == 0 {
		logger.Log.Info().Msg("no FOREIGN rows to delete")
		return
	}

	backupPath := fmt.Sprintf("%s_%s_backup.jsonl", outPrefix, timestamp)
	if err := writeBackup(backupPath, toDelete); err != nil {
		logger.Log.Fatal().Err(err).Str("path", backupPath).
			Msg("backup failed — refusing to delete")
	}
	logger.Log.Info().Str("backup", backupPath).Int("rows", len(toDelete)).Msg("backup written")

	if err := db.Transaction(func(tx *gorm.DB) error {
		ids := make([]string, len(toDelete))
		for i, d := range toDelete {
			ids[i] = d.row.StripeInvoiceID
		}
		res := tx.Where("stripe_invoice_id IN ?", ids).Delete(&model.Invoice{})
		if res.Error != nil {
			return res.Error
		}
		logger.Log.Info().Int64("rows_affected", res.RowsAffected).Msg("delete completed")
		if int(res.RowsAffected) != len(toDelete) {
			return fmt.Errorf("expected %d rows deleted, got %d — aborting transaction",
				len(toDelete), res.RowsAffected)
		}
		return nil
	}); err != nil {
		logger.Log.Fatal().Err(err).Msg("delete transaction failed — DB unchanged, backup retained")
	}

	logger.Log.Info().
		Int("deleted", len(toDelete)).
		Int("foreign_paid_cents_removed", foreignCents).
		Str("backup", backupPath).
		Msg("cleanup complete")
}

// classify fetches the live Stripe invoice and decides what to do with the
// local row. Returns (action, priceID, resolvedBrand, note).
func classify(inv model.Invoice, cfg config.StripeConfig) (string, string, string, string) {
	if inv.StripeInvoiceID == "" {
		return statusError, "", "", "empty stripe_invoice_id in DB"
	}

	params := &stripe.InvoiceParams{}
	params.AddExpand("lines.data.price")
	live, err := stripeinvoice.Get(inv.StripeInvoiceID, params)
	if err != nil {
		var stripeErr *stripe.Error
		if asStripeErr(err, &stripeErr) && stripeErr.HTTPStatusCode == 404 {
			return statusStripeMissing, "", "", "invoice not found in Stripe (manual review)"
		}
		return statusError, "", "", fmt.Sprintf("stripe error: %v", err)
	}

	if live.Lines == nil || len(live.Lines.Data) == 0 || live.Lines.Data[0].Price == nil {
		return statusError, "", "", "no line items / price on Stripe invoice"
	}
	priceID := live.Lines.Data[0].Price.ID
	brand, ok := cfg.BrandFromPriceID(priceID)
	if !ok {
		return statusForeign, priceID, "", "price not in our whitelist (foreign product on shared Stripe account)"
	}
	if brand != inv.Brand {
		return statusKeep, priceID, brand, fmt.Sprintf("brand mismatch — DB has %q, price implies %q", inv.Brand, brand)
	}
	return statusKeep, priceID, brand, ""
}

// asStripeErr unwraps a Stripe SDK error if possible.
func asStripeErr(err error, out **stripe.Error) bool {
	if e, ok := err.(*stripe.Error); ok {
		*out = e
		return true
	}
	return false
}

type invoiceDecision struct {
	row    model.Invoice
	action string
}

func writeBackup(path string, rows []invoiceDecision) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	for _, r := range rows {
		if err := enc.Encode(r.row); err != nil {
			return err
		}
	}
	return nil
}
