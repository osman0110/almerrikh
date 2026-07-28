<?php
/**
 * Injury / Rehab / Return-to-Play file.
 * Clinical detail — gated behind medical_detail.read/write (doctor,
 * physiotherapist only). Coach-visible status/return-date stays on the
 * existing club_players.status/expected_return_date fields, untouched here.
 *
 * GET  ?player_id=X            — list cases for a player (newest first)
 * GET  ?id=X&updates=1         — one case + its update timeline
 * POST action=create           — open a new injury case
 * POST action=update           — add a timeline update, optionally advance
 *                                 rtp_stage/case_status
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

const VALID_SEVERITY = ['mild', 'moderate', 'severe'];
const VALID_CASE_STATUS = ['open', 'in_treatment', 'rehab', 'graduated', 'closed'];
const VALID_RTP_STAGE = ['rest', 'light_activity', 'running', 'noncontact_training', 'full_training', 'match_ready'];

function caseOut(array $c): array {
    return [
        'id'                   => (string)$c['id'],
        'player_id'            => $c['player_id'],
        'injury_date'          => $c['injury_date'],
        'body_location'        => $c['body_location'],
        'injury_type'          => $c['injury_type'],
        'severity'             => $c['severity'],
        'diagnosis'            => $c['diagnosis'],
        'exam_notes'           => $c['exam_notes'],
        'case_status'          => $c['case_status'],
        'rtp_stage'            => $c['rtp_stage'],
        'expected_return_date' => $c['expected_return_date'],
        'actual_return_date'   => $c['actual_return_date'],
        'created_at'           => $c['created_at'],
        'updated_at'           => $c['updated_at'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'medical_detail.read');

    $id = trim($_GET['id'] ?? '');
    if ($id) {
        $stmt = $pdo->prepare('SELECT * FROM injury_cases WHERE id = ? AND club_id = ?');
        $stmt->execute([$id, $ctx['club_id']]);
        $case = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$case) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $result = ['success' => true, 'case' => caseOut($case)];

        if (($_GET['updates'] ?? '') === '1') {
            $uStmt = $pdo->prepare(
                'SELECT u.id, u.note, u.rtp_stage, u.case_status, u.created_at, users.name AS author_name
                 FROM injury_updates u
                 JOIN users ON users.id = u.author_user_id
                 WHERE u.injury_case_id = ?
                 ORDER BY u.created_at DESC'
            );
            $uStmt->execute([$id]);
            $result['updates'] = array_map(function ($u) {
                return [
                    'id'           => (string)$u['id'],
                    'note'         => $u['note'],
                    'rtp_stage'    => $u['rtp_stage'],
                    'case_status'  => $u['case_status'],
                    'author_name'  => $u['author_name'],
                    'created_at'   => $u['created_at'],
                ];
            }, $uStmt->fetchAll());
        }

        jsonOut($result);
    }

    $playerId = trim($_GET['player_id'] ?? '');
    if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id or id is required'], 400);

    $stmt = $pdo->prepare(
        'SELECT * FROM injury_cases WHERE player_id = ? AND club_id = ? ORDER BY injury_date DESC, id DESC'
    );
    $stmt->execute([$playerId, $ctx['club_id']]);
    jsonOut(['success' => true, 'cases' => array_map('caseOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'medical_detail.write');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? 'create');

    if ($action === 'create') {
        $playerId = trim($body['player_id'] ?? '');
        $injuryDate = trim($body['injury_date'] ?? '');
        if (!$playerId)  jsonOut(['success' => false, 'message' => 'player_id is required'], 400);
        if (!$injuryDate) jsonOut(['success' => false, 'message' => 'injury_date is required'], 400);

        $ownStmt = $pdo->prepare('SELECT status FROM club_players WHERE id = ? AND club_id = ?');
        $ownStmt->execute([$playerId, $ctx['club_id']]);
        $priorStatus = $ownStmt->fetchColumn();
        if ($priorStatus === false) jsonOut(['success' => false, 'message' => 'Player not found'], 404);

        $severity = in_array($body['severity'] ?? '', VALID_SEVERITY, true) ? $body['severity'] : 'moderate';

        $stmt = $pdo->prepare(
            'INSERT INTO injury_cases
                 (club_id, player_id, injury_date, body_location, injury_type, severity,
                  diagnosis, exam_notes, case_status, rtp_stage, expected_return_date, created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, \'open\', \'rest\', ?, ?)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId, $injuryDate,
            trim($body['body_location'] ?? '') ?: null,
            trim($body['injury_type'] ?? '') ?: null,
            $severity,
            trim($body['diagnosis'] ?? '') ?: null,
            trim($body['exam_notes'] ?? '') ?: null,
            trim($body['expected_return_date'] ?? '') ?: null,
            $user['id'],
        ]);
        $caseId = (int)$pdo->lastInsertId();

        // Mirror onto the coach-visible legacy fields so the existing
        // Availability Card reflects the new case immediately.
        $pdo->prepare(
            "UPDATE club_players SET status = 'injured', unavailable_reason = ?, expected_return_date = ?
             WHERE id = ? AND club_id = ?"
        )->execute([
            trim($body['injury_type'] ?? '') ?: 'Injury',
            trim($body['expected_return_date'] ?? '') ?: null,
            $playerId, $ctx['club_id'],
        ]);
        if ($priorStatus !== 'injured') {
            recordPlayerStatusChange($pdo, $playerId, $priorStatus ?: null, 'injured', $user['id'], 'Injury case opened');
        }

        $pdo->prepare(
            'INSERT INTO injury_updates (injury_case_id, author_user_id, note, rtp_stage, case_status)
             VALUES (?, ?, ?, \'rest\', \'open\')'
        )->execute([$caseId, $user['id'], 'Case opened']);

        // Notify doctor + physiotherapist staff (per the injury workflow —
        // they need to pick up diagnosis/treatment from here), excluding
        // whoever just opened the case.
        $staffStmt = $pdo->prepare(
            "SELECT user_id FROM club_staff
             WHERE club_id = ? AND status = 'active'
               AND staff_role IN ('doctor', 'physiotherapist', 'massage_specialist')
               AND user_id != ?"
        );
        $staffStmt->execute([$ctx['club_id'], $user['id']]);
        $playerName = $pdo->prepare('SELECT name FROM club_players WHERE id = ?');
        $playerName->execute([$playerId]);
        $pName = $playerName->fetchColumn() ?: '';
        foreach ($staffStmt->fetchAll(PDO::FETCH_COLUMN) as $staffUserId) {
            createNotification(
                $pdo, $ctx['club_id'], (int)$staffUserId,
                'injury_created',
                'إصابة جديدة: ' . $pName,
                trim($body['injury_type'] ?? ''),
                '/club/players/' . $playerId
            );
        }

        jsonOut(['success' => true, 'id' => (string)$caseId]);
    }

    if ($action === 'update') {
        $caseId = trim($body['id'] ?? '');
        if (!$caseId) jsonOut(['success' => false, 'message' => 'id is required'], 400);

        $stmt = $pdo->prepare('SELECT * FROM injury_cases WHERE id = ? AND club_id = ?');
        $stmt->execute([$caseId, $ctx['club_id']]);
        $case = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$case) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $note = trim($body['note'] ?? '');
        $rtpStage = in_array($body['rtp_stage'] ?? '', VALID_RTP_STAGE, true) ? $body['rtp_stage'] : null;
        $caseStatus = in_array($body['case_status'] ?? '', VALID_CASE_STATUS, true) ? $body['case_status'] : null;

        if (!$note && !$rtpStage && !$caseStatus) {
            jsonOut(['success' => false, 'message' => 'note, rtp_stage or case_status is required'], 400);
        }

        $newStage  = $rtpStage ?: $case['rtp_stage'];
        $newStatus = $caseStatus ?: $case['case_status'];
        $isClosing = $caseStatus && in_array($caseStatus, ['graduated', 'closed'], true);

        $pdo->prepare(
            'UPDATE injury_cases SET rtp_stage = ?, case_status = ?, actual_return_date = COALESCE(actual_return_date, ?)
             WHERE id = ?'
        )->execute([
            $newStage, $newStatus,
            $isClosing ? date('Y-m-d') : null,
            $caseId,
        ]);

        $pdo->prepare(
            'INSERT INTO injury_updates (injury_case_id, author_user_id, note, rtp_stage, case_status)
             VALUES (?, ?, ?, ?, ?)'
        )->execute([$caseId, $user['id'], $note ?: null, $rtpStage, $caseStatus]);

        if ($isClosing) {
            $priorStmt = $pdo->prepare('SELECT status FROM club_players WHERE id = ? AND club_id = ?');
            $priorStmt->execute([$case['player_id'], $ctx['club_id']]);
            $priorStatus = $priorStmt->fetchColumn();

            $pdo->prepare(
                "UPDATE club_players SET status = 'active', unavailable_reason = NULL
                 WHERE id = ? AND club_id = ?"
            )->execute([$case['player_id'], $ctx['club_id']]);

            if ($priorStatus !== false && $priorStatus !== 'active') {
                recordPlayerStatusChange(
                    $pdo, $case['player_id'], $priorStatus ?: null, 'active', $user['id'],
                    'Injury case ' . $caseStatus
                );
            }
        }

        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
