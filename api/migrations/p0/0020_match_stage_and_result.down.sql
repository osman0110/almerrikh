-- Down for 0020_match_stage_and_result.sql
ALTER TABLE matches
    DROP COLUMN stage,
    DROP COLUMN round_label,
    DROP COLUMN group_name,
    DROP COLUMN our_score,
    DROP COLUMN opponent_score;

ALTER TABLE match_participations
    DROP COLUMN rating,
    DROP COLUMN injured;
