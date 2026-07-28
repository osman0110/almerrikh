<?php

final class EligiblePlayerRepository
{
    public static function activeForScope(PDO $pdo, int $clubId, ?int $teamId = null): array
    {
        $sql = 'SELECT id, name, position, team_name, team_id, linked_user_id, photo_url
                FROM club_players
                WHERE club_id = ? AND is_active = 1
                  AND (player_type IS NULL OR player_type = \'club\')';
        $params = [$clubId];
        if ($teamId !== null) {
            $sql .= ' AND team_id = ?';
            $params[] = $teamId;
        }
        $sql .= ' ORDER BY name ASC';
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    public static function populationSummary(array $players, array $submittedPlayerIds): array
    {
        $eligibleIds = array_values(array_unique(array_column($players, 'id')));
        $submitted = array_values(array_intersect(
            $eligibleIds,
            array_values(array_unique(array_filter($submittedPlayerIds)))
        ));
        $withAccounts = count(array_filter($players, fn(array $p) => !empty($p['linked_user_id'])));
        return [
            'eligible_players' => count($eligibleIds),
            'players_with_accounts' => $withAccounts,
            'players_without_accounts' => count($eligibleIds) - $withAccounts,
            'submitted_players' => count($submitted),
            'missing_players' => count($eligibleIds) - count($submitted),
        ];
    }
}
