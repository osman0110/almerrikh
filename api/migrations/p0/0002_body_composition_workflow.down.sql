DROP TABLE IF EXISTS body_composition_revisions;
DROP TABLE IF EXISTS body_composition_import_batches;
ALTER TABLE player_body_composition_assessments
    DROP INDEX idx_bc_import_batch,
    DROP INDEX idx_bc_approval_scope,
    DROP COLUMN import_batch_id,
    DROP COLUMN legacy_source_id,
    DROP COLUMN muscle_mass_kg,
    DROP COLUMN device_name,
    DROP COLUMN measurement_method,
    DROP COLUMN formula_version,
    DROP COLUMN missing_sites_json,
    DROP COLUMN measurement_completeness,
    DROP COLUMN calculation_status,
    DROP COLUMN approved_at,
    DROP COLUMN approved_by,
    DROP COLUMN approval_status;
