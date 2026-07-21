# Payment Subsystem Fix Plan — v2

Revised 2026-05-20 after dual plan-review (Codex + Claude self-critique).

**Total findings: 17** (12 from original dual audit + 5 surfaced during plan review)
**Waves: 3** | **Deploy gate**: each wave ends with `git push origin main` → verify `/health` SHA → spot-check on a recent license.

---

## Guiding principles

- **One concern per commit**; revert-friendly.
- **Tests before ship** — every fix lands with a regression test. The recent `subscription_create` bug shipped without webhook handler integration tests; we close that gap as Wave 0.
- **No big-bang refactor**; surgical edits only.
- **No "minimum patch" half-measures** — the plan review showed each minimum patch leaks the original vulnerability through an adjacent code path. Build the real fix.

---

## Wave 0 — Test infrastructure (prereq, ~1 day)

The plan reviews unanimously flagged that webhook handler integration tests are missing AND must use real Postgres (not SQLite — pgconn duplicate handling, partial indexes, interval arithmetic are Postgres-specific). W1.4 and all of W2.x depend on this safety net.

**Codex pre-review (2026-05-20) flagged 5 sharpenings; folded in below.**

### W0.1a — Local dev test runner
- `backend/docker-compose.test.yml` — `postgres:16-alpine` on port **5433** (dev uses 5432), separate volume, separate container_name (`snakeloader-postgres-test`). **Must include explicit healthcheck** (Postgres image's built-in default does not check connection acceptance — only `--wait` would race past it):
  ```yaml
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U snakeloader -d snakeloader_test"]
    interval: 2s
    timeout: 3s
    retries: 15
  ```
- `backend/Makefile` adds `test-webhook` target:
  ```
  docker compose -f docker-compose.test.yml up -d --wait postgres-test
  DB_HOST=localhost DB_PORT=5433 DB_NAME=snakeloader_test \
      go test ./internal/premium/handler/... -count=1 -race -tags=integration
  docker compose -f docker-compose.test.yml down -v
  ```
  `--wait` (compose v2) blocks until the healthcheck passes. `trap` ensures cleanup even on test failure.

### W0.1b — CI integration (NEW from review)
GitHub Actions already runs `go test ./...` in `.github/workflows/backend.yml` (current CI is unit-test only, no DB). Add a `services:` block to the existing `test` job:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    env:
      POSTGRES_USER: snakeloader
      POSTGRES_PASSWORD: test
      POSTGRES_DB: snakeloader_test
    ports: ["5432:5432"]
    options: >-
      --health-cmd "pg_isready -U snakeloader"
      --health-interval 5s --health-timeout 3s --health-retries 5
```
And export `DB_HOST=localhost DB_PORT=5432 DB_NAME=snakeloader_test` + the `-tags=integration` flag. **Integration tests gated by build tag** so default `go test ./...` (current behavior) doesn't require a DB.

### W0.1c — TestMain pattern (sharpened per Codex)
- `internal/premium/handler/setup_integration_test.go` with `//go:build integration` tag.
- `TestMain` runs `database.RunMigrations(db)` ONCE at process start (AutoMigrate is idempotent — proven by current dev workflow, but assert explicitly with a second AutoMigrate call to catch regressions).
- Truncation uses a single FK-safe statement: `TRUNCATE TABLE license_devices, invoices, payment_transactions, premium_licenses, webhook_events, devices RESTART IDENTITY CASCADE`. CASCADE handles transitive references; RESTART IDENTITY resets sequences. Single statement = atomic + ordering-irrelevant.
- Helper `func resetDB(t *testing.T)` callable from any test that needs a clean slate.

### W0.1d — Sign-on-the-fly Stripe signatures (per Codex)
- `internal/premium/handler/stripe_fixtures_test.go`: helper `signStripeRequest(secret, payload []byte) http.Header` that produces a valid `Stripe-Signature: t=<now>,v1=<HMAC>` header. Fixtures store JSON payloads only; signature generated at test time.
- Pre-signed payloads rejected because they bake in timestamps that fail the 5-min replay window.

### W0.1e — Fixture expansion (per Codex)
Original plan listed 6 fixtures. Expand to **10** to cover every event type Waves 1-2 touch:
```
testdata/stripe/
  checkout.session.completed.json
  invoice.finalized.json           (NEW — W2.4 needs)
  invoice.paid.subscription_create.json
  invoice.paid.subscription_cycle.json
  invoice.paid.subscription_update.json   (NEW — W2.1 needs)
  invoice.payment_failed.json      (NEW — W2.6 needs)
  customer.subscription.updated.json   (NEW — W2.1b needs)
  customer.subscription.deleted.json
  charge.refunded.json
  charge.dispute.created.json      (NEW — W1.4 adds handler)
```

### W0.1f — Replay/idempotency tests (NEW per Codex)
Codex flagged: having fixtures isn't enough. Explicit test cases must cover:
- Same event ID delivered twice → handler runs once (`webhook_events` dedup).
- Two concurrent goroutines firing the same event → exactly one handler executes (defends the W3.1 race window).
- `subscription_create` invoice does NOT extend expires_at (regression test for the recent fix `ae0867f1`).

### W0.2 — License key validator registration with Gin (prereq for W3.3)
- New function `validator.Register(v *validator.Validate) error` in `internal/pkg/validator`:
  ```go
  v.RegisterValidation("license_key", func(fl validator.FieldLevel) bool {
      s := fl.Field().String()
      return licenseKeyRegex.MatchString(s)
  })
  ```
- Wire from `cmd/api/main.go` after Gin engine creation, **loud-fail on misconfiguration** (per Codex iter-2: don't silently skip if Gin changes its validator backend):
  ```go
  v, ok := binding.Validator.Engine().(*validator.Validate)
  if !ok {
      logger.Log.Fatal().Msg("Gin validator engine is not go-playground/validator/v10 — license_key validator cannot be registered")
  }
  if err := validator.Register(v); err != nil {
      logger.Log.Fatal().Err(err).Msg("Failed to register custom validators")
  }
  ```
- ALSO call from `TestMain` of any DTO test using the new validator. Otherwise tests run without the registration.

### Concurrent test runs (NEW from review)
Port 5433 collision risk if a developer runs `make test-webhook` while CI runs the same against the local laptop... mostly a theoretical concern. CI runs in isolated containers; dev laptop is one user. Document in Makefile comment: "5433 is fixed; if you have another Postgres on 5433, override DB_PORT for both compose and tests."

---

## Wave 1 — Critical: security & active-fraud (~1-2 days)

Close exploitable holes. No partial patches — each fix must close the vulnerability in every code path that exposes it.

### W1.1 — `AdminCreateLicense` semiannual = 12 months ⇒ 6 months
**File:** `premium_service.go:1040-1048`
**Change:** single-line fix using the canonical helper:
```go
expiresAt := AddBillingCycleToTime(time.Now(), req.BillingCycle)
```
`AddBillingCycleToTime` already handles lifetime cases internally (see `premium_service.go:43-52`) — no outer branch needed.

**Test:** add to W0.1's suite. Table test for monthly/semiannual/yearly/lifetime. The implementation MUST take an injected `clock func() time.Time` (or the test must factor out the `time.Now()` call so it captures a single instant shared between code under test and assertion). Assert **exact** `AddDate(...)` equality per cycle, not a loose window — the helper is deterministic, so loose tolerances hide regressions.

**Backfill:** **none required**. Verified empirically: `SELECT count(*) FROM premium_licenses WHERE billing_cycle='semiannual' AND payment_method='manual'` = 0. No admin-issued semi licenses exist in production today. (If this changes before deploy, re-check.)

**Deploy risk:** zero.

### W1.2 + W1.3 — Email magic-link for restore + portal (combined; same infra)
**Files:** `premium_handler.go:678-766`, `premium_service.go:964-992` (restore), `stripe_service.go:515-556` (portal), `router.go:198-217`, `cmd/api/main.go:273` (handler constructor), `internal/config/config.go` (magic-link config), `internal/premium/repository/license_repository.go:142-151` (`FindActiveByEmail`). New: `internal/premium/service/magiclink_service.go`, `premium_handler.go:RedeemMagicLink`, `dto/premium_request.go:{WebRestoreRequest,WebPortalRequest,RedeemRequest}`, email template `magic_link` in `internal/pkg/email/email.go`.

**Why combined:** Codex correctly flagged that any auth-only minimum patch leaks the same vulnerability through an adjacent path (e.g., `WebPortalSession` would still call `CreatePortalSessionByEmail` regardless of who held the API key). Both endpoints need the same magic-link primitive.

**Design:**
1. `POST /api/v1/premium/web-restore { email }` → look up active license by email → if found, **enqueue (goroutine)** signed email send via `internal/pkg/email`. Always respond `{"sent": true}` **immediately** regardless of whether email matched. Email send is off the request path so found-email vs unknown-email responses are timing-indistinguishable.
2. `POST /api/v1/premium/web-portal { email }` → same flow. Portal lookup uses a new `FindActiveStripeByEmail` (prefers licenses with non-null `StripeCustomerID` so an email with a newer manual/crypto license + older Stripe license still gets a working portal link).
3. New endpoint: `POST /api/v1/premium/redeem { token, scope }` → verify HMAC-SHA256 JWT (`typ=magic_link`, `scope`, `license_id`, `email_normalized`, `iat`, `nbf`, `exp=10min`, `jti`), one-time use via Redis `SETNX magic_link:redeemed:<sha256(jti)> 1 EX <ttl>`, respond with license_key (restore) or Stripe portal URL (portal). POST (not GET) so the token never lands in browser history, server logs, or referrer headers. The website's magic-link landing page reads the token from the URL fragment client-side and POSTs to this endpoint.
4. Token = JWS with HS256 over `{ typ: "magic_link", iss: "ssvid-backend", aud: "ssvid-magic-link", scope, license_id, email_normalized, jti, iat, nbf, exp }` using existing `JWT_SECRET`. 10-min TTL. **Pin alg=HS256** at verify time — reject any other alg in the header. Scope is enforced from the claim, not the request — a portal-scoped token must not redeem against restore and vice versa.
5. **Email normalization:** `strings.ToLower(strings.TrimSpace(email))` before lookup, signing, Redis key, and rate-limit key. `FindActiveByEmail` currently does exact equality (`license_repository.go:145`); update to compare against the normalized form (one-time migration: normalize all `contact_email` rows pre-deploy — safe, lowercase is idempotent).
6. **Re-verify at redeem time:** look up license by `license_id`, confirm it is still `tier='premium'` and not cancelled, and matches the signed normalized email and scope before returning the secret.

**Wiring:**
- `PremiumHandler` constructor signature extends to accept an `EmailSender` **interface** (not the concrete `*email.Service`), `*redis.Client`, `config.MagicLinkConfig`. Define:
  ```go
  type EmailSender interface {
      Send(to, subject, templateName string, data map[string]string) error
  }
  ```
  Production passes `*email.Service` (already satisfies the interface). Tests pass a `mockEmailSender` recording calls. Avoids real SMTP and timing-dependent goroutine sleeps in tests. Update `cmd/api/main.go:273` to pass the interface.
- `internal/config/config.go` gets a new `MagicLinkConfig { BaseURLSSvid, BaseURLVidCombo string; TTLMinutes int }` with env binds `MAGIC_LINK_BASE_SSVID` (default `https://ssvid.app/restore`), `MAGIC_LINK_BASE_VIDCOMBO` (default `https://vidcombo.com/restore`), `MAGIC_LINK_TTL_MIN` (default 10). The email body uses the brand-specific base URL with `#token=...&scope=...` fragment.

**Email-write normalization (codebase-wide):**
Add a single helper `func NormalizeEmail(s string) string { return strings.ToLower(strings.TrimSpace(s)) }` in `internal/premium/service/email_util.go` (or similar). **Every site that persists `contact_email` must call it** — otherwise post-deploy a new mixed-case row will be unrestorable. Audit grep BEFORE implementation:
```
git grep -n "ContactEmail\s*[:=]" backend/internal/premium/
```
Known sites: `stripe_service.go` checkout-session email fill-in, `webhook_handler.go` invoice-paid email backfill, `premium_service.go` AdminCreateLicense (if it accepts email), `premium_handler.go` any restore/web-restore path that writes. All call `NormalizeEmail()` before assignment.

**Also fix the authenticated path (`/premium/restore`):** `RestoreLicense` accepts `device_id` from request body (`premium_handler.go:685-694`). On authenticated routes, **ignore the body field**; read `device_id` from `c.GetString(middleware.DeviceIDKey)` (auth middleware sets it at `internal/middleware/auth.go:60,100`). Without this fix, any valid API key can pass an empty `device_id` and recover any license by email.

**Failure modes (must be defined and tested):**
- **Redis unavailable at redeem time:** fail-closed with 503 (matches existing rate-limiter policy at `cmd/api/main.go:296`). Single-use enforcement is non-negotiable.
- **Redis unavailable at issuance time:** The existing `StrictMiddleware("web_restore", 5, 60)` returns 503 before the handler when Redis is unavailable (see `cmd/api/main.go:296` — strict endpoints fail-closed by design). So during a Redis outage, web-restore and web-portal both return 503 — handler never runs. **This is acceptable degradation**: outages are rare and operationally visible. We do NOT special-case "200 sent:true during outage" because that would require swapping the strict middleware for a fail-open variant, which weakens the per-IP rate limit. Documented trade-off: outage window opens a brief enumeration signal (503 vs 200), but the outage itself is the more pressing problem.
- **SMTP send fails (after issuance):** log + alert, response was already `{"sent": true}`. Idempotent — user can re-request.

**Per-email rate limit (in addition to per-IP):** Add `sha256(normalized_email)` Redis-backed counter inside the handler for web-restore and web-portal: 5/hour. Prevents email-bomb attacks where an attacker hits one email from many IPs. Per-IP `StrictMiddleware` limits at `router.go:206-211` stay as-is. If the in-handler Redis counter call fails (separate from the middleware's pre-handler Redis check): fail-closed for that request (return 503 / generic error consistent with rate-limit denial). Same Redis nil/error path as middleware.

**Redeem route rate limit:** Register `POST /api/v1/premium/redeem` with `StrictMiddleware("redeem", 10, 60)` per-IP. The strict middleware already handles Redis-down as fail-closed, which is exactly what single-use redemption requires. Router test must verify the route is registered in BOTH the rate-limited branch AND the nil-rate-limiter branch (mirroring the existing `web-restore` pattern at `router.go:215`).

**Tests:**
- **Unit:** token sign/verify round-trip; expired token rejected (`exp` past); not-yet-valid rejected (`nbf` future); replay (Redis SETNX returns 0) rejected; wrong-scope claim rejected (portal-token used for restore); wrong `aud`/`typ` rejected; alg=none/RS256 in header rejected; malformed UUID `license_id` rejected; email normalization round-trip.
- **Integration:** full restore flow with **mock email sender** (verify template + recipient + brand-aware URL); full portal flow; **timing test** — measure response times for unknown-email vs known-email and assert they're within a tight band (e.g., ≤10ms variance) to enforce the async-send invariant.
- **Regression:** authenticated `/premium/restore` with body `device_id=""` and valid API key for an unrelated email returns `404 LICENSE_NOT_FOUND` (not 401 — auth is valid; not the secret — device mismatch). Without auth: `401`. Body `device_id` for an unrelated device: ignored (used from context, returns 404 if context device not on license).
- **Concurrent redeem:** 2 goroutines redeeming the same token concurrently; exactly one returns 200, the other 410 Gone.
- **Portal selection:** seed email with two active licenses — older Stripe + newer crypto. Assert magic-link portal request finds the Stripe one (via `FindActiveStripeByEmail`).
- **Redis-down redeem:** force Redis error; assert 503 (fail-closed).
- **Email-bombing:** 6 requests for the same email from 6 different IPs in 1 hour — 6th returns 429.

**Deploy risk:** medium. Existing web users who restored via the old flow will need to re-trigger via the new email link — communicate via in-app banner / website notice. ~150 LOC + email template + Redis interaction + small website landing page (POST-redeem helper). Email normalization pre-migration is a one-shot SQL update over `premium_licenses.contact_email`.

### W1.4 — Refund/chargeback on renewal invoices doesn't revoke license
**Files:** `webhook_handler.go:331-345` (stripeInvoice struct), `webhook_handler.go:385-417` (handleChargeRefunded), `webhook_handler.go:583-610` (handleChargeDispute), `webhook_handler.go:669-720` (handleDisputeClosed), `webhook_handler.go:268` (persistInvoiceRecord caller), `premium/model/invoice.go` (add fields), `premium/repository/invoice_repository.go` (new methods), `premium/service/premium_service.go:994-1036` (`RevokeLicenseByPaymentIntent` error wrapping), migration (auto via `AutoMigrate`).

**Changes:**
1. Extend `stripeInvoice` struct (`webhook_handler.go:331`):
   - Add `PaymentIntent string \`json:"payment_intent"\`` (top-level — current API version).
   - Add defensive nested parse: `Payments stripeInvoicePayments \`json:"payments,omitempty"\`` where `stripeInvoicePayments { Data []struct { Payment struct { PaymentIntent string \`json:"payment_intent"\` } } }`. Helper `(inv stripeInvoice) effectivePaymentIntent() string` returns top-level if set, otherwise `Payments.Data[0].Payment.PaymentIntent`. This covers both the current legacy shape (`testdata/stripe/invoice.paid.subscription_cycle.json` has `"payment_intent": "pi_test_cycle"`) AND the newer Invoice Payments shape — without coupling our deploy timing to Stripe's account-version upgrade decision. Fixtures for both shapes get added to W0.1.
2. Add to `Invoice` model:
   - `StripePaymentIntentID *string \`gorm:"size:255;index"\``
   - `StripeSubscriptionID *string \`gorm:"size:255;index"\`` — **critical for orphan-invoice recovery.** Without it, an `invoice.finalized` row persisted before checkout completes (LicenseID NULL) can be found via PI but we still can't resolve the license. With it, lookup chain becomes invoice → license_id (direct) → fallback license = `licenseRepo.FindByStripeSubscriptionID(*invoice.StripeSubscriptionID)`.
3. Wire both fields in `persistInvoiceRecord` — both the new-row branch and the upsert branch.
4. New `InvoiceRepository.FindByStripePaymentIntentID(pi string) (*Invoice, error)`. Returns `gorm.ErrRecordNotFound` cleanly on miss.
5. **Fix `RevokeLicenseByPaymentIntent` error wrapping** (`premium_service.go:997-1000`). Currently collapses any txn lookup error into `ErrTransactionNotFound` — would swallow a real DB error and mark a webhook as successfully processed. Change to:
   ```go
   txn, err := s.txnRepo.FindByStripePaymentIntentID(paymentIntentID)
   if errors.Is(err, gorm.ErrRecordNotFound) {
       return ErrTransactionNotFound
   }
   if err != nil {
       return fmt.Errorf("find transaction by payment intent: %w", err)
   }
   ```
   Same pattern for the `FindByID` and `Update` calls below — only translate not-found; propagate everything else so Stripe retries.
6. Extract `revokeLicenseByID(licenseID uuid.UUID, reason, paymentIntentID string) error` helper in `premium_service.go` that does the tier=free / IsAutoRenew=false / CancelledAt / repo.Update sequence. Called by both the transaction path (after txn lookup) and the new invoice-fallback path.
7. In `handleChargeRefunded` (line 385): after `RevokeLicenseByPaymentIntent` returns `ErrTransactionNotFound`, fall back through the invoice lookup chain. Wrap the whole thing in `service.RevokeByPaymentIntentWithInvoiceFallback(pi, reason)` helper to keep the handler thin.
8. **Step 6 (rewritten — earlier draft was factually wrong):** `charge.dispute.created` IS already dispatched (`webhook_handler.go:104-105`) and `handleChargeDispute` exists (`webhook_handler.go:583-610`). Apply the **same** invoice-fallback to it. Also handle the `dispute.PaymentIntent == ""` case (per Stripe docs, dispute.payment_intent can be null when the dispute is on a charge object only) — resolve via `charge` lookup: read `dispute.Charge`, call Stripe API `charge.Retrieve(dispute.Charge)`, use its PaymentIntent. If still empty: return an error so Stripe retries (better than silently dropping a real chargeback).
9. **`handleDisputeClosed` needs the same fallback for the won-dispute restore path** (`webhook_handler.go:689-720`). If a dispute revoked an invoice-only renewal in step 8, a later `charge.dispute.closed` with `status="won"` must restore via the same lookup chain. Currently it only looks up via `payment_transactions`.
10. Backfill tool `cmd/backfill_invoice_pi` populates **both** `invoices.stripe_payment_intent_id` AND `invoices.stripe_subscription_id` for historical rows. Pattern matches `cleanup_invoices` / `backfill_license_expiry`: dry-run default, JSONL backup, single transaction, `--confirm` flag. For each invoice missing the fields, call Stripe API `invoice.Retrieve(stripe_invoice_id)`, extract both, update. Rate-limit to ≤4 req/sec (Stripe default).

**Tests:**
- W0.1 fixture: `charge.refunded` for a `PaymentIntent` that exists only in `invoices` (not `payment_transactions`) → assert license tier flips to `free`. Two sub-cases: (a) invoice has `license_id` directly, (b) invoice has only `stripe_subscription_id` (orphan finalized-only row), license resolved via subscription chain.
- Same matrix for `charge.dispute.created`.
- `charge.dispute.closed` with `status="won"` after a previous dispute.created flipped tier=free → assert tier restored to premium.
- Dispute with empty `payment_intent` field but non-empty `charge`: assert Stripe API is consulted, fallback works. (Mock Stripe `charge.Retrieve` in test.)
- `RevokeLicenseByPaymentIntent` error path: force `txnRepo.FindByStripePaymentIntentID` to return a non-`gorm.ErrRecordNotFound` error → assert it propagates (does not get wrapped as `ErrTransactionNotFound`, webhook returns 500 so Stripe retries).
- Migration test: both columns added, AutoMigrate idempotent on re-run (verified twice in `TestMain`).
- Backfill tool dry-run on a snapshot DB: emits JSONL, mutates nothing. With `--confirm`: populates both fields, idempotent on re-run.

**Deploy risk:** medium. Two new nullable columns + indexes via GORM `AutoMigrate`. `ALTER TABLE ADD COLUMN ... NULL` is instant on Postgres. **GORM AutoMigrate does NOT use `CREATE INDEX CONCURRENTLY`** — it issues a regular `CREATE INDEX` which takes an `ACCESS EXCLUSIVE` lock on the table during the build. At the current `invoices` row count this is essentially instant; verified empirically:
```sql
-- run pre-deploy:
SELECT count(*) FROM invoices;
```
If the count is < 10k, accept the AutoMigrate lock (sub-second). If ≥ 10k: run `CREATE INDEX CONCURRENTLY idx_invoices_stripe_payment_intent_id ON invoices(stripe_payment_intent_id); CREATE INDEX CONCURRENTLY idx_invoices_stripe_subscription_id ON invoices(stripe_subscription_id);` manually pre-deploy, then let AutoMigrate be a no-op for those indexes. Backfill tool runs separately, post-deploy.

---

## Wave 2 — Money correctness (~2-3 days)

### W2.1 — Plan-change `invoice.paid` extends as full renewal — **split into 2 commits**
**Files:** `webhook_handler.go:189-271` (handler), `webhook_handler.go:370-377` (stripeSubscription struct), `internal/config/config.go` (extend StripeConfig with priceID→cycle map).

**Codex correctly flagged** that "skip extend" isn't enough — current code mutates `Tier`, `IsAutoRenew`, `ContactEmail`, `ExpiryNotifiedAt` AFTER the extend branch, applied to every invoice. Plain `if !subscription_cycle { skip extend }` leaves the trailing mutation. Fix needs to be an **early return** after persisting the invoice but before mutating the license.

**W2.1a (handler fix only):**
- Persist invoice via `persistInvoiceRecord` first.
- If `billing_reason != "subscription_cycle"`: log + return. Don't extend, don't mutate license tier/auto-renew/etc. The license already has correct state from `FindOrCreateLicenseForSession` (initial) or the previous renewal.
- Only for `subscription_cycle`: existing extend logic + tier/auto-renew restore.

**W2.1b (sync BillingCycle on plan change):**
- Extend `stripeSubscription` struct with `Items []stripeSubscriptionItem` where each item has `Price stripePriceRef { ID string }`.
- Add config map `priceIDToBillingCycle` populated alongside `BrandFromPriceID`.
- New method `cfg.Stripe.BillingCycleFromPriceID(id) (cycle string, ok bool)`.
- In `handleSubscriptionUpdated` (need to verify the handler is even dispatched — check `webhook_handler.go` switch): after the existing `cancel_at_period_end` handling, look up the new cycle from `sub.Items.Data[0].Price.ID` and update `license.BillingCycle` if it changed.

**Tests:** W0.1 fixtures for `invoice.paid` with `billing_reason="subscription_update"` (assert no expiry change), `customer.subscription.updated` with a different price (assert `license.BillingCycle` updated).

**Deploy risk:** low (W2.1a) + low (W2.1b).

### W2.2 — `VerifyLicense` doesn't enforce brand match
**File:** `premium_service.go:122-198`

**Change:** inside `VerifyLicense`, after `FindByKey`, compare `license.Brand` against the device's brand. On mismatch return `ErrInvalidLicenseKey` (same error as not-found for enumeration resistance).

**Codex flagged additional risk:** `Heartbeat` mutates `devices.brand`. A user with a registered cross-brand device could trigger a lockout retroactively if they call heartbeat with a different brand. Fix:
- Block `devices.brand` mutation in `Heartbeat` if the device has any active `license_devices` rows. Force user to detach (call new admin/support path) before brand switch.
- Pre-deploy SQL audit: `SELECT count(*) FROM license_devices ld JOIN premium_licenses pl ON ld.license_id=pl.id JOIN devices d ON ld.device_id=d.id WHERE pl.brand != d.brand;`. If N > 0 → contact affected users individually before deploy. Expected: 0.

**Tests:** matrix (SSvid license × VidCombo device) + (heartbeat brand change attempt on a device with licenses).

**Deploy risk:** medium. SQL audit gate before deploy is mandatory.

### W2.3 — `handleInvoicePaid` no status/amount gate
**File:** `webhook_handler.go:189-205`

**Change:** early return when `invoice.Status != "" && invoice.Status != "paid"` OR `invoice.AmountPaid <= 0`.

**Test:** fixture with `status="open"` and another with `amount_paid=0`. Both expect no license mutation.

**Deploy risk:** zero — adds preconditions, never broadens.

### W2.4 — `invoice.finalized` orphan invoices never linked to license
**Files:** `webhook_handler.go:560-580` (upsert branch), new `cmd/backfill_invoice_license_link/main.go`.

**Change:**
1. In the upsert branch, when `existing.LicenseID == nil && record.LicenseID != nil` → assign and persist. Same defensive backfill for `Brand` when `existing.Brand` is the default `"ssvid"` and `record.Brand` is non-default (e.g., `"vidcombo"`).
2. Per Codex, also update `period_start/end`, `amount_due_cents`, `billing_reason` on upsert when the incoming record has higher-confidence values (paid invoice has more info than finalized).
3. **Backfill safety (per Codex):** only link orphan invoices when (a) the invoice's price_id is whitelisted (`BrandFromPriceID` returns `ok=true`) AND (b) exactly one local license matches the subscription_id. Skip ambiguous matches; log them for manual review.

**Tests:** integration fixture firing `invoice.finalized` before `checkout.session.completed`, then `invoice.paid` after the license exists — assert the orphan row now has `LicenseID` set.

**Deploy risk:** low.

### W2.5 — **NEW from review:** `resolveBrandFromDevice` mis-attributes deleted devices to SSvid
**File:** `webhook_handler.go:483-493`

**Trigger:** Admin or GDPR delete prunes a device row. A subsequent renewal webhook on that license calls `resolveBrandFromDevice(deviceID)` → row missing → defaults to `"ssvid"` even if the license belongs to vidcombo.

**Change:** lookup priority becomes (1) device row brand, (2) `license.Brand`, (3) `"ssvid"` last resort. Pass the license in or change the call signature to `resolveBrand(license)`.

**Test:** unit on `resolveBrandFromDevice` with a deleted device + non-ssvid license.

**Deploy risk:** zero.

### W2.6 — **NEW from review:** `handleInvoicePaymentFailed` overwrites `IsAutoRenew=true` from concurrent renewal
**File:** `webhook_handler.go:406-441`

**Trigger:** `invoice.payment_failed` fires shortly after `invoice.paid` for the same subscription (Stripe retry storm). The failed-payment handler reads-then-writes without conditional protection; if the read happened before the renewal set `IsAutoRenew=true`, the failed update reverts to `false`.

**Change:** convert to a conditional UPDATE `SET is_auto_renew=false WHERE id=? AND updated_at=? AND <invoice is still the latest>`. Or wrap in a `SELECT FOR UPDATE` transaction.

**Test:** concurrency test in W0.1 — fire `invoice.paid` then `invoice.payment_failed` for the same subscription in quick succession.

**Deploy risk:** low.

### W2.7 — **NEW from review:** `GetPremiumStats.RevenueByBillingCycle` ignores brand filter
**File:** `premium_service.go:851` (RevenueByBillingCycle call), `repository/transaction_repository.go` (the method itself).

**Trigger:** Admin dashboard renders revenue stats filtered by brand (e.g., "show SSvid revenue"). The handler correctly filters `total_revenue` by brand, but the per-cycle revenue calls (`"monthly"`, `"yearly"`) don't pass the brand → returns cross-brand totals → dashboard pie chart inflates one brand with the other's revenue.

**Change:** add brand param to `RevenueByBillingCycle(cycle, brand string)`. Update the 2 callsites in `GetPremiumStats`.

**Tests:** repository test with mixed-brand transactions; assert filter applied.

**Deploy risk:** zero — affects dashboard accuracy only, no customer-facing behavior.

---

## Wave 3 — Defensive cleanup (within the week)

### W3.1 — `MarkProcessing` webhook retry race
**File:** `webhook_event_repository.go:29-56`, migration.

**Change:**
1. Add nullable column `processing_started_at TIMESTAMPTZ`.
2. Reclaim logic: atomic conditional `UPDATE WHERE event_id = ? AND (status='failed' OR (status='processing' AND COALESCE(processing_started_at, NOW() - INTERVAL '10 minutes') < NOW() - INTERVAL '5 minutes'))`. The `COALESCE` ensures legacy rows with NULL `processing_started_at` are treated as stale (safe — they're either really stuck or pre-migration).
3. If `RowsAffected == 0`: another worker holds the row, return `(false, nil)`.

**Test:** repository test launching two goroutines concurrently — exactly one wins.

**Deploy risk:** schema change. Defer until W1.4's migration has been stable for a week to avoid stacking migrations. Nullable column + COALESCE makes the migration backward-compatible.

### W3.2 — `RefundTransaction` no idempotency key
**File:** `premium_service.go:674-683`

**Change:**
```go
refundParams := &stripe.RefundParams{PaymentIntent: stripe.String(paymentIntentID)}
refundParams.IdempotencyKey = stripe.String("refund-" + txnID.String())
_, err = refund.New(refundParams)
```

**Test:** unit asserting `IdempotencyKey` is set.

**Deploy risk:** zero.

### W3.3 — `CancelRequest` validation rejects VidCombo (48-char) keys
**File:** `dto/premium_request.go:16` + grep for other `min=45,max=45` (~2-3 other DTOs).

**Change:** replace with `binding:"required,license_key"`. The custom validator (registered in W0.2) accepts the two known prefixes via regex:
```
^(SSVID|VIDCOMBO)(-[0-9a-f]{4}){8}$
```

**Codex flagged:** before tightening, audit existing `premium_licenses.license_key` values for legacy formats:
```sql
SELECT license_key FROM premium_licenses
WHERE license_key !~ '^(SSVID|VIDCOMBO)(-[0-9a-f]{4}){8}$';
```
If any rows are found, document them and either migrate or widen the regex.

**Test:** DTO unit test for valid SSvid (45 ch) + valid VidCombo (48 ch) + invalid prefix + invalid length.

**Deploy risk:** low. Loosens a validator. Audit query is the gate.

### W3.4 — Bare `"lifetime"` cycle accepted; crypto creates $0 invoice
**Files:** `dto/premium_request.go` (4× oneof lists), `crypto_service.go:111`, `stripe_service.go:136`.

**Change:**
1. Drop bare `"lifetime"` from the four `oneof` lists. Keep `lifetime1/lifetime2/lifetime3`.
2. Belt-and-braces: in `CreateCryptoInvoice` and `CreateCheckoutSession`, reject any `amountCents <= 0` with `ErrInvalidBillingCycle`.

**Test:** DTO test (`{"billingCycle":"lifetime"}` fails validation). Service test (zero amount path returns error before BTCPay/Stripe call).

**Deploy risk:** zero — desktop clients today only emit `lifetime1/2/3`.

---

## Backfill tools needed

| For | Tool | Purpose |
|---|---|---|
| W1.4 | `cmd/backfill_invoice_pi` | Populate `invoices.stripe_payment_intent_id` from Stripe API for historical rows |
| W2.4 | `cmd/backfill_invoice_license_link` | Link orphan invoices to their license (safety gates per Codex) |

All follow the established pattern (`cleanup_invoices` / `backfill_license_expiry`): dry-run default, JSONL backup before mutation, single transaction, gitignored output.

**Removed from v1 plan:** `cmd/backfill_admin_semi` — verified empirically that no admin-issued semi licenses exist.

---

## Ordering & dependencies

```
Wave 0 (test infra):    W0.1 ─┬─ W0.2 ─┐
                              │        │
Wave 1 (security):     W1.1 ─┴─────────┴─→ W1.2+W1.3 (paired, magic-link) ─→ W1.4
                                                                              │ (adds stripe_payment_intent_id)
Wave 2 (money):              W2.1a → W2.1b → W2.3 → W2.4 ─→ W2.5,W2.6,W2.7
                              │                              (depends on W1.4 column)
                              └─→ W2.2 (requires SQL audit + heartbeat fix)
Wave 3 (defensive):    W3.4 → W3.3 → W3.2 → W3.1 (last; schema change spaced from W1.4)
```

**Realistic timeline:**
- Wave 0: 1 day
- Wave 1: 1-2 days (W1.2/W1.3 magic-link is the biggest piece)
- Wave 2: 2-3 days
- Wave 3: 1 day

Total: ~1 week of focused work, 4-5 deploys.

---

## Out-of-scope (called out, not fixing now)

- Refactor of god-files (`premium_handler.go`, `premium_service.go`). Large blast radius, not justified by these findings.
- Stripe Tax integration.
- Migration off GORM.
- Full BTCPay audit beyond W3.4.
- The `cmd/` graveyard problem (long-term: add `backend/cmd/README.md` listing each one-shot and whether it's safe to delete).

---

## Findings index (cross-reference to original audit)

| ID | Description | From | Severity |
|---|---|---|---|
| W1.1 | AdminCreateLicense semiannual=12mo | Claude | critical |
| W1.2 | WebRestoreLicense email-only key disclosure | Both | critical |
| W1.3 | WebPortalSession email-only Stripe Portal | Both | critical |
| W1.4 | Refund/chargeback on renewal doesn't revoke | Both | high |
| W2.1 | invoice.paid extends on non-cycle billing_reasons | Codex | high |
| W2.2 | VerifyLicense no brand check | Codex | high |
| W2.3 | invoice.paid no status/amount gate | Both | medium |
| W2.4 | invoice.finalized orphans not linked | Claude | high |
| W2.5 | resolveBrandFromDevice → ssvid on deleted device | Claude (review) | medium |
| W2.6 | invoice.payment_failed races renewal | Claude (review) | medium |
| W2.7 | GetPremiumStats per-cycle revenue ignores brand | Codex (review) | medium |
| W3.1 | MarkProcessing webhook retry race | Both | medium |
| W3.2 | RefundTransaction no IdempotencyKey | Claude | medium |
| W3.3 | CancelRequest length blocks VidCombo | Codex | medium |
| W3.4 | Bare "lifetime" → $0 crypto invoice | Both | low |
| (+) | Authenticated /premium/restore body device_id bypass | Codex (review) | high — folded into W1.2 |
| (+) | Heartbeat changes device brand → retroactive lockout | Codex (review) | medium — folded into W2.2 |
