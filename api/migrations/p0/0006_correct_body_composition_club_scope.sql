-- P0 0006 - MANUAL APPROVAL REQUIRED
-- Corrects only rows whose linked roster player proves the expected club.
-- Original values are retained in a correction ledger and audit log.

CREATE TABLE IF NOT EXISTS body_composition_club_id_corrections (
    assessment_id VARCHAR(64) PRIMARY KEY,
    old_club_id INT NULL,
    new_club_id INT NOT NULL,
    operation_id VARCHAR(100) NOT NULL,
    corrected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO body_composition_club_id_corrections
    (assessment_id, old_club_id, new_club_id, operation_id)
SELECT a.id, a.club_id, cp.club_id, 'P0-BC-CLUB-ID-V1'
FROM player_body_composition_assessments a
JOIN club_players cp ON cp.id = a.linked_player_id
WHERE a.club_id <> cp.club_id OR a.club_id IS NULL
ON DUPLICATE KEY UPDATE assessment_id = assessment_id;

INSERT INTO audit_logs
    (entity_type, entity_id, field_name, old_value, new_value, changed_by_user_id,
     club_id, player_id, operation, reason, operation_id)
SELECT
    'player_body_composition_assessments',
    c.assessment_id,
    'club_id',
    CAST(c.old_club_id AS CHAR),
    CAST(c.new_club_id AS CHAR),
    0,
    c.new_club_id,
    a.linked_player_id,
    'body_composition.club_id_corrected',
    'P0 correction based on linked roster player club',
    c.operation_id
FROM body_composition_club_id_corrections c
JOIN player_body_composition_assessments a ON a.id = c.assessment_id;

UPDATE player_body_composition_assessments a
JOIN body_composition_club_id_corrections c ON c.assessment_id = a.id
SET a.club_id = c.new_club_id;

-- Validation: must return zero.
SELECT COUNT(*) AS remaining_wrong_club_ids
FROM player_body_composition_assessments a
JOIN club_players cp ON cp.id = a.linked_player_id
WHERE a.club_id <> cp.club_id OR a.club_id IS NULL;
