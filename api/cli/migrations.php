<?php

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "CLI only.\n");
    exit(1);
}

require_once dirname(__DIR__) . '/db.php';

$command = $argv[1] ?? 'status';
$requested = $argv[2] ?? null;
$directory = dirname(__DIR__) . '/migrations/p0';

function migrationFiles(string $directory): array
{
    $files = glob($directory . '/*.sql') ?: [];
    $files = array_values(array_filter(
        $files,
        fn(string $file) => !str_ends_with($file, '.down.sql')
            && basename($file) !== 'preflight_data_audit.sql'
    ));
    sort($files, SORT_STRING);
    return $files;
}

function ensureMigrationTable(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS p0_schema_migrations (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            migration_name VARCHAR(190) NOT NULL,
            checksum_sha256 CHAR(64) NOT NULL,
            batch_id VARCHAR(64) NOT NULL,
            applied_by VARCHAR(190) NULL,
            execution_ms INT UNSIGNED NULL,
            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_p0_schema_migrations_name (migration_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );
}

function appliedMigrations(PDO $pdo): array
{
    ensureMigrationTable($pdo);
    $rows = $pdo->query(
        'SELECT migration_name, checksum_sha256, applied_at
         FROM p0_schema_migrations ORDER BY migration_name'
    )->fetchAll(PDO::FETCH_ASSOC);
    $result = [];
    foreach ($rows as $row) $result[$row['migration_name']] = $row;
    return $result;
}

$files = migrationFiles($directory);
$applied = appliedMigrations($pdo);

if ($command === 'status') {
    foreach ($files as $file) {
        $name = basename($file);
        $checksum = hash_file('sha256', $file);
        $state = !isset($applied[$name])
            ? 'PENDING'
            : (hash_equals($applied[$name]['checksum_sha256'], $checksum) ? 'APPLIED' : 'CHECKSUM_MISMATCH');
        echo str_pad($state, 20) . $name . PHP_EOL;
    }
    exit(0);
}

if ($command === 'up') {
    $batchId = 'p0-' . gmdate('YmdHis') . '-' . bin2hex(random_bytes(4));
    foreach ($files as $file) {
        $name = basename($file);
        if ($requested !== null && $requested !== $name) continue;
        if (isset($applied[$name])) continue;

        $sql = file_get_contents($file);
        if ($requested === null && str_contains($sql, 'MANUAL APPROVAL REQUIRED')) {
            echo "SKIPPED_MANUAL $name\n";
            continue;
        }
        $started = microtime(true);
        $pdo->exec($sql);
        $elapsedMs = (int)round((microtime(true) - $started) * 1000);
        $pdo->prepare(
            'INSERT INTO p0_schema_migrations
             (migration_name, checksum_sha256, batch_id, applied_by, execution_ms)
             VALUES (?, ?, ?, ?, ?)'
        )->execute([
            $name,
            hash('sha256', $sql),
            $batchId,
            getenv('USERNAME') ?: get_current_user(),
            $elapsedMs,
        ]);
        echo "APPLIED $name\n";
    }
    exit(0);
}

if ($command === 'down') {
    if ($requested === null) {
        fwrite(STDERR, "Specify one migration filename for rollback.\n");
        exit(1);
    }
    $upFile = $directory . '/' . $requested;
    $downFile = preg_replace('/\.sql$/', '.down.sql', $upFile);
    if (!is_file($downFile)) {
        fwrite(STDERR, "Rollback file not found: $downFile\n");
        exit(1);
    }
    $pdo->exec(file_get_contents($downFile));
    $pdo->prepare('DELETE FROM p0_schema_migrations WHERE migration_name = ?')->execute([$requested]);
    echo "ROLLED_BACK $requested\n";
    exit(0);
}

fwrite(STDERR, "Usage: php api/cli/migrations.php status|up [migration.sql]|down migration.sql\n");
exit(1);
