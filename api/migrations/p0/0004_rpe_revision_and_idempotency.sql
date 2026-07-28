-- P0 0004
-- Purpose: logical identity, idempotent writes, revisions and reversible archive.
-- This migration does not archive or delete duplicates and adds no unique key.

ALTER TABLE player_rpe
    ADD COLUMN logical_key VARCHAR(255) NULL AFTER id,
    ADD COLUMN archived_logical_key VARCHAR(255) NULL AFTER logical_key,
    ADD COLUMN idempotency_key VARCHAR(100) NULL AFTER archived_logical_key,
    ADD COLUMN source_type VARCHAR(30) NOT NULL DEFAULT 'post' AFTER idempotency_key,
    ADD COLUMN revision_number INT UNSIGNED NOT NULL DEFAULT 1 AFTER source_type,
    ADD COLUMN is_active_record TINYINT(1) NOT NULL DEFAULT 1 AFTER revision_number,
    ADD COLUMN archived_at DATETIME NULL AFTER is_active_record,
    ADD COLUMN replaced_by_rpe_id INT NULL AFTER archived_at,
    ADD INDEX idx_rpe_logical_active (logical_key, is_active_record),
    ADD INDEX idx_rpe_idempotency (club_id, idempotency_key);

CREATE TABLE IF NOT EXISTS player_rpe_revisions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    player_rpe_id INT NOT NULL,
    revision_number INT UNSIGNED NOT NULL,
    old_values_json JSON NOT NULL,
    changed_by_user_id INT NOT NULL,
    reason VARCHAR(500) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_rpe_revision_record (player_rpe_id, revision_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE player_rpe
SET source_type = COALESCE(NULLIF(rpe_type, ''), 'post'),
    logical_key = CASE
        WHEN COALESCE(session_id, training_session_id) IS NOT NULL THEN CONCAT(
            IF(linked_player_id IS NOT NULL, CONCAT('p:', linked_player_id), CONCAT('u:', user_id)),
            '|session:', COALESCE(session_id, training_session_id),
            '|rpe:', COALESCE(NULLIF(rpe_type, ''), 'post')
        )
        ELSE CONCAT(
            IF(linked_player_id IS NOT NULL, CONCAT('p:', linked_player_id), CONCAT('u:', user_id)),
            '|date:', DATE(submitted_at),
            '|activity:', COALESCE(NULLIF(session_type, ''), 'unspecified'),
            '|external:default|rpe:', COALESCE(NULLIF(rpe_type, ''), 'post')
        )
    END
WHERE logical_key IS NULL;

-- Validation: must be reviewed before 0005.
SELECT logical_key, COUNT(*) AS duplicate_count, MIN(id) AS oldest_id, MAX(id) AS newest_id
FROM player_rpe
WHERE logical_key IS NOT NULL AND is_active_record = 1
GROUP BY logical_key
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
