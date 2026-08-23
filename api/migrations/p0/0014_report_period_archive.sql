-- Automatic archive index for completed report periods.

CREATE TABLE IF NOT EXISTS report_period_archives (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    club_id INT NOT NULL,
    team_id INT NOT NULL DEFAULT 0,
    report_type VARCHAR(40) NOT NULL,
    period_kind VARCHAR(20) NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    data_count INT UNSIGNED NOT NULL DEFAULT 0,
    generated_by_user_id INT NULL,
    generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_refreshed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_report_period_archive (
        club_id, team_id, report_type, period_start, period_end
    ),
    INDEX idx_report_period_archive_list (
        club_id, team_id, period_end, report_type
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
