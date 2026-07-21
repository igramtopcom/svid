-- Phase 17 Supabase Setup
-- Task 17.4: Cross-Device Preferences & Bookmarks Sync
-- Run this in the Supabase SQL editor for project axfohdwwtzglttorukrh

-- user_preferences: key-value store for syncing settings
CREATE TABLE user_preferences (
  user_id UUID REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  key TEXT NOT NULL,
  value JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, key)
);
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users can manage own preferences"
  ON user_preferences FOR ALL USING (auth.uid() = user_id);
CREATE INDEX idx_prefs_user_updated ON user_preferences(user_id, updated_at);

-- bookmarked_channels: synced bookmark list (mirrors local Drift table)
CREATE TABLE bookmarked_channels (
  user_id UUID REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  channel_url TEXT NOT NULL,
  channel_name TEXT NOT NULL,
  latest_video_id TEXT,
  notify_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_checked_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, channel_url)
);
ALTER TABLE bookmarked_channels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users can manage own bookmarks"
  ON bookmarked_channels FOR ALL USING (auth.uid() = user_id);
CREATE INDEX idx_bookmarks_user_updated ON bookmarked_channels(user_id, updated_at);
