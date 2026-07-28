<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// ── CORS: restrict browser-origin requests to known domains ──────────────────
// Mobile apps do not send Origin; this only affects browser-based callers.
$__origin  = $_SERVER['HTTP_ORIGIN'] ?? '';
$__allowed = ['https://nextkick.me', 'https://www.nextkick.me'];
if ($__origin !== '' && in_array($__origin, $__allowed, true)) {
    header("Access-Control-Allow-Origin: $__origin");
} else {
    header('Access-Control-Allow-Origin: https://nextkick.me');
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db.php';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const RL_WINDOW_MIN    = 15;   // sliding window in minutes
const RL_MAX_PER_IP    = 10;   // failed attempts allowed per IP per window
const RL_MAX_PER_IDENT = 7;    // failed attempts allowed per identifier per window
const RL_LOCKOUT_SEC   = 900;  // 15 minutes in seconds

const TOKEN_TTL_DAYS   = 30;   // auth token lifetime

const TRIAL_ROLES      = ['club', 'academy', 'team'];   // roles that require an active trial

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

// Alias used by mobile endpoint and task specs.
function json_response(array $data, int $code = 200): void {
    jsonOut($data, $code);
}

function generateToken(): string {
    return bin2hex(random_bytes(32));
}

function bearerToken(): string {
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization']
        ?? '';

    if (!$auth && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    }
    return stripos($auth, 'Bearer ') === 0 ? trim(substr($auth, 7)) : trim($auth);
}

function normalizePhone(string $phone): string {
    return preg_replace('/[^\d+]/', '', trim($phone));
}

/**
 * Returns the real client IP.
 * If nextkick.me is behind a trusted reverse proxy (e.g. Cloudflare / nginx),
 * set the environment variable TRUSTED_PROXY=1 and this will read
 * X-Forwarded-For. Otherwise REMOTE_ADDR is used directly.
 */
function clientIp(): string {
    if (getenv('TRUSTED_PROXY') && !empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = array_map('trim', explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']));
        // First IP in the chain is the original client
        return filter_var($ips[0], FILTER_VALIDATE_IP) ?: ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
    }
    return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
}

/**
 * Returns a safe SHA-256 hash of the identifier.
 * We track attempts per email/phone without storing the plain value.
 */
function identHash(string $identifier): string {
    return hash('sha256', strtolower(trim($identifier)));
}

// ─────────────────────────────────────────────────────────────────────────────
// Rate Limiting
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Checks rate limit before processing a login attempt.
 * Exits with HTTP 429 immediately if the limit is exceeded.
 */
function checkRateLimit(PDO $pdo, string $ip, string $idHash): void {
    $since = date('Y-m-d H:i:s', time() - RL_WINDOW_MIN * 60);

    // Per-IP check
    $s = $pdo->prepare(
        'SELECT COUNT(*) FROM auth_rate_limit WHERE ip = ? AND failed_at > ?'
    );
    $s->execute([$ip, $since]);
    if ((int)$s->fetchColumn() >= RL_MAX_PER_IP) {
        header('Retry-After: ' . RL_LOCKOUT_SEC);
        jsonOut([
            'error'       => 'Too many attempts from your network. Try again in 15 minutes.',
            'retry_after' => RL_LOCKOUT_SEC,
        ], 429);
    }

    // Per-identifier check
    $s2 = $pdo->prepare(
        'SELECT COUNT(*) FROM auth_rate_limit WHERE identifier_hash = ? AND failed_at > ?'
    );
    $s2->execute([$idHash, $since]);
    if ((int)$s2->fetchColumn() >= RL_MAX_PER_IDENT) {
        header('Retry-After: ' . RL_LOCKOUT_SEC);
        jsonOut([
            'error'       => 'Too many failed attempts. Try again in 15 minutes.',
            'retry_after' => RL_LOCKOUT_SEC,
        ], 429);
    }
}

function recordFailedAttempt(PDO $pdo, string $ip, string $idHash): void {
    $pdo->prepare(
        'INSERT INTO auth_rate_limit (ip, identifier_hash) VALUES (?, ?)'
    )->execute([$ip, $idHash]);
}

/**
 * Clears the identifier's failed-attempt history on successful login.
 * Also runs a 5% probabilistic cleanup of expired records to keep the table small.
 */
function clearRateLimit(PDO $pdo, string $idHash): void {
    $pdo->prepare(
        'DELETE FROM auth_rate_limit WHERE identifier_hash = ?'
    )->execute([$idHash]);

    if (mt_rand(1, 20) === 1) {
        $pdo->exec("DELETE FROM auth_rate_limit WHERE failed_at < NOW() - INTERVAL 24 HOUR");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Token Management
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Creates a new 30-day token, pruning expired tokens for this user first.
 */
function createToken(PDO $pdo, int $userId): string {
    // Prune this user's expired tokens (housekeeping)
    $pdo->prepare(
        'DELETE FROM user_tokens WHERE user_id = ? AND expires_at IS NOT NULL AND expires_at < NOW()'
    )->execute([$userId]);

    $token   = generateToken();
    $expires = date('Y-m-d H:i:s', strtotime('+' . TOKEN_TTL_DAYS . ' days'));

    $pdo->prepare(
        'INSERT INTO user_tokens (token, user_id, expires_at) VALUES (?, ?, ?)'
    )->execute([$token, $userId, $expires]);

    return $token;
}

// ─────────────────────────────────────────────────────────────────────────────
// Trial Enforcement
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Blocks login for club / academy accounts whose trial has expired — OR
 * whose paid subscription has expired/been cancelled.
 * Players are never blocked — they join at the club's invitation.
 *
 * IMPORTANT: subscription_status is checked FIRST and, when the account is on
 * a paid plan, is the only thing that matters — trial_ends_at is never
 * consulted for a paid account, even if it still holds a stale past date
 * (the admin panel's "Save Subscription" action does not always clear it).
 * This must stay in sync with the web admin panel's SubscriptionService
 * (includes/SubscriptionService.php) — same precedence, same rules.
 */
function enforceTrialStatus(array $user): void {
    $role = $user['role'] ?? 'club';
    if (!in_array($role, TRIAL_ROLES, true)) return;

    $subStatus = $user['subscription_status'] ?? 'trial';
    $subEnds   = $user['subscription_ends_at'] ?? null;

    if ($subStatus === 'active') {
        if ($subEnds && strtotime($subEnds) < time()) {
            jsonOut([
                'error'                 => 'Your subscription has expired. Please renew to continue.',
                'subscription_expired'  => true,
                'subscription_ends_at'  => $subEnds,
            ], 402);
        }
        return; // Active paid subscription — never blocked by trial_ends_at.
    }

    if ($subStatus === 'cancelled') {
        jsonOut([
            'error'                  => 'Your subscription has been cancelled. Please contact support to continue.',
            'subscription_cancelled' => true,
        ], 402);
    }

    // Trial (or legacy 'expired' status) — fall back to trial_ends_at.
    $trialEnd = $user['trial_ends_at'] ?? null;
    if (!$trialEnd) return;

    if (strtotime($trialEnd) < time()) {
        jsonOut([
            'error'         => 'Your trial has expired. Please contact support to continue.',
            'trial_expired' => true,
            'trial_ends_at' => $trialEnd,
        ], 402); // 402 Payment Required
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Authenticated Endpoint Guard
// ─────────────────────────────────────────────────────────────────────────────

function getAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);

    $stmt = $pdo->prepare(
        'SELECT u.id,
                COALESCE(u.name, \'\')       AS name,
                u.email,
                COALESCE(u.phone, \'\')      AS phone,
                COALESCE(u.role, \'player\') AS role,
                u.player_type, u.linked_player_id, u.club_user_id,
                u.trial_started_at, u.trial_ends_at
         FROM users u
         JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ?
           AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($user && $user['name'] === '') {
        $user['name'] = explode('@', $user['email'])[0];
    }
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

// ─────────────────────────────────────────────────────────────────────────────
// Response Builder
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Builds the unified user object. Structure is stable — both naming conventions
 * are included so Flutter and the live server work with the same contract.
 */
function buildUserResponse(array $u, ?PDO $pdo = null): array {
    $role       = $u['role']        ?? 'club';
    $name       = $u['name']        ?? '';
    $clubUserId = isset($u['club_user_id']) && $u['club_user_id']
                    ? (int)$u['club_user_id'] : null;

    $trialEnds      = $u['trial_ends_at'] ?? null;
    $trialRemaining = null;
    if ($trialEnds) {
        $trialRemaining = max(0, (int)ceil((strtotime($trialEnds) - time()) / 86400));
    }

    // Staff/club context — populates the org_role field the Flutter app
    // already reads (lib/app_state.dart) but the backend never sent before.
    $orgRole = null;
    if ($pdo !== null && isset($u['id'])) {
        require_once __DIR__ . '/includes/club_auth.php';
        $ctx = resolveClubContext($pdo, ['id' => $u['id']]);
        $orgRole = $ctx['staff_role'];
    }

    return [
        'id'                   => (int)$u['id'],
        'name'                 => $name,
        'full_name'            => $name,
        'email'                => $u['email']  ?? '',
        'phone'                => $u['phone']  ?? null,
        'role'                 => $role,
        'account_type'         => $role,
        'player_type'          => $u['player_type']      ?? null,
        'club_id'              => $clubUserId,
        'club_user_id'         => $clubUserId,
        'linked_player_id'     => $u['linked_player_id'] ?? null,
        'trial_started_at'     => $u['trial_started_at'] ?? null,
        'trial_ends_at'        => $trialEnds,
        'trial_days_remaining' => $trialRemaining,
        'org_role'             => $orgRole,
    ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────────────────────────────────────

$action = $_GET['action'] ?? '';

// Read raw body once — supports JSON (Flutter) and form-data (browsers / tests).
$_raw  = file_get_contents('php://input');
$body  = json_decode($_raw, true);
if (!is_array($body)) {
    // Not JSON — fall back to form-encoded POST fields.
    $body = $_POST;
}
if (!is_array($body)) {
    $body = [];
}

// ─────────────────────────────────────────────────────────────────────────────
// Routes
// ─────────────────────────────────────────────────────────────────────────────

switch ($action) {

    // ── Register ─────────────────────────────────────────────────────────────
    case 'register': {
        $name       = trim($body['name']        ?? '');
        $email      = strtolower(trim($body['email'] ?? ''));
        $phone      = normalizePhone($body['phone']  ?? '');
        $password   = $body['password']         ?? '';
        $rawRole    = trim($body['role']        ?? 'club');
        $rawPType   = trim($body['player_type'] ?? '');
        $inviteCode = trim($body['invite_code'] ?? '');

        // ── Input validation ─────────────────────────────────────────────────
        if (!$name || !$email || !$phone || !$password) {
            jsonOut(['error' => 'All fields are required'], 400);
        }
        if (mb_strlen($name) > 100) {
            jsonOut(['error' => 'Name is too long'], 400);
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 255) {
            jsonOut(['error' => 'Invalid email address'], 400);
        }
        if (strlen(preg_replace('/\D/', '', $phone)) < 8) {
            jsonOut(['error' => 'Invalid phone number'], 400);
        }
        if (strlen($password) < 6 || strlen($password) > 128) {
            jsonOut(['error' => 'Password must be 6–128 characters'], 400);
        }

        // 'parent' intentionally excluded — this club is senior team only, no academy/youth parent portal
        $allowedRoles  = ['club', 'team', 'coach', 'player', 'academy', 'staff'];
        $role          = in_array($rawRole, $allowedRoles, true) ? $rawRole : 'club';
        $playerType    = in_array($rawPType, ['independent', 'club', ''], true) ? $rawPType : '';

        // ── Duplicate check ──────────────────────────────────────────────────
        $check = $pdo->prepare('SELECT id FROM users WHERE email = ? OR phone = ?');
        $check->execute([$email, $phone]);
        if ($check->fetch()) {
            jsonOut(['error' => 'Email or phone is already registered'], 409);
        }

        // ── Access code (unified — one reusable code covers players AND staff) ──
        // A code is the single source of truth for what this join grants: it's
        // never single-use (no expiry, no "used" flag) — a club hands out one
        // code per account type and reuses it for every player/staff member
        // until they deactivate or delete it. The code's account_type always
        // overrides whatever role/player_type the client sent.
        $accessCode = null;
        if ($inviteCode) {
            $codeStmt = $pdo->prepare('SELECT * FROM club_access_codes WHERE code = ? AND is_active = 1');
            $codeStmt->execute([$inviteCode]);
            $accessCode = $codeStmt->fetch();
            if (!$accessCode) {
                jsonOut(['error' => 'Invalid or inactive invite code'], 400);
            }
            $role       = $accessCode['account_type'] === 'player' ? 'player' : 'staff';
            $playerType = $accessCode['account_type'] === 'player' ? 'club'   : '';
        } elseif ($role === 'player' && $playerType === 'club') {
            jsonOut(['error' => 'Invite code is required to join a club'], 400);
        } elseif ($role === 'staff') {
            jsonOut(['error' => 'Invite code is required to join a club'], 400);
        }

        // ── Create user ──────────────────────────────────────────────────────
        $needsApproval = in_array($role, ['academy', 'club'], true);

        $hash       = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);
        $trialStart = date('Y-m-d H:i:s');
        $trialEnd   = date('Y-m-d H:i:s', strtotime('+3 days'));
        $accountType = $role;

        $pdo->prepare(
            'INSERT INTO users (name, email, phone, password_hash, role, account_type, player_type,
                                trial_started_at, trial_ends_at, is_active, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        )->execute([
            $name, $email, $phone, $hash,
            $role, $accountType,
            $role === 'player' ? ($playerType ?: 'independent') : null,
            $trialStart, $trialEnd,
            $needsApproval ? 0 : 1,
            $needsApproval ? 'pending' : 'active',
        ]);
        $userId = (int)$pdo->lastInsertId();

        if ($role === 'club') {
            $clubName   = trim($body['club_name'] ?? '') ?: ($name . ' Club');
            $clubStatus = $needsApproval ? 'pending' : 'active';
            $pdo->prepare(
                'INSERT INTO clubs (owner_user_id, name, email, phone, status)
                 VALUES (?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)'
            )->execute([$userId, $clubName, $email, $phone, $clubStatus]);
            $clubId = (int) $pdo->lastInsertId();

            $pdo->prepare('UPDATE users SET club_id = ? WHERE id = ?')
                ->execute([$clubId, $userId]);
        }

        // ── Staff setup (join an existing club via an access code) ───────────
        if ($role === 'staff' && $accessCode) {
            $staffClubId = (int)$accessCode['club_id'];
            $pdo->prepare(
                'INSERT INTO club_staff (club_id, user_id, staff_role, status, invited_by_user_id)
                 VALUES (?, ?, ?, "active", ?)'
            )->execute([$staffClubId, $userId, $accessCode['account_type'], $accessCode['created_by_user_id']]);
            $pdo->prepare('UPDATE users SET club_id = ? WHERE id = ?')
                ->execute([$staffClubId, $userId]);
        }

        // ── Player setup ─────────────────────────────────────────────────────
        $linkedPlayerId = null;
        $clubUserId     = null;

        if ($role === 'player') {
            if ($playerType === 'independent' || !$playerType) {
                $linkedPlayerId = 'indie-' . $userId;
                $pdo->prepare(
                    'INSERT INTO club_players (id, user_id, name, player_type, linked_user_id, is_active)
                     VALUES (?, ?, ?, "independent", ?, 1)'
                )->execute([$linkedPlayerId, $userId, $name, $userId]);
                $pdo->prepare('UPDATE users SET linked_player_id = ? WHERE id = ?')
                    ->execute([$linkedPlayerId, $userId]);

            } elseif ($accessCode) {
                $clubUserId     = (int)$accessCode['club_user_id'];
                $linkedPlayerId = 'cp-' . $userId . '-' . time();
                $pdo->prepare(
                    'INSERT INTO club_players (id, user_id, name, player_type, linked_user_id, is_active)
                     VALUES (?, ?, ?, "club", ?, 1)'
                )->execute([$linkedPlayerId, $clubUserId, $name, $userId]);
                $pdo->prepare(
                    'UPDATE users SET club_user_id = ?, linked_player_id = ?, player_type = "club" WHERE id = ?'
                )->execute([$clubUserId, $linkedPlayerId, $userId]);
            }
        }

        // ── Access code usage stats — the code stays active/reusable; we only
        // track how many times and when it was last used, never consume it. ──
        if ($accessCode) {
            $pdo->prepare('UPDATE club_access_codes SET use_count = use_count + 1, last_used_at = NOW() WHERE code = ?')
                ->execute([$inviteCode]);
        }

        if ($needsApproval) {
            // No token issued — the account cannot sign in until an admin
            // approves it from the web control panel (api/admin/approvals.php).
            // The Flutter app only special-cases an 'error' key on the
            // register response — without it, it would hard-cast the missing
            // 'token'/'user' fields and show a generic "Something went wrong".
            jsonOut([
                'success' => true,
                'pending' => true,
                'error'   => 'Your account is awaiting admin approval. We will notify you once it is reviewed.',
                'message' => 'Your account is awaiting admin approval. We will notify you once it is reviewed.',
            ]);
        }

        $token = createToken($pdo, $userId);

        jsonOut(['success' => true, 'token' => $token, 'user' => buildUserResponse([
            'id'               => $userId,
            'name'             => $name,
            'email'            => $email,
            'phone'            => $phone,
            'role'             => $role,
            'player_type'      => $role === 'player' ? ($playerType ?: 'independent') : null,
            'linked_player_id' => $linkedPlayerId,
            'club_user_id'     => $clubUserId,
            'trial_started_at' => $trialStart,
            'trial_ends_at'    => $trialEnd,
        ], $pdo)]);
    }

    // ── Login ─────────────────────────────────────────────────────────────────
    case 'login': {
        try {
            $identifier = strtolower(trim($body['email'] ?? $body['login'] ?? ''));
            $phone      = normalizePhone($identifier);
            $password   = $body['password'] ?? '';

            // ── Basic input validation ─────────────────────────────────────────
            if (!$identifier || !$password) {
                jsonOut(['error' => 'Email and password are required'], 400);
            }
            if (strlen($identifier) > 255 || strlen($password) > 128) {
                jsonOut(['error' => 'Invalid credentials'], 400);
            }

            $ip     = clientIp();
            $idHash = identHash($identifier);

            // ── Rate limit check (before touching user table) ──────────────────
            checkRateLimit($pdo, $ip, $idHash);

            // ── Credential lookup ──────────────────────────────────────────────
            // Columns are declared safe: ensureSchema() (via db.php) runs before
            // this query and guarantees name, role, player_type, etc. exist.
            $stmt = $pdo->prepare(
                'SELECT id,
                        COALESCE(name, \'\')        AS name,
                        email,
                        COALESCE(phone, \'\')       AS phone,
                        password_hash,
                        COALESCE(role, \'player\')  AS role,
                        player_type,
                        linked_player_id,
                        club_user_id,
                        trial_started_at,
                        trial_ends_at,
                        subscription_status,
                        subscription_ends_at,
                        is_active,
                        status
                 FROM users
                 WHERE email = ? OR phone = ?
                 LIMIT 1'
            );
            $stmt->execute([$identifier, $phone]);
            $user = $stmt->fetch(PDO::FETCH_ASSOC);

            // If name is blank (old row before migration), fall back to email prefix.
            if ($user && $user['name'] === '') {
                $user['name'] = explode('@', $user['email'])[0];
            }

            // ── Verify password — always run password_verify to prevent timing attacks ──
            $validPassword = $user && password_verify($password, $user['password_hash'] ?? '');

            if (!$user || !$validPassword) {
                recordFailedAttempt($pdo, $ip, $idHash);
                // Uniform error — never reveal whether email or password was wrong.
                jsonOut(['error' => 'Invalid email or password'], 401);
            }

            // ── Successful credential check — clear rate limit counter ─────────
            clearRateLimit($pdo, $idHash);

            // ── Parent accounts disabled — this club is senior team only, no academy/youth parents ──
            if (($user['role'] ?? '') === 'parent') {
                jsonOut(['error' => 'حسابات أولياء الأمور غير متاحة لهذا النادي'], 403);
            }

            // ── Account status checks ───────────────────────────────────────────
            if (($user['status'] ?? '') === 'pending') {
                jsonOut([
                    'error'           => 'Your account is awaiting admin approval. We will notify you once it is reviewed.',
                    'pending_approval' => true,
                ], 403);
            }
            if (!(bool)($user['is_active'] ?? 1)) {
                jsonOut(['error' => 'Your account has been deactivated. Contact support.'], 403);
            }

            // ── Server-side trial enforcement ──────────────────────────────────
            enforceTrialStatus($user);

            // ── Issue token ────────────────────────────────────────────────────
            $token = createToken($pdo, (int)$user['id']);

            jsonOut([
                'success' => true,
                'message' => 'Login successful',
                'token'   => $token,
                'user'    => buildUserResponse($user, $pdo),
            ]);

        } catch (Throwable $e) {
            error_log('Login API error: ' . $e->getMessage());
            jsonOut(['error' => 'Server error. Please try again.'], 500);
        }
    }

    // ── Me (refresh user profile) ─────────────────────────────────────────────
    case 'me': {
        $user = getAuthUser($pdo);
        jsonOut(['success' => true, 'user' => buildUserResponse($user, $pdo)]);
    }

    // ── Logout ────────────────────────────────────────────────────────────────
    case 'logout': {
        $token = bearerToken();
        if ($token) {
            $pdo->prepare('DELETE FROM user_tokens WHERE token = ?')->execute([$token]);
        }
        jsonOut(['success' => true]);
    }

    default:
        jsonOut(['error' => 'Unknown action'], 400);
}
