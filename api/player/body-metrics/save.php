<?php
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/audit_log.php';
require_once dirname(__DIR__, 2) . '/includes/bmi_for_age.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('Method not allowed', 405);

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

$user = getAuthUser($pdo);
$body = json_decode(file_get_contents('php://input'), true) ?? [];

// A coach (any non-player/parent role) may record metrics on behalf of a
// roster player — most club players never sign in themselves, so this is
// the only way their body composition ever gets tracked.
$isCoach = !in_array($user['role'], ['player', 'parent'], true);
$recordedBy = 'self';
$linkedPlayerId = null;
$clubId = null;

if ($isCoach) {
    $ctx = requireClubPermission($pdo, $user, 'medical.write');
    $targetPlayerId = trim((string)($body['player_id'] ?? ''));
    if (!$targetPlayerId) jsonOut(['error' => 'player_id is required'], 400);
    $pStmt = $pdo->prepare(
        'SELECT id FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1 LIMIT 1'
    );
    $pStmt->execute([$targetPlayerId, $ctx['club_id']]);
    if (!$pStmt->fetch()) jsonOut(['error' => 'Player not found in your roster'], 404);
    $linkedPlayerId = $targetPlayerId;
    $clubId = $ctx['club_id'];
    $recordedBy = 'coach';
} elseif ($user['role'] !== 'player') {
    jsonOut(['error' => 'Forbidden'], 403);
} else {
    $linkedPlayerId = $user['linked_player_id'] ?? null;
    if ($linkedPlayerId) {
        $cpStmt = $pdo->prepare('SELECT club_id FROM club_players WHERE id = ?');
        $cpStmt->execute([$linkedPlayerId]);
        $clubId = $cpStmt->fetchColumn() ?: null;
    }
}

$weight = isset($body['weight_kg']) ? (float)$body['weight_kg'] : null;
$height = isset($body['height_cm']) ? (float)$body['height_cm'] : null;
$fat    = isset($body['body_fat_percent']) ? (float)$body['body_fat_percent'] : null;

if ($weight === null || $height === null || $fat === null)
    jsonOut(['error' => 'weight_kg, height_cm, body_fat_percent are required'], 400);
if ($weight < 20 || $weight > 300)
    jsonOut(['error' => 'weight_kg must be 20–300'], 400);
if ($height < 100 || $height > 250)
    jsonOut(['error' => 'height_cm must be 100–250'], 400);
if ($fat < 1 || $fat > 60)
    jsonOut(['error' => 'body_fat_percent must be 1–60'], 400);

// Optional extra measurements
$waist = isset($body['waist_cm']) ? (float)$body['waist_cm'] : null;
if ($waist !== null && ($waist < 30 || $waist > 200))
    jsonOut(['error' => 'waist_cm must be 30–200'], 400);

$allowedMethods = ['caliper', 'bia', 'dexa', 'visual_estimate', 'other'];
$method = isset($body['measurement_method']) && in_array($body['measurement_method'], $allowedMethods, true)
    ? $body['measurement_method'] : null;
$deviceName  = isset($body['device_name'])   ? substr((string)$body['device_name'], 0, 100) : null;
$measuredBy  = isset($body['measured_by'])   ? substr((string)$body['measured_by'], 0, 100) : null;
if (!$measuredBy && $isCoach) $measuredBy = $user['name'];
$specialistNotes = isset($body['specialist_notes']) ? substr((string)$body['specialist_notes'], 0, 1000) : null;

$heightM = $height / 100;
$bmi = round($weight / ($heightM * $heightM), 2);

// Derived body composition — computed and persisted server-side (previously
// only ever computed transiently in the Flutter UI and never saved).
$fatMassKg  = round($weight * $fat / 100, 2);
$leanMassKg = round($weight - $fatMassKg, 2);

// BMI-for-age (youth players only) — uses age from user_profiles if the
// player has one on file; explicit age_years in the request takes priority.
$ageYears = isset($body['age_years']) ? (float)$body['age_years'] : null;
if ($ageYears === null) {
    if ($isCoach) {
        $ageStmt = $pdo->prepare('SELECT date_of_birth FROM club_players WHERE id = ?');
        $ageStmt->execute([$linkedPlayerId]);
        $dob = $ageStmt->fetchColumn();
        $ageYears = $dob ? (float)date_diff(date_create($dob), date_create('now'))->y : null;
    } else {
        $ageStmt = $pdo->prepare('SELECT age FROM user_profiles WHERE user_id = ?');
        $ageStmt->execute([$user['id']]);
        $ageRow = $ageStmt->fetch(PDO::FETCH_ASSOC);
        $ageYears = $ageRow && $ageRow['age'] !== null ? (float)$ageRow['age'] : null;
    }
}
$bmiForAgeCategory = ($ageYears !== null && $ageYears > 0) ? classifyBmiForAge($bmi, $ageYears) : null;

// Previous measurement, for the audit trail below — each submission is a new
// historical row (never overwritten), but we still log the delta vs the
// last known value so a specialist can see who changed what and when.
if ($isCoach) {
    $prevStmt = $pdo->prepare(
        'SELECT weight_kg, body_fat_percent, waist_cm FROM player_body_metrics
         WHERE linked_player_id = ? ORDER BY measured_at DESC LIMIT 1'
    );
    $prevStmt->execute([$linkedPlayerId]);
} else {
    $prevStmt = $pdo->prepare(
        'SELECT weight_kg, body_fat_percent, waist_cm FROM player_body_metrics
         WHERE user_id = ? ORDER BY measured_at DESC LIMIT 1'
    );
    $prevStmt->execute([$user['id']]);
}
$prev = $prevStmt->fetch(PDO::FETCH_ASSOC) ?: null;

$stmt = $pdo->prepare(
    'INSERT INTO player_body_metrics
     (user_id, club_id, weight_kg, height_cm, body_fat_percent, bmi,
      fat_mass_kg, lean_mass_kg, waist_cm, bmi_for_age_category,
      measurement_method, device_name, measured_by, specialist_notes,
      linked_player_id, recorded_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
);
$stmt->execute([
    $user['id'], $clubId, $weight, $height, $fat, $bmi,
    $fatMassKg, $leanMassKg, $waist, $bmiForAgeCategory,
    $method, $deviceName, $measuredBy, $specialistNotes,
    $linkedPlayerId, $recordedBy,
]);
$id = (int)$pdo->lastInsertId();

logAuditDiff($pdo, 'player_body_metrics', (string)($linkedPlayerId ?? $user['id']), $prev, [
    'weight_kg'        => $weight,
    'body_fat_percent' => $fat,
    'waist_cm'         => $waist,
], (int)$user['id']);

jsonOut([
    'success'  => true,
    'id'       => $id,
    'bmi'      => $bmi,
    'fat_mass_kg'  => $fatMassKg,
    'lean_mass_kg' => $leanMassKg,
    'bmi_for_age_category' => $bmiForAgeCategory,
]);
