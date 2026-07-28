<?php
/**
 * Club Staff + Access Codes API
 * GET               — list staff members for the caller's club
 * GET  ?codes=1      — list unified access codes for the caller's club
 * POST               — create an access code { account_type, note? }
 *                       account_type is 'player' or a staff role (coach/doctor/...).
 *                       Player codes are reusable; staff invitations are
 *                       single-use and expire after 72 hours.
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
    $hasTeamScope = SchemaInspector::hasColumn($pdo, 'club_staff', 'team_id');
    $stmt = $pdo->prepare(
        'SELECT s.id, s.user_id, s.staff_role, s.status, s.created_at,
                ' . ($hasTeamScope ? 's.team_id, ct.name AS team_name,' : 'NULL AS team_id, NULL AS team_name,') . '
                u.name, u.email
         FROM club_staff s
         JOIN users u ON u.id = s.user_id
         ' . ($hasTeamScope
            ? 'LEFT JOIN club_teams ct ON ct.id = s.team_id AND ct.club_id = s.club_id'
            : '') . '
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
        'SELECT code, account_type, note, is_active, use_count, last_used_at, created_at,
                CASE
                    WHEN account_type != "player" AND use_count > 0 THEN "used"
                    WHEN is_active = 0 THEN "revoked"
                    WHEN account_type != "player"
                         AND created_at < DATE_SUB(NOW(), INTERVAL 72 HOUR) THEN "expired"
                    ELSE "active"
                END AS invitation_status,
                CASE
                    WHEN account_type != "player"
                    THEN DATE_ADD(created_at, INTERVAL 72 HOUR)
                    ELSE NULL
                END AS expires_at
         FROM club_access_codes
         WHERE club_id = ?
         ORDER BY is_active DESC, created_at DESC'
    );
    $stmt->execute([$ctx['club_id']]);
    jsonOut(['codes' => $stmt->fetchAll()]);
}

if ($method === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    if (($body['action'] ?? '') === 'assign_team') {
        if (!SchemaInspector::hasColumn($pdo, 'club_staff', 'team_id')) {
            jsonOut(['error' => 'club_staff.team_id is missing'], 409);
        }
        $staffId = (int)($body['staff_id'] ?? 0);
        $teamId = (int)($body['team_id'] ?? 0);
        if ($staffId <= 0 || $teamId <= 0) {
            jsonOut(['error' => 'staff_id and team_id are required'], 400);
        }
        $teamStmt = $pdo->prepare(
            'SELECT name FROM club_teams WHERE id = ? AND club_id = ? AND is_active = 1'
        );
        $teamStmt->execute([$teamId, $ctx['club_id']]);
        $teamName = $teamStmt->fetchColumn();
        if (!$teamName) jsonOut(['error' => 'Team not found'], 404);

        $staffStmt = $pdo->prepare(
            "SELECT staff_role FROM club_staff
             WHERE id = ? AND club_id = ? AND status = 'active'"
        );
        $staffStmt->execute([$staffId, $ctx['club_id']]);
        $staffRole = $staffStmt->fetchColumn();
        if (!$staffRole) jsonOut(['error' => 'Staff member not found'], 404);
        if ($staffRole === 'owner') {
            jsonOut(['error' => 'Club owner cannot be team-scoped'], 409);
        }

        $pdo->prepare(
            'UPDATE club_staff SET team_id = ? WHERE id = ? AND club_id = ?'
        )->execute([$teamId, $staffId, $ctx['club_id']]);
        jsonOut([
            'success' => true,
            'staff_id' => $staffId,
            'team_id' => $teamId,
            'team_name' => $teamName,
        ]);
    }

    // ── Toggle an existing code active/inactive ───────────────────────────
    if (($body['action'] ?? '') === 'toggle_code') {
        $code     = trim($body['code'] ?? '');
        $isActive = !empty($body['is_active']) ? 1 : 0;
        if (!$code) jsonOut(['error' => 'code is required'], 400);
        $existing = $pdo->prepare(
            'SELECT account_type, use_count, created_at
             FROM club_access_codes WHERE code = ? AND club_id = ?'
        );
        $existing->execute([$code, $ctx['club_id']]);
        $invite = $existing->fetch();
        if (!$invite) jsonOut(['error' => 'Invitation not found'], 404);
        if ($isActive && $invite['account_type'] !== 'player') {
            $expired = strtotime($invite['created_at']) < strtotime('-72 hours');
            if ((int)$invite['use_count'] > 0 || $expired) {
                jsonOut(['error' => 'Create a new staff invitation instead'], 409);
            }
        }
        $pdo->prepare(
            'UPDATE club_access_codes SET is_active = ? WHERE code = ? AND club_id = ?'
        )->execute([$isActive, $code, $ctx['club_id']]);
        jsonOut(['success' => true, 'code' => $code, 'is_active' => (bool)$isActive]);
    }

    // ── Create a new access code ───────────────────────────────────────────
    $requestedType = $body['account_type'] ?? $body['staff_role'] ?? '';
    if (!in_array($requestedType, $allowedAccountTypes, true)) {
        jsonOut(['error' => 'Invalid account type'], 400);
    }
    $accountType = $requestedType;
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
        $stmt = $pdo->prepare(
            'DELETE FROM club_access_codes WHERE code = ? AND club_id = ?'
        );
        $stmt->execute([$code, $ctx['club_id']]);
        if ($stmt->rowCount() === 0) {
            jsonOut(['error' => 'Invitation not found'], 404);
        }
        jsonOut(['success' => true]);
    }

    $id = $_GET['id'] ?? ($body['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id or code is required'], 400);

    $memberStmt = $pdo->prepare(
        'SELECT staff_role FROM club_staff WHERE id = ? AND club_id = ?'
    );
    $memberStmt->execute([$id, $ctx['club_id']]);
    $member = $memberStmt->fetch();
    if (!$member) jsonOut(['error' => 'Staff member not found'], 404);
    if ($member['staff_role'] === 'owner') {
        jsonOut(['error' => 'Club owner cannot be removed'], 409);
    }

    $pdo->prepare(
        "UPDATE club_staff SET status = 'suspended' WHERE id = ? AND club_id = ?"
    )->execute([$id, $ctx['club_id']]);

    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
