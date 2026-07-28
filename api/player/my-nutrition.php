<?php
/**
 * GET /api/player/my-nutrition.php?section=profile|plans|supplements
 * Read-only: the authenticated player's own nutrition profile, day plans,
 * and supplements. Scoped to the caller's own club_players.id only.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';

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
        'SELECT u.id, u.role FROM users u
         JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);

$stmt = $pdo->prepare(
    "SELECT id FROM club_players
     WHERE linked_user_id = ? AND is_active = 1 AND player_type = 'club'
     ORDER BY created_at DESC LIMIT 1"
);
$stmt->execute([$user['id']]);
$playerId = $stmt->fetchColumn();

$section = trim($_GET['section'] ?? 'profile');

if (!$playerId) {
    jsonOut($section === 'profile' ? ['profile' => null] : ($section === 'plans' ? ['plans' => []] : ['supplements' => []]));
}

if ($section === 'profile') {
    $stmt = $pdo->prepare('SELECT * FROM nutrition_profiles WHERE player_id = ?');
    $stmt->execute([$playerId]);
    $p = $stmt->fetch(PDO::FETCH_ASSOC);
    jsonOut(['profile' => $p ? [
        'allergies'             => $p['allergies'],
        'dietary_restrictions'  => $p['dietary_restrictions'],
        'calorie_target'        => $p['calorie_target'] !== null ? (int)$p['calorie_target'] : null,
        'protein_target_g'      => $p['protein_target_g'] !== null ? (int)$p['protein_target_g'] : null,
        'carb_target_g'         => $p['carb_target_g'] !== null ? (int)$p['carb_target_g'] : null,
        'fluid_target_ml'       => $p['fluid_target_ml'] !== null ? (int)$p['fluid_target_ml'] : null,
        'notes'                 => $p['notes'],
    ] : null]);
}

if ($section === 'plans') {
    $stmt = $pdo->prepare('SELECT * FROM nutrition_day_plans WHERE player_id = ?');
    $stmt->execute([$playerId]);
    $plans = array_map(function ($p) {
        return [
            'plan_type'         => $p['plan_type'],
            'calorie_target'    => $p['calorie_target'] !== null ? (int)$p['calorie_target'] : null,
            'protein_target_g'  => $p['protein_target_g'] !== null ? (int)$p['protein_target_g'] : null,
            'carb_target_g'     => $p['carb_target_g'] !== null ? (int)$p['carb_target_g'] : null,
            'fluid_target_ml'   => $p['fluid_target_ml'] !== null ? (int)$p['fluid_target_ml'] : null,
            'hydration_before'  => $p['hydration_before'],
            'hydration_during'  => $p['hydration_during'],
            'hydration_after'   => $p['hydration_after'],
            'notes'             => $p['notes'],
        ];
    }, $stmt->fetchAll(PDO::FETCH_ASSOC));
    jsonOut(['plans' => $plans]);
}

if ($section === 'supplements') {
    $stmt = $pdo->prepare(
        'SELECT supplement_name, dosage, reason, doctor_signoff, nutritionist_signoff, status
         FROM supplements WHERE player_id = ? ORDER BY created_at DESC'
    );
    $stmt->execute([$playerId]);
    $supplements = array_map(function ($s) {
        return [
            'supplement_name'      => $s['supplement_name'],
            'dosage'                => $s['dosage'],
            'reason'                => $s['reason'],
            'doctor_signoff'        => (bool)$s['doctor_signoff'],
            'nutritionist_signoff'  => (bool)$s['nutritionist_signoff'],
            'status'                => $s['status'],
        ];
    }, $stmt->fetchAll(PDO::FETCH_ASSOC));
    jsonOut(['supplements' => $supplements]);
}

jsonOut(['error' => 'Unknown section'], 400);
