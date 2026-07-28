<?php
// Shared helpers for the body-composition endpoint family. Every sibling
// module (hooper/, rpe/, body-metrics/) duplicates this boilerplate per file;
// this module has 10+ endpoints sharing an unusually large scoping block
// (resolvePlayerScope), so it lives in one include instead to avoid drift
// across that many copies.

require_once dirname(__DIR__, 2) . '/includes/club_auth.php';

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
        'SELECT u.id, u.name, u.role, u.linked_player_id, u.club_user_id FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

function bcValidDate(string $date): bool {
    $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
    return $parsed !== false && $parsed->format('Y-m-d') === $date;
}

/**
 * Resolves who the request is acting on behalf of, exactly like every other
 * player/* module: a coach (any non-player/parent role) must supply
 * player_id and own that roster player; a player acts on their own linked
 * record. Returns null fields for a player account with no linked roster
 * player yet, letting the caller decide whether that's fatal.
 *
 * $requirePlayerId: when true and the caller is a coach, player_id is
 * mandatory (used by write endpoints); read endpoints pass false and treat
 * a missing player_id as "coach browsing the whole roster".
 */
function resolvePlayerScope(
    PDO $pdo,
    array $user,
    array $body,
    bool $requirePlayerId = true,
    string $permission = 'fitness.body_composition.view'
): array {
    $isCoach = !in_array($user['role'], ['player', 'parent'], true);

    if ($isCoach) {
        // Scoped by club_id — a roster player belongs to the whole club,
        // shared across every coach/staff member, not to whichever coach is
        // currently logged in.
        $ctx = requireClubPermission($pdo, $user, $permission);
        $clubId = $ctx['club_id'];

        $targetPlayerId = trim((string)($body['player_id'] ?? ''));
        if (!$targetPlayerId) {
            if ($requirePlayerId) jsonOut(['error' => 'player_id is required'], 400);
            return [
                'isCoach' => true,
                'recordedBy' => 'coach',
                'linkedPlayerId' => null,
                'clubId' => $clubId,
                'teamId' => $ctx['team_id'] ?? null,
                'staffRole' => $ctx['staff_role'],
                'player' => null,
            ];
        }
        $pStmt = $pdo->prepare(
            'SELECT id, name, position, team_name, team_id, date_of_birth, height_cm FROM club_players
             WHERE id = ? AND club_id = ? AND is_active = 1' .
             (($ctx['team_id'] ?? null) !== null ? ' AND team_id = ?' : '') .
             ' LIMIT 1'
        );
        $playerParams = [$targetPlayerId, $clubId];
        if (($ctx['team_id'] ?? null) !== null) $playerParams[] = $ctx['team_id'];
        $pStmt->execute($playerParams);
        $player = $pStmt->fetch(PDO::FETCH_ASSOC);
        if (!$player) jsonOut(['error' => 'Player not found in your roster'], 404);
        return [
            'isCoach' => true, 'recordedBy' => 'coach',
            'linkedPlayerId' => $targetPlayerId, 'clubId' => $clubId,
            'teamId' => $ctx['team_id'] ?? null, 'staffRole' => $ctx['staff_role'],
            'player' => $player,
        ];
    }

    if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden'], 403);

    $linkedPlayerId = $user['linked_player_id'] ?? null;
    $player = null;
    if ($linkedPlayerId) {
        $pStmt = $pdo->prepare(
            'SELECT id, name, position, team_name, date_of_birth, height_cm FROM club_players WHERE id = ? LIMIT 1'
        );
        $pStmt->execute([$linkedPlayerId]);
        $player = $pStmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }
    return [
        'isCoach' => false, 'recordedBy' => 'self',
        'linkedPlayerId' => $linkedPlayerId, 'clubId' => $user['club_user_id'] ?? null,
        'teamId' => null, 'staffRole' => null,
        'player' => $player,
    ];
}

/** Goal-vs-current status, shared by save.php/history.php/goals/get.php responses. */
function bcGoalStatus(?array $goal, ?float $currentBodyFat, ?string $todayDate = null): ?array {
    if (!$goal) return null;
    $today = $todayDate ?? date('Y-m-d');
    $daysRemaining = null;
    if (!empty($goal['target_date'])) {
        $daysRemaining = (int)((strtotime($goal['target_date']) - strtotime($today)) / 86400);
    }

    $status = 'on_track';
    if ($currentBodyFat !== null && $goal['target_body_fat_percentage'] !== null) {
        $target = (float)$goal['target_body_fat_percentage'];
        $diff = abs($currentBodyFat - $target);
        if ($diff <= 0.5) {
            $status = 'achieved';
        } elseif (
            ($goal['min_acceptable_body_fat'] !== null && $currentBodyFat < (float)$goal['min_acceptable_body_fat']) ||
            ($goal['max_acceptable_body_fat'] !== null && $currentBodyFat > (float)$goal['max_acceptable_body_fat'])
        ) {
            $status = 'needs_follow_up';
        } elseif ($daysRemaining !== null && $daysRemaining < 0) {
            $status = 'behind';
        }
    }

    return [
        'target_weight_kg'             => $goal['target_weight_kg'] !== null ? (float)$goal['target_weight_kg'] : null,
        'target_body_fat_percentage'   => $goal['target_body_fat_percentage'] !== null ? (float)$goal['target_body_fat_percentage'] : null,
        'target_fat_mass_kg'           => $goal['target_fat_mass_kg'] !== null ? (float)$goal['target_fat_mass_kg'] : null,
        'target_date'                  => $goal['target_date'],
        'days_remaining'               => $daysRemaining,
        'status'                       => $status,
    ];
}
