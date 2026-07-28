-- ============================================================
-- Live server migration v1 — Unified API Contract
-- Run once on nextkick.me database (idempotent).
-- ============================================================

-- users: add missing columns (IF NOT EXISTS guards idempotency)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS player_type      VARCHAR(20)  NULL,
  ADD COLUMN IF NOT EXISTS club_user_id     INT          NULL,
  ADD COLUMN IF NOT EXISTS linked_player_id VARCHAR(64)  NULL,
  ADD COLUMN IF NOT EXISTS trial_started_at DATETIME     NULL,
  ADD COLUMN IF NOT EXISTS trial_ends_at    DATETIME     NULL;

-- Backfill role from account_type if role column missing / live uses account_type
-- Safe: only updates rows where role IS NULL
UPDATE users
  SET role = account_type
  WHERE role IS NULL
    AND account_type IS NOT NULL;

-- Backfill name from full_name if name column missing / live uses full_name
UPDATE users
  SET name = full_name
  WHERE (name IS NULL OR name = '')
    AND full_name IS NOT NULL
    AND full_name != '';

-- players → club_players compat: if live uses 'players' table add player_type + linked_user_id
-- Replace 'players' with your actual table name if different.
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS player_type   VARCHAR(20) DEFAULT 'club',
  ADD COLUMN IF NOT EXISTS linked_user_id INT         NULL;

-- club_invites: needed for invite flow
CREATE TABLE IF NOT EXISTS club_invites (
    code            VARCHAR(16)  PRIMARY KEY,
    club_user_id    INT          NOT NULL,
    team_name       VARCHAR(100) NULL,
    player_name     VARCHAR(255) NULL,
    note            TEXT         NULL,
    expires_at      TIMESTAMP    NULL,
    used_at         TIMESTAMP    NULL,
    used_by_user_id INT          NULL,
    player_id       VARCHAR(64)  NULL,
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- user_tokens: needed for bearer token auth
CREATE TABLE IF NOT EXISTS user_tokens (
    token      VARCHAR(64) PRIMARY KEY,
    user_id    INT         NOT NULL,
    created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_tokens_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- system_meta: migration guard
CREATE TABLE IF NOT EXISTS system_meta (
    key_name   VARCHAR(64) PRIMARY KEY,
    value      TEXT        NOT NULL,
    updated_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO system_meta (key_name, value) VALUES ('live_migration_v1', '1');
