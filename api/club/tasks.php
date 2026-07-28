<?php
/**
 * Cross-department task system.
 * Any staff role can view/create/comment on tasks (gated by 'tasks.manage');
 * assigning a task to someone OTHER than yourself requires
 * 'tasks.assign_others' (owner/admin/coach/doctor/performance_manager).
 * Analyst is view-only ('tasks.view' but no 'tasks.manage').
 *
 * GET  ?filter=mine|created|all&player_id=X   — list tasks
 * GET  ?id=X&comments=1                       — one task + its comments
 * POST action=create                          — new task
 * POST action=update_status                   — change status
 * POST action=comment                         — add a comment
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

const VALID_PRIORITY = ['low', 'normal', 'high', 'urgent'];
const VALID_STATUS = ['new', 'accepted', 'in_progress', 'needs_review', 'completed', 'overdue', 'cancelled'];

function taskOut(array $t): array {
    return [
        'id'                  => (string)$t['id'],
        'title'               => $t['title'],
        'description'         => $t['description'],
        'created_by_user_id'  => (string)$t['created_by_user_id'],
        'created_by_name'     => $t['created_by_name'] ?? null,
        'assigned_to_user_id' => (string)$t['assigned_to_user_id'],
        'assigned_to_name'    => $t['assigned_to_name'] ?? null,
        'linked_player_id'    => $t['linked_player_id'],
        'linked_player_name'  => $t['linked_player_name'] ?? null,
        'linked_entity_type'  => $t['linked_entity_type'],
        'linked_entity_id'    => $t['linked_entity_id'],
        'priority'            => $t['priority'],
        'status'              => $t['status'],
        'due_date'            => $t['due_date'],
        'created_at'          => $t['created_at'],
        'updated_at'          => $t['updated_at'],
    ];
}

$method = $_SERVER['REQUEST_METHOD'];
$user   = getAuthUser($pdo);

if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
    jsonOut(['success' => false, 'message' => 'Forbidden'], 403);
}

// ── GET ──────────────────────────────────────────────────────────────────────
if ($method === 'GET') {
    $ctx = requireClubPermission($pdo, $user, 'tasks.view');

    // Lightweight staff directory (id/name/role only) for the assignee
    // picker — every role with tasks.view can see it. staff.php's own staff
    // list is admin-only ('staff.manage'), so it can't be reused here.
    if (($_GET['directory'] ?? '') === '1') {
        $stmt = $pdo->prepare(
            "SELECT s.user_id, s.staff_role, u.name
             FROM club_staff s
             JOIN users u ON u.id = s.user_id
             WHERE s.club_id = ? AND s.status = 'active'
             ORDER BY u.name ASC"
        );
        $stmt->execute([$ctx['club_id']]);
        jsonOut(['success' => true, 'staff' => array_map(function ($s) {
            return [
                'user_id'    => (string)$s['user_id'],
                'name'       => $s['name'],
                'staff_role' => $s['staff_role'],
            ];
        }, $stmt->fetchAll(PDO::FETCH_ASSOC))]);
    }

    $id = trim($_GET['id'] ?? '');
    if ($id) {
        $stmt = $pdo->prepare(
            'SELECT t.*, creator.name AS created_by_name, assignee.name AS assigned_to_name,
                    p.name AS linked_player_name
             FROM tasks t
             JOIN users creator  ON creator.id  = t.created_by_user_id
             JOIN users assignee ON assignee.id = t.assigned_to_user_id
             LEFT JOIN club_players p ON p.id = t.linked_player_id
             WHERE t.id = ? AND t.club_id = ?'
        );
        $stmt->execute([$id, $ctx['club_id']]);
        $task = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$task) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $result = ['success' => true, 'task' => taskOut($task)];

        if (($_GET['comments'] ?? '') === '1') {
            $cStmt = $pdo->prepare(
                'SELECT c.id, c.comment, c.attachment_url, c.created_at, u.name AS author_name
                 FROM task_comments c
                 JOIN users u ON u.id = c.author_user_id
                 WHERE c.task_id = ?
                 ORDER BY c.created_at ASC'
            );
            $cStmt->execute([$id]);
            $result['comments'] = array_map(function ($c) {
                return [
                    'id'             => (string)$c['id'],
                    'comment'        => $c['comment'],
                    'attachment_url' => $c['attachment_url'],
                    'author_name'    => $c['author_name'],
                    'created_at'     => $c['created_at'],
                ];
            }, $cStmt->fetchAll());
        }

        jsonOut($result);
    }

    $filter    = trim($_GET['filter'] ?? 'mine');
    $playerId  = trim($_GET['player_id'] ?? '');
    $where     = ['t.club_id = ?'];
    $params    = [$ctx['club_id']];

    if ($playerId) {
        $where[] = 't.linked_player_id = ?';
        $params[] = $playerId;
    } elseif ($filter === 'created') {
        $where[] = 't.created_by_user_id = ?';
        $params[] = $user['id'];
    } elseif ($filter !== 'all') {
        // default: 'mine' — tasks assigned to me
        $where[] = 't.assigned_to_user_id = ?';
        $params[] = $user['id'];
    }

    $sql = 'SELECT t.*, creator.name AS created_by_name, assignee.name AS assigned_to_name,
                   p.name AS linked_player_name
            FROM tasks t
            JOIN users creator  ON creator.id  = t.created_by_user_id
            JOIN users assignee ON assignee.id = t.assigned_to_user_id
            LEFT JOIN club_players p ON p.id = t.linked_player_id
            WHERE ' . implode(' AND ', $where) . '
            ORDER BY FIELD(t.status, \'overdue\', \'new\', \'in_progress\', \'needs_review\', \'accepted\', \'completed\', \'cancelled\'),
                     t.due_date IS NULL, t.due_date ASC, t.created_at DESC';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    jsonOut(['success' => true, 'tasks' => array_map('taskOut', $stmt->fetchAll(PDO::FETCH_ASSOC))]);
}

// ── POST ─────────────────────────────────────────────────────────────────────
if ($method === 'POST') {
    $ctx    = requireClubPermission($pdo, $user, 'tasks.manage');
    $body   = json_decode(file_get_contents('php://input'), true) ?? [];
    $action = trim($body['action'] ?? 'create');

    if ($action === 'create') {
        $title = trim($body['title'] ?? '');
        if (!$title) jsonOut(['success' => false, 'message' => 'title is required'], 400);

        $assignedTo = (int)($body['assigned_to_user_id'] ?? $user['id']);
        if ($assignedTo !== (int)$user['id'] && !clubStaffCan($ctx['staff_role'], 'tasks.assign_others')) {
            jsonOut(['success' => false, 'message' => 'Not allowed to assign tasks to others'], 403);
        }

        $priority = in_array($body['priority'] ?? '', VALID_PRIORITY, true) ? $body['priority'] : 'normal';
        $linkedPlayerId = trim($body['linked_player_id'] ?? '') ?: null;

        $stmt = $pdo->prepare(
            'INSERT INTO tasks
                 (club_id, title, description, created_by_user_id, assigned_to_user_id,
                  linked_player_id, linked_entity_type, linked_entity_id, priority, due_date)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([
            $ctx['club_id'], $title,
            trim($body['description'] ?? '') ?: null,
            $user['id'], $assignedTo,
            $linkedPlayerId,
            trim($body['linked_entity_type'] ?? '') ?: null,
            trim($body['linked_entity_id'] ?? '') ?: null,
            $priority,
            trim($body['due_date'] ?? '') ?: null,
        ]);
        $taskId = (int)$pdo->lastInsertId();

        if ($assignedTo !== (int)$user['id']) {
            createNotification(
                $pdo, $ctx['club_id'], $assignedTo,
                'task_assigned',
                'مهمة جديدة: ' . $title,
                trim($body['description'] ?? ''),
                '/club/tasks/' . $taskId
            );
        }

        jsonOut(['success' => true, 'id' => (string)$taskId]);
    }

    if ($action === 'update_status') {
        $taskId = trim($body['id'] ?? '');
        $status = $body['status'] ?? '';
        if (!$taskId) jsonOut(['success' => false, 'message' => 'id is required'], 400);
        if (!in_array($status, VALID_STATUS, true)) jsonOut(['success' => false, 'message' => 'Invalid status'], 400);

        $stmt = $pdo->prepare('SELECT * FROM tasks WHERE id = ? AND club_id = ?');
        $stmt->execute([$taskId, $ctx['club_id']]);
        $task = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$task) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $isParticipant = (int)$task['assigned_to_user_id'] === (int)$user['id']
            || (int)$task['created_by_user_id'] === (int)$user['id'];
        if (!$isParticipant && !clubStaffCan($ctx['staff_role'], 'tasks.assign_others')) {
            jsonOut(['success' => false, 'message' => 'Not allowed to update this task'], 403);
        }

        $pdo->prepare('UPDATE tasks SET status = ? WHERE id = ?')->execute([$status, $taskId]);
        jsonOut(['success' => true]);
    }

    if ($action === 'comment') {
        $taskId  = trim($body['id'] ?? '');
        $comment = trim($body['comment'] ?? '');
        if (!$taskId)  jsonOut(['success' => false, 'message' => 'id is required'], 400);
        if (!$comment) jsonOut(['success' => false, 'message' => 'comment is required'], 400);

        $stmt = $pdo->prepare('SELECT * FROM tasks WHERE id = ? AND club_id = ?');
        $stmt->execute([$taskId, $ctx['club_id']]);
        $task = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$task) jsonOut(['success' => false, 'message' => 'Not found'], 404);

        $pdo->prepare(
            'INSERT INTO task_comments (task_id, author_user_id, comment, attachment_url)
             VALUES (?, ?, ?, ?)'
        )->execute([$taskId, $user['id'], $comment, trim($body['attachment_url'] ?? '') ?: null]);

        // Notify the other participant (not the commenter).
        $notifyUserId = (int)$task['assigned_to_user_id'] === (int)$user['id']
            ? (int)$task['created_by_user_id']
            : (int)$task['assigned_to_user_id'];
        if ($notifyUserId !== (int)$user['id']) {
            createNotification(
                $pdo, $ctx['club_id'], $notifyUserId,
                'task_comment',
                'تعليق جديد على مهمة: ' . $task['title'],
                $comment,
                '/club/tasks/' . $taskId
            );
        }

        jsonOut(['success' => true]);
    }

    jsonOut(['success' => false, 'message' => 'Unknown action'], 400);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
