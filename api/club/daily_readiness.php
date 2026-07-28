<?php
/**
 * Unified Daily Readiness & Intervention Dashboard (roadmap item 6).
 *
 * Player questionnaire -> readiness check -> alert to physical coach/medical
 * staff -> treatment/nutrition intervention -> participation status decision.
 *
 * Coach-safe by construction: only ever reads club_players.status/
 * unavailable_reason/expected_return_date from the injury side (never
 * diagnosis/exam_notes/case detail), and physio_sessions.status only (never
 * specialist_notes/contraindications).
 *
 * GET  ?date=YYYY-MM-DD          — roster + readiness + today's decision for the whole club
 * POST action=set_decision        — log/update today's participation decision for a player
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';
require_once dirname(__DIR__) . '/includes/player_status.php';

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

const VALID_PARTICIPATION = ['fully_available', 'modified_training', 'unavailable'];

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx  = requireClubPermission($pdo, $user, 'daily_readiness.read');
    $date = trim($_GET['date'] ?? date('Y-m-d'));

    $roster = $pdo->prepare(
        'SELECT id, name, position, linked_user_id, status, unavailable_reason, expected_return_date
         FROM club_players
         WHERE club_id = ? AND is_active = 1 AND player_type = "club"
         ORDER BY name ASC'
    );
    $roster->execute([$ctx['club_id']]);
    $players = $roster->fetchAll(PDO::FETCH_ASSOC);

    $linkedUserIds = array_values(array_filter(array_column($players, 'linked_user_id')));

    // Today's Hooper check-in per player (readiness), same threshold logic
    // used by team-wellness.php — reused, not reinvented.
    $hooperByUser = [];
    if ($linkedUserIds) {
        $inList = implode(',', array_fill(0, count($linkedUserIds), '?'));
        $stmt = $pdo->prepare(
            "SELECT user_id, hooper_score, fatigue, sleep_quality
             FROM player_hooper_index
             WHERE DATE(submitted_at) = ? AND user_id IN ($inList)"
        );
        $stmt->execute(array_merge([$date], $linkedUserIds));
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $hooperByUser[(int)$row['user_id']] = $row;
        }
    }

    // Today's physio sessions (status only — no specialist notes/contraindications).
    $physioByPlayer = [];
    $stmt = $pdo->prepare(
        'SELECT player_id, status FROM physio_sessions
         WHERE club_id = ? AND DATE(scheduled_at) = ?'
    );
    $stmt->execute([$ctx['club_id'], $date]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $physioByPlayer[$row['player_id']] = $row['status'];
    }

    // Today's nutrition compliance status.
    $complianceByPlayer = [];
    $stmt = $pdo->prepare(
        'SELECT player_id, status FROM nutrition_compliance_logs
         WHERE club_id = ? AND log_date = ?'
    );
    $stmt->execute([$ctx['club_id'], $date]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $complianceByPlayer[$row['player_id']] = $row['status'];
    }

    // Today's logged participation decisions.
    $decisionByPlayer = [];
    $stmt = $pdo->prepare(
        'SELECT d.player_id, d.participation_status, d.allowed_duration_minutes,
                d.restrictions, u.name AS decided_by_name
         FROM player_daily_decisions d
         LEFT JOIN users u ON u.id = d.decided_by_user_id
         WHERE d.club_id = ? AND d.decision_date = ?'
    );
    $stmt->execute([$ctx['club_id'], $date]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $decisionByPlayer[$row['player_id']] = $row;
    }

    $out = [];
    foreach ($players as $p) {
        $userId = $p['linked_user_id'] ? (int)$p['linked_user_id'] : null;
        $hooper = $userId && isset($hooperByUser[$userId]) ? $hooperByUser[$userId] : null;

        $riskLevel = 'unknown';
        $needsAttention = false;
        if ($hooper) {
            $score = (float)$hooper['hooper_score'];
            $fatigue = (float)$hooper['fatigue'];
            $sleep = (float)$hooper['sleep_quality'];
            $needsAttention = $score >= 17 || $fatigue >= 6 || $sleep <= 2;
            if ($score >= 17) {
                $riskLevel = 'high_risk';
            } elseif ($needsAttention || $score >= 11) {
                $riskLevel = 'moderate';
            } else {
                $riskLevel = 'normal';
            }
        }

        $decision = $decisionByPlayer[$p['id']] ?? null;
        $compositeStatus = computePlayerCompositeStatus($p['status'], $hooper, $decision);

        $out[] = [
            'player_id'          => $p['id'],
            'player_name'        => $p['name'],
            'position'           => $p['position'],
            'checked_in'         => $hooper !== null,
            'hooper_score'       => $hooper ? (int)$hooper['hooper_score'] : null,
            'fatigue'            => $hooper ? (int)$hooper['fatigue'] : null,
            'sleep_quality'      => $hooper ? (int)$hooper['sleep_quality'] : null,
            'risk_level'         => $riskLevel,
            'needs_attention'    => $needsAttention,
            'composite_status'   => $compositeStatus,
            'status'             => $p['status'],
            'unavailable_reason' => $p['unavailable_reason'],
            'expected_return_date' => $p['expected_return_date'],
            'physio_today'       => $physioByPlayer[$p['id']] ?? null,
            'nutrition_status_today' => $complianceByPlayer[$p['id']] ?? null,
            'decision'           => $decision ? [
                'participation_status'     => $decision['participation_status'],
                'allowed_duration_minutes' => $decision['allowed_duration_minutes'] !== null
                    ? (int)$decision['allowed_duration_minutes'] : null,
                'restrictions'             => $decision['restrictions'],
                'decided_by_name'          => $decision['decided_by_name'],
            ] : null,
        ];
    }

    jsonOut(['success' => true, 'date' => $date, 'players' => $out]);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'daily_readiness.write');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? '');

    if ($action === 'set_decision') {
        $playerId = trim($body['player_id'] ?? '');
        if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);

        $ownStmt = $pdo->prepare('SELECT 1 FROM club_players WHERE id = ? AND club_id = ?');
        $ownStmt->execute([$playerId, $ctx['club_id']]);
        if (!$ownStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Player not found'], 404);

        $date = trim($body['decision_date'] ?? date('Y-m-d'));
        $status = in_array($body['participation_status'] ?? '', VALID_PARTICIPATION, true)
            ? $body['participation_status'] : 'fully_available';
        $duration = is_numeric($body['allowed_duration_minutes'] ?? null)
            ? (int)$body['allowed_duration_minutes'] : null;

        $stmt = $pdo->prepare(
            'INSERT INTO player_daily_decisions
                 (club_id, player_id, decision_date, participation_status, allowed_duration_minutes,
                  restrictions, decided_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 participation_status = VALUES(participation_status),
                 allowed_duration_minutes = VALUES(allowed_duration_minutes),
                 restrictions = VALUES(restrictions),
                 decided_by_user_id = VALUES(decided_by_user_id)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId, $date, $status, $duration,
            trim($body['restrictions'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
