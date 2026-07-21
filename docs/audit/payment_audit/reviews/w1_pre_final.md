## Verdict
no-blockers

## Round-2 blockers — resolved?
1. Issuance Redis-down conflicts with StrictMiddleware — resolved. W1.2+W1.3 now explicitly says web-restore and web-portal return 503 before handlers run during Redis outage, documents that as acceptable degradation, and acknowledges the outage-time enumeration signal (`fix_plan.md:167-170`). This is concrete and matches the existing strict-rate-limiter behavior.

2. Mockable email dependency — resolved. The plan defines a narrow `EmailSender` interface with `Send(to, subject, templateName string, data map[string]string) error`, extends the `PremiumHandler` constructor to accept it, and states production uses `*email.Service` while tests use a mock (`fix_plan.md:148-155`). The existing email service method signature matches this interface.

3. Normalize email writes, not just reads/migration — resolved. W1.2+W1.3 adds a dedicated codebase-wide write-normalization section, specifies `NormalizeEmail`, requires every `contact_email` persistence site to call it, and includes a pre-implementation grep plus known write sites (`fix_plan.md:158-163`). This is actionable enough to prevent post-deploy mixed-case writes from bypassing restore lookup.

4. Redeem route explicit rate limit + router test — resolved. The plan explicitly registers `POST /api/v1/premium/redeem` with `StrictMiddleware("redeem", 10, 60)` and requires router tests for both the rate-limited and nil-rate-limiter branches (`fix_plan.md:174`). That closes the previously implicit route-coverage gap.

5. W1.4 nested invoice `payment_intent` — resolved. W1.4 adds both the top-level `payment_intent` field and the nested `payments.data[0].payment.payment_intent` parse path via `effectivePaymentIntent()`, with fixture coverage for both shapes (`fix_plan.md:190-193`). The nested path matches Stripe's current Invoice Payments shape.

6. W1.4 AutoMigrate index not `CONCURRENTLY` — resolved. The deploy-risk section now explicitly calls out that GORM AutoMigrate will create regular indexes, adds a pre-deploy `SELECT count(*) FROM invoices` gate, accepts the lock only under 10k rows, and requires manual `CREATE INDEX CONCURRENTLY` before AutoMigrate at or above 10k (`fix_plan.md:225-230`). This is concrete and operationally usable.

## Remaining issues (if any)
None. I also re-read W1.1 and did not find a new blocker in the semiannual expiry fix/test plan (`fix_plan.md:121-133`).

## Final recommendation
proceed-to-impl

REVIEW_COMPLETE
