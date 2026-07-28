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

// club, coach, academy only
if (in_array($user['role'], ['player', 'parent'], true)) {
    jsonOut(['error' => 'Forbidden'], 403);
}

$ctx = requireClubPermission($pdo, $user, 'assessments.read');

$playerId = trim($_GET['player_id'] ?? '');
if (!$playerId) jsonOut(['error' => 'player_id is required'], 400);

// Verify player belongs to this club's scope (exits 403 if not)
$cp = rptScopedPlayer($pdo, $playerId, $ctx['club_id']);

$linkedUserId = ($cp['linked_user_id'] !== null) ? (int)$cp['linked_user_id'] : null;

$bodyMetrics    = rptBodyMetrics($pdo, $linkedUserId, $playerId);
$hooperTrend    = rptHooperTrend($pdo, $cp['id']);
$rpeTrend       = rptRpeTrend($pdo, $cp['id']);
$assessmentHist = rptAssessmentHistory($pdo, $cp['id'], $ctx['club_id']);
$sessionHist    = rptSessionHistory($pdo, $cp['id'], $ctx['club_id']);
$summary        = rptPlayerSummary($pdo, $cp['id'], $cp['id'], $ctx['club_id']);

jsonOut([
    'success'            => true,
    'player'             => [
        'id'          => $cp['id'],
        'name'        => $cp['name'],
        'position'    => $cp['position']    ?? null,
        'team_name'   => $cp['team_name']   ?? null,
        'player_type' => $cp['player_type'] ?? 'club',
    ],
    'body_metrics'       => $bodyMetrics,
    'hooper_trend'       => $hooperTrend,
    'rpe_trend'          => $rpeTrend,
    'assessment_history' => $assessmentHist,
    'session_history'    => $sessionHist,
    'summary'            => $summary,
]);
