<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/club_auth.php';

function suspensionJson(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

$auth = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
$token = stripos($auth, 'Bearer ') === 0 ? trim(substr($auth, 7)) : trim($auth);
if (!$token) suspensionJson(['error' => 'Unauthorized'], 401);
$stmt = $pdo->prepare('SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())');
$stmt->execute([$token]);
$user = $stmt->fetch();
if (!$user) suspensionJson(['error' => 'Invalid token'], 401);
$ctx = requireClubPermission($pdo, $user, 'competitions.read');
$clubId = (int)$ctx['club_id'];

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $sql = 'SELECT ps.*, c.name AS competition_name, s.name AS season_name
            FROM player_suspensions ps
            JOIN club_competitions c ON c.id = ps.competition_id
            LEFT JOIN club_seasons s ON s.id = ps.season_id
            WHERE ps.club_id = ?';
    $params = [$clubId];
    if (!empty($_GET['player_id'])) { $sql .= ' AND ps.player_id = ?'; $params[] = trim($_GET['player_id']); }
    if (!empty($_GET['status'])) { $sql .= ' AND ps.status = ?'; $params[] = trim($_GET['status']); }
    $sql .= ' ORDER BY ps.created_at DESC';
    $stmt = $pdo->prepare($sql); $stmt->execute($params);
    suspensionJson(['suspensions' => $stmt->fetchAll()]);
}

requireClubPermission($pdo, $user, 'competitions.write');
$body = json_decode(file_get_contents('php://input'), true) ?? [];
$id = (int)($body['id'] ?? 0);
if (!$id) suspensionJson(['error' => 'id is required'], 422);
$stmt = $pdo->prepare('SELECT id FROM player_suspensions WHERE id = ? AND club_id = ?');
$stmt->execute([$id, $clubId]);
if (!$stmt->fetchColumn()) suspensionJson(['error' => 'Suspension not found'], 404);
$remaining = max(0, (int)($body['matches_remaining'] ?? 0));
$status = $remaining === 0 ? 'completed' : 'active';
$stmt = $pdo->prepare('UPDATE player_suspensions SET matches_remaining = ?, status = ?, administrative_decision = ?, decision_document = ?, executed_at = IF(? = 0, COALESCE(executed_at, CURDATE()), executed_at) WHERE id = ? AND club_id = ?');
$stmt->execute([$remaining, $status, $body['administrative_decision'] ?? null, $body['decision_document'] ?? null, $remaining, $id, $clubId]);
suspensionJson(['success' => true]);
