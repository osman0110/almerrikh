<?php

require_once __DIR__ . '/SchemaInspector.php';

final class BodyCompositionRepository
{
    public static function latestForPlayer(
        PDO $pdo,
        ?string $linkedPlayerId,
        ?int $userId,
        bool $approvedOnly = true
    ): ?array {
        $new = self::latestNew($pdo, $linkedPlayerId, $userId, $approvedOnly);
        if ($new) return self::mapNew($new);
        if ($approvedOnly) return null;

        $legacy = self::latestLegacy($pdo, $linkedPlayerId, $userId);
        return $legacy ? self::mapLegacy($legacy) : null;
    }

    public static function historyForPlayer(
        PDO $pdo,
        ?string $linkedPlayerId,
        ?int $userId,
        int $limit = 30,
        bool $approvedOnly = true
    ): array {
        $records = [];
        if (SchemaInspector::hasTable($pdo, 'player_body_composition_assessments')) {
            $where = ['deleted_at IS NULL'];
            $params = [];
            if ($linkedPlayerId) {
                $where[] = 'linked_player_id = ?';
                $params[] = $linkedPlayerId;
            } elseif ($userId !== null) {
                $where[] = 'user_id = ?';
                $params[] = $userId;
            }
            // Approval gating removed — a coach-recorded measurement is usable
            // in reports the moment it's saved, no separate approval step.
            $stmt = $pdo->prepare(
                'SELECT * FROM player_body_composition_assessments
                 WHERE ' . implode(' AND ', $where) . '
                 ORDER BY assessment_date DESC, created_at DESC LIMIT ' . (int)$limit
            );
            $stmt->execute($params);
            $records = array_map([self::class, 'mapNew'], $stmt->fetchAll(PDO::FETCH_ASSOC));
        }

        if (!$approvedOnly && SchemaInspector::hasTable($pdo, 'player_body_metrics')) {
            if ($linkedPlayerId) {
                $stmt = $pdo->prepare(
                    'SELECT * FROM player_body_metrics
                     WHERE linked_player_id = ? ORDER BY measured_at DESC, id DESC LIMIT ' . (int)$limit
                );
                $stmt->execute([$linkedPlayerId]);
            } elseif ($userId !== null) {
                $stmt = $pdo->prepare(
                    'SELECT * FROM player_body_metrics
                     WHERE user_id = ? ORDER BY measured_at DESC, id DESC LIMIT ' . (int)$limit
                );
                $stmt->execute([$userId]);
            } else {
                return array_slice($records, 0, $limit);
            }
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $legacy) {
                $records[] = self::mapLegacy($legacy);
            }
        }

        usort($records, function (array $a, array $b): int {
            $dateOrder = strcmp((string)$b['measured_at'], (string)$a['measured_at']);
            if ($dateOrder !== 0) return $dateOrder;
            if ($a['source_system'] === $b['source_system']) return 0;
            return $a['source_system'] === 'NEW_SYSTEM' ? -1 : 1;
        });
        $deduplicated = [];
        $seen = [];
        foreach ($records as $record) {
            $key = implode('|', [
                substr((string)$record['measured_at'], 0, 10),
                (string)$record['weight_kg'],
                (string)$record['body_fat_percentage'],
            ]);
            if (isset($seen[$key])) continue;
            $seen[$key] = true;
            $deduplicated[] = $record;
            if (count($deduplicated) >= $limit) break;
        }
        return $deduplicated;
    }

    public static function latestApprovedForClub(PDO $pdo, int $clubId, ?int $teamId = null): array
    {
        // Approval gating removed — a coach-recorded measurement is usable
        // in reports the moment it's saved, no separate approval step.
        $subStatusFilter = '';
        $outerStatusFilter = '';

        $teamFilter = $teamId !== null ? ' AND cp.team_id = ?' : '';
        $params = [$clubId];
        if ($teamId !== null) $params[] = $teamId;

        $sql = "SELECT a.*, cp.name AS player_name
                FROM player_body_composition_assessments a
                JOIN club_players cp ON cp.id = a.linked_player_id
                JOIN (
                    SELECT linked_player_id, MAX(CONCAT(assessment_date, ' ', created_at)) AS max_key
                    FROM player_body_composition_assessments
                    WHERE deleted_at IS NULL AND club_id = ?$subStatusFilter
                    GROUP BY linked_player_id
                ) latest ON latest.linked_player_id = a.linked_player_id
                        AND CONCAT(a.assessment_date, ' ', a.created_at) = latest.max_key
                WHERE a.deleted_at IS NULL$teamFilter$outerStatusFilter";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        return array_map([self::class, 'mapNew'], $stmt->fetchAll(PDO::FETCH_ASSOC));
    }

    public static function latestUnifiedForClub(PDO $pdo, int $clubId, ?int $teamId = null): array
    {
        $sql = 'SELECT id, name, linked_user_id FROM club_players
                WHERE club_id = ? AND is_active = 1
                  AND (player_type IS NULL OR player_type = \'club\')';
        $params = [$clubId];
        if ($teamId !== null) {
            $sql .= ' AND team_id = ?';
            $params[] = $teamId;
        }
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        $result = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $player) {
            $measurement = self::latestForPlayer(
                $pdo,
                $player['id'],
                $player['linked_user_id'] !== null ? (int)$player['linked_user_id'] : null,
                true
            );
            if (!$measurement) continue;
            $measurement['player_name'] = $player['name'];
            $result[] = $measurement;
        }
        return $result;
    }

    private static function latestNew(
        PDO $pdo,
        ?string $linkedPlayerId,
        ?int $userId,
        bool $approvedOnly
    ): ?array {
        if (!SchemaInspector::hasTable($pdo, 'player_body_composition_assessments')) return null;
        $where = ['deleted_at IS NULL'];
        $params = [];
        if ($linkedPlayerId) {
            $where[] = 'linked_player_id = ?';
            $params[] = $linkedPlayerId;
        } elseif ($userId !== null) {
            $where[] = 'user_id = ?';
            $params[] = $userId;
        } else {
            return null;
        }
        // Approval gating removed — a coach-recorded measurement is usable
        // in reports the moment it's saved, no separate approval step.
        $stmt = $pdo->prepare(
            'SELECT * FROM player_body_composition_assessments
             WHERE ' . implode(' AND ', $where) . '
             ORDER BY assessment_date DESC, created_at DESC LIMIT 1'
        );
        $stmt->execute($params);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    private static function latestLegacy(PDO $pdo, ?string $linkedPlayerId, ?int $userId): ?array
    {
        if (!SchemaInspector::hasTable($pdo, 'player_body_metrics')) return null;
        if ($linkedPlayerId) {
            $stmt = $pdo->prepare(
                'SELECT * FROM player_body_metrics
                 WHERE linked_player_id = ?
                 ORDER BY measured_at DESC, id DESC LIMIT 1'
            );
            $stmt->execute([$linkedPlayerId]);
        } elseif ($userId !== null) {
            $stmt = $pdo->prepare(
                'SELECT * FROM player_body_metrics
                 WHERE user_id = ?
                 ORDER BY measured_at DESC, id DESC LIMIT 1'
            );
            $stmt->execute([$userId]);
        } else {
            return null;
        }
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    private static function mapNew(array $row): array
    {
        return [
            'id' => $row['id'],
            'linked_player_id' => $row['linked_player_id'] ?? null,
            'player_name' => $row['player_name'] ?? null,
            'measured_at' => trim(($row['assessment_date'] ?? '') . ' ' . ($row['assessment_time'] ?? '')),
            'weight_kg' => self::number($row['weight_kg'] ?? null),
            'height_cm' => self::number($row['height_cm'] ?? null),
            'body_fat_percentage' => self::number($row['body_fat_percentage'] ?? null),
            'fat_mass_kg' => self::number($row['fat_mass_kg'] ?? null),
            'fat_free_mass_kg' => self::number($row['fat_free_mass_kg'] ?? null),
            'muscle_mass_kg' => self::number($row['muscle_mass_kg'] ?? null),
            'measurement_method' => $row['measurement_method'] ?? 'skinfold',
            'status' => $row['approval_status'] ?? 'legacy_unreviewed',
            'source_system' => 'NEW_SYSTEM',
            'is_legacy' => false,
            'is_migrated' => !empty($row['legacy_source_id']),
            'raw' => $row,
        ];
    }

    private static function mapLegacy(array $row): array
    {
        return [
            'id' => $row['id'],
            'linked_player_id' => $row['linked_player_id'] ?? null,
            'player_name' => null,
            'measured_at' => $row['measured_at'] ?? null,
            'weight_kg' => self::number($row['weight_kg'] ?? null),
            'height_cm' => self::number($row['height_cm'] ?? null),
            'body_fat_percentage' => self::number($row['body_fat_percent'] ?? null),
            'fat_mass_kg' => self::number($row['fat_mass_kg'] ?? null),
            'fat_free_mass_kg' => self::number($row['lean_mass_kg'] ?? null),
            'muscle_mass_kg' => null,
            'measurement_method' => $row['measurement_method'] ?? null,
            'status' => 'legacy_unreviewed',
            'source_system' => 'LEGACY_SYSTEM',
            'is_legacy' => true,
            'is_migrated' => false,
            'raw' => $row,
        ];
    }

    private static function number($value): ?float
    {
        return $value === null ? null : (float)$value;
    }
}
