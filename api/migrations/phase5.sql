-- Phase 5: AI Coach/Academy Plan
-- Run once (idempotent via IF NOT EXISTS guards)

-- Run via PHP helper (MySQL 5.x compatible — no IF NOT EXISTS on ALTER COLUMN)
-- php -r "require 'api/db.php'; $pdo->exec('ALTER TABLE training_plans ADD COLUMN plan_summary TEXT NULL, ADD COLUMN target_type VARCHAR(30) NULL');"

CREATE TABLE IF NOT EXISTS plan_players (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    plan_id         VARCHAR(32)  NOT NULL,
    club_player_id  VARCHAR(64)  NOT NULL,
    player_user_id  INT          NULL,
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    INDEX  idx_pp_plan (plan_id),
    UNIQUE KEY uq_pp (plan_id, club_player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO system_meta (key_name, value) VALUES ('phase5_migration', '1');
