-- Rollback note: the columns may pre-date 0021 (legacy ensureSchema
-- bootstrap), and dropping them would erase every coach approval. This down
-- migration is intentionally a no-op; drop the columns manually only after
-- confirming they were created by 0021 and exporting approval history.
SELECT 1;
