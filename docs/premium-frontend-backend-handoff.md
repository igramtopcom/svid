# Premium Frontend → Backend Handoff

> Generated 2026-03-25 after Premium Flow Redesign (Phases 0-6) completed.
> Frontend: Flutter 3.29 · Backend: Go + Gin + PostgreSQL + Redis
> Base URL: `https://api.ssvid.app/api/v1`

---

## API Contract

All endpoints require `X-API-Key: snk_...` header (except `/devices/register`).
Standard response envelope: `{ "success": bool, "data": {...}, "error": { "code": "UPPER_SNAKE", "message": "..." } }`

### Endpoints

| # | Endpoint | Method | Purpose |
|---|----------|--------|---------|
| 1 | `/premium/plans` | GET | Fetch Stripe pricing (5 billing cycles) |
| 2 | `/premium/stripe/checkout` | POST | Create Stripe Checkout session |
| 3 | `/premium/stripe/verify` | GET | Poll Stripe payment result |
| 4 | `/premium/stripe/cancel` | POST | Cancel recurring subscription |
| 5 | `/premium/crypto/invoice` | POST | Create BTCPay invoice |
| 6 | `/premium/crypto/status` | GET | Poll blockchain confirmations |
| 7 | `/premium/licenses/verify` | GET | Verify license validity (7-day interval) |
| 8 | `/premium/restore` | POST | Restore license by purchase email |
| 9 | `/devices/register` | POST | Register device (auto-recovery on 401) |

---

## 1. Pricing Plans

```
GET /premium/plans
→ 200:
{
  "success": true,
  "data": [
    { "billingCycle": "monthly",   "amountCents": 799,  "currency": "usd", "interval": "month",    "maxDevices": 5,  "isLifetime": false },
    { "billingCycle": "yearly",    "amountCents": 2999, "currency": "usd", "interval": "year",     "maxDevices": 5,  "isLifetime": false },
    { "billingCycle": "lifetime1", "amountCents": 4999, "currency": "usd", "interval": "one_time", "maxDevices": 1,  "isLifetime": true  },
    { "billingCycle": "lifetime2", "amountCents": 7999, "currency": "usd", "interval": "one_time", "maxDevices": 3,  "isLifetime": true  },
    { "billingCycle": "lifetime3", "amountCents": 9900, "currency": "usd", "interval": "one_time", "maxDevices": 10, "isLifetime": true  }
  ]
}
```

Frontend has hardcoded fallback if this endpoint is unreachable. Stripe Dashboard is source of truth for prices.

## 2. Stripe Checkout

```
POST /premium/stripe/checkout
Body: { "billingCycle": "monthly", "idempotencyKey": "uuid-v4" }
→ 200:
{
  "success": true,
  "data": {
    "sessionId": "cs_live_...",
    "checkoutUrl": "https://checkout.stripe.com/...",
    "expiresAt": "2026-03-25T12:30:00Z"
  }
}
```

Frontend opens `checkoutUrl` in default browser. User completes payment on Stripe.

## 3. Stripe Verify (Polling)

```
GET /premium/stripe/verify?sessionId=cs_live_...
→ 200 (pending):
{ "success": true, "data": { "status": "pending" } }

→ 200 (completed):
{
  "success": true,
  "data": {
    "status": "completed",
    "licenseKey": "SSVID-a1b2-c3d4-e5f6-7890-abcd-ef01-2345-6789",
    "expiresAt": "2027-03-25T00:00:00Z",
    "billingCycle": "monthly",
    "paymentMethod": "stripe",
    "transactionId": "pi_..."
  }
}

→ 200 (failed):
{ "success": true, "data": { "status": "failed", "errorMessage": "Card declined" } }
```

Frontend polls every 2-10s (exponential backoff), max 30 attempts.

## 4. Stripe Cancel

```
POST /premium/stripe/cancel
Body: { "licenseKey": "SSVID-..." }
→ 200: { "success": true, "data": {} }
```

Marks subscription for end-of-period cancellation (not immediate).

## 5. Crypto Invoice

```
POST /premium/crypto/invoice
Body: { "currency": "BTC", "billingCycle": "yearly", "idempotencyKey": "uuid-v4" }
→ 200:
{
  "success": true,
  "data": {
    "invoiceId": "btcpay_inv_...",
    "currency": "BTC",
    "amount": "0.00045",
    "address": "bc1q...",
    "paymentUri": "bitcoin:bc1q...?amount=0.00045",
    "confirmations": 0,
    "expiresAt": "2026-03-25T12:30:00Z",
    "createdAt": "2026-03-25T12:00:00Z"
  }
}
```

Currencies: `BTC` (1 confirmation), `LTC` (3 confirmations), `XMR` (10 confirmations).

## 6. Crypto Status (Polling)

```
GET /premium/crypto/status?invoiceId=btcpay_inv_...
→ 200 (waiting):
{ "success": true, "data": { "status": "pending", "confirmations": 0 } }

→ 200 (confirming):
{ "success": true, "data": { "status": "pending", "confirmations": 2 } }

→ 200 (completed):
{
  "success": true,
  "data": {
    "status": "completed",
    "licenseKey": "SSVID-...",
    "confirmations": 3,
    "billingCycle": "yearly",
    "expiresAt": "2027-03-25T00:00:00Z",
    "paymentMethod": "crypto",
    "transactionId": "btcpay_inv_..."
  }
}
```

Frontend polls every 5-30s (exponential backoff), max 120 attempts (~2 hours for XMR).

## 7. License Verification

```
GET /premium/licenses/verify?key=SSVID-a1b2-c3d4-...
→ 200 (valid):
{
  "success": true,
  "data": {
    "is_valid": true,
    "tier": "premium",
    "verified_at": "2026-03-25T10:00:00Z",
    "device_count": 2,
    "max_devices": 5,
    "billing_cycle": "monthly",
    "expires_at": "2026-04-25T00:00:00Z",
    "is_auto_renew": true
  }
}

→ 200 (invalid):
{
  "success": true,
  "data": {
    "is_valid": false,
    "reason": "revoked" | "expired" | "device_limit_exceeded",
    "device_count": 6,
    "max_devices": 5
  }
}
```

Frontend calls every 7 days. 30-day offline grace period if network unreachable.

## 8. License Restore

```
POST /premium/restore
Body: { "email": "user@example.com" }
→ 200 (found):
{
  "success": true,
  "data": {
    "license_key": "SSVID-...",
    "billing_cycle": "yearly",
    "expires_at": "2027-03-25T00:00:00Z",
    "message": "License restored successfully"
  }
}

→ 404:
{ "success": false, "error": { "code": "LICENSE_NOT_FOUND", "message": "No active license found for this email" } }
```

## 9. Device Registration

```
POST /devices/register
Body: {
  "hardware_id": "unique-hardware-hash",
  "os": "macos",
  "os_version": "15.3",
  "app_version": "1.1.2",
  "device_name": "MacBook Pro"
}
→ 200:
{
  "success": true,
  "data": {
    "api_key": "snk_...",
    "device_id": "uuid-v4"
  }
}
```

Auto-called on 401 `INVALID_API_KEY`. Prevents stale API key issues.

---

## License Key Format

`SSVID-[0-9A-Fa-f]{4}(-[0-9A-Fa-f]{4}){7}`

Example: `SSVID-a1b2-c3d4-e5f6-7890-abcd-ef01-2345-6789` (128-bit hex, 8 groups of 4).

## Deep Link Activation

`ssvid://activate?key=SSVID-a1b2-c3d4-...`

Registered on all 3 platforms (macOS Info.plist, Windows HKCU registry, Linux .desktop).
Frontend validates format → calls `/premium/licenses/verify` → activates locally.
If offline, activates locally and verifies on next startup.

---

## Backend CTO Tasks

### Phase 1: Verify Existing Endpoints
All 9 endpoints above should already be implemented in `snakeloader-backend/`.
Verify each endpoint matches the contract above:
- [ ] `GET /premium/plans` — returns 5 billing cycles with correct `amountCents`
- [ ] `POST /premium/stripe/checkout` — supports `idempotencyKey`
- [ ] `GET /premium/stripe/verify` — returns `licenseKey` on completed
- [ ] `POST /premium/stripe/cancel` — end-of-period cancellation
- [ ] `POST /premium/crypto/invoice` — creates BTCPay invoice with 3 currencies
- [ ] `GET /premium/crypto/status` — returns `confirmations` count
- [ ] `GET /premium/licenses/verify` — returns `is_auto_renew`, `device_count`
- [ ] `POST /premium/restore` — looks up license by email
- [ ] `POST /devices/register` — returns `api_key` with `snk_` prefix

### Phase 2: Verify Stripe Webhook
Backend receives Stripe webhooks (`checkout.session.completed`, `invoice.paid`, `customer.subscription.deleted`) and:
- Generates license key (128-bit hex, `SSVID-` prefix)
- Stores license in PostgreSQL
- Makes license available via `/premium/stripe/verify` polling endpoint
- Handles refund/dispute → revokes license

### Phase 3: Verify BTCPay Webhook
Backend receives BTCPay webhooks (`InvoiceSettled`, `InvoicePaymentSettled`) and:
- Updates confirmation count
- Generates license key on sufficient confirmations
- Makes license available via `/premium/crypto/status` polling endpoint

### Phase 4: Verify Email Restore
- `/premium/restore` must query purchase records by email
- Must return the most recent active license for that email
- Must handle multiple purchases (return latest, or most valuable tier)

### Phase 5: Test End-to-End
1. Stripe: Create checkout → complete → verify → license key returned
2. Crypto: Create invoice → send payment → confirmations → license key
3. Verify: Valid key → `is_valid: true` with all fields
4. Verify: Expired key → `is_valid: false, reason: "expired"`
5. Verify: Revoked key → `is_valid: false, reason: "revoked"`
6. Verify: Device limit → `is_valid: false, reason: "device_limit_exceeded"`
7. Restore: Valid email → license key + metadata
8. Restore: Unknown email → 404
9. Cancel: Active subscription → marks for end-of-period

---

## Frontend Source Files (for reference)

| Layer | File | Lines | Purpose |
|-------|------|-------|---------|
| Service | `data/services/stripe_payment_service.dart` | ~165 | Stripe API calls |
| Service | `data/services/crypto_payment_service.dart` | ~140 | BTCPay API calls |
| Service | `data/services/license_verification_service.dart` | ~200 | License verify logic |
| Handler | `data/services/license_activation_handler.dart` | ~100 | Deep link activation |
| Provider | `presentation/providers/payment_providers.dart` | ~390 | Payment state machine |
| Provider | `presentation/providers/premium_providers.dart` | ~120 | License state + refresh |
| Entity | `domain/entities/premium_license.dart` | ~205 | License model |
| Entity | `domain/entities/pricing_plan.dart` | ~50 | Pricing DTO |
| Entity | `domain/entities/crypto_invoice.dart` | ~66 | Invoice DTO |
| Entity | `domain/entities/payment_result.dart` | ~48 | Payment result DTO |
| Backend | `core/network/backend_client.dart` | ~250 | HTTP client + auto-recovery |
| Backend | `core/services/backend_service.dart` | ~290 | High-level backend API |
