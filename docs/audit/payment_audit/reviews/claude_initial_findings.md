# Svid Payment Subsystem Audit Findings

Audit date: 2026-05-20. Read-only review of `backend/internal/premium/*` plus
related routes. The already-fixed `subscription_create` double-extend bug
(commit ae0867f1) is excluded.

---

## [SEVERITY: critical] AdminCreateLicense gives `semiannual` licenses 12 months instead of 6

**File:** `backend/internal/premium/service/premium_service.go:1040-1048`

**Trigger:** Admin issues a comp/manual license via
`POST /admin/v1/licenses` with `billing_cycle: "semiannual"` (a value the DTO
explicitly allows — `dto/premium_request.go:54`).

**Evidence:**
```go
var expiresAt time.Time
if IsLifetimePlan(req.BillingCycle) {
    expiresAt = time.Now().AddDate(100, 0, 0)
} else if req.BillingCycle == "monthly" {
    expiresAt = time.Now().AddDate(0, 1, 0)
} else {
    expiresAt = time.Now().AddDate(1, 0, 0)   // <-- "semiannual" lands here
}
```
This is the *same* bug class that `AddBillingCycleToTime` was created to fix
(see the long comment at `premium_service.go:33-42` listing the four sites
that had it). This admin entry point was missed in that refactor. The doc
comment even says VidCombo semiannual subscribers silently got 365 days —
admins handing out comp licenses now do the same.

**Impact:** Every admin-issued `semiannual` license (VidCombo comp / support
refund / reseller key) gets 6 months of free service the company is not paid
for. Also drifts the renewal clock off Stripe's actual cadence for any user
later attached.

**Fix sketch:** `premium_service.go:1040-1048` — replace the if/else chain
with the single source of truth:
```go
if IsLifetimePlan(req.BillingCycle) {
    expiresAt = time.Now().AddDate(100, 0, 0)
} else {
    expiresAt = AddBillingCycleToTime(time.Now(), req.BillingCycle)
}
```

---

## [SEVERITY: critical] `WebRestoreLicense` returns full license key by email alone (account takeover)

**File:** `backend/internal/premium/handler/premium_handler.go:678-724`,
service at `service/premium_service.go:964-992`, route at
`server/router.go:206-208`.

**Trigger:** `POST /api/v1/premium/web-restore { "email": "victim@x.com" }`
with NO `device_id`. No authentication. Rate limit 5 req/min per IP.

**Evidence:** `RestoreLicense` skips device verification when `deviceID ==
uuid.Nil` (line 972), and `WebRestoreLicense` defaults `deviceID` to
`uuid.Nil` when the optional `device_id` is omitted
(`premium_handler.go:686-694`). The handler then returns the full
`LicenseKey` in `RestoreResponse` (service.go:987-991). Any attacker with a
list of customer emails (purchase leaks, OSINT, breached marketing DBs) can
harvest live license keys at 5 keys / min / IP — trivially parallelised
across IPv6 ranges or residential proxies.

**Impact:** Total bypass of the device-limit + payment system. Stolen keys
work on any device up to the per-plan device cap (3-10). Customers reporting
"I never gave anyone my key" will be impossible to triage because the API
deliberately allows this. Money lost = #stolen-licenses × plan-price.

**Fix sketch:** `premium_service.go:972` — make device verification
mandatory in `RestoreLicense`. Move the unauthenticated convenience flow to
emit an *email* (signed restore-link sent to the registered address) rather
than returning the key in the HTTP response. Minimum patch: in
`WebRestoreLicense` reject when `req.DeviceID == ""`, returning
`LICENSE_NOT_FOUND` to preserve enumeration resistance.

---

## [SEVERITY: high] Refund / chargeback on a subscription *renewal* invoice does NOT revoke license

**File:** `backend/internal/premium/handler/webhook_handler.go:385-417`
(`handleChargeRefunded`), `service/premium_service.go:994-1036`
(`RevokeLicenseByPaymentIntent`).

**Trigger:** Customer pays monthly subscription. After 6 months they file a
dispute / refund request with their bank for the most recent renewal charge
(say, month 6). `charge.refunded` webhook fires.

**Evidence:** `RevokeLicenseByPaymentIntent` looks up the transaction by
`stripe_payment_intent_id` in `payment_transactions`. But
`payment_transactions` only ever stores the **initial** session's
PaymentIntent (set in `FindOrCreateLicenseForSession` at
`premium_service.go:338-340`). Renewal invoices each get a NEW PaymentIntent
from Stripe, and renewals are recorded only in the `invoices` table — there
is no `transactions` row created for renewals (see `handleInvoicePaid`
webhook, which only calls `persistInvoiceRecord`). Thus
`FindByStripePaymentIntentID` returns `ErrRecordNotFound`,
`handleChargeRefunded` swallows it as "Not our charge, skip gracefully"
(line 408), and the license keeps tier=premium until ExpiresAt — which
`handleInvoicePaid` has been steadily extending.

**Impact:** Customer keeps premium access after a successful chargeback for
the most recent cycle, AND money is lost (chargeback fee + refunded
amount). At scale this becomes a refund-fraud vector: subscribe, use
heavily, dispute most recent charge, keep using.

**Fix sketch:** `webhook_handler.go:385` — also resolve the license via the
`invoices` table when transaction lookup fails. Add
`InvoiceRepository.FindByStripeChargeID` or by `stripe_payment_intent_id`
(would require persisting PI on invoice rows), and have
`handleChargeRefunded` fall through to invoice→license_id lookup. Same fix
needed for `handleChargeDispute` (line 583).

---

## [SEVERITY: high] `invoice.finalized` orphan invoices are never linked to a license

**File:** `backend/internal/premium/handler/webhook_handler.go:560-580`
(`persistInvoiceRecord` upsert branch), called from
`handleInvoiceStatusChange:494` and `handleInvoicePaid:268`.

**Trigger:** Stripe normally fires `invoice.finalized` BEFORE
`invoice.paid` for the same invoice. If `invoice.finalized` arrives before
`checkout.session.completed` has run (real race, especially under load),
the license doesn't exist yet, so `handleInvoiceStatusChange` writes an
Invoice row with `LicenseID = nil`. Later when `invoice.paid` fires the
license exists, and `persistInvoiceRecord` is called with a non-nil
`licenseID`.

**Evidence:** Lines 561-574 — the update branch copies status, amounts,
URLs, paid_at, contact_email — but never sets `existing.LicenseID = record.LicenseID`:
```go
existing.Status = record.Status
existing.AmountPaidCents = record.AmountPaidCents
existing.InvoicePDFURL = record.InvoicePDFURL
existing.HostedInvoiceURL = record.HostedInvoiceURL
existing.PaidAt = record.PaidAt
if existing.ContactEmail == "" && record.ContactEmail != "" {
    existing.ContactEmail = record.ContactEmail
}
// LicenseID is never assigned to existing.
```

**Impact:** Admin dashboard shows revenue ($X paid) with no license attached
→ customer support cannot find which license that invoice belongs to. MRR /
customer-spend joins that go through `invoices.license_id` undercount these
customers. `GetCustomer` (premium_service.go:1261) which fetches invoices
via license joins will miss the renewal payment from the orphan row.

**Fix sketch:** `webhook_handler.go:568` — add
```go
if existing.LicenseID == nil && record.LicenseID != nil {
    existing.LicenseID = record.LicenseID
}
```
Also add `Brand` backfill with the same guard — finalized-before-paid
invoices may have landed with the wrong brand if the price_id lookup raced
config reload.

---

## [SEVERITY: high] `WebPortalSession` lets anyone open any customer's Stripe Billing Portal by email

**File:** `backend/internal/premium/handler/premium_handler.go:739-766`,
service at `service/stripe_service.go:515-556`, route at
`server/router.go:209-211`.

**Trigger:** `POST /api/v1/premium/web-portal { "email": "victim@x.com" }`.
No authentication, no possession proof. Rate limit 3 req/min per IP.

**Evidence:** `CreatePortalSessionByEmail` does
`licenseRepo.FindActiveByEmail(email)` and calls
`billingportalsession.New` with the matching `StripeCustomerID`. Stripe
Billing Portal links are bearer tokens valid for ~1 hour and grant the
holder full ability to:
- View all past invoices (PII, address, last 4 of card)
- Update payment method
- Cancel subscription
- Change plan (potential to downgrade and abuse refund credit on upgrade)

The endpoint deliberately accepts only email, with no verification token or
device-ownership check.

**Impact:** Targeted harassment / competitive sabotage (cancel a
competitor's known-email subscription); PII disclosure (billing addresses
from invoice PDFs); subscription manipulation. Rate limit of 3/min is
trivially defeated with multiple IPs since the attacker only needs ONE
successful portal session per target.

**Fix sketch:** `premium_handler.go:739` — require an email-verified flow:
issue a one-time signed link via email to the registered address that
redirects through `/api/v1/premium/portal-redeem?token=...` to the actual
Stripe portal session. Alternatively, gate the entire web-portal endpoint
behind device auth (move it into the authenticated group) and direct
website users to log into the desktop app first.

---

## [SEVERITY: medium] `MarkProcessing` reclaim path is racy — two concurrent webhook retries can both proceed

**File:**
`backend/internal/premium/repository/webhook_event_repository.go:29-56`

**Trigger:** Stripe retries a failed/timed-out webhook (`failed` or stuck
`processing` row). Two retries arrive within milliseconds of each other.

**Evidence:** The flow is:
1. Both attempts `INSERT` → both get `23505` unique-constraint conflict.
2. Both fall into the duplicate branch (line 36-50).
3. Both read `existing.Status` — both see `"failed"` or `"processing"`.
4. Both run `UPDATE status = 'processing'` (line 47).
5. Both return `(true, nil)` → both proceed to call the handler.

There is no `SELECT ... FOR UPDATE` and no `UPDATE ... WHERE status != 'processing'`
guard, so the duplicate-detection invariant is lost on retry.

**Impact:** For idempotent handlers (e.g. `handleChargeRefunded` which
already-revoked-licenses doesn't double-revoke) the harm is small. But
`handleInvoicePaid` extends `ExpiresAt` for `subscription_cycle` invoices
— two concurrent winners would extend it twice, reintroducing the exact
bug that `ae0867f1` fixed. Risk is small because retries usually arrive
seconds apart, but the window exists on real Stripe retry storms.

**Fix sketch:**
`webhook_event_repository.go:46-49` — make the reclaim conditional:
```go
res := r.db.Model(&existing).
    Where("event_id = ? AND status IN ('failed', 'processing')", eventID).
    Updates(map[string]interface{}{"status": "processing"})
if res.RowsAffected == 0 {
    return false, nil // Lost the race, another worker is processing
}
return true, nil
```

---

## [SEVERITY: medium] `handleInvoicePaid` accepts unpaid invoices and extends expiry on them

**File:** `backend/internal/premium/handler/webhook_handler.go:189-271`

**Trigger:** Stripe sends an `invoice.paid` event where `status != "paid"`
(possible on `marked_uncollectible` then `pay()`, or some edge collection
flows), or `amount_paid == 0` (free trial invoice, 100% coupon).

**Evidence:** The handler never checks `invoice.Status == "paid"` or
`invoice.AmountPaid > 0` before extending `ExpiresAt`. A 100%-discount
coupon, a trial conversion with $0 charge, or a manually-paid invoice
would extend the license by a full cycle even though no money moved. The
`stripeInvoice.AmountPaid` field is parsed but never gated against.

**Impact:** Free billing-cycle grants whenever Stripe fires `invoice.paid`
on a zero-amount invoice. If support ever issues a 100% coupon for a single
cycle, the customer gets that cycle PLUS an extension on top.

**Fix sketch:** `webhook_handler.go:228` — add an early gate:
```go
if invoice.Status != "" && invoice.Status != "paid" {
    return nil
}
if invoice.AmountPaid <= 0 {
    return nil
}
```

---

## [SEVERITY: medium] `RefundTransaction` issues Stripe refund without idempotency key

**File:** `backend/internal/premium/service/premium_service.go:674-683`

**Trigger:** Admin clicks "Refund" twice in the dashboard (double-click,
flaky network, retry on 504). Or the handler's caller retries after a
timeout where Stripe processed the refund but the response was lost.

**Evidence:**
```go
_, err = refund.New(&stripe.RefundParams{
    PaymentIntent: stripe.String(paymentIntentID),
})
```
No `IdempotencyKey` set on the params. Stripe's API explicitly recommends
idempotency keys for write operations to avoid duplicates on retry. If the
admin click double-fires, Stripe will create two refund records, which on a
partial-refund-eligible charge can refund more than the charge amount (up
to original total split across them) or generate spurious
`charge.refunded` webhooks.

**Impact:** Money lost on flaky network retries. Even when bounded by
Stripe's "cannot refund more than charged" guard, two refund events can
trigger `RevokeLicenseByPaymentIntent` twice (idempotent — license stays
revoked) and pollute the txn status flapping `refunded` → `refunded`.

**Fix sketch:** `premium_service.go:675` — derive a stable key:
```go
refundParams := &stripe.RefundParams{PaymentIntent: stripe.String(paymentIntentID)}
refundParams.IdempotencyKey = stripe.String("refund-" + txnID.String())
_, err = refund.New(refundParams)
```

---

## [SEVERITY: low] `IsLifetimePlan` accepts the literal cycle `"lifetime"` but DTO validation also accepts it — orphan tier

**File:** `backend/internal/premium/dto/premium_request.go:5,11,22,54`,
`service/premium_service.go:43-60`

**Trigger:** Anyone (web checkout, device checkout, crypto, admin) sends
`billing_cycle: "lifetime"` (no digit). DTO `binding:"oneof=monthly
semiannual yearly lifetime lifetime1 lifetime2 lifetime3"` accepts it.

**Evidence:**
- `AmountCentsForBillingCycle("lifetime", "svid")` returns **0**
  (`premium_service.go:1099-1112`, no `"lifetime"` case in svid switch).
- `resolvePriceID("lifetime", brand)` returns "" → `ErrInvalidBillingCycle`
  in Stripe checkout — so Stripe path is safe.
- But crypto checkout (`crypto_service.go:111`) calls
  `AmountCentsForBillingCycle("lifetime", brand) → 0` → invoice for `$0.00`
  USD is created at BTCPay. BTCPay may accept the invoice and immediately
  mark it Settled with zero confirmations needed, granting the user a
  100-year lifetime license for nothing.

**Impact:** Free lifetime licenses via crypto path. Requires BTCPay
configured and zero-amount invoices to be accepted by the configured
store; depends on the store's minimum invoice amount setting.

**Fix sketch:** Either (a) drop bare `"lifetime"` from the four `oneof`
lists in `dto/premium_request.go`, or (b) add an
`if amountCents <= 0 { return ErrInvalidBillingCycle }` check at
`crypto_service.go:112` and `stripe_service.go:136`.

---

## Summary

**Counts by severity**
- Critical: 2
- High: 3
- Medium: 3
- Low: 1
- Total: 9

**Top-3 must-fix (before next deploy)**
1. **AdminCreateLicense semiannual = 365d** — same bug class as the one
   just fixed; immediate revenue loss on every admin-issued semiannual
   license.
2. **WebRestoreLicense leaks license keys by email alone** — public
   endpoint, rate-limited only at the IP layer, defeats the entire payment
   system for anyone with a customer email list.
3. **Charge refund on renewal cycle never revokes the license** — the
   refund-fraud vector. The dedup mechanism (transaction-by-PI lookup)
   doesn't cover renewals because renewals don't create transaction rows.

**Areas that looked clean** (checked, no findings)
- Stripe webhook signature verification — HMAC-SHA256, 5-min replay window,
  constant-time compare, validates v1 sig and rejects unsigned (lines 735-773).
- `FindOrCreateLicenseForSession` / `FindOrCreateLicenseForCryptoInvoice`
  concurrency — proper `FOR UPDATE` locking on the transaction row inside
  a single GORM transaction; double-creation race is closed.
- `RegisterDeviceWithLimit` atomicity — locks license row, counts inside
  same tx, unique index on (license_id, device_id) backs it up.
- Brand isolation in webhook handlers — `BrandFromPriceID` whitelist applied
  consistently in `handleInvoicePaid`, `handleInvoicePaymentFailed`, and
  `handleInvoiceStatusChange`. `InvoiceAudit` provides the safety net for
  any rows that slipped past.
- `AddBillingCycleToTime` is now the single source of truth for non-admin
  renewal/initial expiry math (4 of 5 sites converted, see Finding #1 for
  the missed 5th).
- Stripe Cancel device-ownership check — `CancelSubscription` correctly
  verifies the requesting device is on the license before mutating Stripe.
- Webhook signature replay window — rejects timestamps older than 5 min,
  guarding against captured-and-replayed events.
