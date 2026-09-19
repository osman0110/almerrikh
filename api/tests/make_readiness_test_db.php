<?php
// Builds a throw-away, fully-migrated test database for
// p1_readiness_http_test.php:
//
//   php api/tests/make_readiness_test_db.php <source_test_db> <new_test_db>
//
// 1. Clones <source_test_db> (schema + data) into <new_test_db>.
// 2. Seeds p0_schema_migrations from the source's legacy `schema_migrations`
//    rows so already-applied migrations are not re-run.
// 3. Applies every pending p0 migration with the project's own runner
//    (api/cli/migrations.php up — MANUAL-APPROVAL migrations are skipped).
// 4. Adds users.language (ensureSchema-only column, no migration file yet).
//
// Refuses to touch anything whose name does not contain "test".
if (PHP_SAPI !== 'cli') exit(1);
[$src, $dst] = [$argv[1] ?? '', $argv[2] ?? ''];
if (!$src || !$dst || !str_contains($src, 'test') || !str_contains($dst, 'test') || $src === $dst) {
    fwrite(STDERR, "Usage: php make_readiness_test_db.php <source_test_db> <new_test_db> (names must contain 'test')\n");
    exit(2);
}
$pdo = new PDO('mysql:host=127.0.0.1;charset=utf8mb4', 'root', '', [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$pdo->exec("DROP DATABASE IF EXISTS `$dst`");
$pdo->exec("CREATE DATABASE `$dst` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
$pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
$tables = $pdo->query("SELECT table_name FROM information_schema.tables WHERE table_schema = " . $pdo->quote($src) . " AND table_type = 'BASE TABLE'")->fetchAll(PDO::FETCH_COLUMN);
foreach ($tables as $t) {
    $pdo->exec("CREATE TABLE `$dst`.`$t` LIKE `$src`.`$t`");
    // Generated columns cannot be inserted into — copy the stored ones only.
    $cols = $pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema = " . $pdo->quote($src) . " AND table_name = " . $pdo->quote($t) . " AND extra NOT LIKE '%GENERATED%' ORDER BY ordinal_position")->fetchAll(PDO::FETCH_COLUMN);
    $list = implode(',', array_map(fn($c) => "`$c`", $cols));
    $pdo->exec("INSERT INTO `$dst`.`$t` ($list) SELECT $list FROM `$src`.`$t`");
}
$pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
echo "cloned " . count($tables) . " tables\n";

$pdo->exec("CREATE TABLE IF NOT EXISTS `$dst`.p0_schema_migrations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    migration_name VARCHAR(190) NOT NULL,
    checksum_sha256 CHAR(64) NOT NULL,
    batch_id VARCHAR(64) NOT NULL,
    applied_by VARCHAR(190) NULL,
    execution_ms INT UNSIGNED NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_p0_schema_migrations_name (migration_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
if (in_array('schema_migrations', $tables, true)) {
    $pdo->exec("INSERT IGNORE INTO `$dst`.p0_schema_migrations (migration_name, checksum_sha256, batch_id, applied_by, execution_ms, applied_at)
                SELECT migration_name, checksum_sha256, batch_id, applied_by, execution_ms, applied_at FROM `$src`.schema_migrations");
}

// 0008/0009 use `ADD COLUMN IF NOT EXISTS`, which is MariaDB-only syntax and
// fails on MySQL (a real deployment finding — see the readiness report).
// On MySQL, apply the equivalent plain ALTERs here and record them, so the
// runner can continue with the remaining migrations.
$isMaria = stripos((string)$pdo->query('SELECT VERSION()')->fetchColumn(), 'mariadb') !== false;
if (!$isMaria) {
    $dir = dirname(__DIR__) . '/migrations/p0';
    foreach (['0008_club_player_nickname.sql', '0009_club_player_bilingual_names.sql'] as $name) {
        $done = $pdo->query("SELECT COUNT(*) FROM `$dst`.p0_schema_migrations WHERE migration_name = " . $pdo->quote($name))->fetchColumn();
        if ($done) continue;
        $sql = str_replace('ADD COLUMN IF NOT EXISTS', 'ADD COLUMN', file_get_contents("$dir/$name"));
        $pdo->exec("USE `$dst`");
        $pdo->exec($sql);
        $pdo->prepare("INSERT INTO `$dst`.p0_schema_migrations (migration_name, checksum_sha256, batch_id, applied_by) VALUES (?, ?, 'test-mysql-shim', 'make_readiness_test_db')")
            ->execute([$name, hash_file('sha256', "$dir/$name")]);
        echo "APPLIED (MySQL-compatible form) $name\n";
    }
}

$cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg(dirname(__DIR__) . '/cli/migrations.php') . ' up';
putenv("DB_NAME=$dst");
passthru($cmd, $rc);
if ($rc !== 0) { fwrite(STDERR, "migrations failed ($rc)\n"); exit(1); }

$hasLang = $pdo->query("SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = " . $pdo->quote($dst) . " AND table_name = 'users' AND column_name = 'language'")->fetchColumn();
if (!$hasLang) $pdo->exec("ALTER TABLE `$dst`.users ADD COLUMN language VARCHAR(5) NOT NULL DEFAULT 'ar'");
echo "ready: $dst\n";
