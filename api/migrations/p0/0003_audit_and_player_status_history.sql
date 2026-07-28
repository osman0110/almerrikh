-- P0 0003
-- Purpose: fitness audit context and period-correct player availability.
-- No historical status is invented by this migration.

ALTER TABLE audit_logs
    ADD COLUMN club_id INT NULL AFTER changed_by_user_id,
    ADD COLUMN player_id VARCHAR(64) NULL AFTER club_id,
    ADD COLUMN operation VARCHAR(80) NULL AFTER player_id,
    ADD COLUMN reason VARCHAR(500) NULL AFTER operation,
    ADD COLUMN ip_address VARCHAR(45) NULL AFTER reason,
    ADD COLUMN device_info VARCHAR(255) NULL AFTER ip_address,
    ADD COLUMN operation_id VARCHAR(100) NULL AFTER device_info,
    ADD INDEX idx_audit_club_operation (club_id, operation, created_at),
    ADD INDEX idx_audit_operation_id (operation_id);

-- Keep this separate from the legacy player_status_history change log, whose
-- columns are old_status/new_status/changed_at.
CREATE TABLE IF NOT EXISTS player_status_periods (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id INT NOT NULL,
    player_id VARCHAR(64) NOT NULL,
    status VARCHAR(30) NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    reason VARCHAR(500) NULL,
    recorded_by INT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_player_status_period (player_id, effective_from, effective_to),
    INDEX idx_player_status_club (club_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Validation
SELECT COUNT(*) AS overlapping_periods
FROM player_status_periods a
JOIN player_status_periods b
  ON a.player_id = b.player_id
 AND a.id < b.id
 AND a.effective_from <= COALESCE(b.effective_to, '9999-12-31')
 AND b.effective_from <= COALESCE(a.effective_to, '9999-12-31');
