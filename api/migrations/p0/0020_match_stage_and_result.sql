-- Match stage/round/group linkage, final score, and per-player rating/injury.

ALTER TABLE matches
    ADD COLUMN stage VARCHAR(30) NULL,        -- e.g. group | quarterfinal | semifinal | final | round
    ADD COLUMN round_label VARCHAR(50) NULL,  -- free-text round/matchday label
    ADD COLUMN group_name VARCHAR(30) NULL,
    ADD COLUMN our_score INT NULL,
    ADD COLUMN opponent_score INT NULL;

ALTER TABLE match_participations
    ADD COLUMN rating DECIMAL(3,1) NULL,      -- post-match performance rating, e.g. 7.5
    ADD COLUMN injured TINYINT NOT NULL DEFAULT 0;
