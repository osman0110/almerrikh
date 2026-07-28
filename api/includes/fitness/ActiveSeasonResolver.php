<?php

require_once __DIR__ . '/SchemaInspector.php';

final class ActiveSeasonResolver
{
    public static function resolve(PDO $pdo, int $clubId, ?int $teamId = null): ?array
    {
        if (!SchemaInspector::hasTable($pdo, 'club_seasons')) return null;

        $sql = 'SELECT id AS active_season_id, club_id, team_id, starts_on, ends_on, status
                FROM club_seasons
                WHERE club_id = ? AND status = \'active\'';
        $params = [$clubId];
        if ($teamId !== null) {
            $sql .= ' AND (team_id = ? OR team_id IS NULL)';
            $params[] = $teamId;
        }
        $sql .= ' ORDER BY team_id IS NULL ASC, starts_on DESC LIMIT 1';

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }
}
