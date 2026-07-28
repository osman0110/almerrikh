<?php

final class SchemaInspector
{
    private static array $columnCache = [];
    private static array $tableCache = [];

    public static function hasTable(PDO $pdo, string $table): bool
    {
        $key = spl_object_id($pdo) . ':' . $table;
        if (array_key_exists($key, self::$tableCache)) {
            return self::$tableCache[$key];
        }
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?'
        );
        $stmt->execute([$table]);
        return self::$tableCache[$key] = ((int)$stmt->fetchColumn() > 0);
    }

    public static function hasColumn(PDO $pdo, string $table, string $column): bool
    {
        $key = spl_object_id($pdo) . ':' . $table . ':' . $column;
        if (array_key_exists($key, self::$columnCache)) {
            return self::$columnCache[$key];
        }
        if (!self::hasTable($pdo, $table)) {
            return self::$columnCache[$key] = false;
        }
        $stmt = $pdo->prepare(
            'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
        );
        $stmt->execute([$table, $column]);
        return self::$columnCache[$key] = ((int)$stmt->fetchColumn() > 0);
    }
}
