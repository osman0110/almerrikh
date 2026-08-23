-- Rollback for 0017: re-expand physio_session_players back into duplicate
-- physio_sessions rows (one per player), regenerating session_group_id for
-- any session that has more than one player.

ALTER TABLE physio_sessions
    ADD COLUMN player_id           VARCHAR(64) NULL AFTER club_id,
    ADD COLUMN status              VARCHAR(12) NOT NULL DEFAULT 'scheduled',
    ADD COLUMN recommendation      VARCHAR(20) NULL,
    ADD COLUMN specialist_notes    TEXT NULL,
    ADD COLUMN player_response     TEXT NULL,
    ADD COLUMN session_group_id    VARCHAR(40) NULL AFTER created_by_user_id,
    ADD INDEX idx_physio_player (player_id),
    ADD INDEX idx_physio_group (session_group_id);

-- Turn the canonical (first) player of each session into that session's own
-- physio_sessions row, and assign a group id to every session that has more
-- than one player (so the app's old grouping logic still collapses them).
UPDATE physio_sessions s
JOIN (
    SELECT sp.*,
           ROW_NUMBER() OVER (PARTITION BY sp.session_id ORDER BY sp.id) AS rn,
           COUNT(*) OVER (PARTITION BY sp.session_id) AS player_count
    FROM physio_session_players sp
) first_sp ON first_sp.session_id = s.id AND first_sp.rn = 1
SET s.player_id        = first_sp.player_id,
    s.status            = first_sp.status,
    s.recommendation    = first_sp.recommendation,
    s.specialist_notes  = first_sp.specialist_notes,
    s.player_response   = first_sp.player_response,
    s.session_group_id  = IF(first_sp.player_count > 1, CONCAT('grp_', s.id), NULL);

-- Re-insert one physio_sessions row per additional (non-canonical) player.
INSERT INTO physio_sessions
    (club_id, therapist_user_id, scheduled_at, duration_minutes, room, body_area,
     session_reason, treatment_type, intensity, contraindications, status,
     created_by_user_id, session_group_id, session_name, player_id,
     recommendation, specialist_notes, player_response, created_at, updated_at)
SELECT
    s.club_id, s.therapist_user_id, s.scheduled_at, s.duration_minutes, s.room, s.body_area,
    s.session_reason, s.treatment_type, s.intensity, s.contraindications, sp.status,
    s.created_by_user_id, s.session_group_id, s.session_name, sp.player_id,
    sp.recommendation, sp.specialist_notes, sp.player_response, sp.created_at, sp.updated_at
FROM physio_session_players sp
JOIN physio_sessions s ON s.id = sp.session_id
WHERE sp.id NOT IN (
    SELECT first_sp.id FROM (
        SELECT sp2.id, ROW_NUMBER() OVER (PARTITION BY sp2.session_id ORDER BY sp2.id) AS rn
        FROM physio_session_players sp2
    ) first_sp WHERE first_sp.rn = 1
);

ALTER TABLE physio_sessions
    MODIFY COLUMN player_id VARCHAR(64) NOT NULL;

DROP TABLE physio_session_players;
