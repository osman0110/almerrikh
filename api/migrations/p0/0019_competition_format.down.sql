-- Down for 0019_competition_format.sql
ALTER TABLE club_competitions
    DROP COLUMN format_type,
    DROP COLUMN stages_count,
    DROP COLUMN win_points,
    DROP COLUMN draw_points,
    DROP COLUMN loss_points,
    DROP COLUMN tie_break_rule,
    DROP COLUMN competition_status;
