-- P0 0016
-- Purpose: optional free-text title for a physio/massage session (e.g.
-- "جلسة تدليك ما قبل المباراة"), shown wherever the session appears —
-- physiotherapist dashboard, the shared club Sessions list, notifications.
-- Falls back to session_reason/treatment_type in the UI when left blank.
-- Lock risk: single nullable column on an existing table.

ALTER TABLE physio_sessions
    ADD COLUMN session_name VARCHAR(150) NULL AFTER session_group_id;
