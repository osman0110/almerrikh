-- Rollback P0 0001. Review dependencies before use.
DELETE FROM fitness_settings
WHERE setting_key IN ('timezone', 'training_week_start_iso', 'acwr_formula_version');
DROP TABLE IF EXISTS club_seasons;
DROP TABLE IF EXISTS fitness_settings;
ALTER TABLE club_staff DROP INDEX idx_club_staff_team_scope, DROP COLUMN team_id;
-- schema_migrations is intentionally retained as operational history.
