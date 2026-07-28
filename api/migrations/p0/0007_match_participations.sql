-- P0 0007
-- Purpose: per-player, per-match participation record (starter/sub, minute
-- in/out, position, goals/assists, not-played reason) — richer than the
-- matches.player_minutes JSON blob, feeds player-match-stats.php and the
-- admin dashboard/player full report aggregates.
-- Lock risk: new table only.

CREATE TABLE IF NOT EXISTS match_participations (
    id                INT AUTO_INCREMENT PRIMARY KEY,
    match_id          VARCHAR(64) NOT NULL,
    player_id         VARCHAR(64) NOT NULL,
    starter           TINYINT NOT NULL DEFAULT 0,
    played            TINYINT NOT NULL DEFAULT 1,
    minute_in         SMALLINT NULL,
    minute_out        SMALLINT NULL,
    minutes_played    SMALLINT NOT NULL DEFAULT 0,
    position          VARCHAR(10) NULL,
    goals             TINYINT NOT NULL DEFAULT 0,
    assists           TINYINT NOT NULL DEFAULT 0,
    not_played_reason VARCHAR(30) NULL,
    created_by_user_id INT NOT NULL,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_match_participation (match_id, player_id),
    INDEX idx_match_participations_match (match_id),
    INDEX idx_match_participations_player (player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
