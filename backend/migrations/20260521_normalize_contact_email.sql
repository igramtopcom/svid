-- Migration: normalize contact_email to lowercase + trim across
-- premium_licenses + invoices tables.
--
-- Why: Round 4 ultra-review found that Stripe webhook handlers were writing
-- raw user-typed casing to contact_email columns, while RestoreLicense
-- lookup expected lowercase. Pre-Round-4 rows may carry mixed case,
-- silently failing /premium/restore for ~165 SSvid customers.
--
-- After this migration, all existing rows are normalized AND a functional
-- index is created so the new case-insensitive WHERE clauses in
-- FindActiveByEmail / FindByEmail use the index (else they fall back to
-- seq scan as the table grows beyond ~5k rows).
--
-- Apply order:
--   1. Deploy backend code containing webhook + repo normalizations.
--   2. Run this migration (idempotent — re-runnable safely).
--   3. Run γ-ETL to populate VidCombo legacy rows.
--   4. Smoke: random-sample 20 emails to confirm restore works.
--
-- Idempotency: the WHERE clauses skip rows already normalized. Re-running
-- after a partial application is safe.

BEGIN;

-- premium_licenses: normalize contact_email on existing rows.
UPDATE premium_licenses
SET    contact_email = LOWER(TRIM(contact_email)),
       updated_at    = NOW()
WHERE  contact_email IS NOT NULL
  AND  contact_email <> LOWER(TRIM(contact_email));

-- invoices: normalize contact_email for admin search consistency.
UPDATE invoices
SET    contact_email = LOWER(TRIM(contact_email)),
       updated_at    = NOW()
WHERE  contact_email IS NOT NULL
  AND  contact_email <> ''
  AND  contact_email <> LOWER(TRIM(contact_email));

-- Functional index so the new repo predicates use index scan, not seq scan.
-- Safe under CONCURRENTLY (won't block writes) but the wrapping transaction
-- forbids it — drop the BEGIN/COMMIT and re-add `CONCURRENTLY` for prod
-- runs against >100k row tables. For ~5k rows the locking index build is
-- sub-second.
CREATE INDEX IF NOT EXISTS idx_premium_licenses_contact_email_lower
    ON premium_licenses (LOWER(TRIM(contact_email)))
    WHERE contact_email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_contact_email_lower
    ON invoices (LOWER(TRIM(contact_email)))
    WHERE contact_email IS NOT NULL AND contact_email <> '';

COMMIT;

-- Verification queries (run AFTER commit):
--   SELECT COUNT(*) FROM premium_licenses
--     WHERE contact_email IS NOT NULL
--       AND contact_email <> LOWER(TRIM(contact_email));
--   -- Expect 0.
--
--   SELECT COUNT(*) FROM invoices
--     WHERE contact_email IS NOT NULL AND contact_email <> ''
--       AND contact_email <> LOWER(TRIM(contact_email));
--   -- Expect 0.
--
--   EXPLAIN ANALYZE
--   SELECT * FROM premium_licenses
--   WHERE LOWER(TRIM(contact_email)) = 'customer@example.com'
--     AND tier = 'premium'
--   ORDER BY created_at DESC LIMIT 1;
--   -- Expect: Index Scan using idx_premium_licenses_contact_email_lower.
