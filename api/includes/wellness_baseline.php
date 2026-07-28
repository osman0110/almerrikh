<?php
// Personal wellness baselines — rolling averages of a player's OWN recent
// history, so "high" can mean "high for this player" instead of only a
// fixed cutoff applied identically to every player.

/**
 * Rolling 28-day Hooper Index baseline for a single player, computed from
 * history strictly before $beforeDate (so "today" never leaks into its own
 * baseline). Returns null when there isn't enough history yet (<5 entries)
 * — callers should fall back to the fixed absolute bands in that case.
 */
function getHooperBaseline(PDO $pdo, int $userId, string $beforeDate): ?array {
    $stmt = $pdo->prepare(
        'SELECT AVG(hooper_score) AS avg_score, STDDEV(hooper_score) AS stddev_score, COUNT(*) AS n
         FROM player_hooper_index
         WHERE user_id = ?
           AND submitted_at >= DATE_SUB(?, INTERVAL 28 DAY)
           AND submitted_at < ?'
    );
    $stmt->execute([$userId, $beforeDate, $beforeDate]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $n = (int)($row['n'] ?? 0);
    if ($n < 5) return null;

    return [
        'avg'    => round((float)$row['avg_score'], 1),
        'stddev' => round((float)($row['stddev_score'] ?? 0), 1),
        'n'      => $n,
    ];
}

/**
 * True when $todayScore is meaningfully elevated relative to the player's
 * own baseline (at least 3 points above their average, or 1 stddev if that
 * player's history is more variable than 3 points) — catches players whose
 * personal normal already runs high, and players whose normal is low enough
 * that the fixed absolute cutoff would miss an early warning sign.
 */
function isElevatedVsBaseline(float $todayScore, ?array $baseline): bool {
    if ($baseline === null) return false;
    $delta = max(3.0, $baseline['stddev']);
    return $todayScore >= ($baseline['avg'] + $delta);
}
