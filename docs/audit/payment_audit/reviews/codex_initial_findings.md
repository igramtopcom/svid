## [CRITICAL] Public restore returns license keys by email alone
File: /projects/svid_app/backend/internal/premium/handler/premium_handler.go:685
Trigger: Call `POST /api/v1/premium/web-restore` with a customer's email and omit `device_id`; the handler sets `deviceID := uuid.Nil`, and `PremiumService.RestoreLicense` only checks device ownership when the provided ID is non-nil.
Impact: Anyone who knows or guesses a customer email can retrieve the bearer license key and activate premium on another device if slots remain.
Fix: Do not return license keys from a public email-only flow. Require an email challenge/magic link, or require the authenticated device ID from middleware and make `PremiumService.RestoreLicense` reject `uuid.Nil`.

## [CRITICAL] Public Billing Portal access is granted by email alone
File: /projects/svid_app/backend/internal/premium/service/stripe_service.go:515
Trigger: Call `POST /api/v1/premium/web-portal` with a customer's email; `CreatePortalSessionByEmail` finds the active license by email and returns a live Stripe Billing Portal session without proving mailbox or device ownership.
Impact: An attacker can obtain a bearer portal URL for the customer and manage or cancel the subscription, and may expose billing/account details.
Fix: Gate portal creation behind an email verification link or authenticated device already registered to the license. Do not mint Stripe portal sessions from email alone.

## [HIGH] Crypto checkout can create zero-dollar invoices for unsupported plans
File: /projects/svid_app/backend/internal/premium/service/crypto_service.go:110
Trigger: Submit a crypto invoice request for a billing cycle allowed by the DTO but unsupported for the resolved brand, such as Svid `semiannual` or VidCombo `lifetime1`; `AmountCentsForBillingCycle` returns `0`, and `CreateInvoice` formats and sends `0.00` USD to BTCPay.
Impact: If BTCPay accepts or an operator settles the zero-amount invoice, the later status check grants a premium or lifetime license for no money; otherwise users get broken invoice attempts instead of a validation error.
Fix: Reject `amountCents <= 0` before calling BTCPay and apply the same brand-specific billing-cycle whitelist used by the Stripe price resolver.

## [HIGH] Subscription refunds and chargebacks cannot map renewal invoice payments
File: /projects/svid_app/backend/internal/premium/handler/webhook_handler.go:405
Trigger: Stripe sends `charge.refunded` or `charge.dispute.created` for a subscription renewal invoice, or for any subscription payment whose PaymentIntent was only present on the invoice; the handler calls `RevokeLicenseByPaymentIntent`, but renewal invoice PaymentIntents are never stored in `payment_transactions`.
Impact: Full refunds or chargebacks can be silently skipped as "not our charge", leaving premium access and paid revenue intact after a reversed subscription payment.
Fix: Parse and persist invoice PaymentIntent/charge IDs on `invoice.paid`, create or update renewal payment records, and resolve refund/dispute webhooks by charge, invoice, subscription, and PaymentIntent rather than checkout transactions only.

## [HIGH] Concurrent duplicate webhooks can process the same event twice
File: /projects/svid_app/backend/internal/premium/repository/webhook_event_repository.go:43
Trigger: Two deliveries of the same Stripe event arrive while the first is still running; the second sees the row in `processing`, immediately "reclaims" it, returns `true`, and runs the handler concurrently.
Impact: Non-idempotent handlers such as renewal `invoice.paid` can extend a license twice for one paid invoice; refund and cancellation handlers can also race into conflicting state.
Fix: Treat `processing` as already claimed unless it is stale by a clear timeout. Reclaim only `failed` or stale rows with an atomic conditional update and a `processing_started_at` timestamp.

## [HIGH] Portal plan-change invoices are treated as full renewals
File: /projects/svid_app/backend/internal/premium/handler/webhook_handler.go:229
Trigger: A customer changes plans in Stripe Billing Portal and Stripe emits a paid proration or `subscription_update` invoice; `handleInvoicePaid` extends entitlement for every non-`subscription_create` invoice using the old local `license.BillingCycle`, while `customer.subscription.updated` never syncs the new price or plan.
Impact: A prorated upgrade/downgrade can grant a full extra billing period or leave device limits and future expiry math on the wrong plan.
Fix: Extend only for true renewal invoices, such as `billing_reason == "subscription_cycle"`, and set local `BillingCycle`, device limits, and `ExpiresAt` from Stripe subscription items and invoice period end.

## [HIGH] License activation does not enforce brand isolation
File: /projects/svid_app/backend/internal/premium/service/premium_service.go:122
Trigger: An authenticated device from one brand submits a valid license key issued for the other brand; `VerifyLicense` looks up the key and registers the device without comparing `license.Brand` to the authenticated device brand.
Impact: Svid and VidCombo entitlements can be used across products despite separate prices and plans, creating underpayment and brand/revenue contamination.
Fix: Pass the authenticated device brand into `VerifyLicense` or load it inside the service, then reject any license whose brand does not match before registering `license_devices`.

## [MEDIUM] VidCombo subscriptions cannot be cancelled with valid VidCombo keys
File: /projects/svid_app/backend/internal/premium/dto/premium_request.go:16
Trigger: A VidCombo customer posts to `/api/v1/premium/stripe/cancel` with a valid `VIDCOMBO-...` license key; the key format is 48 characters, but `CancelRequest` requires `min=45,max=45`.
Impact: VidCombo users are blocked by validation before `StripeCancel` runs, so they may continue being billed until support or Stripe portal intervention.
Fix: Replace the fixed 45-character validator with a prefix-aware license-key validator, or allow the full known range for Svid and VidCombo keys.

AUDIT_COMPLETE
