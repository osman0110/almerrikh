-- Assessment review workflow columns (coach approval → player visibility).
-- Previously created only by the legacy ensureSchema() runtime bootstrap,
-- which is disabled by default, so a database migrated purely through this
-- folder never had them. Idempotent and portable (MySQL and MariaDB): each
-- column is added only when information_schema says it is missing.
-- Existing rows get 'pending_review' (the same default the bootstrap used);
-- no row is updated, approved or deleted.

SET @col := (SELECT COUNT(*) FROM information_schema.columns
             WHERE table_schema = DATABASE() AND table_name = 'assessments' AND column_name = 'status');
SET @sql := IF(@col = 0,
    "ALTER TABLE assessments ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending_review'",
    'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col := (SELECT COUNT(*) FROM information_schema.columns
             WHERE table_schema = DATABASE() AND table_name = 'assessments' AND column_name = 'approved_by_user_id');
SET @sql := IF(@col = 0, 'ALTER TABLE assessments ADD COLUMN approved_by_user_id INT NULL', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col := (SELECT COUNT(*) FROM information_schema.columns
             WHERE table_schema = DATABASE() AND table_name = 'assessments' AND column_name = 'approved_at');
SET @sql := IF(@col = 0, 'ALTER TABLE assessments ADD COLUMN approved_at TIMESTAMP NULL', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
