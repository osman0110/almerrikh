-- P0 0002
-- Purpose: body-composition completeness, provenance, approval and import trace.
-- Existing rows are marked legacy_unreviewed; no row is silently approved.
-- Lock risk: ALTER may rebuild the assessment table on older MySQL versions.

ALTER TABLE player_body_composition_assessments
    ADD COLUMN approval_status VARCHAR(24) NOT NULL DEFAULT 'legacy_unreviewed' AFTER recorded_by,
    ADD COLUMN approved_by INT NULL AFTER approval_status,
    ADD COLUMN approved_at DATETIME NULL AFTER approved_by,
    ADD COLUMN calculation_status VARCHAR(40) NOT NULL DEFAULT 'LEGACY_UNREVIEWED' AFTER calculation_age_group,
    ADD COLUMN measurement_completeness DECIMAL(5,4) NOT NULL DEFAULT 0.0000 AFTER calculation_status,
    ADD COLUMN missing_sites_json JSON NULL AFTER measurement_completeness,
    ADD COLUMN formula_version VARCHAR(60) NULL AFTER calculation_formula_code,
    ADD COLUMN measurement_method VARCHAR(40) NOT NULL DEFAULT 'skinfold' AFTER assessment_type,
    ADD COLUMN device_name VARCHAR(100) NULL AFTER measurement_method,
    ADD COLUMN muscle_mass_kg DECIMAL(5,2) NULL AFTER fat_free_mass_kg,
    ADD COLUMN legacy_source_id BIGINT NULL AFTER muscle_mass_kg,
    ADD COLUMN import_batch_id VARCHAR(64) NULL AFTER legacy_source_id,
    ADD INDEX idx_bc_approval_scope (club_id, approval_status, assessment_date),
    ADD INDEX idx_bc_import_batch (import_batch_id);

CREATE TABLE IF NOT EXISTS body_composition_import_batches (
    id VARCHAR(64) PRIMARY KEY,
    club_id INT NOT NULL,
    created_by INT NOT NULL,
    import_policy VARCHAR(30) NOT NULL DEFAULT 'PARTIAL_IMPORT',
    received_count INT NOT NULL DEFAULT 0,
    imported_count INT NOT NULL DEFAULT 0,
    rejected_count INT NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'completed',
    result_json JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_bc_batch_club (club_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS body_composition_revisions (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    assessment_id VARCHAR(64) NOT NULL,
    revision_number INT UNSIGNED NOT NULL,
    old_values_json JSON NOT NULL,
    new_values_json JSON NULL,
    reason VARCHAR(500) NULL,
    changed_by INT NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_bc_revision_assessment (assessment_id, revision_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Backfill only calculation metadata that can be proven from stored values.
UPDATE player_body_composition_assessments
SET calculation_status = CASE
        WHEN body_fat_percentage IS NOT NULL
         AND biceps_mm IS NOT NULL
         AND triceps_mm IS NOT NULL
         AND subscapular_mm IS NOT NULL
         AND suprailiac_mm IS NOT NULL THEN 'LEGACY_COMPLETE'
        WHEN body_fat_percentage IS NOT NULL THEN 'LEGACY_PARTIAL_CALCULATION'
        ELSE 'LEGACY_UNREVIEWED'
    END,
    measurement_completeness = (
        (biceps_mm IS NOT NULL) +
        (triceps_mm IS NOT NULL) +
        (subscapular_mm IS NOT NULL) +
        (suprailiac_mm IS NOT NULL)
    ) / 4.0,
    missing_sites_json = JSON_ARRAY(
        IF(biceps_mm IS NULL, 'biceps', NULL),
        IF(triceps_mm IS NULL, 'triceps', NULL),
        IF(subscapular_mm IS NULL, 'subscapular', NULL),
        IF(suprailiac_mm IS NULL, 'suprailiac', NULL)
    )
WHERE calculation_status = 'LEGACY_UNREVIEWED';

-- Validation
SELECT approval_status, calculation_status, COUNT(*) AS records
FROM player_body_composition_assessments
GROUP BY approval_status, calculation_status;
