## Verdict
push-to-main

## Plan-vs-impl deltas
- Old public `POST /api/v1/premium/web-restore` leak: ✓ fixed. `WebRestoreLicense` now delegates to `issueMagicLink(c, service.ScopeRestore)` and no longer returns a license key directly (`backend/internal/premium/handler/premium_handler.go:744`).

- Old public `POST /api/v1/premium/web-portal` leak: ✓ fixed. `WebPortalSession` now delegates to `issueMagicLink(c, service.ScopePortal)` and no longer calls `CreatePortalSessionByEmail` (`backend/internal/premium/handler/premium_handler.go:908`). The route paths remain registered for compatibility, but their behavior is now magic-link issuance.

- Async issuance context: ✓ fixed for the original bug. The goroutine now creates `context.WithTimeout(context.Background(), 30*time.Second)` instead of capturing `c.Request.Context()` after the handler returns (`backend/internal/premium/handler/premium_handler.go:805`). FYI: that context currently bounds Redis calls; the repository lookup and SMTP sender are not context-aware.

- Redeem active-window checks: ✓ fixed. `MagicLinkService.Redeem` now rejects non-premium, `CancelledAt != nil`, and expired non-lifetime licenses before returning a license key or portal URL (`backend/internal/premium/service/magiclink_service.go:274`).

- Won-dispute auto-renew restore: ✓ fixed for the stated policy. `restoreLicenseByID` now sets `IsAutoRenew=true` for non-lifetime licenses with a Stripe subscription ID (`backend/internal/premium/service/premium_service.go:1164`), and the integration test asserts it (`backend/internal/premium/handler/refund_dispute_integration_test.go:378`).

- Empty-PI dispute handling: ✓ fixed. `charge.dispute.created` resolves `dispute.charge` through `chargeResolver` and uses the resolved PaymentIntent for the invoice fallback revoke; resolver errors or empty PI results return an error so Stripe retries (`backend/internal/premium/handler/webhook_handler.go:719`). `charge.dispute.closed` also attempts the resolver before restore (`backend/internal/premium/handler/webhook_handler.go:819`).

- W1.4 dispute orphan-invoice coverage: ✓ added. `TestWebhook_ChargeDispute_InvoiceFallback_OrphanInvoice` covers the `invoice -> subscription_id -> license` revoke leg (`backend/internal/premium/handler/refund_dispute_integration_test.go:167`).

- Empty-PI resolver tests: ✓ added for dispute-created success and resolver-empty failure (`backend/internal/premium/handler/refund_dispute_integration_test.go:252`, `backend/internal/premium/handler/refund_dispute_integration_test.go:304`).

- Per-email rate-limit response deviation: ✓ acceptable. Keeping the HTTP response as `200 {"sent":true}` while suppressing sends preserves the enumeration-resistance invariant better than a per-email 429.

- Transaction status update failure after revoke: ✓ acceptable as an explicit tradeoff. The license mutation is the security-critical operation; swallowing the audit/status update failure avoids Stripe retry noise against an already-revoked license.

## Production bugs introduced (if any)
- No new blocking production bug found in `f676f706`.

- FYI: `WebPortalSession`'s Swagger comments still describe the old direct portal URL behavior and old failure shapes (`backend/internal/premium/handler/premium_handler.go:895`). This is not a runtime leak, but update it before regenerating public API docs.

- FYI: the new 30s context does not actually bound SMTP `SendMail` or the Gorm lookup because those dependencies do not accept the context. This is not a regression from the round-1 critical, but the comment overstates the guarantee.

- Consider: blindly restoring `IsAutoRenew=true` for any non-lifetime Stripe subscription may overcorrect if the customer had already scheduled cancellation before the dispute. If preserving that edge state matters, restore the previous value or query Stripe subscription state before setting it.

## Test gaps
- Accepted gap: no backfill tool tests. Deferred with a reasonable rationale because the tool defaults to dry-run and Stripe API mocking would be additional infrastructure.

- Accepted gap: no nil-rate-limiter router test for the new routes. The old route handlers now point at the secured behavior, which was the blocker.

- Accepted gap: no per-email 429 response test because the planned 429 semantics were intentionally rejected in favor of `200 {"sent":true}` enumeration resistance.

- Accepted gap: admin-create expiry integration test still uses a tolerance window. The shared `AddBillingCycleToTime` helper has exact unit coverage, so this is not a blocker.

- Remaining useful follow-ups: add direct route tests proving `/premium/web-restore` and `/premium/web-portal` return `sent:true`, add portal magic-link redemption coverage, add redeem rejection tests for `CancelledAt` and expired licenses, and add a won-dispute empty-PI resolver test.

## W1 punch list
- W1.2/W1.3 old `/premium/web-restore` converted to magic-link issuance: ✓ done.

- W1.2/W1.3 old `/premium/web-portal` converted to magic-link issuance: ✓ done.

- W1.2/W1.3 async issuance no longer uses canceled request context: ✓ done.

- W1.2/W1.3 redeem rejects revoked/cancelled/expired licenses: ✓ done.

- W1.2/W1.3 per-email rate-limit returns generic `sent:true`: ✓ accepted plan deviation.

- W1.4 dispute orphan-invoice fallback: ✓ done.

- W1.4 empty-PI dispute charge retrieval path: ✓ done.

- W1.4 won-dispute restore auto-renew assertion: ✓ done.

- W1.4 transaction status update failure remains logged-only: ✓ accepted plan deviation.

## Verification
- Reviewed `git diff 2bd66849..f676f706 -- backend/`.
- Ran `git diff --check 2bd66849..f676f706 -- backend/`: passed.
- Could not run Go tests locally: `go` is not installed in this environment (`/bin/bash: go: command not found`).

## Final recommendation
Push `f676f706` to main after normal backend CI/test-webhook verification in an environment with Go installed.

REVIEW_COMPLETE
