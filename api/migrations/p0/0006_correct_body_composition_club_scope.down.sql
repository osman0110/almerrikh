UPDATE player_body_composition_assessments a
JOIN body_composition_club_id_corrections c ON c.assessment_id = a.id
SET a.club_id = c.old_club_id
WHERE c.operation_id = 'P0-BC-CLUB-ID-V1';

DELETE FROM audit_logs
WHERE operation_id = 'P0-BC-CLUB-ID-V1'
  AND operation = 'body_composition.club_id_corrected';

DROP TABLE IF EXISTS body_composition_club_id_corrections;
