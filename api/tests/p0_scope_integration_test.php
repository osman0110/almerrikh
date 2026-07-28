<?php
// Integration test skeleton. It intentionally refuses to run outside an
// explicitly configured test database.
if (getenv('APP_ENV') !== 'test' || getenv('TEST_DB_NAME') === false) {
    fwrite(STDERR, "Refusing to run: set APP_ENV=test and TEST_DB_NAME.\n");
    exit(2);
}

require_once dirname(__DIR__) . '/includes/fitness/EligiblePlayerRepository.php';
require_once dirname(__DIR__) . '/includes/fitness/BodyCompositionRepository.php';

$pdo = new PDO(
    'mysql:host=' . (getenv('TEST_DB_HOST') ?: '127.0.0.1')
        . ';dbname=' . getenv('TEST_DB_NAME') . ';charset=utf8mb4',
    getenv('TEST_DB_USER') ?: 'root',
    getenv('TEST_DB_PASS') ?: '',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);

$pdo->beginTransaction();
try {
    $seed = random_int(100000, 900000);
    $clubA = 1000000000 + $seed;
    $clubB = 1100000000 + $seed;
    $teamA = 1200000000 + $seed;
    $teamB = 1300000000 + $seed;
    $playerA = 'p0_scope_a_' . $seed;
    $playerB = 'p0_scope_b_' . $seed;
    $playerOtherClub = 'p0_scope_other_' . $seed;

    $insert = $pdo->prepare(
        'INSERT INTO club_players
         (id, user_id, name, player_type, linked_user_id, is_active, club_id, team_id)
         VALUES (?, 1, ?, \'club\', ?, 1, ?, ?)'
    );
    $insert->execute([$playerA, 'P0 Scope A', null, $clubA, $teamA]);
    $insert->execute([$playerB, 'P0 Scope B', 1, $clubA, $teamB]);
    $insert->execute([$playerOtherClub, 'P0 Scope Other', null, $clubB, $teamA]);

    $clubPlayers = EligiblePlayerRepository::activeForScope($pdo, $clubA, null);
    $teamAPlayers = EligiblePlayerRepository::activeForScope($pdo, $clubA, $teamA);
    $teamBPlayers = EligiblePlayerRepository::activeForScope($pdo, $clubA, $teamB);
    $otherClubPlayers = EligiblePlayerRepository::activeForScope($pdo, $clubB, null);

    if (!$clubPlayers) throw new RuntimeException('Club A fixture has no players');
    if (array_intersect(array_column($teamAPlayers, 'id'), array_column($teamBPlayers, 'id'))) {
        throw new RuntimeException('Team scopes overlap unexpectedly');
    }
    if (array_intersect(array_column($clubPlayers, 'id'), array_column($otherClubPlayers, 'id'))) {
        throw new RuntimeException('Cross-club data leak');
    }
    if (!array_filter($clubPlayers, fn(array $p) => empty($p['linked_user_id']))) {
        throw new RuntimeException('Player without an account was excluded');
    }
    echo "p0_scope_integration_test: OK\n";
} finally {
    $pdo->rollBack();
}
