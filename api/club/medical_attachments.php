<?php
/**
 * Medical attachments — reference links (images/X-rays/reports already
 * hosted elsewhere) on an injury case. Gated behind medical_detail.read/write
 * (doctor, physiotherapist only — same as injuries.php).
 *
 * GET    ?injury_case_id=X   — list attachments for a case
 * POST                        — add an attachment { injury_case_id, file_url, file_type, description }
 * DELETE ?id=X                — remove an attachment
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
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
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

const VALID_FILE_TYPES = ['image', 'xray', 'report', 'other'];

function attachmentOut(array $a): array {
    return [
        'id'          => (string)$a['id'],
        'file_url'    => $a['file_url'],
        'file_type'   => $a['file_type'],
        'description' => $a['description'],
        'created_at'  => $a['created_at'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'medical_detail.read');
    $injuryCaseId = trim($_GET['injury_case_id'] ?? '');
    if (!$injuryCaseId) jsonOut(['success' => false, 'message' => 'injury_case_id is required'], 400);

    $stmt = $pdo->prepare(
        'SELECT a.* FROM medical_attachments a
         JOIN injury_cases c ON c.id = a.injury_case_id
         WHERE a.injury_case_id = ? AND c.club_id = ?
         ORDER BY a.created_at DESC'
    );
    $stmt->execute([$injuryCaseId, $ctx['club_id']]);
    jsonOut(['success' => true, 'attachments' => array_map('attachmentOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

if ($method === 'POST') {
    $ctx  = requireClubPermission($pdo, $user, 'medical_detail.write');
    $body = json_decode(file_get_contents('php://input'), true) ?? [];

    $injuryCaseId = trim($body['injury_case_id'] ?? '');
    $fileUrl      = trim($body['file_url'] ?? '');
    if (!$injuryCaseId) jsonOut(['success' => false, 'message' => 'injury_case_id is required'], 400);
    if (!$fileUrl)      jsonOut(['success' => false, 'message' => 'file_url is required'], 400);
    if (!filter_var($fileUrl, FILTER_VALIDATE_URL)) jsonOut(['success' => false, 'message' => 'file_url must be a valid URL'], 400);

    $caseStmt = $pdo->prepare('SELECT id FROM injury_cases WHERE id = ? AND club_id = ?');
    $caseStmt->execute([$injuryCaseId, $ctx['club_id']]);
    if (!$caseStmt->fetchColumn()) jsonOut(['success' => false, 'message' => 'Injury case not found'], 404);

    $fileType = in_array($body['file_type'] ?? '', VALID_FILE_TYPES, true) ? $body['file_type'] : 'other';

    $stmt = $pdo->prepare(
        'INSERT INTO medical_attachments (injury_case_id, uploaded_by_user_id, file_url, file_type, description)
         VALUES (?, ?, ?, ?, ?)'
    );
    $stmt->execute([
        $injuryCaseId, $user['id'], $fileUrl, $fileType,
        trim($body['description'] ?? '') ?: null,
    ]);
    jsonOut(['success' => true, 'id' => (string)$pdo->lastInsertId()]);
}

if ($method === 'DELETE') {
    $ctx = requireClubPermission($pdo, $user, 'medical_detail.write');
    $id  = trim($_GET['id'] ?? '');
    if (!$id) jsonOut(['success' => false, 'message' => 'id is required'], 400);

    $pdo->prepare(
        'DELETE a FROM medical_attachments a
         JOIN injury_cases c ON c.id = a.injury_case_id
         WHERE a.id = ? AND c.club_id = ?'
    )->execute([$id, $ctx['club_id']]);
    jsonOut(['success' => true]);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
