<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';
require_once 'includes/audit_log.php';
require_once 'includes/player_status.php';
require_once 'includes/club_auth.php';

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
        'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

// ── GET: list players ─────────────────────────────────────────────────────────
if ($method === 'GET') {
    $filterId = isset($_GET['id']) ? trim($_GET['id']) : '';

    // Status change history — small "status log" section on the player
    // profile page. Same 'players.read' scope as everything else here.
    if ($filterId !== '' && ($_GET['status_history'] ?? '') === '1') {
        $ctx = requireClubPermission($pdo, $user, 'players.read');
        $ownStmt = $pdo->prepare('SELECT 1 FROM club_players WHERE id = ? AND club_id = ?');
        $ownStmt->execute([$filterId, $ctx['club_id']]);
        if (!$ownStmt->fetchColumn()) jsonOut(['error' => 'Not found'], 404);

        $stmt = $pdo->prepare(
            'SELECT h.old_status, h.new_status, h.reason, h.changed_at, u.name AS changed_by_name
             FROM player_status_history h
             JOIN users u ON u.id = h.changed_by_user_id
             WHERE h.player_id = ?
             ORDER BY h.changed_at DESC'
        );
        $stmt->execute([$filterId]);
        jsonOut(['history' => $stmt->fetchAll()]);
    }

    // Fast single-player lookup (used by profile page)
    if ($filterId !== '') {
        // Scoped to the caller's club (any staff member — coach/doctor/analyst/admin/owner)
        $ctx = requireClubPermission($pdo, $user, 'players.read');
        $stmt = $pdo->prepare(
            "SELECT * FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1 LIMIT 1"
        );
        $stmt->execute([$filterId, $ctx['club_id']]);
        $rows = $stmt->fetchAll();

        foreach ($rows as &$r) {
            $r['height_cm']            = $r['height_cm'] !== null ? (float)$r['height_cm'] : null;
            $r['weight_kg']            = $r['weight_kg'] !== null ? (float)$r['weight_kg'] : null;
            $r['is_active']            = (bool)$r['is_active'];
            $r['status']               = $r['status'] ?? 'active';
            $r['expected_return_date'] = $r['expected_return_date'] ?? null;
            $r['unavailable_reason']   = $r['unavailable_reason'] ?? null;
            $r['last_assessment_at']   = $r['last_assessment_at'] ?? null;
            $r['latest_score']         = $r['latest_score'] !== null ? (float)$r['latest_score'] : null;
            $r['movement_score']       = $r['movement_score'] !== null ? (float)$r['movement_score'] : null;
            $r['stability_score']      = $r['stability_score'] !== null ? (float)$r['stability_score'] : null;
            $r['symmetry_score']       = $r['symmetry_score'] !== null ? (float)$r['symmetry_score'] : null;
            $r['control_score']        = $r['control_score'] !== null ? (float)$r['control_score'] : null;
        }
        unset($r);
        jsonOut(['players' => $rows]);
    }

    // Determine if the caller is a player (needs to see their own record)
    // or a coach/admin (sees only their club's players)
    $roleStmt = $pdo->prepare('SELECT role, player_type FROM users WHERE id = ?');
    $roleStmt->execute([$user['id']]);
    $callerInfo = $roleStmt->fetch();
    $callerIsPlayer = ($callerInfo['player_type'] !== null && $callerInfo['player_type'] !== '');

    if ($callerIsPlayer) {
        // Players see ONLY their own linked record (independent or club)
        $stmt = $pdo->prepare(
            "SELECT * FROM club_players
             WHERE (linked_user_id = ?
                    OR (user_id = ? AND player_type = 'independent'))
               AND is_active = 1
             ORDER BY name ASC"
        );
        $stmt->execute([$user['id'], $user['id']]);
    } else {
        // Coaches/admins/doctors/analysts see their club's players; never independent
        $ctx = requireClubPermission($pdo, $user, 'players.read');
        $stmt = $pdo->prepare(
            "SELECT * FROM club_players
             WHERE club_id = ?
               AND is_active = 1
               AND (player_type IS NULL OR player_type = 'club')
             ORDER BY name ASC"
        );
        $stmt->execute([$ctx['club_id']]);
    }
    $rows = $stmt->fetchAll();
    foreach ($rows as &$r) {
        $r['height_cm']            = $r['height_cm'] !== null ? (float)$r['height_cm'] : null;
        $r['weight_kg']            = $r['weight_kg'] !== null ? (float)$r['weight_kg'] : null;
        $r['is_active']            = (bool)$r['is_active'];
        $r['status']               = $r['status'] ?? 'active';
        $r['expected_return_date'] = $r['expected_return_date'] ?? null;
        $r['unavailable_reason']   = $r['unavailable_reason'] ?? null;
        $r['last_assessment_at']   = $r['last_assessment_at'] ?? null;
        $r['latest_score']         = $r['latest_score'] !== null ? (float)$r['latest_score'] : null;
        $r['movement_score']       = $r['movement_score'] !== null ? (float)$r['movement_score'] : null;
        $r['stability_score']      = $r['stability_score'] !== null ? (float)$r['stability_score'] : null;
        $r['symmetry_score']       = $r['symmetry_score'] !== null ? (float)$r['symmetry_score'] : null;
        $r['control_score']        = $r['control_score'] !== null ? (float)$r['control_score'] : null;
    }
    unset($r);
    jsonOut(['players' => $rows]);
}

// ── POST: create / update player (ownership-checked upsert) ─────────────────
if ($method === 'POST') {
    // Players cannot manage player records via this endpoint
    $roleStmt2 = $pdo->prepare('SELECT role FROM users WHERE id = ?');
    $roleStmt2->execute([$user['id']]);
    $callerRole = $roleStmt2->fetchColumn();
    if ($callerRole === 'player' || $callerRole === 'parent') {
        jsonOut(['error' => 'Forbidden — coaches only'], 403);
    }

    $ctx = resolveClubContext($pdo, $user);
    if (!$ctx['club_id']) jsonOut(['error' => 'Not a member of a club'], 403);

    $canFullWrite    = clubStaffCan($ctx['staff_role'], 'players.write');
    $canMedicalWrite = clubStaffCan($ctx['staff_role'], 'medical.write');
    if (!$canFullWrite && !$canMedicalWrite) {
        jsonOut(['error' => 'Forbidden — insufficient staff role'], 403);
    }

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $id   = trim($body['id'] ?? '');
    $name = trim($body['name'] ?? '');

    if (!$id)   jsonOut(['error' => 'id is required'], 400);
    if (!$name) jsonOut(['error' => 'name is required'], 400);

    // Ownership check: if record already exists, verify it belongs to this club
    $existStmt = $pdo->prepare('SELECT * FROM club_players WHERE id = ?');
    $existStmt->execute([$id]);
    $existing = $existStmt->fetch(PDO::FETCH_ASSOC) ?: null;
    if ($existing && (int)$existing['club_id'] !== (int)$ctx['club_id']) {
        jsonOut(['error' => 'Forbidden — not your player'], 403);
    }

    // Roles limited to medical.write only (doctor) can edit an existing
    // player's medical/injury fields, but cannot create players or change
    // identity/roster fields (name, number, position, team, etc.).
    if (!$canFullWrite) {
        if (!$existing) jsonOut(['error' => 'Forbidden — cannot create players'], 403);
        $body['name']         = $existing['name'];
        $body['number']       = $existing['number'];
        $body['position']     = $existing['position'];
        $body['team']         = $existing['team_name'];
        $body['category']     = $existing['category'];
        $body['dominantFoot'] = $existing['dominant_foot'];
        $body['heightCm']     = $existing['height_cm'];
        $body['weightKg']     = $existing['weight_kg'];
        $body['dateOfBirth']  = $existing['date_of_birth'];
        $body['nationality']  = $existing['nationality'];
        $body['photoUrl']     = $existing['photo_url'];
        $body['email']        = '';
        $body['password']     = '';
        $name = $existing['name'];
    }

    // ── Optional: coach provisions a direct login for this player ────────────
    // Only meaningful when the player has no linked account yet — never
    // silently overwrite an existing player's credentials via this endpoint.
    $email    = trim($body['email']    ?? '');
    $password = (string)($body['password'] ?? '');
    $wantsLogin = ($email !== '' || $password !== '');
    $alreadyLinked = $existing && !empty($existing['linked_user_id']);

    if ($wantsLogin && $alreadyLinked) {
        jsonOut(['error' => 'This player already has a login account'], 409);
    }

    if ($wantsLogin) {
        $email = strtolower($email);
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 255) {
            jsonOut(['error' => 'Invalid email address'], 400);
        }
        if (strlen($password) < 6 || strlen($password) > 128) {
            jsonOut(['error' => 'Password must be 6–128 characters'], 400);
        }
        $dupStmt = $pdo->prepare('SELECT id FROM users WHERE email = ?');
        $dupStmt->execute([$email]);
        if ($dupStmt->fetch()) {
            jsonOut(['error' => 'Email is already registered'], 409);
        }
    }

    $statusVal = trim($body['status'] ?? 'active');
    $isAvailable = ($statusVal === 'active');

    // When player is available, clear injury/suspension fields automatically
    $expectedReturn  = $isAvailable ? null
        : ($body['expected_return_date'] ?? $body['expectedReturnDate'] ?? null);
    $unavailReason   = $isAvailable ? null
        : ($body['unavailable_reason'] ?? $body['unavailableReason'] ?? null);
    // injury_notes: keep even when active (historical record)
    $injuryNotes     = $body['injury_notes']   ?? $body['injuryNotes']   ?? null;
    $physicalNotes   = $body['physical_notes'] ?? $body['physicalNotes'] ?? null;
    $medicalNotes    = $body['medical_notes']  ?? $body['medicalNotes']  ?? null;

    // club_players.user_id historically means "the owning coach account" —
    // preserved as-is (not the acting staff member) so the many endpoints
    // still scoped by user_id keep resolving to the same owner.
    if ($existing) {
        $ownerUserId = (int)$existing['user_id'];
    } else {
        $ownerStmt = $pdo->prepare('SELECT owner_user_id FROM clubs WHERE id = ?');
        $ownerStmt->execute([$ctx['club_id']]);
        $ownerUserId = (int)($ownerStmt->fetchColumn() ?: $user['id']);
    }

    $stmt = $pdo->prepare(
        'INSERT INTO club_players
             (id, user_id, club_id, name, number, position, team_name, category,
              dominant_foot, height_cm, weight_kg, date_of_birth, nationality,
              injury_notes, physical_notes, medical_notes, status, photo_url,
              expected_return_date, unavailable_reason)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
             name                 = VALUES(name),
             number               = VALUES(number),
             position             = VALUES(position),
             team_name            = VALUES(team_name),
             category             = VALUES(category),
             dominant_foot        = VALUES(dominant_foot),
             height_cm            = VALUES(height_cm),
             weight_kg            = VALUES(weight_kg),
             date_of_birth        = VALUES(date_of_birth),
             nationality          = VALUES(nationality),
             injury_notes         = VALUES(injury_notes),
             physical_notes       = VALUES(physical_notes),
             medical_notes        = VALUES(medical_notes),
             status               = VALUES(status),
             photo_url            = VALUES(photo_url),
             expected_return_date = VALUES(expected_return_date),
             unavailable_reason   = VALUES(unavailable_reason),
             is_active            = 1'
    );
    $heightCm = isset($body['heightCm']) ? (float)$body['heightCm'] : (isset($body['height_cm']) ? (float)$body['height_cm'] : null);
    $weightKg = isset($body['weightKg']) ? (float)$body['weightKg'] : (isset($body['weight_kg']) ? (float)$body['weight_kg'] : null);

    $stmt->execute([
        $id,
        $ownerUserId,
        $ctx['club_id'],
        $name,
        $body['number']       ?? null,
        $body['position']     ?? null,
        $body['team']         ?? $body['team_name'] ?? null,
        $body['category']     ?? null,
        $body['dominantFoot'] ?? $body['dominant_foot'] ?? null,
        $heightCm,
        $weightKg,
        $body['dateOfBirth']  ?? $body['date_of_birth'] ?? null,
        $body['nationality']  ?? null,
        $injuryNotes,
        $physicalNotes,
        $medicalNotes,
        $statusVal,
        $body['photoUrl']     ?? $body['photo_url'] ?? null,
        $expectedReturn,
        $unavailReason,
    ]);

    // Audit sensitive fields — only meaningful for edits to an existing
    // player, not the initial creation of the record.
    if ($existing !== null) {
        logAuditDiff($pdo, 'club_players', $id, $existing, [
            'weight_kg'     => $weightKg,
            'height_cm'     => $heightCm,
            'injury_notes'  => $injuryNotes,
            'medical_notes' => $medicalNotes,
            'status'        => $statusVal,
        ], (int)$user['id']);

        if (($existing['status'] ?? null) !== $statusVal) {
            recordPlayerStatusChange($pdo, $id, $existing['status'] ?? null, $statusVal, (int)$user['id']);
        }
    }

    // ── Provision the player's own login, if requested above ─────────────────
    if ($wantsLogin) {
        $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);
        $pdo->prepare(
            'INSERT INTO users (name, email, password_hash, role, account_type,
                                 player_type, club_user_id, linked_player_id, is_active, status)
             VALUES (?, ?, ?, \'player\', \'player\', \'club\', ?, ?, 1, \'active\')'
        )->execute([$name, $email, $hash, $ownerUserId, $id]);
        $newUserId = (int)$pdo->lastInsertId();

        $pdo->prepare('UPDATE club_players SET linked_user_id = ? WHERE id = ?')
            ->execute([$newUserId, $id]);
    }

    jsonOut(['success' => true, 'id' => $id, 'login_created' => $wantsLogin]);
}

// ── DELETE: soft-delete player ────────────────────────────────────────────────
if ($method === 'DELETE') {
    $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
    if (!$id) jsonOut(['error' => 'id is required'], 400);

    $ctx = requireClubPermission($pdo, $user, 'players.delete');
    $stmt = $pdo->prepare(
        'UPDATE club_players SET is_active = 0 WHERE id = ? AND club_id = ?'
    );
    $stmt->execute([$id, $ctx['club_id']]);
    jsonOut(['success' => true]);
}

jsonOut(['error' => 'Method not allowed'], 405);
