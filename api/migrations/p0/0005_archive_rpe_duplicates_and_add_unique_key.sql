-- P0 0005 - MANUAL APPROVAL REQUIRED
-- Preconditions:
--   1) Run api/migrations/p0/preflight_data_audit.sql.
--   2) Export the duplicate detail result.
--   3) Approve the keep/archive decisions.
-- Policy: keep the newest valid row per logical_key; archive, never delete.
-- Rollback is provided in the matching down file.

CREATE TEMPORARY TABLE p0_rpe_keep AS
SELECT logical_key, id AS keep_id
FROM (
    SELECT
        r.*,
        COUNT(*) OVER (PARTITION BY logical_key) AS duplicate_count,
        ROW_NUMBER() OVER (
            PARTITION BY logical_key
            ORDER BY
                (
                    rpe_score BETWEEN 1 AND 10
                    AND COALESCE(
                        CASE WHEN completed_full_session = 0 THEN actual_duration_minutes END,
                        duration_minutes
                    ) BETWEEN 1 AND 480
                ) DESC,
                submitted_at DESC,
                id DESC
        ) AS keep_rank
    FROM player_rpe r
    WHERE logical_key IS NOT NULL AND is_active_record = 1
) ranked
WHERE duplicate_count > 1 AND keep_rank = 1;

INSERT INTO audit_logs
    (entity_type, entity_id, field_name, old_value, new_value, changed_by_user_id,
     club_id, player_id, operation, reason, operation_id)
SELECT
    'player_rpe', CAST(r.id AS CHAR), 'is_active_record', '1', '0', 0,
    r.club_id, r.linked_player_id, 'rpe.duplicate_archived',
    'P0 duplicate consolidation; newest row retained',
    CONCAT('P0-RPE-DEDUP-', k.keep_id)
FROM player_rpe r
JOIN p0_rpe_keep k ON k.logical_key = r.logical_key
WHERE r.id <> k.keep_id AND r.is_active_record = 1;

UPDATE player_rpe r
JOIN p0_rpe_keep k ON k.logical_key = r.logical_key
SET r.is_active_record = 0,
    r.archived_at = NOW(),
    r.replaced_by_rpe_id = k.keep_id,
    r.archived_logical_key = r.logical_key,
    r.logical_key = NULL
WHERE r.id <> k.keep_id AND r.is_active_record = 1;

DROP TEMPORARY TABLE p0_rpe_keep;

ALTER TABLE player_rpe
    ADD UNIQUE KEY uq_rpe_logical_key (logical_key),
    ADD UNIQUE KEY uq_rpe_idempotency (club_id, idempotency_key);

-- Validation: both must return zero.
SELECT COUNT(*) AS remaining_active_duplicate_groups
FROM (
    SELECT logical_key
    FROM player_rpe
    WHERE logical_key IS NOT NULL AND is_active_record = 1
    GROUP BY logical_key
    HAVING COUNT(*) > 1
) duplicates;

SELECT COUNT(*) AS archived_without_replacement
FROM player_rpe
WHERE is_active_record = 0 AND replaced_by_rpe_id IS NULL;
