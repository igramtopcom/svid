-- Migration: add crash_logs table for Windows/Linux crash reporting
-- Run this in the Supabase SQL editor or via psql.
-- See: memory/plans/plan_16.6_firebase_crashlytics_integration.md Section 3

CREATE TABLE IF NOT EXISTS crash_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  platform TEXT NOT NULL,           -- 'windows' | 'linux'
  app_version TEXT NOT NULL,
  error_message TEXT NOT NULL,
  stack_trace TEXT,
  device_info JSONB,                -- { "os_version": "..." }
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE crash_logs ENABLE ROW LEVEL SECURITY;

-- Users can only insert their own logs (or anonymous logs with null user_id)
CREATE POLICY "Users can insert own crash logs" ON crash_logs
  FOR INSERT WITH CHECK (user_id = auth.uid() OR user_id IS NULL);

-- Service role (dashboard / backend) can read all logs
CREATE POLICY "Service role reads all crash logs" ON crash_logs
  FOR SELECT USING (true);
