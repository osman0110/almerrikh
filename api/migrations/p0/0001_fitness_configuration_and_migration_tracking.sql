-- P0 0001
-- Purpose: reviewed migration tracking, official fitness configuration,
-- active-season source, and optional staff team scope.
-- Lock risk: short metadata locks on club_staff only.

CREATE TABLE IF NOT EXISTS schema_migrations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    migration_name VARCHAR(190) NOT NULL,
    checksum_sha256 CHAR(64) NOT NULL,
    batch_id VARCHAR(64) NOT NULL,
    applied_by VARCHAR(190) NULL,
    execution_ms INT UNSIGNED NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_schema_migrations_name (migration_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fitness_settings (
    club_id INT NOT NULL,
    setting_key VARCHAR(100) NOT NULL,
    setting_value VARCHAR(255) NOT NULL,
    updated_by INT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (club_id, setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS club_seasons (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id INT NOT NULL,
    team_id INT NULL,
    name VARCHAR(150) NOT NULL,
    starts_on DATE NOT NULL,
    ends_on DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    active_scope_key VARCHAR(80)
        GENERATED ALWAYS AS (
            CASE
                WHEN status = 'active' THEN CONCAT(club_id, ':', COALESCE(team_id, 0))
                ELSE NULL
            END
        ) STORED,
    created_by INT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_club_seasons_scope (club_id, team_id, status),
    INDEX idx_club_seasons_dates (starts_on, ends_on),
    UNIQUE KEY uq_club_seasons_active_scope (active_scope_key),
    CONSTRAINT chk_club_seasons_dates CHECK (starts_on <= ends_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE club_staff
    ADD COLUMN team_id INT NULL AFTER club_id,
    ADD INDEX idx_club_staff_team_scope (club_id, team_id, status);

INSERT INTO fitness_settings (club_id, setting_key, setting_value)
SELECT id, 'timezone', 'Africa/Kigali' FROM clubs
ON DUPLICATE KEY UPDATE setting_value = setting_value;

INSERT INTO fitness_settings (club_id, setting_key, setting_value)
SELECT id, 'training_week_start_iso', '1' FROM clubs
ON DUPLICATE KEY UPDATE setting_value = setting_value;

INSERT INTO fitness_settings (club_id, setting_key, setting_value)
SELECT id, 'acwr_formula_version', 'rolling_7_over_rolling_28_weekly_average_v1' FROM clubs
ON DUPLICATE KEY UPDATE setting_value = setting_value;

-- Validation
SELECT setting_key, COUNT(*) AS clubs_configured
FROM fitness_settings
WHERE setting_key IN ('timezone', 'training_week_start_iso', 'acwr_formula_version')
GROUP BY setting_key;
