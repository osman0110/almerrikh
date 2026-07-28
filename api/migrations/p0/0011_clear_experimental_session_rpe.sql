-- P0 0011
-- Destructive one-time cleanup explicitly requested for experimental
-- Session RPE data. Hooper, sessions, matches and attendance are untouched.

START TRANSACTION;

DELETE FROM player_rpe_revisions
WHERE player_rpe_id IN (
    SELECT id FROM player_rpe WHERE rpe_type = 'post'
);

DELETE FROM post_training_feedback;

UPDATE assessments
SET post_rpe = NULL,
    pain_reported = 0,
    difficulty = NULL,
    mood_after = NULL
WHERE post_rpe IS NOT NULL
   OR pain_reported <> 0
   OR difficulty IS NOT NULL
   OR mood_after IS NOT NULL;

DELETE FROM player_rpe WHERE rpe_type = 'post';

COMMIT;
