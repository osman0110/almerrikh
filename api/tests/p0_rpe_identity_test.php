<?php
require_once dirname(__DIR__) . '/includes/fitness/RpeIdentity.php';

function rpeP0Assert($condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}

$first = RpeIdentity::logicalKey('player-1', 10, 'session-7', 'post', '2026-07-26', 'team', null);
$replay = RpeIdentity::logicalKey('player-1', 99, 'session-7', 'post', '2026-07-27', 'other', 'ignored');
rpeP0Assert($first === $replay, 'Same player/session/source must have the same logical key');

$otherSession = RpeIdentity::logicalKey('player-1', 10, 'session-8', 'post', '2026-07-26', 'team', null);
rpeP0Assert($first !== $otherSession, 'Different sessions must not collide');

$standaloneA = RpeIdentity::logicalKey('player-1', 10, null, 'post', '2026-07-26', 'match', 'match-3');
$standaloneReplay = RpeIdentity::logicalKey('player-1', 10, null, 'post', '2026-07-26', 'match', 'match-3');
rpeP0Assert($standaloneA === $standaloneReplay, 'Standalone idempotent activity must be stable');

$secondActivity = RpeIdentity::logicalKey('player-1', 10, null, 'post', '2026-07-26', 'match', 'match-4');
rpeP0Assert($standaloneA !== $secondActivity, 'External reference must separate same-day activities');

echo "p0_rpe_identity_test: OK\n";
