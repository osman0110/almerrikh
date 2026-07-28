<?php
// Audit trail for edits to sensitive player data (weight, body-fat, injury
// notes, pain). One row per changed field so history reads like a diff,
// not a snapshot.
require_once __DIR__ . '/fitness/SchemaInspector.php';

/**
 * Records a single field change. No-ops when old and new are equal (only
 * actual edits are logged) — call once per field you want tracked.
 */
function logAudit(
    PDO $pdo,
    string $entityType,
    string $entityId,
    string $fieldName,
    ?string $oldValue,
    ?string $newValue,
    int $changedByUserId
): void {
    if ($oldValue === $newValue) return;

    $stmt = $pdo->prepare(
        'INSERT INTO audit_logs (entity_type, entity_id, field_name, old_value, new_value, changed_by_user_id)
         VALUES (?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([$entityType, $entityId, $fieldName, $oldValue, $newValue, $changedByUserId]);
}

/**
 * Diffs a set of $fields (name => newValue) against $oldRow (assoc array,
 * or null if the entity didn't exist yet) and logs each real change.
 */
function logAuditDiff(
    PDO $pdo,
    string $entityType,
    string $entityId,
    ?array $oldRow,
    array $fields,
    int $changedByUserId
): void {
    foreach ($fields as $field => $newValue) {
        $oldValue = $oldRow[$field] ?? null;
        $oldStr = $oldValue === null ? null : (string)$oldValue;
        $newStr = $newValue === null ? null : (string)$newValue;
        logAudit($pdo, $entityType, $entityId, $field, $oldStr, $newStr, $changedByUserId);
    }
}

/**
 * Records an auditable fitness operation. Before the P0 audit migration is
 * applied it falls back to the legacy audit shape, keeping deployments
 * backward compatible while never logging credentials or authorization data.
 */
function logFitnessAudit(
    PDO $pdo,
    string $entityType,
    string $entityId,
    string $operation,
    int $changedByUserId,
    ?int $clubId = null,
    ?string $playerId = null,
    $oldValue = null,
    $newValue = null,
    ?string $reason = null,
    ?string $operationId = null
): void {
    $oldJson = $oldValue === null ? null : json_encode($oldValue, JSON_UNESCAPED_UNICODE);
    $newJson = $newValue === null ? null : json_encode($newValue, JSON_UNESCAPED_UNICODE);

    if (!SchemaInspector::hasColumn($pdo, 'audit_logs', 'operation')) {
        logAudit($pdo, $entityType, $entityId, $operation, $oldJson, $newJson, $changedByUserId);
        return;
    }

    $ip = substr((string)($_SERVER['REMOTE_ADDR'] ?? ''), 0, 45) ?: null;
    $device = substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255) ?: null;
    $stmt = $pdo->prepare(
        'INSERT INTO audit_logs
         (entity_type, entity_id, field_name, old_value, new_value, changed_by_user_id,
          club_id, player_id, operation, reason, ip_address, device_info, operation_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([
        $entityType, $entityId, $operation, $oldJson, $newJson, $changedByUserId,
        $clubId, $playerId, $operation, $reason, $ip, $device, $operationId,
    ]);
}
