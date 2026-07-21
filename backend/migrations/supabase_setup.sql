-- =============================================================================
-- Svid App — Supabase Schema Setup
-- Run this in: Supabase Dashboard → SQL Editor → New Query → Run
-- =============================================================================

-- =============================================
-- TABLE: download_history
-- Stores per-user download sync records.
-- Sensitive fields (url, thumbnail) are AES-encrypted
-- client-side before upload.
-- =============================================

CREATE TABLE IF NOT EXISTS download_history (
  id            TEXT PRIMARY KEY,           -- composite: "{user_id}-{local_id}"
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  url           TEXT NOT NULL,              -- encrypted (FieldEncryptor XOR+HMAC-SHA256)
  filename      TEXT NOT NULL,
  platform      TEXT NOT NULL,              -- e.g. "youtube", "tiktok"
  total_bytes   BIGINT NOT NULL DEFAULT 0,
  status        TEXT NOT NULL,              -- pending/downloading/completed/failed/cancelled
  thumbnail     TEXT,                       -- encrypted, nullable
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_download_history_user_id
  ON download_history(user_id);

CREATE INDEX IF NOT EXISTS idx_download_history_updated_at
  ON download_history(user_id, updated_at DESC);

-- =============================================
-- RLS: download_history
-- Users can only access their own records.
-- =============================================

ALTER TABLE download_history ENABLE ROW LEVEL SECURITY;

-- SELECT: user sees only own rows
CREATE POLICY "Users can select own download history"
  ON download_history FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT: user can insert rows for themselves only
CREATE POLICY "Users can insert own download history"
  ON download_history FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: user can update their own rows
CREATE POLICY "Users can update own download history"
  ON download_history FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: user can delete their own rows
CREATE POLICY "Users can delete own download history"
  ON download_history FOR DELETE
  USING (auth.uid() = user_id);

-- =============================================
-- TABLE: user_subscriptions
-- Tracks payment plan per user (Stripe / Crypto).
-- =============================================

CREATE TABLE IF NOT EXISTS user_subscriptions (
  id                      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  plan                    TEXT NOT NULL DEFAULT 'free',   -- 'free' | 'pro' | 'lifetime'
  status                  TEXT NOT NULL DEFAULT 'active', -- 'active' | 'cancelled' | 'expired'
  stripe_customer_id      TEXT,
  stripe_subscription_id  TEXT,
  current_period_end      TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================
-- RLS: user_subscriptions
-- Users can read their own subscription.
-- Only service_role (backend) can write.
-- =============================================

ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;

-- SELECT: user sees only their own subscription row
CREATE POLICY "Users can select own subscription"
  ON user_subscriptions FOR SELECT
  USING (auth.uid() = id);

-- INSERT/UPDATE/DELETE: restricted to service_role (Stripe webhook, Edge Functions)
-- No public policies — writes happen server-side only.

-- =============================================
-- FUNCTION: auto-create free subscription on signup
-- Triggered when a new user registers.
-- =============================================

CREATE OR REPLACE FUNCTION handle_new_user_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO user_subscriptions (id, plan, status)
  VALUES (NEW.id, 'free', 'active')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user_subscription();

-- =============================================================================
-- VERIFICATION QUERIES (run after setup to confirm):
-- =============================================================================
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
-- SELECT policyname FROM pg_policies WHERE tablename = 'download_history';
-- SELECT policyname FROM pg_policies WHERE tablename = 'user_subscriptions';
-- =============================================================================
