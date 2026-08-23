-- Durable activity clocks for coach/admin-operated sessions and matches.
-- Run this migration before deploying the matching API and Flutter changes.

ALTER TABLE club_sessions
    ADD COLUMN actual_started_at DATETIME NULL,
    ADD COLUMN actual_ended_at DATETIME NULL;

ALTER TABLE session_attendance
    ADD COLUMN timer_started_at DATETIME NULL,
    ADD COLUMN timer_ended_at DATETIME NULL,
    ADD COLUMN elapsed_seconds INT NOT NULL DEFAULT 0;

ALTER TABLE matches
    ADD COLUMN actual_started_at DATETIME NULL,
    ADD COLUMN actual_ended_at DATETIME NULL;

ALTER TABLE match_participations
    ADD COLUMN timer_started_at DATETIME NULL,
    ADD COLUMN accumulated_seconds INT NOT NULL DEFAULT 0;
