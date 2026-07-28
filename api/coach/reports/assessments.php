<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/report_helpers.php';

$user = rptAuthUser($pdo);

if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden'], 403);
}

$ctx = requireClubPermission($pdo, $user, 'assessments.read');

$playerId = trim($_GET['player_id'] ?? '');
if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);

// Verify player is in scope (exits 403 if not)
$cp = rptScopedPlayer($pdo, $playerId, $ctx['club_id']);

$assessments = rptFullAssessmentList($pdo, $cp['id'], $ctx['club_id']);

// Summary
$scores = array_column($assessments, 'overall_score');
if (!empty($scores)) {
    $best    = max($scores);
    $worst   = min($scores);
    $average = round(array_sum($scores) / count($scores), 1);
} else {
    $best = $worst = $average = null;
}

$trend = rptAssessmentTrend($assessments);

jsonOut([
    'success'     => true,
    'player'      => [
        'id'          => $cp['id'],
        'name'        => $cp['name'],
        'position'    => $cp['position']  ?? null,
        'team_name'   => $cp['team_name'] ?? null,
        'player_type' => $cp['player_type'] ?? 'club',
    ],
    'assessments' => $assessments,
    'summary'     => [
        'best_score'    => $best,
        'worst_score'   => $worst,
        'average_score' => $average,
        'trend'         => $trend,
    ],
]);
