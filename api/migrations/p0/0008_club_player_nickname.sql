-- Add the player short name used by the club player form.
ALTER TABLE club_players
    ADD COLUMN IF NOT EXISTS nickname VARCHAR(255) NULL AFTER name;
