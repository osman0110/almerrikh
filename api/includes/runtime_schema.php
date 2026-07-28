<?php

/**
 * Runtime requests validate only. They never create or alter schema.
 * Legacy bootstrap remains available behind ALLOW_RUNTIME_SCHEMA_BOOTSTRAP=1
 * until every historical ensureSchema operation has a reviewed migration.
 */
function validateRuntimeSchema(PDO $pdo): void
{
    $required = ['users', 'user_tokens'];
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?'
    );
    $missing = [];
    foreach ($required as $table) {
        $stmt->execute([$table]);
        if ((int)$stmt->fetchColumn() === 0) $missing[] = $table;
    }
    if ($missing) {
        throw new RuntimeException(
            'Database schema is not initialized. Missing: ' . implode(', ', $missing)
        );
    }
}
