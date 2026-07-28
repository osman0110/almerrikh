<?php
/**
 * Return-to-Play phase tracking — the 8-stage progression behind an
 * injury_cases row (injury_cases.rtp_stage stays the coach-visible single
 * summary field; this table is the detailed phase-by-phase record).
 * Gated behind medical_detail.read/write (doctor, physiotherapist only —
 * same as injuries.php).
 *
 * GET  ?injury_case_id=X          — list phases for a case (ordered)
 * POST action=upsert              — create or update a phase's detail
 * POST action=complete             — mark a phase completed (no auto-advance)
 * POST action=advance              — complete current phase + start the next
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/notifications.php';

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

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['success' => false, 'message' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.name FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

// Fixed 8-stage progression, in order. Stages 7-8 hand the player back to
// the coach, so notifications for those go to coach/performance_manager
// instead of doctor/physiotherapist.
const RTP_PHASES = [
    1 => 'pain_control',
    2 => 'rom',
    3 => 'strength',
    4 => 'balance_control',
    5 => 'running',
    6 => 'football_specific',
    7 => 'partial_training',
    8 => 'full_return',
];
const COACH_HANDOFF_PHASES = [7, 8];

function phaseOut(array $p): array {
    return [
        'id'                  => (string)$p['id'],
        'phase_number'        => (int)$p['phase_number'],
        'phase_key'           => $p['phase_key'],
        'status'              => $p['status'],
        'start_date'          => $p['start_date'],
        'expected_end_date'   => $p['expected_end_date'],
        'actual_end_date'     => $p['actual_end_date'],
        'goals'               => $p['goals'],
        'exercises'           => $p['exercises'],
        'completion_percent'  => (int)$p['completion_percent'],
        'pain_score'          => $p['pain_score'] !== null ? (int)$p['pain_score'] : null,
        'player_notes'        => $p['player_notes'],
        'specialist_notes'    => $p['specialist_notes'],
        'approved_by_user_id' => $p['approved_by_user_id'] !== null ? (string)$p['approved_by_user_id'] : null,
        'created_at'          => $p['created_at'],
        'updated_at'          => $p['updated_at'],
    ];
}

function notifyPhaseChange(PDO $pdo, int $clubId, string $injuryCaseId, int $phaseNumber, string $eventLabel): void {
    $caseStmt = $pdo->prepare('SELECT player_id FROM injury_cases WHERE id = ?');
    $caseStmt->execute([$injuryCaseId]);
    $playerId = $caseStmt->fetchColumn();
    if (!$playerId) return;

    $nameStmt = $pdo->prepare('SELECT name FROM club_players WHERE id = ?');
    $nameStmt->execute([$playerId]);
    $playerName = $nameStmt->fetchColumn() ?: '';

    $roles = in_array($phaseNumber, COACH_HANDOFF_PHASES, true)
        ? ['coach', 'performance_manager']
        : ['doctor', 'physiotherapist', 'massage_specialist'];
    $placeholders = implode(',', array_fill(0, count($roles), '?'));
    $staffStmt = $pdo->prepare(
        "SELECT user_id FROM club_staff
         WHERE club_id = ? AND status = 'active' AND staff_role IN ($placeholders)"
    );
    $staffStmt->execute(array_merge([$clubId], $roles));

    foreach ($staffStmt->fetchAll(PDO::FETCH_COLUMN) as $staffUserId) {
        createNotification(
            $pdo, $clubId, (int)$staffUserId,
            'rtp_phase_change',
            "$eventLabel: $playerName",
            'المرحلة ' . $phaseNumber . ' — ' . (RTP_PHASES[$phaseNumber] ?? ''),
            '/club/players/' . $playerId
        );
    }
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'medical_detail.read');

    $injuryCaseId = trim($_GET['injury_case_id'] ?? '');
    if (!$injuryCaseId) jsonOut(['success' => false, 'message' => 'injury_case_id is required'], 400);

    $caseStmt = $pdo->prepare('SELECT id FROM injury_cases WHERE id = ? AND club_id = ?');
    $caseStmt->execute([$injuryCaseId, $ctx['club_id']]);
    if (!$caseStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Not found'], 404);

    $stmt = $pdo->prepare(
        'SELECT * FROM rehabilitation_phases WHERE injury_case_id = ? ORDER BY phase_number ASC'
    );
    $stmt->execute([$injuryCaseId]);
    jsonOut(['success' => true, 'phases' => array_map('phaseOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'medical_detail.write');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? 'upsert');

    $injuryCaseId = trim($body['injury_case_id'] ?? '');
    if (!$injuryCaseId) jsonOut(['success' => false, 'message' => 'injury_case_id is required'], 400);

    $caseStmt = $pdo->prepare('SELECT id FROM injury_cases WHERE id = ? AND club_id = ?');
    $caseStmt->execute([$injuryCaseId, $ctx['club_id']]);
    if (!$caseStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Injury case not found'], 404);

    if ($action === 'upsert') {
        $phaseNumber = (int)($body['phase_number'] ?? 0);
        if (!isset(RTP_PHASES[$phaseNumber])) jsonOut(['success' => false, 'message' => 'Invalid phase_number'], 400);

        $stmt = $pdo->prepare(
            'INSERT INTO rehabilitation_phases
                 (injury_case_id, phase_number, phase_key, start_date, expected_end_date,
                  goals, exercises, completion_percent, pain_score, player_notes, specialist_notes,
                  created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 expected_end_date  = VALUES(expected_end_date),
                 goals              = VALUES(goals),
                 exercises          = VALUES(exercises),
                 completion_percent = VALUES(completion_percent),
                 pain_score         = VALUES(pain_score),
                 player_notes       = VALUES(player_notes),
                 specialist_notes   = VALUES(specialist_notes)'
        );
        $stmt->execute([
            $injuryCaseId, $phaseNumber, RTP_PHASES[$phaseNumber],
            trim($body['start_date'] ?? '') ?: date('Y-m-d'),
            trim($body['expected_end_date'] ?? '') ?: null,
            trim($body['goals'] ?? '') ?: null,
            trim($body['exercises'] ?? '') ?: null,
            (int)($body['completion_percent'] ?? 0),
            isset($body['pain_score']) ? (int)$body['pain_score'] : null,
            trim($body['player_notes'] ?? '') ?: null,
            trim($body['specialist_notes'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true]);
    }

    if ($action === 'complete' || $action === 'advance') {
        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['success' => false, 'message' => 'id is required'], 400);

        $stmt = $pdo->prepare(
            'SELECT p.* FROM rehabilitation_phases p
             JOIN injury_cases c ON c.id = p.injury_case_id
             WHERE p.id = ? AND c.club_id = ?'
        );
        $stmt->execute([$id, $ctx['club_id']]);
        $phase = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$phase) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $pdo->prepare(
            "UPDATE rehabilitation_phases
             SET status = 'completed', completion_percent = 100, actual_end_date = COALESCE(actual_end_date, ?),
                 approved_by_user_id = ?
             WHERE id = ?"
        )->execute([date('Y-m-d'), $user['id'], $id]);

        notifyPhaseChange($pdo, $ctx['club_id'], $phase['injury_case_id'], (int)$phase['phase_number'], 'مرحلة مكتملة');

        if ($action === 'advance') {
            $nextNumber = (int)$phase['phase_number'] + 1;
            if (isset(RTP_PHASES[$nextNumber])) {
                $pdo->prepare(
                    'INSERT INTO rehabilitation_phases
                         (injury_case_id, phase_number, phase_key, start_date, created_by_user_id)
                     VALUES (?, ?, ?, ?, ?)
                     ON DUPLICATE KEY UPDATE start_date = start_date'
                )->execute([$phase['injury_case_id'], $nextNumber, RTP_PHASES[$nextNumber], date('Y-m-d'), $user['id']]);

                notifyPhaseChange($pdo, $ctx['club_id'], $phase['injury_case_id'], $nextNumber, 'مرحلة جديدة بدأت');
            }
        }

        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
