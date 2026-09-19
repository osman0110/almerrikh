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
require_once dirname(__DIR__) . '/includes/audit_log.php';

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
        // Re-activating an admin invite would mint admins — owner only.
        if ($isActive && ($ctx['staff_role'] ?? '') !== 'owner') {
            $typeStmt = $pdo->prepare('SELECT account_type FROM club_access_codes WHERE code = ? AND club_id = ?');
            $typeStmt->execute([$code, $ctx['club_id']]);
            if ($typeStmt->fetchColumn() === 'admin') {
                jsonOut(['error' => 'Only the club owner can activate an admin invite', 'code' => 'owner_only'], 403);
            }
        }
        $pdo->prepare('UPDATE club_access_codes SET is_active = ? WHERE code = ? AND club_id = ?')
            ->execute([$isActive, $code, $ctx['club_id']]);
        jsonOut(['success' => true, 'code' => $code, 'is_active' => (bool)$isActive]);
    }

    // ── Create a new access code ───────────────────────────────────────────
    // ── Create a staff login directly (no invite code / self sign-up) ───────
    // In-app sign-up was removed for App Store review (commit 7d66633), so
    // the club administration provisions staff accounts here, the same way
    // player logins are provisioned from the player form (players.php).
    // Mirrors the staff branch of auth.php `register`: users row with role
    // 'staff' + an active club_staff row + users.club_id.
    if (($body['action'] ?? '') === 'create_account') {
        $name      = trim((string)($body['name'] ?? ''));
        $email     = strtolower(trim((string)($body['email'] ?? '')));
        $phone     = preg_replace('/[^\d+]/', '', trim((string)($body['phone'] ?? '')));
        $password  = (string)($body['password'] ?? '');
        $staffRole = (string)($body['staff_role'] ?? '');

        if ($name === '' || mb_strlen($name) > 100) jsonOut(['error' => 'Name is required'], 400);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 255) {
            jsonOut(['error' => 'Invalid email address'], 400);
        }
        if ($phone !== '' && strlen(preg_replace('/\D/', '', $phone)) < 8) {
            jsonOut(['error' => 'Invalid phone number'], 400);
        }
        if (strlen($password) < 6 || strlen($password) > 128) {
            jsonOut(['error' => 'Password must be 6-128 characters'], 400);
        }
        $staffRoles = array_values(array_diff($allowedAccountTypes, ['player']));
        if (!in_array($staffRole, $staffRoles, true)) {
            jsonOut(['error' => 'Invalid staff role', 'allowed' => $staffRoles], 400);
        }
        // Privilege escalation guard: only the owner may create an admin
        // (an admin cannot mint another admin; nobody can create an owner).
        if ($staffRole === 'admin' && ($ctx['staff_role'] ?? '') !== 'owner') {
            jsonOut(['error' => 'Only the club owner can create an admin account', 'code' => 'owner_only'], 403);
        }

        $dup = $pdo->prepare('SELECT id FROM users WHERE email = ?' . ($phone !== '' ? ' OR phone = ?' : ''));
        $dup->execute($phone !== '' ? [$email, $phone] : [$email]);
        if ($dup->fetch()) jsonOut(['error' => 'Email or phone is already registered', 'code' => 'duplicate_account'], 409);

        $pdo->beginTransaction();
        try {
            $pdo->prepare(
                "INSERT INTO users (name, email, phone, password_hash, role, account_type, player_type,
                                    club_id, trial_started_at, trial_ends_at, is_active, status)
                 VALUES (?, ?, ?, ?, 'staff', 'staff', NULL, ?, NOW(), NOW() + INTERVAL 3 DAY, 1, 'active')"
            )->execute([
                $name, $email, $phone !== '' ? $phone : null,
                password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]),
                $ctx['club_id'],
            ]);
            $newUserId = (int)$pdo->lastInsertId();
            $pdo->prepare(
                "INSERT INTO club_staff (club_id, user_id, staff_role, status, invited_by_user_id)
                 VALUES (?, ?, ?, 'active', ?)"
            )->execute([$ctx['club_id'], $newUserId, $staffRole, $user['id']]);
            $pdo->commit();
        } catch (PDOException $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ((string)$e->getCode() === '23000') {
                // Unique email/phone race between the check above and insert.
                jsonOut(['error' => 'Email or phone is already registered', 'code' => 'duplicate_account'], 409);
            }
            error_log('staff.php create_account failed: ' . $e->getMessage());
            jsonOut(['error' => 'Unable to create the staff account'], 500);
        }

        logAuditSafe($pdo, 'users', (string)$newUserId, 'staff_account_created', null,
            $staffRole . '@club' . $ctx['club_id'], (int)$user['id']);
        jsonOut(['success' => true, 'user_id' => $newUserId, 'staff_role' => $staffRole]);
    }

    // ── Reset another user's password (temporary password set by admin) ─────
    // Target must belong to the caller's club, as staff or as a linked
    // player login. Nobody can reset the club owner here (the owner uses
    // change_password), and only the owner may reset an admin. The old
    // password is never returned; all of the target's sessions are revoked
    // so the new password takes effect on every device immediately.
    if (($body['action'] ?? '') === 'reset_password') {
        $targetId    = (int)($body['user_id'] ?? 0);
        $newPassword = (string)($body['new_password'] ?? '');
        if ($targetId <= 0) jsonOut(['error' => 'user_id is required'], 400);
        if (strlen($newPassword) < 6 || strlen($newPassword) > 128) {
            jsonOut(['error' => 'Password must be 6-128 characters'], 400);
        }
        if ($targetId === (int)$user['id']) {
            jsonOut(['error' => 'Use change password for your own account'], 400);
        }

        $staffRow = $pdo->prepare('SELECT staff_role FROM club_staff WHERE user_id = ? AND club_id = ? LIMIT 1');
        $staffRow->execute([$targetId, $ctx['club_id']]);
        $targetStaffRole = $staffRow->fetchColumn();
        $targetKind = null;
        if ($targetStaffRole !== false) {
            $targetKind = 'staff';
            if ($targetStaffRole === 'owner') {
                jsonOut(['error' => 'The club owner password cannot be reset here'], 403);
            }
            if ($targetStaffRole === 'admin' && ($ctx['staff_role'] ?? '') !== 'owner') {
                jsonOut(['error' => 'Only the club owner can reset an admin password'], 403);
            }
        } else {
            $playerRow = $pdo->prepare('SELECT id FROM club_players WHERE linked_user_id = ? AND club_id = ? LIMIT 1');
            $playerRow->execute([$targetId, $ctx['club_id']]);
            if ($playerRow->fetchColumn() !== false) $targetKind = 'player';
        }
        // Unknown id and another club's user look the same: not found.
        if ($targetKind === null) jsonOut(['error' => 'User not found'], 404);

        $pdo->beginTransaction();
        try {
            $pdo->prepare('UPDATE users SET password_hash = ? WHERE id = ?')
                ->execute([password_hash($newPassword, PASSWORD_BCRYPT, ['cost' => 11]), $targetId]);
            $pdo->prepare('DELETE FROM user_tokens WHERE user_id = ?')->execute([$targetId]);
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            error_log('staff.php reset_password failed: ' . $e->getMessage());
            jsonOut(['error' => 'Unable to reset the password'], 500);
        }

        // Never log the password itself — only that a reset happened.
        logAuditSafe($pdo, 'users', (string)$targetId, 'password_reset', null, $targetKind, (int)$user['id']);
        jsonOut(['success' => true, 'user_id' => $targetId, 'sessions_revoked' => true]);
    }

    $accountType = in_array($body['account_type'] ?? $body['staff_role'] ?? '', $allowedAccountTypes, true)
        ? ($body['account_type'] ?? $body['staff_role'])
        : 'coach';
    // Same guard for invite codes: an admin-type code is an admin account.
    if ($accountType === 'admin' && ($ctx['staff_role'] ?? '') !== 'owner') {
        jsonOut(['error' => 'Only the club owner can create an admin invite', 'code' => 'owner_only'], 403);
    }
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
    $target = $pdo->prepare("SELECT user_id, staff_role FROM club_staff WHERE id = ? AND club_id = ? AND staff_role != 'owner'");
    $target->execute([$id, $ctx['club_id']]);
    $targetRow = $target->fetch(PDO::FETCH_ASSOC);
    if (!$targetRow) jsonOut(['error' => 'Staff member not found'], 404);
    $targetUserId = (int)$targetRow['user_id'];
    // Admins are managed by the owner only (no admin-vs-admin suspension).
    if ($targetRow['staff_role'] === 'admin' && ($ctx['staff_role'] ?? '') !== 'owner') {
        jsonOut(['error' => 'Only the club owner can suspend an admin', 'code' => 'owner_only'], 403);
    }

    $pdo->prepare(
        "UPDATE club_staff SET status = 'suspended'
         WHERE id = ? AND club_id = ? AND staff_role != 'owner'"
    )->execute([$id, $ctx['club_id']]);
    // Log the suspended member out everywhere — previously their tokens
    // stayed valid and the app kept showing club screens that then failed.
    $pdo->prepare('DELETE FROM user_tokens WHERE user_id = ?')->execute([(int)$targetUserId]);
    logAuditSafe($pdo, 'club_staff', (string)$id, 'status', null, 'suspended', (int)$user['id']);

    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
