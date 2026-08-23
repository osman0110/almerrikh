-- P0 0018
-- Purpose: injury_cases, injury_updates, player_daily_decisions were only ever
-- created by db.php::ensureSchema(), which stopped running on normal requests
-- once ALLOW_RUNTIME_SCHEMA_BOOTSTRAP was disabled (see
-- runtime_schema_inventory.md, "Medical/rehab/tasks ... Out of P0 scope").
-- Production never got these tables, so doctor_dashboard.php and the
-- injuries/rehab endpoints throw an uncaught PDOException on every request.
-- Lock risk: new tables only.

CREATE TABLE IF NOT EXISTS injury_cases (
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    club_id               INT NOT NULL,
    player_id             VARCHAR(64) NOT NULL,
    injury_date           DATE NOT NULL,
    body_location         VARCHAR(100) NULL,
    injury_type           VARCHAR(100) NULL,
    severity              VARCHAR(10) NOT NULL DEFAULT 'moderate',
    diagnosis             TEXT NULL,
    exam_notes            TEXT NULL,
    case_status           VARCHAR(20) NOT NULL DEFAULT 'open',
    rtp_stage             VARCHAR(30) NULL,
    expected_return_date  DATE NULL,
    actual_return_date    DATE NULL,
    created_by_user_id    INT NOT NULL,
    created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_injury_club (club_id),
    INDEX idx_injury_player (player_id),
    INDEX idx_injury_status (case_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS injury_updates (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    injury_case_id   INT NOT NULL,
    author_user_id   INT NOT NULL,
    note             TEXT NULL,
    rtp_stage        VARCHAR(30) NULL,
    case_status      VARCHAR(20) NULL,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_injury_updates_case (injury_case_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_daily_decisions (
    id                       INT AUTO_INCREMENT PRIMARY KEY,
    club_id                  INT NOT NULL,
    player_id                VARCHAR(64) NOT NULL,
    decision_date            DATE NOT NULL,
    participation_status     VARCHAR(20) NOT NULL DEFAULT 'fully_available',
    allowed_duration_minutes INT NULL,
    restrictions             TEXT NULL,
    decided_by_user_id       INT NOT NULL,
    created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_daily_decision (player_id, decision_date),
    INDEX idx_daily_decision_club_date (club_id, decision_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
