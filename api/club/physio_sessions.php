<?php
/**
 * Physiotherapy & Massage Scheduling (roadmap item 4).
 * Independent treatment-session log, gated behind physio_sessions.read/write
 * (doctor, physiotherapist, massage specialist). Coach-visible availability
 * stays on the existing club_players.status field, untouched here.
 *
 * Storage: physio_sessions is one row per booking (shared time/room/reason/
 * therapist); physio_session_players is one row per player in that booking
 * (status/notes/recommendation) — mirrors club_sessions + session_attendance.
 * The wire format stays a flat list of "session x player" rows (as if still
 * denormalized) so every existing client-side grouping/display code keeps
 * working unchanged; `id` always means the player row, `session_id` the
 * shared booking.
 *
 * GET  ?player_id=X            — list sessions for a player (newest first)
 * GET  ?id=X                   — one player-row + its shared session fields
 * GET  ?date=YYYY-MM-DD         — daily schedule for the club (therapist/room workload)
 * POST action=create           — book a new session (one or more players)
 * POST action=create_bulk      — book a new session for an audience of players
 * POST action=update           — update status/notes/recommendation (player-level)
 *                                 and/or scheduled_at/duration/room (session-level)
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

const VALID_REASON  = ['recovery', 'pain', 'muscle_tightness', 'pre_match', 'post_match'];
const VALID_INTENSITY = ['light', 'moderate', 'deep'];
const VALID_RECOMMENDATION = ['rest', 'modified_training', 'doctor_followup', 'another_session'];
const VALID_STATUS  = ['scheduled', 'completed', 'cancelled', 'no_show', 'late'];

function normalizeScheduledAt($value): string {
    $value = trim((string)$value);
    if (!$value) jsonOut(['success' => false, 'message' => 'scheduled_at is required'], 400);
    try {
        return (new DateTimeImmutable($value))->format('Y-m-d H:i:s');
    } catch (Throwable $e) {
        jsonOut(['success' => false, 'message' => 'Invalid scheduled_at'], 400);
    }
}

function normalizeDuration($value): int {
    $duration = (int)$value;
    if ($duration < 5 || $duration > 480) {
        jsonOut(['success' => false, 'message' => 'duration_minutes must be between 5 and 480'], 400);
    }
    return $duration;
}

function assertAssignableTherapist(PDO $pdo, int $clubId, int $therapistId): void {
    if ($therapistId <= 0) {
        jsonOut(['success' => false, 'message' => 'Invalid therapist_user_id'], 400);
    }
    $stmt = $pdo->prepare(
        'SELECT 1 FROM club_staff
         WHERE club_id = ? AND user_id = ? AND status = \'active\'
           AND staff_role IN (\'owner\', \'admin\', \'performance_manager\', \'doctor\', \'physiotherapist\', \'massage_specialist\')'
    );
    $stmt->execute([$clubId, $therapistId]);
    if (!$stmt->fetchColumn()) {
        jsonOut(['success' => false, 'message' => 'Therapist is not an active medical staff member'], 422);
    }
}

/**
 * Per-player schedule conflicts: does this player already have another
 * physio session (any session) overlapping the given window?
 */
function findPlayerConflicts(
    PDO $pdo,
    int $clubId,
    string $playerId,
    string $scheduledAt,
    int $duration,
    ?int $excludeSessionId = null
): array {
    $endAt = (new DateTimeImmutable($scheduledAt))->modify('+' . $duration . ' minutes')->format('Y-m-d H:i:s');
    $excludeSql = $excludeSessionId ? ' AND s.id <> ?' : '';
    $sql = "SELECT sp.id AS player_row_id, s.id AS session_id, s.scheduled_at, s.duration_minutes
            FROM physio_session_players sp
            JOIN physio_sessions s ON s.id = sp.session_id
            WHERE s.club_id = ? AND sp.player_id = ?
              AND sp.status NOT IN ('cancelled', 'no_show')
              AND s.scheduled_at < ?
              AND DATE_ADD(s.scheduled_at, INTERVAL s.duration_minutes MINUTE) > ?$excludeSql";
    $params = [$clubId, $playerId, $endAt, $scheduledAt];
    if ($excludeSessionId) $params[] = $excludeSessionId;
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

/**
 * Therapist/room conflicts: does this therapist or room already have another
 * physio session (any session) overlapping the given window?
 */
function findResourceConflicts(
    PDO $pdo,
    int $clubId,
    int $therapistId,
    string $scheduledAt,
    int $duration,
    ?string $room = null,
    ?int $excludeSessionId = null
): array {
    $endAt = (new DateTimeImmutable($scheduledAt))->modify('+' . $duration . ' minutes')->format('Y-m-d H:i:s');
    $room = trim((string)$room);
    $roomSql = $room !== '' ? ' OR s.room = ?' : '';
    $excludeSql = $excludeSessionId ? ' AND s.id <> ?' : '';
    $sql = "SELECT s.id AS session_id, s.therapist_user_id, s.room, s.scheduled_at, s.duration_minutes
            FROM physio_sessions s
            WHERE s.club_id = ?
              AND s.scheduled_at < ?
              AND DATE_ADD(s.scheduled_at, INTERVAL s.duration_minutes MINUTE) > ?
              AND (s.therapist_user_id = ?$roomSql)$excludeSql";
    $params = [$clubId, $endAt, $scheduledAt, $therapistId];
    if ($room !== '') $params[] = $room;
    if ($excludeSessionId) $params[] = $excludeSessionId;
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

/**
 * Full conflict check for a single player being booked/rescheduled into a
 * session — combines their own overlap with therapist/room overlap, in the
 * same response shape the app already expects.
 */
function findSessionConflictsForPlayer(
    PDO $pdo,
    int $clubId,
    string $playerId,
    string $playerName,
    int $therapistId,
    string $scheduledAt,
    int $duration,
    ?string $room = null,
    ?int $excludeSessionId = null
): array {
    $reasons = [];
    $sessions = [];

    $playerHits = findPlayerConflicts($pdo, $clubId, $playerId, $scheduledAt, $duration, $excludeSessionId);
    if ($playerHits) {
        $reasons[] = 'player';
        foreach ($playerHits as $hit) {
            $sessions[] = [
                'session_id' => (string)$hit['session_id'],
                'player_id' => $playerId,
                'player_name' => $playerName,
                'scheduled_at' => $hit['scheduled_at'],
                'reasons' => ['player'],
            ];
        }
    }

    $resourceHits = findResourceConflicts($pdo, $clubId, $therapistId, $scheduledAt, $duration, $room, $excludeSessionId);
    foreach ($resourceHits as $hit) {
        $hitReasons = [];
        if ((int)$hit['therapist_user_id'] === $therapistId) $hitReasons[] = 'therapist';
        if ($room !== null && trim($room) !== '' && (string)$hit['room'] === trim($room)) $hitReasons[] = 'room';
        if (!$hitReasons) continue;
        $reasons = array_merge($reasons, $hitReasons);
        $sessions[] = [
            'session_id' => (string)$hit['session_id'],
            'player_id' => $playerId,
            'player_name' => $playerName,
            'scheduled_at' => $hit['scheduled_at'],
            'reasons' => $hitReasons,
        ];
    }

    if (!$reasons) return [];
    return [
        'player_id' => $playerId,
        'player_name' => $playerName,
        'reasons' => array_values(array_unique($reasons)),
        'sessions' => $sessions,
    ];
}

/** Merge a physio_sessions row + a physio_session_players row into the flat
 *  wire shape every client already consumes. */
function sessionOut(array $s, array $pp): array {
    return [
        'id'                => (string)$pp['id'],
        'session_id'        => (string)$s['id'],
        'player_id'         => $pp['player_id'],
        'session_name'      => $s['session_name'] ?? null,
        'therapist_user_id' => (string)$s['therapist_user_id'],
        'scheduled_at'      => $s['scheduled_at'],
        'duration_minutes'  => (int)$s['duration_minutes'],
        'room'              => $s['room'],
        'body_area'         => $s['body_area'],
        'session_reason'    => $s['session_reason'],
        'treatment_type'    => $s['treatment_type'],
        'intensity'         => $s['intensity'],
        'contraindications' => $s['contraindications'],
        'specialist_notes'  => $pp['specialist_notes'],
        'player_response'   => $pp['player_response'],
        'recommendation'    => $pp['recommendation'],
        'status'            => $pp['status'],
        'created_at'        => $s['created_at'],
        'updated_at'        => $pp['updated_at'],
    ];
}

$SESSION_FIELDS = "s.id AS s_id, s.club_id AS s_club_id, s.therapist_user_id AS s_therapist_user_id,
    s.scheduled_at AS s_scheduled_at, s.duration_minutes AS s_duration_minutes, s.room AS s_room,
    s.body_area AS s_body_area, s.session_reason AS s_session_reason, s.treatment_type AS s_treatment_type,
    s.intensity AS s_intensity, s.contraindications AS s_contraindications, s.session_name AS s_session_name,
    s.created_by_user_id AS s_created_by_user_id, s.created_at AS s_created_at";

function splitJoinedRow(array $row): array {
    $s = [
        'id' => $row['s_id'], 'club_id' => $row['s_club_id'], 'therapist_user_id' => $row['s_therapist_user_id'],
        'scheduled_at' => $row['s_scheduled_at'], 'duration_minutes' => $row['s_duration_minutes'],
        'room' => $row['s_room'], 'body_area' => $row['s_body_area'], 'session_reason' => $row['s_session_reason'],
        'treatment_type' => $row['s_treatment_type'], 'intensity' => $row['s_intensity'],
        'contraindications' => $row['s_contraindications'], 'session_name' => $row['s_session_name'],
        'created_by_user_id' => $row['s_created_by_user_id'], 'created_at' => $row['s_created_at'],
    ];
    $pp = [
        'id' => $row['id'], 'player_id' => $row['player_id'], 'status' => $row['status'],
        'specialist_notes' => $row['specialist_notes'], 'player_response' => $row['player_response'],
        'recommendation' => $row['recommendation'], 'updated_at' => $row['updated_at'],
    ];
    return [$s, $pp];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'physio_sessions.read');

    $id = trim($_GET['id'] ?? '');
    if ($id) {
        $stmt = $pdo->prepare(
            "SELECT sp.*, $SESSION_FIELDS
             FROM physio_session_players sp
             JOIN physio_sessions s ON s.id = sp.session_id
             WHERE sp.id = ? AND s.club_id = ?"
        );
        $stmt->execute([$id, $ctx['club_id']]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) jsonOut(['success' => false, 'message' => 'Not found'], 404);
        [$s, $pp] = splitJoinedRow($row);
        jsonOut(['success' => true, 'session' => sessionOut($s, $pp)]);
    }

    $date = trim($_GET['date'] ?? '');
    if ($date) {
        $stmt = $pdo->prepare(
            "SELECT sp.*, $SESSION_FIELDS, p.name AS player_name, u.name AS therapist_name
             FROM physio_session_players sp
             JOIN physio_sessions s ON s.id = sp.session_id
             LEFT JOIN club_players p ON p.id = sp.player_id
             LEFT JOIN users u ON u.id = s.therapist_user_id
             WHERE s.club_id = ? AND DATE(s.scheduled_at) = ?
             ORDER BY s.scheduled_at ASC"
        );
        $stmt->execute([$ctx['club_id'], $date]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        jsonOut(['success' => true, 'sessions' => array_map(function ($row) {
            [$s, $pp] = splitJoinedRow($row);
            $out = sessionOut($s, $pp);
            $out['player_name'] = $row['player_name'];
            $out['therapist_name'] = $row['therapist_name'];
            return $out;
        }, $rows)]);
    }

    $playerId = trim($_GET['player_id'] ?? '');
    if (!$playerId) {
        // No id/date/player_id — recent club-wide list, same pattern as
        // sessions.php's default GET, for the shared Sessions tab (coach/
        // admin) to merge physio sessions alongside training sessions.
        $limit = min((int)($_GET['limit'] ?? 100), 300);
        $stmt = $pdo->prepare(
            "SELECT sp.*, $SESSION_FIELDS, p.name AS player_name, u.name AS therapist_name
             FROM physio_session_players sp
             JOIN physio_sessions s ON s.id = sp.session_id
             LEFT JOIN club_players p ON p.id = sp.player_id
             LEFT JOIN users u ON u.id = s.therapist_user_id
             WHERE s.club_id = ?
             ORDER BY s.scheduled_at DESC
             LIMIT $limit"
        );
        $stmt->execute([$ctx['club_id']]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        jsonOut(['success' => true, 'sessions' => array_map(function ($row) {
            [$s, $pp] = splitJoinedRow($row);
            $out = sessionOut($s, $pp);
            $out['player_name'] = $row['player_name'];
            $out['therapist_name'] = $row['therapist_name'];
            return $out;
        }, $rows)]);
    }

    $stmt = $pdo->prepare(
        "SELECT sp.*, $SESSION_FIELDS
         FROM physio_session_players sp
         JOIN physio_sessions s ON s.id = sp.session_id
         WHERE sp.player_id = ? AND s.club_id = ?
         ORDER BY s.scheduled_at DESC, sp.id DESC"
    );
    $stmt->execute([$playerId, $ctx['club_id']]);
    jsonOut(['success' => true, 'sessions' => array_map(function ($row) {
        [$s, $pp] = splitJoinedRow($row);
        return sessionOut($s, $pp);
    }, $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'physio_sessions.write');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? 'create');

    if ($action === 'create_bulk' || $action === 'create') {
        $scheduledAt = normalizeScheduledAt($body['scheduled_at'] ?? '');
        $duration = normalizeDuration($body['duration_minutes'] ?? 30);
        $therapistId = (int)($body['therapist_user_id'] ?? $user['id']);
        assertAssignableTherapist($pdo, (int)$ctx['club_id'], $therapistId);
        $reason = in_array($body['session_reason'] ?? '', VALID_REASON, true) ? $body['session_reason'] : 'recovery';
        $intensity = in_array($body['intensity'] ?? '', VALID_INTENSITY, true) ? $body['intensity'] : 'moderate';
        $room = trim((string)($body['room'] ?? '')) ?: null;
        $sessionName = trim((string)($body['session_name'] ?? '')) ?: null;

        if ($action === 'create') {
            // Single-player quick booking.
            $playerId = trim($body['player_id'] ?? '');
            if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);

            $ownStmt = $pdo->prepare('SELECT id, name, linked_user_id FROM club_players WHERE id = ? AND club_id = ?');
            $ownStmt->execute([$playerId, $ctx['club_id']]);
            $player = $ownStmt->fetch(PDO::FETCH_ASSOC);
            if (!$player) jsonOut(['success' => false, 'message' => 'Player not found'], 404);
            $selectedPlayers = [$player];
        } else {
            // Bulk booking — audience of players.
            $audience = trim($body['audience'] ?? 'all_active');
            $rosterStmt = $pdo->prepare(
                "SELECT id, name, linked_user_id
                 FROM club_players
                 WHERE club_id = ? AND is_active = 1
                   AND (player_type IS NULL OR player_type = 'club')
                 ORDER BY name ASC"
            );
            $rosterStmt->execute([$ctx['club_id']]);
            $roster = $rosterStmt->fetchAll(PDO::FETCH_ASSOC);
            $rosterById = [];
            foreach ($roster as $player) $rosterById[(string)$player['id']] = $player;

            if ($audience === 'individual') {
                $playerId = trim((string)($body['player_id'] ?? ''));
                if (!$playerId || !isset($rosterById[$playerId])) {
                    jsonOut(['success' => false, 'message' => 'An active player is required'], 422);
                }
                $selectedPlayers = [$rosterById[$playerId]];
            } elseif ($audience === 'all_active') {
                $excluded = array_values(array_unique(array_map('strval', (array)($body['excluded_player_ids'] ?? []))));
                foreach ($excluded as $excludedId) {
                    if (!isset($rosterById[$excludedId])) {
                        jsonOut(['success' => false, 'message' => 'One or more excluded players are invalid'], 422);
                    }
                }
                $selectedPlayers = array_values(array_filter(
                    $roster,
                    static fn(array $player): bool => !in_array((string)$player['id'], $excluded, true)
                ));
            } else {
                jsonOut(['success' => false, 'message' => 'Invalid audience'], 400);
            }

            if (!$selectedPlayers) {
                jsonOut(['success' => false, 'message' => 'At least one active player must be selected'], 422);
            }
        }

        $conflicts = [];
        foreach ($selectedPlayers as $player) {
            $playerConflict = findSessionConflictsForPlayer(
                $pdo, (int)$ctx['club_id'], (string)$player['id'], $player['name'] ?? '',
                $therapistId, $scheduledAt, $duration, $room
            );
            if ($playerConflict) $conflicts[] = $playerConflict;
        }
        if ($conflicts) {
            jsonOut([
                'success' => false,
                'message' => 'Some players or resources have schedule conflicts',
                'conflicts' => $conflicts,
            ], 409);
        }

        $pdo->beginTransaction();
        try {
            $pdo->prepare(
                'INSERT INTO physio_sessions
                     (club_id, therapist_user_id, scheduled_at, duration_minutes, room,
                      body_area, session_reason, treatment_type, intensity, contraindications,
                      created_by_user_id, session_name)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            )->execute([
                $ctx['club_id'], $therapistId, $scheduledAt, $duration, $room,
                trim((string)($body['body_area'] ?? '')) ?: null,
                $reason,
                trim((string)($body['treatment_type'] ?? '')) ?: null,
                $intensity,
                trim((string)($body['contraindications'] ?? '')) ?: null,
                $user['id'],
                $sessionName,
            ]);
            $sessionId = (int)$pdo->lastInsertId();

            $insertPlayer = $pdo->prepare(
                "INSERT INTO physio_session_players (session_id, player_id, status)
                 VALUES (?, ?, 'scheduled')"
            );
            $createdPlayerRowIds = [];
            foreach ($selectedPlayers as $player) {
                $insertPlayer->execute([$sessionId, $player['id']]);
                $createdPlayerRowIds[] = (string)$pdo->lastInsertId();
            }
            $pdo->commit();
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            throw $e;
        }

        // The physio session(s) above are already committed — a notification
        // failure here must never be reported back to the caller as a save
        // failure.
        try {
            foreach ($selectedPlayers as $index => $player) {
                if (!empty($player['linked_user_id'])) {
                    createNotification(
                        $pdo, (int)$ctx['club_id'], (int)$player['linked_user_id'], 'physio_session_scheduled',
                        ['reason' => $reason, 'scheduled_at' => $scheduledAt], '/physio-session/' . $createdPlayerRowIds[$index]
                    );
                }
            }
            if ($therapistId !== (int)$user['id']) {
                $playerCount = count($selectedPlayers);
                createNotification(
                    $pdo, (int)$ctx['club_id'], $therapistId, 'physio_session_assigned',
                    ['player_count' => $playerCount, 'scheduled_at' => $scheduledAt], '/physio-session/' . $createdPlayerRowIds[0]
                );
            }
        } catch (Throwable $e) {
            error_log('physio_sessions.php: notification failed: ' . $e->getMessage());
        }

        jsonOut([
            'success' => true,
            'created_count' => count($createdPlayerRowIds),
            'created_ids' => $createdPlayerRowIds,
            'session_id' => (string)$sessionId,
            'unlinked_count' => count(array_filter($selectedPlayers, static fn(array $p): bool => empty($p['linked_user_id']))),
        ]);
    }

    if ($action === 'update') {
        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['success' => false, 'message' => 'id is required'], 400);

        $stmt = $pdo->prepare(
            "SELECT sp.*, $SESSION_FIELDS
             FROM physio_session_players sp
             JOIN physio_sessions s ON s.id = sp.session_id
             WHERE sp.id = ? AND s.club_id = ?"
        );
        $stmt->execute([$id, $ctx['club_id']]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) jsonOut(['success' => false, 'message' => 'Not found'], 404);
        [$s, $pp] = splitJoinedRow($row);
        $sessionId = (int)$s['id'];

        // Session-level reschedule — affects every player in this session.
        $wantsReschedule = array_key_exists('scheduled_at', $body)
            || array_key_exists('duration_minutes', $body)
            || array_key_exists('room', $body);
        if ($wantsReschedule) {
            $newScheduledAt = array_key_exists('scheduled_at', $body)
                ? normalizeScheduledAt($body['scheduled_at']) : $s['scheduled_at'];
            $newDuration = array_key_exists('duration_minutes', $body)
                ? normalizeDuration($body['duration_minutes']) : (int)$s['duration_minutes'];
            $newRoom = array_key_exists('room', $body) ? (trim((string)$body['room']) ?: null) : $s['room'];

            $resourceConflicts = findResourceConflicts(
                $pdo, (int)$ctx['club_id'], (int)$s['therapist_user_id'], $newScheduledAt, $newDuration, $newRoom, $sessionId
            );
            if ($resourceConflicts) {
                jsonOut([
                    'success' => false,
                    'message' => 'Resource has a schedule conflict',
                    'conflicts' => [['reasons' => ['therapist_or_room'], 'sessions' => $resourceConflicts]],
                ], 409);
            }
            // Every other player in this session must also be free at the new time.
            $otherPlayers = $pdo->prepare(
                'SELECT player_id FROM physio_session_players WHERE session_id = ? AND id <> ?'
            );
            $otherPlayers->execute([$sessionId, $id]);
            foreach (array_column($otherPlayers->fetchAll(PDO::FETCH_ASSOC), 'player_id') as $otherPlayerId) {
                $hits = findPlayerConflicts($pdo, (int)$ctx['club_id'], $otherPlayerId, $newScheduledAt, $newDuration, $sessionId);
                if ($hits) {
                    jsonOut([
                        'success' => false,
                        'message' => 'A player in this session has a schedule conflict',
                        'conflicts' => [['player_id' => $otherPlayerId, 'reasons' => ['player']]],
                    ], 409);
                }
            }

            $pdo->prepare(
                'UPDATE physio_sessions SET scheduled_at = ?, duration_minutes = ?, room = ? WHERE id = ?'
            )->execute([$newScheduledAt, $newDuration, $newRoom, $sessionId]);
        }

        // Player-level fields.
        $status         = in_array($body['status'] ?? '', VALID_STATUS, true) ? $body['status'] : $pp['status'];
        $recommendation = in_array($body['recommendation'] ?? '', VALID_RECOMMENDATION, true)
            ? $body['recommendation'] : $pp['recommendation'];
        $specialistNotes = array_key_exists('specialist_notes', $body) ? trim($body['specialist_notes']) : $pp['specialist_notes'];
        $playerResponse  = array_key_exists('player_response', $body) ? trim($body['player_response']) : $pp['player_response'];

        $pdo->prepare(
            'UPDATE physio_session_players
             SET status = ?, recommendation = ?, specialist_notes = ?, player_response = ?
             WHERE id = ?'
        )->execute([
            $status, $recommendation, $specialistNotes ?: null, $playerResponse ?: null, $id,
        ]);

        $rescheduled = $wantsReschedule && $newScheduledAt !== $s['scheduled_at'];
        if ($status !== $pp['status'] || $rescheduled) {
            $linkStmt = $pdo->prepare(
                'SELECT linked_user_id FROM club_players WHERE id = ? AND club_id = ?'
            );
            $linkStmt->execute([$pp['player_id'], $ctx['club_id']]);
            $linkedUserId = $linkStmt->fetchColumn();
            if ($linkedUserId) {
                $effectiveScheduledAt = $rescheduled ? $newScheduledAt : $s['scheduled_at'];
                createNotification(
                    $pdo, (int)$ctx['club_id'], (int)$linkedUserId, 'physio_session_updated',
                    ['status' => $status, 'scheduled_at' => $effectiveScheduledAt], '/physio-session/' . $id
                );
            }
        }

        // Recommendation escalated to a doctor follow-up — alert the club's doctor(s).
        if ($recommendation === 'doctor_followup' && $recommendation !== $pp['recommendation']) {
            notifyClubRole(
                $pdo, (int)$ctx['club_id'], 'doctor', 'physio_doctor_followup',
                [], ['linked_route' => '/physio-session/' . $id]
            );
        }

        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
