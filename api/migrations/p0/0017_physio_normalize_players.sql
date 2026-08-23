-- P0 0017
-- Purpose: fix physio bulk booking creating a full duplicate `physio_sessions`
-- row per selected player (e.g. 40 players => 40 rows). Introduces
-- `physio_session_players` as the per-player status table (status,
-- specialist_notes, player_response, recommendation) and turns
-- `physio_sessions` into a true session-level row (one row per booking,
-- shared time/room/reason/therapist). Mirrors the physical coach's
-- club_sessions (session-level) + session_attendance (per-player) split.
-- Lock risk: new table + backfill + row delete + column drops on an
-- existing table. Take a backup before running.

CREATE TABLE IF NOT EXISTS physio_session_players (
    id                  INT AUTO_INCREMENT PRIMARY KEY,
    session_id          INT NOT NULL,
    player_id           VARCHAR(64) NOT NULL,
    status              VARCHAR(12) NOT NULL DEFAULT 'scheduled',
    specialist_notes    TEXT NULL,
    player_response     TEXT NULL,
    recommendation      VARCHAR(20) NULL,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_physio_sp_session_player (session_id, player_id),
    INDEX idx_physio_sp_player (player_id),
    CONSTRAINT fk_physio_sp_session FOREIGN KEY (session_id)
        REFERENCES physio_sessions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backfill: every existing physio_sessions row becomes a
-- physio_session_players row, keyed to its canonical session
-- (MIN(id) within its session_group_id if grouped, else itself).
INSERT INTO physio_session_players
    (session_id, player_id, status, specialist_notes, player_response, recommendation, created_at, updated_at)
SELECT
    CASE
        WHEN p.session_group_id IS NULL THEN p.id
        ELSE (SELECT MIN(g.id) FROM physio_sessions g WHERE g.session_group_id = p.session_group_id)
    END AS canonical_session_id,
    p.player_id, p.status, p.specialist_notes, p.player_response, p.recommendation,
    p.created_at, p.updated_at
FROM physio_sessions p;

-- Drop the now-duplicate physio_sessions rows: every row in a group except
-- the canonical (lowest-id) one.
DELETE p1 FROM physio_sessions p1
JOIN physio_sessions p2
  ON p1.session_group_id = p2.session_group_id
 AND p1.session_group_id IS NOT NULL
 AND p2.id < p1.id;

-- physio_sessions is now session-level only; the per-player fields moved to
-- physio_session_players, and session_group_id is redundant (physio_sessions.id
-- is now itself the group key).
ALTER TABLE physio_sessions
    DROP INDEX idx_physio_player,
    DROP INDEX idx_physio_group,
    DROP COLUMN player_id,
    DROP COLUMN status,
    DROP COLUMN recommendation,
    DROP COLUMN specialist_notes,
    DROP COLUMN player_response,
    DROP COLUMN session_group_id;
