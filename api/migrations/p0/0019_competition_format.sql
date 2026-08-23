-- Competition format/points/tie-break config and lifecycle status.

ALTER TABLE club_competitions
    ADD COLUMN format_type VARCHAR(20) NOT NULL DEFAULT 'league',      -- league | knockout | groups | friendly
    ADD COLUMN stages_count INT NOT NULL DEFAULT 1,
    ADD COLUMN win_points INT NOT NULL DEFAULT 3,
    ADD COLUMN draw_points INT NOT NULL DEFAULT 1,
    ADD COLUMN loss_points INT NOT NULL DEFAULT 0,
    ADD COLUMN tie_break_rule VARCHAR(30) NOT NULL DEFAULT 'goal_difference', -- goal_difference | head_to_head | goals_scored
    ADD COLUMN competition_status VARCHAR(20) NOT NULL DEFAULT 'upcoming';    -- upcoming | ongoing | completed
