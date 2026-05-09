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
