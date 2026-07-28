-- READ ONLY. Run against a copy or with a read-only DB account.

-- 1. Legacy/new body-composition counts.
SELECT 'legacy_body_metrics' AS metric, COUNT(*) AS value FROM player_body_metrics
UNION ALL
SELECT 'new_body_assessments', COUNT(*) FROM player_body_composition_assessments;

-- 2. Potential cross-system duplicates: same player/date/weight/body fat.
SELECT
    n.id AS new_id,
    l.id AS legacy_id,
    n.linked_player_id,
    n.assessment_date,
    n.weight_kg,
    n.body_fat_percentage
FROM player_body_composition_assessments n
JOIN player_body_metrics l
  ON l.linked_player_id = n.linked_player_id
 AND DATE(l.measured_at) = n.assessment_date
 AND ABS(l.weight_kg - n.weight_kg) < 0.01
 AND ABS(l.body_fat_percent - n.body_fat_percentage) < 0.01
WHERE n.deleted_at IS NULL;

-- 3. Body records whose club_id disagrees with their roster player.
SELECT a.id, a.club_id AS stored_club_id, cp.club_id AS expected_club_id,
       a.linked_player_id, a.created_by
FROM player_body_composition_assessments a
JOIN club_players cp ON cp.id = a.linked_player_id
WHERE a.club_id <> cp.club_id OR a.club_id IS NULL;

-- 4. Partial skinfold with a calculated body-fat percentage.
SELECT id, linked_player_id, assessment_date, body_fat_percentage,
       biceps_mm, triceps_mm, subscapular_mm, suprailiac_mm
FROM player_body_composition_assessments
WHERE deleted_at IS NULL
  AND body_fat_percentage IS NOT NULL
  AND (
      biceps_mm IS NULL OR triceps_mm IS NULL
      OR subscapular_mm IS NULL OR suprailiac_mm IS NULL
  );

-- 5. RPE duplicate groups using the approved logical identity.
SELECT
    COALESCE(linked_player_id, CONCAT('user:', user_id)) AS player_identity,
    COALESCE(session_id, training_session_id, CONCAT(DATE(submitted_at), ':', COALESCE(session_type, 'unspecified'))) AS activity_identity,
    COALESCE(rpe_type, 'post') AS source_type,
    COUNT(*) AS duplicate_count,
    GROUP_CONCAT(id ORDER BY submitted_at DESC, id DESC) AS row_ids,
    SUM(training_load) AS raw_load,
    SUBSTRING_INDEX(
        GROUP_CONCAT(training_load ORDER BY submitted_at DESC, id DESC),
        ',',
        1
    ) AS retained_load
FROM player_rpe
GROUP BY player_identity, activity_identity, source_type
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 6. Total load inflation caused by duplicate logical activities.
WITH ranked_rpe AS (
    SELECT
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY
                COALESCE(linked_player_id, CONCAT('user:', user_id)),
                COALESCE(session_id, training_session_id, CONCAT(DATE(submitted_at), ':', COALESCE(session_type, 'unspecified'))),
                COALESCE(rpe_type, 'post')
            ORDER BY submitted_at DESC, id DESC
        ) AS rn
    FROM player_rpe r
)
SELECT
    SUM(training_load) AS raw_total_load,
    SUM(CASE WHEN rn = 1 THEN training_load ELSE 0 END) AS deduplicated_total_load,
    SUM(training_load) - SUM(CASE WHEN rn = 1 THEN training_load ELSE 0 END) AS inflation
FROM ranked_rpe;

-- 6b. Existing idempotency-key collisions, if migration 0004 has been applied.
-- Run separately after 0004 because older schemas do not have this column:
-- SELECT club_id, idempotency_key, COUNT(*)
-- FROM player_rpe
-- WHERE idempotency_key IS NOT NULL
-- GROUP BY club_id, idempotency_key HAVING COUNT(*) > 1;

-- 7. Active players without user accounts.
SELECT club_id, COUNT(*) AS players_without_accounts
FROM club_players
WHERE is_active = 1
  AND (player_type IS NULL OR player_type = 'club')
  AND linked_user_id IS NULL
GROUP BY club_id;

-- 8. Population difference: players represented in Hooper vs RPE.
SELECT
    cp.club_id,
    COUNT(DISTINCT cp.id) AS eligible_players,
    COUNT(DISTINCT CASE WHEN h.id IS NOT NULL THEN cp.id END) AS hooper_players,
    COUNT(DISTINCT CASE WHEN r.id IS NOT NULL THEN cp.id END) AS rpe_players
FROM club_players cp
LEFT JOIN player_hooper_index h
  ON h.linked_player_id = cp.id
  OR (h.linked_player_id IS NULL AND h.user_id = cp.linked_user_id)
LEFT JOIN player_rpe r
  ON r.linked_player_id = cp.id
  OR (r.linked_player_id IS NULL AND r.user_id = cp.linked_user_id)
WHERE cp.is_active = 1
  AND (cp.player_type IS NULL OR cp.player_type = 'club')
GROUP BY cp.club_id;

-- 9. Scheduled sessions without any RPE row.
SELECT cs.club_id, cs.id AS session_id, cs.date, cs.title
FROM club_sessions cs
LEFT JOIN player_rpe r
  ON r.session_id = cs.id OR r.training_session_id = cs.id
WHERE cs.date <= CURDATE()
GROUP BY cs.club_id, cs.id, cs.date, cs.title
HAVING COUNT(r.id) = 0;

-- 10. Matches with recorded player minutes but no RPE on the match date.
SELECT m.club_id, m.id AS match_id, m.match_date
FROM matches m
LEFT JOIN player_rpe r
  ON r.club_id = m.club_id AND DATE(r.submitted_at) = m.match_date
WHERE m.player_minutes IS NOT NULL
GROUP BY m.club_id, m.id, m.match_date
HAVING COUNT(r.id) = 0;
