-- In-app notifications table + users.language.
-- Both were created only by the legacy ensureSchema() runtime bootstrap
-- (disabled by default), so a database migrated purely through this folder
-- never had them — and every notification (alerts, session scheduled, injury
-- created, task assigned…) failed silently. Idempotent and portable
-- (MySQL and MariaDB). Adds structure only; no row is changed.

CREATE TABLE IF NOT EXISTS notifications (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    club_id      INT NOT NULL,
    user_id      INT NOT NULL,
    type         VARCHAR(40) NOT NULL,
    title        VARCHAR(200) NOT NULL,
    body         TEXT NULL,
    linked_route VARCHAR(200) NULL,
    is_read      TINYINT(1) NOT NULL DEFAULT 0,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notifications_user (user_id, is_read),
    INDEX idx_notifications_club (club_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @col := (SELECT COUNT(*) FROM information_schema.columns
             WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'language');
SET @sql := IF(@col = 0,
    "ALTER TABLE users ADD COLUMN language VARCHAR(5) NOT NULL DEFAULT 'ar'",
    'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
