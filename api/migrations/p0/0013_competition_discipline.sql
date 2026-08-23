-- Competition discipline rules, yellow-card cycles, and independent suspensions.

ALTER TABLE club_competitions
    ADD COLUMN yellow_card_threshold INT NOT NULL DEFAULT 3,
    ADD COLUMN suspension_matches INT NOT NULL DEFAULT 1,
    ADD COLUMN reset_yellow_cycle TINYINT NOT NULL DEFAULT 1,
    ADD COLUMN carry_cards_between_stages TINYINT NOT NULL DEFAULT 1,
    ADD COLUMN carry_suspensions_forward TINYINT NOT NULL DEFAULT 0,
    ADD COLUMN direct_red_suspension_matches INT NOT NULL DEFAULT 2,
    ADD COLUMN two_yellows_suspension_matches INT NOT NULL DEFAULT 1,
    ADD COLUMN allow_admin_override TINYINT NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS player_discipline_cycles (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id INT NOT NULL,
    player_id VARCHAR(64) NOT NULL,
    competition_id INT NOT NULL,
    season_id BIGINT UNSIGNED NULL,
    cycle_number INT NOT NULL DEFAULT 1,
    current_yellow_cards INT NOT NULL DEFAULT 0,
    started_at DATE NOT NULL,
    completed_at DATE NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_discipline_cycle (player_id, competition_id, cycle_number),
    INDEX idx_discipline_cycle_current (club_id, player_id, competition_id, completed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_suspensions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id INT NOT NULL,
    player_id VARCHAR(64) NOT NULL,
    competition_id INT NOT NULL,
    season_id BIGINT UNSIGNED NULL,
    reason_type VARCHAR(40) NOT NULL,
    reason TEXT NULL,
    source_card_id INT NULL,
    matches_total INT NOT NULL,
    matches_remaining INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    administrative_decision TEXT NULL,
    decision_document VARCHAR(500) NULL,
    created_by_user_id INT NOT NULL,
    executed_at DATE NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_suspensions_player (club_id, player_id, status),
    INDEX idx_suspensions_competition (competition_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS suspension_match_executions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    suspension_id BIGINT UNSIGNED NOT NULL,
    match_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_suspension_match (suspension_id, match_id),
    INDEX idx_execution_match (match_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
