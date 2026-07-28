<?php
/**
 * Survey API — public (no auth required)
 * Used by QR/web link for anonymous player responses.
 */

ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

set_exception_handler(function (Throwable $e) {
    error_log('[survey] Uncaught ' . get_class($e) . ': ' . $e->getMessage()
        . ' in ' . $e->getFile() . ':' . $e->getLine());
    if (!headers_sent()) {
        http_response_code(500);
        header('Content-Type: application/json; charset=utf-8');
    }
    echo json_encode(['success' => false, 'message' => 'Server error'], JSON_UNESCAPED_UNICODE);
    exit;
});

require_once 'db.php';

function jsonOut(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];

// ── GET: fetch session/match info for the survey page ─────────────────────────
if ($method === 'GET') {
    $sessionId = $_GET['session_id'] ?? null;
    $matchId   = $_GET['match_id']   ?? null;

    if ($sessionId) {
        $stmt = $pdo->prepare(
            'SELECT id, title, date, wellness_required, rpe_required, player_ids
             FROM club_sessions WHERE id = ?'
        );
        $stmt->execute([$sessionId]);
        $row = $stmt->fetch();
        if (!$row) jsonOut(['error' => 'Session not found'], 404);

        $row['player_ids'] = $row['player_ids'] && $row['player_ids'] !== 'null'
            ? json_decode($row['player_ids'], true) ?? [] : [];

        $players = [];
        if (!empty($row['player_ids'])) {
            $placeholders = implode(',', array_fill(0, count($row['player_ids']), '?'));
            $pStmt = $pdo->prepare(
                "SELECT id, name FROM club_players WHERE id IN ($placeholders) AND is_active = 1 ORDER BY name"
            );
            $pStmt->execute($row['player_ids']);
            $players = $pStmt->fetchAll();
        }

        if (empty($players)) {
            $pStmt = $pdo->prepare(
                "SELECT id, name FROM club_players
                 WHERE user_id = (SELECT user_id FROM club_sessions WHERE id = ?)
                   AND is_active = 1
                   AND (player_type IS NULL OR player_type = 'club')
                 ORDER BY name"
            );
            $pStmt->execute([$sessionId]);
            $players = $pStmt->fetchAll();
        }

        $row['players'] = $players;
        unset($row['player_ids']);
        jsonOut(['type' => 'session', 'data' => $row]);
    }

    if ($matchId) {
        $stmt = $pdo->prepare(
            'SELECT id, opponent, match_date, match_time, wellness_required, rpe_required, player_ids
             FROM matches WHERE id = ?'
        );
        $stmt->execute([$matchId]);
        $row = $stmt->fetch();
        if (!$row) jsonOut(['error' => 'Match not found'], 404);

        $row['player_ids'] = $row['player_ids'] && $row['player_ids'] !== 'null'
            ? json_decode($row['player_ids'], true) ?? [] : [];

        $players = [];
        if (!empty($row['player_ids'])) {
            $placeholders = implode(',', array_fill(0, count($row['player_ids']), '?'));
            $pStmt = $pdo->prepare(
                "SELECT id, name FROM club_players WHERE id IN ($placeholders) AND is_active = 1 ORDER BY name"
            );
            $pStmt->execute($row['player_ids']);
            $players = $pStmt->fetchAll();
        }

        if (empty($players)) {
            $pStmt = $pdo->prepare(
                "SELECT id, name FROM club_players
                 WHERE user_id = (SELECT user_id FROM matches WHERE id = ?)
                   AND is_active = 1
                   AND (player_type IS NULL OR player_type = 'club')
                 ORDER BY name"
            );
            $pStmt->execute([$matchId]);
            $players = $pStmt->fetchAll();
        }

        $row['players'] = $players;
        unset($row['player_ids']);
        jsonOut(['type' => 'match', 'data' => $row]);
    }

    jsonOut(['error' => 'session_id or match_id required'], 400);
}

// ── POST: submit survey response ──────────────────────────────────────────────
if ($method === 'POST') {
    $raw          = file_get_contents('php://input');
    $body         = json_decode($raw, true) ?? [];
    $sessionId    = $body['session_id']    ?? null;
    $matchId      = $body['match_id']      ?? null;
    $playerName   = trim($body['player_name'] ?? '');
    $playerId     = $body['player_id']     ?? null;
    $responseType = $body['response_type'] ?? 'pre';
    $responses    = $body['responses']     ?? [];

    error_log('[survey] POST type=' . $responseType
        . ' player_id=' . ($playerId ?? 'null')
        . ' session_id=' . ($sessionId ?? 'null')
        . ' keys=' . implode(',', array_keys($responses)));

    if (!$playerName)              jsonOut(['error' => 'player_name required'], 400);
    if (!$sessionId && !$matchId) jsonOut(['error' => 'session_id or match_id required'], 400);
    if (empty($responses))        jsonOut(['error' => 'responses required'], 400);

    // ── Duplicate check ───────────────────────────────────────────────────────────
    if ($playerId) {
        $checkSql = $sessionId
            ? 'SELECT id FROM survey_responses WHERE session_id = ? AND player_id = ? AND response_type = ?'
            : 'SELECT id FROM survey_responses WHERE match_id   = ? AND player_id = ? AND response_type = ?';
        $checkStmt = $pdo->prepare($checkSql);
        $checkStmt->execute([$sessionId ?? $matchId, $playerId, $responseType]);
    } else {
        $checkSql = $sessionId
            ? 'SELECT id FROM survey_responses WHERE session_id = ? AND player_name = ? AND response_type = ?'
            : 'SELECT id FROM survey_responses WHERE match_id   = ? AND player_name = ? AND response_type = ?';
        $checkStmt = $pdo->prepare($checkSql);
        $checkStmt->execute([$sessionId ?? $matchId, $playerName, $responseType]);
    }
    if ($checkStmt->fetch()) {
        jsonOut(['error' => 'already_submitted', 'message' => 'You already submitted this survey.'], 409);
    }

    // ── Read-only lookups before any write ───────────────────────────────────────
    // Fetch player's user_id (NOT NULL in wellness tables) and club_id
    $cp = null;
    if ($playerId) {
        $cpStmt = $pdo->prepare(
            'SELECT linked_user_id, user_id AS club_user_id FROM club_players WHERE id = ?'
        );
        $cpStmt->execute([$playerId]);
        $cp = $cpStmt->fetch() ?: null;
        error_log('[survey] player row: linked_user_id='
            . ($cp['linked_user_id'] ?? 'null')
            . ' club_user_id=' . ($cp['club_user_id'] ?? 'null'));
    }

    // Resolve user_id — must be non-zero (NOT NULL constraint on wellness tables)
    // Use player's own user_id if linked, otherwise coach's user_id as fallback.
    $userId = 0;
    if ($cp) {
        $userId = (int)($cp['linked_user_id'] ?? $cp['club_user_id'] ?? 0);
    }
    if ($userId === 0) {
        error_log('[survey] ERROR no valid user_id for player_id=' . ($playerId ?? 'null') . ' — bridge skipped');
    }

    // Fetch session duration for RPE training_load (post surveys only)
    $durMinutes = 0;
    if ($sessionId && $responseType === 'post') {
        $durStmt = $pdo->prepare('SELECT duration_min FROM club_sessions WHERE id = ?');
        $durStmt->execute([$sessionId]);
        $d = $durStmt->fetchColumn();
        $durMinutes = $d ? (int)$d : 0;
        error_log('[survey] session duration_minutes=' . $durMinutes);
    }

    // ── Transaction: survey_responses + wellness bridge ───────────────────────────
    try {
        $pdo->beginTransaction();

        // 1. Save survey_responses (source of truth — always saved)
        $pdo->prepare(
            'INSERT INTO survey_responses
                 (session_id, match_id, player_name, player_id, response_type, responses_json)
             VALUES (?, ?, ?, ?, ?, ?)'
        )->execute([
            $sessionId,
            $matchId,
            $playerName,
            $playerId,
            $responseType,
            json_encode($responses, JSON_UNESCAPED_UNICODE),
        ]);
        error_log('[survey] survey_responses saved OK');

        // 2. Bridge to wellness tables (only when player is found and user_id is valid)
        if ($cp && $userId > 0) {
            $clubUserId = (int)($cp['club_user_id'] ?? 0);
            $notesTxt   = isset($responses['notes']) ? substr((string)$responses['notes'], 0, 500) : null;

            if ($responseType === 'pre') {
                // Survey sleep_quality: 1=bad → 5=good (higher=better).
                // Hooper convention: higher=worse — invert: stored = 6 - survey_val.
                $slQ      = min(5, max(1, 6 - (int)($responses['sleep_quality'] ?? 3)));
                $fat      = min(5, max(1,     (int)($responses['fatigue']         ?? 3)));
                $str      = min(5, max(1,     (int)($responses['stress']          ?? 3)));
                $sor      = min(5, max(1,     (int)($responses['muscle_soreness'] ?? 3)));
                $hooScore = $slQ + $fat + $str + $sor;

                error_log("[survey] hooper bridge: user=$userId player=$playerId"
                    . " slQ=$slQ fat=$fat str=$str sor=$sor score=$hooScore");

                // Columns: only what DESCRIBE player_hooper_index shows (no source_app)
                $pdo->prepare(
                    'INSERT INTO player_hooper_index
                     (user_id, linked_player_id, club_id, session_id, training_session_id,
                      sleep_quality, fatigue, stress, muscle_soreness, pain_today, hooper_score, notes)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)'
                )->execute([
                    $userId, $playerId, $clubUserId,
                    $sessionId, $sessionId,
                    $slQ, $fat, $str, $sor,
                    $hooScore, $notesTxt,
                ]);
                error_log('[survey] hooper bridge OK — score=' . $hooScore);

            } elseif ($responseType === 'post') {
                $rpeScore = isset($responses['rpe']) ? min(10, max(1, (int)$responses['rpe'])) : null;
                if ($rpeScore !== null) {
                    $painReported = isset($responses['pain']) && (int)$responses['pain'] >= 3 ? 1 : 0;
                    $load         = $rpeScore * $durMinutes;

                    error_log("[survey] rpe bridge: user=$userId player=$playerId"
                        . " rpe=$rpeScore dur=$durMinutes load=$load pain=$painReported");

                    // Columns: only what DESCRIBE player_rpe shows (no source_app, field is duration_minutes)
                    $pdo->prepare(
                        "INSERT INTO player_rpe
                         (user_id, linked_player_id, club_id, session_id, training_session_id,
                          rpe_type, rpe_score, duration_minutes, training_load, pain_reported, notes)
                         VALUES (?, ?, ?, ?, ?, 'post', ?, ?, ?, ?, ?)"
                    )->execute([
                        $userId, $playerId, $clubUserId,
                        $sessionId, $sessionId,
                        $rpeScore, $durMinutes, $load,
                        $painReported, $notesTxt,
                    ]);
                    error_log('[survey] rpe bridge OK — load=' . $load);
                } else {
                    error_log('[survey] WARN post survey missing rpe key');
                }
            }
        } elseif (!$cp) {
            error_log('[survey] SKIP bridge — player_id not found in club_players: ' . ($playerId ?? 'null'));
        }

        $pdo->commit();
        jsonOut(['success' => true]);

    } catch (PDOException $e) {
        try { $pdo->rollBack(); } catch (Throwable $_) {}
        error_log('[survey] ERROR transaction: ' . $e->getMessage()
            . ' | type=' . $responseType
            . ' | player_id=' . ($playerId ?? 'null')
            . ' | session_id=' . ($sessionId ?? 'null'));
        jsonOut(['success' => false, 'message' => 'Unable to save survey. Please try again.'], 500);
    }
}

jsonOut(['error' => 'Method not allowed'], 405);
