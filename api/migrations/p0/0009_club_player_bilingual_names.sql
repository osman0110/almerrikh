-- Store the player's Arabic and English display names.
ALTER TABLE club_players
    ADD COLUMN IF NOT EXISTS name_ar VARCHAR(255) NULL AFTER name,
    ADD COLUMN IF NOT EXISTS name_en VARCHAR(255) NULL AFTER name_ar;
