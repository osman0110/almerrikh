<?php
$host = 'localhost';
$dbname = 'smart_sport';
$username = 'root';
$password = '';

function jsonError(string $message, int $code = 500): void {
    http_response_code($code);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

function createPdo(string $dsn, string $username, string $password): PDO {
    return new PDO($dsn, $username, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

function ensureSchema(PDO $pdo): void {
    $pdo->exec("CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) NOT NULL UNIQUE,
        phone VARCHAR(32) NULL,
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY users_phone_unique (phone)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    ensureColumn($pdo, 'users', 'phone', 'VARCHAR(32) NULL AFTER email');
    ensureIndex($pdo, 'users', 'users_phone_unique', 'CREATE UNIQUE INDEX users_phone_unique ON users (phone)');

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_tokens (
        token VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user_tokens_user_id (user_id),
        CONSTRAINT fk_user_tokens_user
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_profiles (
        user_id INT PRIMARY KEY,
        player_name VARCHAR(100),
        age INT,
        position VARCHAR(20),
        foot VARCHAR(20),
        weaknesses TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        CONSTRAINT fk_user_profiles_user
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS assessments (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        player_id VARCHAR(255) NOT NULL,
        player_name VARCHAR(255) DEFAULT '',
        type VARCHAR(50) NOT NULL,
        overall_score INT NOT NULL DEFAULT 0,
        movement_quality_score INT DEFAULT 0,
        stability_score INT DEFAULT 0,
        symmetry_score INT DEFAULT 0,
        control_score INT DEFAULT 0,
        quality_score INT DEFAULT 0,
        issues_json TEXT,
        tips_json TEXT,
        drills_json TEXT,
        angle_metrics_json TEXT,
        notes TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_assessments_user (user_id),
        INDEX idx_assessments_player (player_id),
        CONSTRAINT fk_assessments_user
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Player Monitoring Tables ─────────────────────────────────────────────

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_body_metrics (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        weight_kg DECIMAL(5,2) NOT NULL,
        height_cm DECIMAL(5,1) NOT NULL,
        body_fat_percent DECIMAL(5,2) NOT NULL,
        bmi DECIMAL(5,2) NULL,
        measured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_body_metrics_user (user_id),
        CONSTRAINT fk_body_metrics_user
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_hooper_index (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        training_session_id VARCHAR(64) NULL,
        sleep_quality TINYINT NOT NULL DEFAULT 1,
        fatigue TINYINT NOT NULL DEFAULT 1,
        stress TINYINT NOT NULL DEFAULT 1,
        muscle_soreness TINYINT NOT NULL DEFAULT 1,
        sleep_hours DECIMAL(3,1) NULL,
        hooper_score TINYINT NOT NULL,
        notes TEXT NULL,
        submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_hooper_user (user_id),
        INDEX idx_hooper_submitted (user_id, submitted_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_rpe (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        training_session_id VARCHAR(64) NULL,
        session_type VARCHAR(50) NULL,
        rpe_score TINYINT NOT NULL DEFAULT 1,
        duration_minutes SMALLINT NOT NULL DEFAULT 0,
        training_load SMALLINT NOT NULL DEFAULT 0,
        notes TEXT NULL,
        submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_rpe_user (user_id),
        INDEX idx_rpe_submitted (user_id, submitted_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Wearable Device Integration (Future: Catapult, STATSports, Apple Watch, etc.) ─

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_wearable_data (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        device_id VARCHAR(100) NOT NULL,
        device_type VARCHAR(50) NOT NULL,
        heart_rate INT NULL,
        distance_m DECIMAL(8,2) NULL,
        sprint_count INT NULL,
        top_speed DECIMAL(5,2) NULL,
        max_acceleration DECIMAL(5,2) NULL,
        distance_at_high_intensity INT NULL,
        rpe_device_estimate INT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_wearable_user (user_id),
        INDEX idx_wearable_device (device_id),
        INDEX idx_wearable_recorded (user_id, recorded_at),
        CONSTRAINT fk_wearable_user
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
}

function ensureColumn(PDO $pdo, string $table, string $column, string $definition): void {
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );
    $stmt->execute([$table, $column]);
    if ((int) $stmt->fetchColumn() === 0) {
        $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$column` $definition");
    }
}

function ensureIndex(PDO $pdo, string $table, string $index, string $ddl): void {
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?'
    );
    $stmt->execute([$table, $index]);
    if ((int) $stmt->fetchColumn() === 0) {
        $pdo->exec($ddl);
    }
}

try {
    $serverPdo = createPdo(
        "mysql:host=$host;charset=utf8mb4",
        $username,
        $password
    );
    $serverPdo->exec("CREATE DATABASE IF NOT EXISTS `$dbname` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");

    $pdo = createPdo(
        "mysql:host=$host;dbname=$dbname;charset=utf8mb4",
        $username,
        $password
    );
    ensureSchema($pdo);
} catch (PDOException $e) {
    jsonError('Database connection failed: ' . $e->getMessage());
}
