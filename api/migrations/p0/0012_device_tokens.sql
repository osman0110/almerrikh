-- P0 0012
-- Push notification device tokens (FCM). Additive, no lock risk on existing
-- tables. A user can have multiple rows (multiple devices); token is unique
-- so re-registering on a shared device reassigns user_id instead of a dupe.

CREATE TABLE IF NOT EXISTS device_tokens (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    user_id    INT NOT NULL,
    club_id    INT NULL,
    token      VARCHAR(255) NOT NULL,
    platform   VARCHAR(10) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_device_token (token),
    INDEX idx_device_tokens_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
