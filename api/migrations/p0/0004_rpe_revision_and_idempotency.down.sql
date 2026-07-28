DROP TABLE IF EXISTS player_rpe_revisions;
ALTER TABLE player_rpe
    DROP INDEX idx_rpe_idempotency,
    DROP INDEX idx_rpe_logical_active,
    DROP COLUMN replaced_by_rpe_id,
    DROP COLUMN archived_at,
    DROP COLUMN is_active_record,
    DROP COLUMN revision_number,
    DROP COLUMN source_type,
    DROP COLUMN idempotency_key,
    DROP COLUMN archived_logical_key,
    DROP COLUMN logical_key;
