-- Restores archived rows. If new rows now occupy the same logical key, review
-- conflicts before running; this rollback intentionally drops unique keys first.
ALTER TABLE player_rpe
    DROP INDEX uq_rpe_idempotency,
    DROP INDEX uq_rpe_logical_key;

UPDATE player_rpe
SET logical_key = archived_logical_key,
    archived_logical_key = NULL,
    is_active_record = 1,
    archived_at = NULL,
    replaced_by_rpe_id = NULL
WHERE is_active_record = 0
  AND archived_logical_key IS NOT NULL;
