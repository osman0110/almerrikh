<?php
// ─────────────────────────────────────────────────────────────────────────────
// Player status history — single choke point for writing a row to
// player_status_history (see api/db.php) whenever club_players.status
// actually changes. Call this alongside the status UPDATE, not instead of it
// — this table is a read-only trail, not the source of truth.
// ─────────────────────────────────────────────────────────────────────────────

function recordPlayerStatusChange(
    PDO $pdo,
    string $playerId,
    ?string $oldStatus,
    string $newStatus,
    int $changedByUserId,
    ?string $reason = null
): void {
    $pdo->prepare(
        'INSERT INTO player_status_history (player_id, old_status, new_status, changed_by_user_id, reason)
         VALUES (?, ?, ?, ?, ?)'
    )->execute([$playerId, $oldStatus, $newStatus, $changedByUserId, $reason]);
}

// ─────────────────────────────────────────────────────────────────────────────
// computePlayerCompositeStatus — single source of truth for the "one glance"
// player state shown across the daily readiness screen / admin dashboard.
// Combines the longer-running injury status (club_players.status) with
// today's readiness check-in (Hooper) and today's coach participation
// decision, so every screen agrees on what "ready" actually means instead of
// each computing its own risk_level inline.
//
// Returns one of: ready | ready_with_note | high_strain | injured | rehab |
// incomplete_data.
//
// $playerStatus — club_players.status ('active'|'injured'|'recovering'|
//                 'inactive'|'suspended')
// $hooper       — ['hooper_score' => float, 'fatigue' => float,
//                  'sleep_quality' => float] or null if no check-in today
// $decision     — ['participation_status' => 'fully_available'|
//                  'modified_training'|'unavailable'] or null if not decided
// ─────────────────────────────────────────────────────────────────────────────
function computePlayerCompositeStatus(
    string $playerStatus,
    ?array $hooper,
    ?array $decision
): string {
    if ($playerStatus === 'injured') return 'injured';
    if ($playerStatus === 'recovering') return 'rehab';

    if ($decision !== null) {
        $participation = $decision['participation_status'] ?? null;
        if ($participation === 'unavailable') return 'injured';
        if ($participation === 'modified_training') return 'ready_with_note';
    }

    if ($hooper === null) return 'incomplete_data';

    $score   = (float)($hooper['hooper_score'] ?? 0);
    $fatigue = (float)($hooper['fatigue'] ?? 0);
    $sleep   = (float)($hooper['sleep_quality'] ?? 5);

    if ($score >= 17) return 'high_strain';
    if ($score >= 11 || $fatigue >= 6 || $sleep <= 2) return 'ready_with_note';
    return 'ready';
}
