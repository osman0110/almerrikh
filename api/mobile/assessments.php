<?php
/**
 * api/mobile/assessments.php — Unified assessment create/list endpoint.
 *
 * GET  ?action=list [&player_id=X] [&source_app=X] [&limit=N]
 * POST action=create (or POST without action)
 *
 * Create rules:
 *   - user_id from token only — never from body.
 *   - player_id must belong to the authenticated user.
 *   - source_app validated against allowed registry.
 *   - type preserved verbatim; normalized_type derived server-side.
 *   - external_assessment_ref idempotency: if ref already exists for same
 *     user_id + source_app → update existing row rather than duplicate.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../includes/source_app.php';
require_once __DIR__ . '/../includes/assessment_types.php';

// ── Auth ──────────────────────────────────────────────────────────────────────

function ma_bearer(): string
{
    $auth = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? $_SERVER['Authorization'] ?? '';
    if (!$auth && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    return stripos($auth, 'Bearer ') === 0 ? trim(substr($auth, 7)) : trim($auth);
}

function ma_auth(PDO $pdo): array
{
    $token = ma_bearer();
    if (!$token) { http_response_code(401); echo json_encode(['error' => 'Unauthorized']); exit; }

    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.player_type, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) { http_response_code(401); echo json_encode(['error' => 'Invalid or expired token']); exit; }
    return $user;
}

function ma_json(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Verifies that the given player_id belongs to this user.
 * Players can access their own linked_player_id; coaches verify ownership via user_id.
 */
function ma_verify_player_ownership(PDO $pdo, array $user, string $player_id): void
{
    $isPlayer = !empty($user['player_type']);

    if ($isPlayer) {
        // Players submit under their own ID (from token), never arbitrary player_ids
        $linkedId = (string)($user['linked_player_id'] ?? '');
        if ($linkedId !== $player_id) {
            ma_json(['error' => 'Forbidden — player_id mismatch'], 403);
        }
        return;
    }

    // Coach/club: verify player belongs to their account
    $stmt = $pdo->prepare('SELECT id FROM club_players WHERE id = ? AND user_id = ? AND is_active = 1 LIMIT 1');
    $stmt->execute([$player_id, $user['id']]);
    if (!$stmt->fetch()) {
        ma_json(['error' => 'Forbidden — player not in your account'], 403);
    }
}

// ── Request ───────────────────────────────────────────────────────────────────

$method = $_SERVER['REQUEST_METHOD'];
$body   = [];
if ($method === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true) ?? [];
}

$action = $_GET['action'] ?? ($body['action'] ?? ($method === 'GET' ? 'list' : 'create'));

// ── Routes ────────────────────────────────────────────────────────────────────

switch ($action) {

    // ── list ─────────────────────────────────────────────────────────────────
    case 'list': {
        $user      = ma_auth($pdo);
        $player_id = $_GET['player_id'] ?? null;
        $src       = nk_normalize_source_app($_GET['source_app'] ?? 'all');
        $limit     = min((int)($_GET['limit'] ?? 50), 200);
        $isPlayer  = !empty($user['player_type']);

        $where  = 'a.user_id = ?';
        $params = [(int)$user['id']];

        if ($player_id) {
            $where   .= ' AND a.player_id = ?';
            $params[] = $player_id;
        } elseif ($isPlayer) {
            $linkedId = $user['linked_player_id'] ?? '';
            if (!$linkedId) ma_json(['assessments' => [], 'count' => 0]);
            $where   .= ' AND a.player_id = ?';
            $params[] = $linkedId;
        }

        if ($src !== 'all') {
            $where   .= ' AND a.source_app = ?';
            $params[] = $src;
        }

        $stmt = $pdo->prepare(
            "SELECT a.id, a.player_id, a.player_name, a.type, a.normalized_type,
                    a.overall_score, a.movement_quality_score, a.stability_score,
                    a.symmetry_score, a.control_score, a.quality_score,
                    a.issues_json, a.notes, a.source_app, a.created_at,
                    cp.name AS club_player_name
             FROM assessments a
             LEFT JOIN club_players cp ON cp.id = a.player_id AND cp.user_id = a.user_id
             WHERE {$where}
             ORDER BY a.created_at DESC
             LIMIT " . (int)$limit
        );
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($rows as &$row) {
            $row['issues']          = json_decode($row['issues_json'] ?? '[]', true) ?? [];
            $row['source_app_label'] = nk_source_app_label($row['source_app'] ?? 'legacy');
            $row['normalized_type_label'] = nk_assessment_type_label($row['normalized_type'] ?? 'other');
            unset($row['issues_json']);
        }
        unset($row);

        ma_json(['success' => true, 'assessments' => $rows, 'count' => count($rows)]);
    }

    // ── create ───────────────────────────────────────────────────────────────
    case 'create': {
        if ($method !== 'POST') ma_json(['error' => 'POST required'], 405);

        $user = ma_auth($pdo);

        $id           = trim($body['id'] ?? '');
        $player_id    = trim($body['player_id'] ?? '');
        $player_name  = trim($body['player_name'] ?? '');
        $raw_type     = trim($body['type'] ?? '');
        $source_app   = trim($body['source_app'] ?? 'nextkick_mobile');
        $ext_ref      = !empty($body['external_assessment_ref']) ? trim($body['external_assessment_ref']) : null;
        $session_id   = !empty($body['session_id']) ? trim($body['session_id']) : null;

        if (!$id)        ma_json(['error' => 'id is required'], 400);
        if (!$player_id) ma_json(['error' => 'player_id is required'], 400);
        if (!$raw_type)  ma_json(['error' => 'type is required'], 400);

        nk_require_valid_source_app($source_app);

        // Ownership check (403 on failure)
        ma_verify_player_ownership($pdo, $user, $player_id);

        $normalized_type = nk_normalize_assessment_type($raw_type);

        // Idempotency: if external_assessment_ref already exists for this user + source, update
        if ($ext_ref) {
            $dup = $pdo->prepare(
                'SELECT id FROM assessments WHERE user_id = ? AND source_app = ? AND external_assessment_ref = ? LIMIT 1'
            );
            $dup->execute([$user['id'], $source_app, $ext_ref]);
            $existing_id = $dup->fetchColumn();
            if ($existing_id && $existing_id !== $id) {
                // Redirect to the canonical id so the caller gets consistent player_id
                $id = $existing_id;
            }
        }

        $overall    = (int)($body['overall_score']          ?? 0);
        $movement   = (int)($body['movement_quality_score'] ?? $body['movement_score'] ?? 0);
        $stability  = (int)($body['stability_score']        ?? 0);
        $symmetry   = (int)($body['symmetry_score']         ?? 0);
        $control    = (int)($body['control_score']          ?? 0);
        $quality    = (int)($body['quality_score']          ?? 0);
        $issues     = json_encode($body['issues']            ?? [], JSON_UNESCAPED_UNICODE);
        $tips       = json_encode($body['correction_tips']  ?? [], JSON_UNESCAPED_UNICODE);
        $drills     = json_encode($body['recommended_drills'] ?? [], JSON_UNESCAPED_UNICODE);
        $metrics    = json_encode($body['angle_metrics']    ?? [], JSON_UNESCAPED_UNICODE);
        $raw_json   = isset($body['raw_json']) ? json_encode($body['raw_json']) : null;
        $notes      = $body['coach_notes'] ?? $body['notes'] ?? null;
        $preHooper  = isset($body['pre_hooper_index']) ? (int)$body['pre_hooper_index'] : null;
        $preRpe     = isset($body['pre_rpe'])           ? (int)$body['pre_rpe']          : null;
        $postRpe    = isset($body['post_rpe'])          ? (int)$body['post_rpe']         : null;
        $pain       = (int)(bool)($body['pain_reported'] ?? false);
        $difficulty = $body['difficulty']  ?? null;
        $mood       = isset($body['mood_after']) ? (int)$body['mood_after'] : null;
        $club_id    = isset($user['club_user_id']) && $user['club_user_id']
                        ? (int)$user['club_user_id'] : null;

        $stmt = $pdo->prepare(
            'INSERT INTO assessments
                 (id, user_id, player_id, player_name, type, normalized_type,
                  source_app, external_assessment_ref, club_id,
                  session_id, overall_score, movement_quality_score, stability_score,
                  symmetry_score, control_score, quality_score,
                  issues_json, tips_json, drills_json, angle_metrics_json, notes,
                  pre_hooper_index, pre_rpe, post_rpe, pain_reported, difficulty, mood_after)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 normalized_type         = VALUES(normalized_type),
                 source_app              = VALUES(source_app),
                 external_assessment_ref = COALESCE(VALUES(external_assessment_ref), external_assessment_ref),
                 overall_score           = VALUES(overall_score),
                 movement_quality_score  = VALUES(movement_quality_score),
                 stability_score         = VALUES(stability_score),
                 symmetry_score          = VALUES(symmetry_score),
                 control_score           = VALUES(control_score),
                 quality_score           = VALUES(quality_score),
                 issues_json             = VALUES(issues_json),
                 tips_json               = VALUES(tips_json),
                 drills_json             = VALUES(drills_json),
                 angle_metrics_json      = VALUES(angle_metrics_json),
                 notes                   = COALESCE(VALUES(notes),          notes),
                 pre_hooper_index        = COALESCE(VALUES(pre_hooper_index), pre_hooper_index),
                 pre_rpe                 = COALESCE(VALUES(pre_rpe),         pre_rpe),
                 post_rpe                = COALESCE(VALUES(post_rpe),        post_rpe),
                 pain_reported           = COALESCE(VALUES(pain_reported),   pain_reported),
                 difficulty              = COALESCE(VALUES(difficulty),      difficulty),
                 mood_after              = COALESCE(VALUES(mood_after),      mood_after)'
        );
        $stmt->execute([
            $id, $user['id'], $player_id, $player_name, $raw_type, $normalized_type,
            $source_app, $ext_ref, $club_id,
            $session_id, $overall, $movement, $stability, $symmetry, $control, $quality,
            $issues, $tips, $drills, $metrics, $notes,
            $preHooper, $preRpe, $postRpe, $pain, $difficulty, $mood,
        ]);

        // Back-fill normalized_type on legacy rows for this player
        $pdo->prepare(
            "UPDATE assessments SET normalized_type = ?
             WHERE user_id = ? AND player_id = ? AND type = ? AND (normalized_type IS NULL OR normalized_type = '')"
        )->execute([$normalized_type, $user['id'], $player_id, $raw_type]);

        // Stamp player last_assessment_at
        $pdo->prepare(
            'UPDATE club_players SET last_assessment_at = NOW()
             WHERE id = ? AND user_id = ?'
        )->execute([$player_id, $user['id']]);

        ma_json(['success' => true, 'id' => $id, 'normalized_type' => $normalized_type]);
    }

    default:
        ma_json(['error' => "Unknown action: $action"], 400);
}
