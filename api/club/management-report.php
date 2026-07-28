<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';
require_once '../includes/club_auth.php';

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization'] ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
    return trim($auth);
}

$token = bearerToken();
if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

$stmt = $pdo->prepare(
    'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) jsonOut(['error' => 'Invalid token'], 401);
if (in_array($user['role'], ['player', 'parent'])) jsonOut(['error' => 'Forbidden'], 403);

$ctx = requireClubPermission($pdo, $user, 'management_report.view');
$cid = (int)$ctx['club_id'];

$to   = trim($_GET['to']   ?? '') ?: date('Y-m-d');
$from = trim($_GET['from'] ?? '') ?: date('Y-m-d', strtotime('-30 days', strtotime($to)));
$teamId = isset($_GET['team_id']) && $_GET['team_id'] !== '' ? (int)$_GET['team_id'] : null;

// Roster — matches/club_sessions carry no team_id of their own, so team
// scoping is applied here (which players to report on), not on the
// matches/session_attendance/match_cards queries below, which are
// inherently club-wide.
$rosterSql = 'SELECT id, name FROM club_players WHERE club_id = ? AND is_active = 1';
$rosterParams = [$cid];
if ($teamId !== null) {
    $rosterSql .= ' AND team_id = ?';
    $rosterParams[] = $teamId;
}
$rosterStmt = $pdo->prepare($rosterSql);
$rosterStmt->execute($rosterParams);

$players = [];
foreach ($rosterStmt->fetchAll() as $p) {
    $players[$p['id']] = [
        'player_id'  => $p['id'],
        'name'       => $p['name'],
        'minutes'    => 0,
        'attendance' => ['present' => 0, 'late' => 0, 'absent' => 0],
        'sessions'   => ['completed' => 0, 'assigned' => 0],
        'cards'      => ['yellow' => 0, 'red' => 0],
    ];
}

// ── Minutes: sum player_minutes JSON across matches in range ────────────────
$mStmt = $pdo->prepare(
    'SELECT player_minutes FROM matches WHERE club_id = ? AND match_date BETWEEN ? AND ?'
);
$mStmt->execute([$cid, $from, $to]);
foreach ($mStmt->fetchAll() as $row) {
    $minutes = $row['player_minutes'] && $row['player_minutes'] !== 'null'
        ? json_decode($row['player_minutes'], true) ?? [] : [];
    foreach ($minutes as $playerId => $mins) {
        if (isset($players[$playerId])) {
            $players[$playerId]['minutes'] += (int)$mins;
        }
    }
}

// ── Attendance: present/late/absent counts in range ──────────────────────────
$aStmt = $pdo->prepare(
    'SELECT sa.player_id, sa.status, COUNT(*) AS cnt
     FROM session_attendance sa
     JOIN club_sessions cs ON cs.id = sa.session_id
     WHERE cs.club_id = ? AND cs.date BETWEEN ? AND ?
     GROUP BY sa.player_id, sa.status'
);
$aStmt->execute([$cid, $from, $to]);
foreach ($aStmt->fetchAll() as $row) {
    $pid = $row['player_id'];
    $status = $row['status'];
    if (isset($players[$pid]) && in_array($status, ['present', 'late', 'absent'], true)) {
        $players[$pid]['attendance'][$status] = (int)$row['cnt'];
    }
}

// Sessions: assignment is counted as soon as the player is added. A session
// is completed for that player only after its coach evaluation is saved.
$evaluatedBySession = [];
$eStmt = $pdo->prepare(
    'SELECT ce.session_id, ce.player_id
     FROM coach_evaluations ce
     JOIN club_sessions cs ON cs.id = ce.session_id
     WHERE ce.club_id = ? AND cs.club_id = ? AND ce.session_id IS NOT NULL
       AND (cs.status IS NULL OR cs.status <> ?)'
);
$eStmt->execute([$cid, $cid, 'cancelled']);
foreach ($eStmt->fetchAll() as $row) {
    $evaluatedBySession[(string)$row['session_id']][(string)$row['player_id']] = true;
}

$sStmt = $pdo->prepare(
    'SELECT id, player_ids
     FROM club_sessions
     WHERE club_id = ? AND (status IS NULL OR status <> ?)'
);
$sStmt->execute([$cid, 'cancelled']);
foreach ($sStmt->fetchAll() as $row) {
    $assignedIds = $row['player_ids'] && $row['player_ids'] !== 'null'
        ? json_decode($row['player_ids'], true) ?? [] : [];
    if (!is_array($assignedIds)) continue;

    $sessionId = (string)$row['id'];
    foreach (array_unique(array_map('strval', $assignedIds)) as $playerId) {
        if (!isset($players[$playerId])) continue;
        $players[$playerId]['sessions']['assigned']++;
        if (isset($evaluatedBySession[$sessionId][$playerId])) {
            $players[$playerId]['sessions']['completed']++;
        }
    }
}

// ── Cards: yellow/red counts in range ────────────────────────────────────────
$cStmt = $pdo->prepare(
    'SELECT mc.player_id, mc.card_type, COUNT(*) AS cnt
     FROM match_cards mc
     JOIN matches m ON m.id = mc.match_id
     WHERE m.club_id = ? AND m.match_date BETWEEN ? AND ?
     GROUP BY mc.player_id, mc.card_type'
);
$cStmt->execute([$cid, $from, $to]);
foreach ($cStmt->fetchAll() as $row) {
    $pid = $row['player_id'];
    $type = $row['card_type'];
    if (isset($players[$pid]) && in_array($type, ['yellow', 'red'], true)) {
        $players[$pid]['cards'][$type] = (int)$row['cnt'];
    }
}

jsonOut([
    'players' => array_values($players),
    'range'   => ['from' => $from, 'to' => $to],
]);
