<?php
/**
 * Nutrition, Hydration & Supplements (roadmap item 5).
 * Gated behind nutrition.read/write (doctor, nutritionist). Body-composition
 * goals stay on the existing player_body_composition_goals table, untouched.
 *
 * GET  ?player_id=X&section=profile      — allergy/macro/fluid target profile
 * GET  ?player_id=X&section=plans        — day-type plans (training/match/travel/rest)
 * GET  ?player_id=X&section=supplements  — supplement list + sign-off state
 * GET  ?player_id=X&section=compliance   — recent daily compliance logs
 * GET  ?player_id=X&section=hydration    — recent daily hydration logs (ml)
 * POST action=save_profile               — upsert the profile
 * POST action=save_plan                  — upsert one day-type plan
 * POST action=add_supplement             — add a supplement needing sign-off
 * POST action=signoff_supplement         — caller signs off as doctor/nutritionist
 * POST action=log_compliance             — upsert a daily compliance entry
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

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

const VALID_PLAN_TYPES = ['training_day', 'match_day', 'travel_day', 'rest_day'];
const VALID_COMPLIANCE_STATUS = ['compliant', 'partial', 'non_compliant'];

function profileOut(array $p): array {
    return [
        'id'                    => (string)$p['id'],
        'player_id'             => $p['player_id'],
        'allergies'             => $p['allergies'],
        'dietary_restrictions'  => $p['dietary_restrictions'],
        'calorie_target'        => $p['calorie_target'] !== null ? (int)$p['calorie_target'] : null,
        'protein_target_g'      => $p['protein_target_g'] !== null ? (int)$p['protein_target_g'] : null,
        'carb_target_g'         => $p['carb_target_g'] !== null ? (int)$p['carb_target_g'] : null,
        'fluid_target_ml'       => $p['fluid_target_ml'] !== null ? (int)$p['fluid_target_ml'] : null,
        'notes'                 => $p['notes'],
        'updated_at'            => $p['updated_at'],
    ];
}

function planOut(array $p): array {
    return [
        'id'                => (string)$p['id'],
        'plan_type'         => $p['plan_type'],
        'calorie_target'    => $p['calorie_target'] !== null ? (int)$p['calorie_target'] : null,
        'protein_target_g'  => $p['protein_target_g'] !== null ? (int)$p['protein_target_g'] : null,
        'carb_target_g'     => $p['carb_target_g'] !== null ? (int)$p['carb_target_g'] : null,
        'fluid_target_ml'   => $p['fluid_target_ml'] !== null ? (int)$p['fluid_target_ml'] : null,
        'hydration_before'  => $p['hydration_before'],
        'hydration_during'  => $p['hydration_during'],
        'hydration_after'   => $p['hydration_after'],
        'notes'             => $p['notes'],
        'updated_at'        => $p['updated_at'],
    ];
}

function supplementOut(array $s): array {
    return [
        'id'                      => (string)$s['id'],
        'supplement_name'         => $s['supplement_name'],
        'dosage'                  => $s['dosage'],
        'reason'                  => $s['reason'],
        'doctor_signoff'          => (bool)$s['doctor_signoff'],
        'nutritionist_signoff'    => (bool)$s['nutritionist_signoff'],
        'status'                  => $s['status'],
        'created_at'              => $s['created_at'],
    ];
}

function complianceOut(array $c): array {
    return [
        'id'       => (string)$c['id'],
        'log_date' => $c['log_date'],
        'status'   => $c['status'],
        'notes'    => $c['notes'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'nutrition.read');

    $playerId = trim($_GET['player_id'] ?? '');
    $section  = trim($_GET['section'] ?? 'profile');
    if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);

    if ($section === 'profile') {
        $stmt = $pdo->prepare('SELECT * FROM nutrition_profiles WHERE player_id = ? AND club_id = ?');
        $stmt->execute([$playerId, $ctx['club_id']]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        jsonOut(['success' => true, 'profile' => $row ? profileOut($row) : null]);
    }

    if ($section === 'plans') {
        $stmt = $pdo->prepare('SELECT * FROM nutrition_day_plans WHERE player_id = ? AND club_id = ?');
        $stmt->execute([$playerId, $ctx['club_id']]);
        jsonOut(['success' => true, 'plans' => array_map('planOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
    }

    if ($section === 'supplements') {
        $stmt = $pdo->prepare(
            'SELECT * FROM supplements WHERE player_id = ? AND club_id = ? ORDER BY created_at DESC'
        );
        $stmt->execute([$playerId, $ctx['club_id']]);
        jsonOut(['success' => true, 'supplements' => array_map('supplementOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
    }

    if ($section === 'compliance') {
        $stmt = $pdo->prepare(
            'SELECT * FROM nutrition_compliance_logs WHERE player_id = ? AND club_id = ?
             ORDER BY log_date DESC LIMIT 30'
        );
        $stmt->execute([$playerId, $ctx['club_id']]);
        jsonOut(['success' => true, 'logs' => array_map('complianceOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
    }

    if ($section === 'hydration') {
        $stmt = $pdo->prepare(
            'SELECT log_date, amount_ml FROM hydration_logs WHERE player_id = ? AND club_id = ?
             ORDER BY log_date DESC LIMIT 30'
        );
        $stmt->execute([$playerId, $ctx['club_id']]);
        jsonOut(['success' => true, 'logs' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown section'], 400);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'nutrition.write');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? '');

    $playerId = trim($body['player_id'] ?? '');
    if ($playerId) {
        $ownStmt = $pdo->prepare('SELECT 1 FROM club_players WHERE id = ? AND club_id = ?');
        $ownStmt->execute([$playerId, $ctx['club_id']]);
        if (!$ownStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Player not found'], 404);
    }

    if ($action === 'save_profile') {
        if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);

        $stmt = $pdo->prepare(
            'INSERT INTO nutrition_profiles
                 (club_id, player_id, allergies, dietary_restrictions, calorie_target,
                  protein_target_g, carb_target_g, fluid_target_ml, notes, updated_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 allergies = VALUES(allergies),
                 dietary_restrictions = VALUES(dietary_restrictions),
                 calorie_target = VALUES(calorie_target),
                 protein_target_g = VALUES(protein_target_g),
                 carb_target_g = VALUES(carb_target_g),
                 fluid_target_ml = VALUES(fluid_target_ml),
                 notes = VALUES(notes),
                 updated_by_user_id = VALUES(updated_by_user_id)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId,
            trim($body['allergies'] ?? '') ?: null,
            trim($body['dietary_restrictions'] ?? '') ?: null,
            is_numeric($body['calorie_target'] ?? null) ? (int)$body['calorie_target'] : null,
            is_numeric($body['protein_target_g'] ?? null) ? (int)$body['protein_target_g'] : null,
            is_numeric($body['carb_target_g'] ?? null) ? (int)$body['carb_target_g'] : null,
            is_numeric($body['fluid_target_ml'] ?? null) ? (int)$body['fluid_target_ml'] : null,
            trim($body['notes'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true]);
    }

    if ($action === 'save_plan') {
        if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);
        $planType = trim($body['plan_type'] ?? '');
        if (!in_array($planType, VALID_PLAN_TYPES, true)) {
            jsonOut(['success' => false, 'message' => 'Invalid plan_type'], 400);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO nutrition_day_plans
                 (club_id, player_id, plan_type, calorie_target, protein_target_g, carb_target_g,
                  fluid_target_ml, hydration_before, hydration_during, hydration_after, notes, updated_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 calorie_target = VALUES(calorie_target),
                 protein_target_g = VALUES(protein_target_g),
                 carb_target_g = VALUES(carb_target_g),
                 fluid_target_ml = VALUES(fluid_target_ml),
                 hydration_before = VALUES(hydration_before),
                 hydration_during = VALUES(hydration_during),
                 hydration_after = VALUES(hydration_after),
                 notes = VALUES(notes),
                 updated_by_user_id = VALUES(updated_by_user_id)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId, $planType,
            is_numeric($body['calorie_target'] ?? null) ? (int)$body['calorie_target'] : null,
            is_numeric($body['protein_target_g'] ?? null) ? (int)$body['protein_target_g'] : null,
            is_numeric($body['carb_target_g'] ?? null) ? (int)$body['carb_target_g'] : null,
            is_numeric($body['fluid_target_ml'] ?? null) ? (int)$body['fluid_target_ml'] : null,
            trim($body['hydration_before'] ?? '') ?: null,
            trim($body['hydration_during'] ?? '') ?: null,
            trim($body['hydration_after'] ?? '') ?: null,
            trim($body['notes'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true]);
    }

    if ($action === 'add_supplement') {
        if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);
        $name = trim($body['supplement_name'] ?? '');
        if (!$name) jsonOut(['success' => false, 'message' => 'supplement_name is required'], 400);

        $stmt = $pdo->prepare(
            'INSERT INTO supplements (club_id, player_id, supplement_name, dosage, reason, created_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId, $name,
            trim($body['dosage'] ?? '') ?: null,
            trim($body['reason'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true, 'id' => (string)$pdo->lastInsertId()]);
    }

    if ($action === 'signoff_supplement') {
        $id = trim($body['id'] ?? '');
        if (!$id) jsonOut(['success' => false, 'message' => 'id is required'], 400);

        $stmt = $pdo->prepare('SELECT * FROM supplements WHERE id = ? AND club_id = ?');
        $stmt->execute([$id, $ctx['club_id']]);
        $supplement = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$supplement) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $role = $ctx['staff_role'];
        if (in_array($role, ['owner', 'admin'], true)) {
            // Admin/owner can sign off on behalf of either role in a small-club MVP setup.
            $role = trim($body['as_role'] ?? '');
        }
        if (!in_array($role, ['doctor', 'nutritionist'], true)) {
            jsonOut(['success' => false, 'message' => 'Only a doctor or nutritionist may sign off'], 403);
        }

        if ($role === 'doctor') {
            $pdo->prepare(
                'UPDATE supplements SET doctor_signoff = 1, doctor_signoff_by = ?, doctor_signoff_at = NOW() WHERE id = ?'
            )->execute([$user['id'], $id]);
        } else {
            $pdo->prepare(
                'UPDATE supplements SET nutritionist_signoff = 1, nutritionist_signoff_by = ?, nutritionist_signoff_at = NOW() WHERE id = ?'
            )->execute([$user['id'], $id]);
        }

        $refreshed = $pdo->prepare('SELECT * FROM supplements WHERE id = ?');
        $refreshed->execute([$id]);
        $updated = $refreshed->fetch(PDO::FETCH_ASSOC);
        if ($updated['doctor_signoff'] && $updated['nutritionist_signoff']) {
            $pdo->prepare("UPDATE supplements SET status = 'approved' WHERE id = ?")->execute([$id]);
        }

        jsonOut(['success' => true]);
    }

    if ($action === 'log_compliance') {
        if (!$playerId) jsonOut(['success' => false, 'message' => 'player_id is required'], 400);
        $date   = trim($body['log_date'] ?? date('Y-m-d'));
        $status = in_array($body['status'] ?? '', VALID_COMPLIANCE_STATUS, true) ? $body['status'] : 'compliant';

        $stmt = $pdo->prepare(
            'INSERT INTO nutrition_compliance_logs (club_id, player_id, log_date, status, notes, logged_by_user_id)
             VALUES (?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE status = VALUES(status), notes = VALUES(notes), logged_by_user_id = VALUES(logged_by_user_id)'
        );
        $stmt->execute([
            $ctx['club_id'], $playerId, $date, $status,
            trim($body['notes'] ?? '') ?: null,
            $user['id'],
        ]);
        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
