package service

import (
	"fmt"
	"sync"
	"time"

	"github.com/snakeloader/backend/internal/config"
	"github.com/snakeloader/backend/internal/pkg/logger"
	"github.com/snakeloader/backend/internal/premium/model"
	"github.com/snakeloader/backend/internal/premium/repository"
	"github.com/stripe/stripe-go/v81"
	stripeinvoice "github.com/stripe/stripe-go/v81/invoice"
	"gorm.io/gorm"
)

// Audit action constants. Mirrors cmd/cleanup_invoices so operators get the
// same vocabulary whether they run the CLI or the admin endpoint.
const (
	AuditActionKeep          = "KEEP"
	AuditActionForeign       = "FOREIGN"
	AuditActionStripeMissing = "STRIPE_MISSING"
	AuditActionError         = "ERROR"

	// ConfirmTokenDeleteForeign is the magic string a caller must send to
	// actually delete FOREIGN rows. Any other value (or absence) → dry-run.
	// The token is deliberately verbose so a curl typo can't destroy data.
	ConfirmTokenDeleteForeign = "DELETE_FOREIGN_INVOICES"

	// auditWorkers bounds parallel Stripe API calls. 8 workers × ~3 req/s
	// each stays well under Stripe's 100 req/s read limit even under burst,
	// while finishing a 500-invoice scan in ~20s — inside Cloudflare's 100s
	// proxy timeout. Per-call 429 retry absorbs the occasional clip.
	auditWorkers = 8
)

// InvoiceAuditRow is the per-invoice outcome in an audit run.
type InvoiceAuditRow struct {
	StripeInvoiceID string `json:"stripe_invoice_id"`
	DBBrand         string `json:"db_brand"`
	DBStatus        string `json:"db_status"`
	AmountPaidCents int    `json:"amount_paid_cents"`
	StripePriceID   string `json:"stripe_price_id,omitempty"`
	ResolvedBrand   string `json:"resolved_brand,omitempty"`
	Action          string `json:"action"`
	Note            string `json:"note,omitempty"`
}

// InvoiceAuditReport summarizes a full audit run.
type InvoiceAuditReport struct {
	TotalScanned     int              `json:"total_scanned"`
	Counts           map[string]int   `json:"counts"`
	ForeignPaidCents int              `json:"foreign_paid_cents"`
	KeptPaidCents    int              `json:"kept_paid_cents"`
	ForeignSample    []InvoiceAuditRow `json:"foreign_sample"`
	Errors           []InvoiceAuditRow `json:"errors,omitempty"`
	Deleted          int              `json:"deleted"`
	DryRun           bool             `json:"dry_run"`
	DurationMs       int64            `json:"duration_ms"`
}

// AuditInvoices compares every row in the invoices table against the live
// Stripe account and classifies each as KEEP / FOREIGN / STRIPE_MISSING /
// ERROR. If confirmToken == ConfirmTokenDeleteForeign, all FOREIGN rows are
// deleted inside a single transaction after being logged. Any other token
// value leaves the DB untouched (dry-run).
//
// The live Stripe key must already be set via `stripe.Key` at startup — this
// function uses the package-level default client.
//
// Safety:
//   - STRIPE_MISSING / ERROR rows are NEVER deleted (only confirmed FOREIGN).
//   - Deletion runs inside a GORM transaction; if the affected-row count
//     doesn't match expectations, the transaction rolls back.
//   - A sample of FOREIGN rows is returned in the report so the caller has a
//     permanent record of what was removed, even without server logs.
func AuditInvoices(
	db *gorm.DB,
	invoiceRepo *repository.InvoiceRepository,
	cfg *config.StripeConfig,
	confirmToken string,
) (*InvoiceAuditReport, error) {
	if db == nil || invoiceRepo == nil || cfg == nil {
		return nil, fmt.Errorf("audit: missing dependency (db/repo/cfg)")
	}
	if cfg.SecretKey == "" || stripe.Key == "" {
		return nil, fmt.Errorf("audit: STRIPE_SECRET_KEY not configured — cannot verify invoices")
	}

	start := time.Now()
	confirm := confirmToken == ConfirmTokenDeleteForeign

	var invoices []model.Invoice
	if err := db.Order("created_at ASC").Find(&invoices).Error; err != nil {
		return nil, fmt.Errorf("audit: load invoices: %w", err)
	}

	report := &InvoiceAuditReport{
		TotalScanned: len(invoices),
		Counts:       map[string]int{},
		DryRun:       !confirm,
	}

	rows := classifyInvoicesParallel(invoices, cfg, auditWorkers)

	var foreignIDs []string
	const foreignSampleLimit = 50
	const errorSampleLimit = 20

	for i, row := range rows {
		inv := invoices[i]
		report.Counts[row.Action]++
		switch row.Action {
		case AuditActionForeign:
			report.ForeignPaidCents += inv.AmountPaidCents
			foreignIDs = append(foreignIDs, inv.StripeInvoiceID)
			if len(report.ForeignSample) < foreignSampleLimit {
				report.ForeignSample = append(report.ForeignSample, row)
			}
		case AuditActionKeep:
			if inv.Status == "paid" {
				report.KeptPaidCents += inv.AmountPaidCents
			}
		case AuditActionError:
			if len(report.Errors) < errorSampleLimit {
				report.Errors = append(report.Errors, row)
			}
		}
	}

	if confirm && len(foreignIDs) > 0 {
		err := db.Transaction(func(tx *gorm.DB) error {
			res := tx.Where("stripe_invoice_id IN ?", foreignIDs).Delete(&model.Invoice{})
			if res.Error != nil {
				return res.Error
			}
			if int(res.RowsAffected) != len(foreignIDs) {
				return fmt.Errorf("expected %d rows deleted, got %d — rolling back",
					len(foreignIDs), res.RowsAffected)
			}
			report.Deleted = int(res.RowsAffected)
			return nil
		})
		if err != nil {
			return nil, fmt.Errorf("audit: delete transaction failed: %w", err)
		}
		logger.Log.Warn().
			Int("deleted", report.Deleted).
			Int("foreign_paid_cents", report.ForeignPaidCents).
			Msg("FOREIGN invoices purged via admin audit endpoint")
	}

	report.DurationMs = time.Since(start).Milliseconds()
	return report, nil
}

// AuditInvoicesViaAdmin is the PremiumService entry point for the admin
// endpoint. It wires in the service's own db/repo/cfg so the handler only
// needs the token string. Dry-run unless confirmToken == ConfirmTokenDeleteForeign.
func (s *PremiumService) AuditInvoicesViaAdmin(confirmToken string) (*InvoiceAuditReport, error) {
	if s.invoiceRepo == nil {
		return nil, fmt.Errorf("audit: invoice repository not wired")
	}
	if s.stripe == nil {
		return nil, fmt.Errorf("audit: stripe service not wired")
	}
	return AuditInvoices(s.invoiceRepo.DB(), s.invoiceRepo, s.stripe.Config(), confirmToken)
}

// classifyInvoicesParallel fans out Stripe API calls across N workers while
// preserving input order in the returned slice. Result[i] corresponds to
// invoices[i]. Stays under Cloudflare's 100s proxy budget for ~500 invoices.
func classifyInvoicesParallel(invoices []model.Invoice, cfg *config.StripeConfig, workers int) []InvoiceAuditRow {
	if workers < 1 {
		workers = 1
	}
	results := make([]InvoiceAuditRow, len(invoices))
	jobs := make(chan int, len(invoices))
	var wg sync.WaitGroup

	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for idx := range jobs {
				results[idx] = classifyInvoiceForAudit(invoices[idx], cfg)
			}
		}()
	}
	for i := range invoices {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
	return results
}

func classifyInvoiceForAudit(inv model.Invoice, cfg *config.StripeConfig) InvoiceAuditRow {
	row := InvoiceAuditRow{
		StripeInvoiceID: inv.StripeInvoiceID,
		DBBrand:         inv.Brand,
		DBStatus:        inv.Status,
		AmountPaidCents: inv.AmountPaidCents,
	}
	if inv.StripeInvoiceID == "" {
		row.Action = AuditActionError
		row.Note = "empty stripe_invoice_id in DB"
		return row
	}

	params := &stripe.InvoiceParams{}
	params.AddExpand("lines.data.price")

	// Retry with exponential backoff on 429 (Stripe's default live-mode rate
	// limit is 100 read req/s; 16-worker bursts occasionally clip it).
	var live *stripe.Invoice
	var err error
	backoff := 250 * time.Millisecond
	for attempt := 0; attempt < 5; attempt++ {
		live, err = stripeinvoice.Get(inv.StripeInvoiceID, params)
		if err == nil {
			break
		}
		se, ok := err.(*stripe.Error)
		if !ok || se.HTTPStatusCode != 429 {
			break
		}
		time.Sleep(backoff)
		backoff *= 2
	}
	if err != nil {
		if se, ok := err.(*stripe.Error); ok && se.HTTPStatusCode == 404 {
			row.Action = AuditActionStripeMissing
			row.Note = "invoice not found in Stripe (manual review)"
			return row
		}
		row.Action = AuditActionError
		row.Note = fmt.Sprintf("stripe error: %v", err)
		return row
	}

	if live.Lines == nil || len(live.Lines.Data) == 0 || live.Lines.Data[0].Price == nil {
		row.Action = AuditActionError
		row.Note = "no line items / price on Stripe invoice"
		return row
	}

	priceID := live.Lines.Data[0].Price.ID
	row.StripePriceID = priceID

	brand, ok := cfg.BrandFromPriceID(priceID)
	if !ok {
		row.Action = AuditActionForeign
		row.Note = "price not in our whitelist (foreign product on shared Stripe account)"
		return row
	}
	row.ResolvedBrand = brand
	row.Action = AuditActionKeep
	if brand != inv.Brand {
		row.Note = fmt.Sprintf("brand mismatch — DB has %q, price implies %q", inv.Brand, brand)
	}
	return row
}
