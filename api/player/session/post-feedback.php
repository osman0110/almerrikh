<?php

/**
 * Backwards-compatible alias for older app versions.
 *
 * Session RPE is now a single-question workflow with player-specific duration,
 * duplicate protection and revision tracking in player/rpe/save.php.
 */
$body = json_decode(file_get_contents('php://input'), true) ?? [];
if (isset($body['post_rpe']) && !isset($body['rpe_score'])) {
    $body['rpe_score'] = $body['post_rpe'];
}

// Legacy wellness-style answers are intentionally not forwarded into RPE.
unset(
    $body['pain_reported'],
    $body['difficulty'],
    $body['mood_after'],
    $body['notes'],
    $body['completed_full_session'],
    $body['incomplete_reason']
);

$GLOBALS['sessionRpeRequestBody'] = $body;
require dirname(__DIR__) . '/rpe/save.php';
