<?php
/**
 * Club Staff + Access Codes API
 * GET               — list staff members for the caller's club
 * GET  ?codes=1      — list unified access codes for the caller's club
 * POST               — create an access code { account_type, note? }
 *                       account_type is 'player' or a staff role (coach/doctor/...).
 *                       Codes never expire and are reusable until deactivated/deleted.
 * POST { action:'toggle_code', code, is_active } — activate/deactivate a code
 * DELETE ?id=xxx     — remove/suspend a staff member (club_staff.id)
 * DELETE ?code=xxx   — permanently delete an access code
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

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
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user   = getAuthUser($pdo);
$method = $_SERVER['REQUEST_METHOD'];

// Only owner/admin manage staff — everything else (invite create/list/revoke)
$ctx = requireClubPermission($pdo, $user, 'staff.manage');

if ($method === 'GET' && !isset($_GET['codes'])) {
    $stmt = $pdo->prepare(
        'SELECT s.id, s.user_id, s.staff_role, s.status, s.created_at, u.name, u.email
         FROM club_staff s
         JOIN users u ON u.id = s.user_id
         WHERE s.club_id = ?
         ORDER BY FIELD(s.staff_role, "owner", "admin", "performance_manager", "coach", "tactical_coach", "doctor", "physiotherapist", "massage_specialist", "nutritionist", "analyst"), u.name ASC'
    );
    $stmt->execute([$ctx['club_id']]);
    jsonOut(['staff' => $stmt->fetchAll()]);
}

// 'player' + every invitable staff role — one list for the unified code system.
// 'massage_specialist' intentionally excluded — physiotherapy and massage
// are the same job at this club, so 'physiotherapist' is the single role
// for new invites (existing 'massage_specialist' accounts still work, see
// clubStaffCan() above).
$allowedAccountTypes = [
    'player',
    'admin', 'coach', 'tactical_coach', 'doctor', 'analyst',
    'performance_manager', 'physiotherapist', 'nutritionist',
];

if ($method === 'GET' && isset($_GET['codes'])) {
    $stmt = $pdo->prepare(
        'SELECT code, account_type, note, is_active, use_count, last_used_at, created_at
         FROM club_access_codes
         WHERE club_id = ?
         ORDER BY is_active DESC, created_at DESC'
    );
    $stmt->execute([$ctx['club_id']]);
    jsonOut(['codes' => $stmt->fetchAll()]);
}

if ($method === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    // ── Toggle an existing code active/inactive ───────────────────────────
    if (($body['action'] ?? '') === 'toggle_code') {
        $code     = trim($body['code'] ?? '');
        $isActive = !empty($body['is_active']) ? 1 : 0;
        if (!$code) jsonOut(['error' => 'code is required'], 400);
        $pdo->prepare('UPDATE club_access_codes SET is_active = ? WHERE code = ? AND club_id = ?')
            ->execute([$isActive, $code, $ctx['club_id']]);
        jsonOut(['success' => true, 'code' => $code, 'is_active' => (bool)$isActive]);
    }

    // ── Create a new access code ───────────────────────────────────────────
    $accountType = in_array($body['account_type'] ?? $body['staff_role'] ?? '', $allowedAccountTypes, true)
        ? ($body['account_type'] ?? $body['staff_role'])
        : 'coach';
    $note = trim($body['note'] ?? '');

    do {
        $code = strtoupper(substr(bin2hex(random_bytes(4)), 0, 8));
        $exists = $pdo->prepare('SELECT 1 FROM club_access_codes WHERE code = ?');
        $exists->execute([$code]);
    } while ($exists->fetchColumn());

    $ownerStmt = $pdo->prepare('SELECT owner_user_id FROM clubs WHERE id = ?');
    $ownerStmt->execute([$ctx['club_id']]);
    $clubUserId = (int)($ownerStmt->fetchColumn() ?: $user['id']);

    $pdo->prepare(
        'INSERT INTO club_access_codes (code, club_id, club_user_id, account_type, note, created_by_user_id)
         VALUES (?, ?, ?, ?, ?, ?)'
    )->execute([$code, $ctx['club_id'], $clubUserId, $accountType, $note ?: null, $user['id']]);

    jsonOut(['code' => $code, 'account_type' => $accountType]);
}

if ($method === 'DELETE') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $code = $_GET['code'] ?? ($body['code'] ?? '');
    if ($code) {
        $pdo->prepare('DELETE FROM club_access_codes WHERE code = ? AND club_id = ?')
            ->execute([$code, $ctx['club_id']]);
        jsonOut(['success' => true]);
    }

    $id = $_GET['id'] ?? ($body['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id or code is required'], 400);

    // Never allow removing the owner via this endpoint.
    $pdo->prepare(
        "UPDATE club_staff SET status = 'suspended'
         WHERE id = ? AND club_id = ? AND staff_role != 'owner'"
    )->execute([$id, $ctx['club_id']]);

    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
