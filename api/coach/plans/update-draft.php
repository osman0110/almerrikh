<?php
/**
 * POST /api/coach/plans/update-draft.php
 * Updates a draft plan before publishing.
 * Allowed roles: club, coach, academy
 *
 * Body:
 *   plan_id (required)
 *   title (optional) — new plan title
 *   session_updates (optional array): [{id, title, intensity, duration_minutes}]
 *   exercise_updates (optional array): [{id, exercise_name, sets, reps, duration_seconds, rest_seconds, instructions}]
 *   exercise_removals (optional array): [exercise_id, ...]
 */
require_once dirname(__DIR__, 2) . '/db.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { http_response_code(405); echo '{"error":"Method not allowed"}'; exit; }

function jsonOut(array $d, int $c = 200): never {
    http_response_code($c);
    echo json_encode($d, JSON_UNESCAPED_UNICODE);
    exit;
}
function bearerToken(): string {
    $a = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? $_SERVER['Authorization'] ?? '';
    if (!$a && function_exists('apache_request_headers')) { $h = apache_request_headers(); $a = $h['Authorization'] ?? $h['authorization'] ?? ''; }
    return stripos($a, 'Bearer ') === 0 ? trim(substr($a, 7)) : trim($a);
}
function getAuthUser(PDO $pdo): array {
    $tok = bearerToken();
    if (!$tok) jsonOut(['error' => 'Unauthorized'], 401);
    $s = $pdo->prepare('SELECT u.id,u.role FROM users u JOIN user_tokens t ON u.id=t.user_id WHERE t.token=?');
    $s->execute([$tok]); $u = $s->fetch();
    if (!$u) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $u;
}

$user = getAuthUser($pdo);
if (!in_array($user['role'], ['club','coach','academy'], true)) jsonOut(['error' => 'Forbidden'], 403);
$coachId = (int)$user['id'];

$body   = json_decode(file_get_contents('php://input'), true) ?? [];
$planId = trim((string)($body['plan_id'] ?? ''));
if (!$planId) jsonOut(['error' => 'plan_id is required'], 400);

// Verify ownership + draft status
$stmt = $pdo->prepare('SELECT id,status FROM training_plans WHERE id=? AND coach_user_id=?');
$stmt->execute([$planId, $coachId]);
$plan = $stmt->fetch();
if (!$plan) jsonOut(['error' => 'Plan not found'], 404);
if ($plan['status'] !== 'draft') jsonOut(['error' => 'Only draft plans can be updated'], 400);

$pdo->beginTransaction();
try {
    // Update plan title
    if (!empty($body['title'])) {
        $t = substr(trim((string)$body['title']), 0, 255);
        $pdo->prepare('UPDATE training_plans SET title=?,updated_at=NOW() WHERE id=?')->execute([$t, $planId]);
    }

    // Update sessions
    $sessUpdates = is_array($body['session_updates'] ?? null) ? $body['session_updates'] : [];
    $sessOwn = $pdo->prepare('SELECT id FROM training_sessions WHERE id=? AND plan_id=?');
    foreach ($sessUpdates as $su) {
        $sid = trim((string)($su['id'] ?? ''));
        if (!$sid) continue;
        $sessOwn->execute([$sid, $planId]);
        if (!$sessOwn->fetch()) continue; // not owned

        $sets = [];
        $vals = [];
        if (isset($su['title'])) { $sets[] = 'title=?'; $vals[] = substr(trim($su['title']), 0, 255); }
        if (isset($su['intensity']) && in_array($su['intensity'], ['low','medium','high'], true)) { $sets[] = 'intensity=?'; $vals[] = $su['intensity']; }
        if (isset($su['duration_minutes'])) { $d = max(15, min(180, (int)$su['duration_minutes'])); $sets[] = 'duration_minutes=?'; $vals[] = $d; }
        if (empty($sets)) continue;
        $vals[] = $sid;
        $pdo->prepare('UPDATE training_sessions SET ' . implode(',', $sets) . ' WHERE id=?')->execute($vals);
    }

    // Update exercises
    $exUpdates = is_array($body['exercise_updates'] ?? null) ? $body['exercise_updates'] : [];
    $exOwn = $pdo->prepare('SELECT se.id FROM session_exercises se JOIN training_sessions ts ON ts.id=se.session_id WHERE se.id=? AND ts.plan_id=?');
    foreach ($exUpdates as $eu) {
        $eid = (string)($eu['id'] ?? '');
        if (!$eid) continue;
        $exOwn->execute([$eid, $planId]);
        if (!$exOwn->fetch()) continue;

        $sets = []; $vals = [];
        if (isset($eu['exercise_name'])) { $sets[] = 'exercise_name=?'; $vals[] = substr(trim($eu['exercise_name']), 0, 255); }
        if (isset($eu['sets']))             { $sets[] = 'sets=?';             $vals[] = (int)$eu['sets'];             }
        if (isset($eu['reps']))             { $sets[] = 'reps=?';             $vals[] = (int)$eu['reps'];             }
        if (isset($eu['duration_seconds'])) { $sets[] = 'duration_seconds=?'; $vals[] = (int)$eu['duration_seconds']; }
        if (isset($eu['rest_seconds']))     { $sets[] = 'rest_seconds=?';     $vals[] = (int)$eu['rest_seconds'];     }
        if (isset($eu['instructions']))     { $sets[] = 'instructions=?';     $vals[] = substr(trim($eu['instructions']), 0, 1000); }
        if (empty($sets)) continue;
        $vals[] = $eid;
        $pdo->prepare('UPDATE session_exercises SET ' . implode(',', $sets) . ' WHERE id=?')->execute($vals);
    }

    // Remove exercises
    $exRemovals = is_array($body['exercise_removals'] ?? null) ? $body['exercise_removals'] : [];
    foreach ($exRemovals as $eid) {
        $eid = (string)$eid;
        $exOwn->execute([$eid, $planId]);
        if (!$exOwn->fetch()) continue;
        $pdo->prepare('DELETE FROM session_exercises WHERE id=?')->execute([$eid]);
    }

    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    jsonOut(['error' => 'Update failed: ' . $e->getMessage()], 500);
}

jsonOut(['success' => true, 'plan_id' => $planId]);
