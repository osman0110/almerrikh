-- P0 0002
-- Purpose: competition classification for matches, plus yellow/red card
-- discipline tracking per match.
-- Lock risk: new tables only, plus a nullable column + index on matches.

CREATE TABLE IF NOT EXISTS club_competitions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    club_id INT NOT NULL,
    season_id BIGINT UNSIGNED NULL,
    name VARCHAR(150) NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'league',
    notes VARCHAR(255) NULL,
    is_active TINYINT NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_club_competitions_club (club_id, is_active),
    INDEX idx_club_competitions_season (season_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS match_cards (
    id INT AUTO_INCREMENT PRIMARY KEY,
    match_id VARCHAR(64) NOT NULL,
    player_id VARCHAR(64) NOT NULL,
    card_type VARCHAR(10) NOT NULL,
    minute INT NULL,
    reason VARCHAR(255) NULL,
    created_by_user_id INT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_match_cards_match (match_id),
    INDEX idx_match_cards_player (player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE matches
    ADD COLUMN competition_id INT NULL,
    ADD INDEX idx_matches_competition (competition_id);
