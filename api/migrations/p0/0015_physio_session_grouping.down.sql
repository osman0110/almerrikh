ALTER TABLE physio_sessions
    DROP INDEX idx_physio_group,
    DROP COLUMN session_group_id;
