-- P0 0010
-- Session RPE edit tracking. Apply through the normal reviewed migration flow.

ALTER TABLE player_rpe
    ADD COLUMN last_edited_at DATETIME NULL AFTER revision_number,
    ADD COLUMN last_edited_by_user_id INT NULL AFTER last_edited_at;
