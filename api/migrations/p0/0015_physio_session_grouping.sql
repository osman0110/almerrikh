-- P0 0015
-- Purpose: link the per-player rows a single "group physio session" booking
-- creates (one row per player, sharing scheduled_at/room/therapist) via a
-- shared session_group_id, so the app can present/manage them as ONE
-- session with a player roster instead of N unrelated rows. NULL for
-- sessions booked individually — untouched by this migration.
-- Lock risk: single nullable column + index on an existing table.

ALTER TABLE physio_sessions
    ADD COLUMN session_group_id VARCHAR(40) NULL AFTER created_by_user_id,
    ADD INDEX idx_physio_group (session_group_id);
