<?php
/**
 * League/competition standings table.
 *
 * GET  ?section=competitions                       — list the club's active
 *                                                     competitions (id/name/type)
 * GET  ?section=table&competition_id=X              — standings rows for one
 *                                                     competition, ordered by position
 * POST { competition_id, rows: [...] }               — replace the whole table for
 *                                                     one competition (admin/management only)
 *
 * Read is open to everyone in the club — players and every staff role — since
 * the league table is public information. Write is restricted to
 * owner/admin/performance_manager (same gate as club_competitions.write).
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
        'SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id = t.user_id
         WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['success' => false, 'message' => 'Invalid or expired token'], 401);
    return $user;
}

// Resolves the caller's club_id for read access, whichever side of the app
// they're on — players aren't club_staff rows, so resolveClubContext() (used
// for the write path) doesn't cover them.
function resolveReaderClubId(PDO $pdo, array $user): ?int {
    if (in_array($user['role'] ?? '', ['player', 'parent'], true)) {
        $stmt = $pdo->prepare(
            "SELECT club_id FROM club_players
             WHERE linked_user_id = ? AND is_active = 1
             ORDER BY created_at DESC LIMIT 1"
        );
        $stmt->execute([$user['id']]);
        $clubId = $stmt->fetchColumn();
        return $clubId ? (int)$clubId : null;
    }
    $ctx = requireClubPermission($pdo, $user, 'competitions.read');
    return $ctx['club_id'];
}

$user   = getAuthUser($pdo);
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $clubId = resolveReaderClubId($pdo, $user);
    if (!$clubId) jsonOut(['success' => true, 'competitions' => [], 'standings' => []]);

    $section = trim($_GET['section'] ?? 'competitions');

    if ($section === 'table') {
        $competitionId = (int)($_GET['competition_id'] ?? 0);
        if (!$competitionId) jsonOut(['success' => false, 'message' => 'competition_id is required'], 400);

        // Confirm the competition actually belongs to this club before leaking rows.
        $own = $pdo->prepare('SELECT 1 FROM club_competitions WHERE id = ? AND club_id = ?');
        $own->execute([$competitionId, $clubId]);
        if (!$own->fetchColumn()) jsonOut(['success' => false, 'message' => 'Competition not found'], 404);

        $stmt = $pdo->prepare(
            'SELECT id, position, team_name, played, won, drawn, lost,
                    goals_for, goals_against, points, is_own_team
             FROM club_standings WHERE competition_id = ? ORDER BY position ASC, points DESC'
        );
        $stmt->execute([$competitionId]);
        $rows = array_map(function ($r) {
            return [
                'id'            => (string)$r['id'],
                'position'      => (int)$r['position'],
                'teamName'      => $r['team_name'],
                'played'        => (int)$r['played'],
                'won'           => (int)$r['won'],
                'drawn'         => (int)$r['drawn'],
                'lost'          => (int)$r['lost'],
                'goalsFor'      => (int)$r['goals_for'],
                'goalsAgainst'  => (int)$r['goals_against'],
                'goalDifference' => (int)$r['goals_for'] - (int)$r['goals_against'],
                'points'        => (int)$r['points'],
                'isOwnTeam'     => (bool)$r['is_own_team'],
            ];
        }, $stmt->fetchAll());

        jsonOut(['success' => true, 'standings' => $rows]);
    }

    $stmt = $pdo->prepare(
        'SELECT id, name, type FROM club_competitions
         WHERE club_id = ? AND is_active = 1 ORDER BY created_at DESC'
    );
    $stmt->execute([$clubId]);
    jsonOut(['success' => true, 'competitions' => $stmt->fetchAll()]);
}

if ($method === 'POST') {
    $ctx = requireClubPermission($pdo, $user, 'competitions.write');
    $clubId = $ctx['club_id'];

    $body = json_decode(file_get_contents('php://input'), true) ?? [];
    $competitionId = (int)($body['competition_id'] ?? 0);
    $rows = $body['rows'] ?? [];
    if (!$competitionId) jsonOut(['success' => false, 'message' => 'competition_id is required'], 400);
    if (!is_array($rows)) jsonOut(['success' => false, 'message' => 'rows must be an array'], 400);

    $own = $pdo->prepare('SELECT 1 FROM club_competitions WHERE id = ? AND club_id = ?');
    $own->execute([$competitionId, $clubId]);
    if (!$own->fetchColumn()) jsonOut(['success' => false, 'message' => 'Competition not found'], 404);

    $pdo->beginTransaction();
    try {
        $pdo->prepare('DELETE FROM club_standings WHERE competition_id = ?')->execute([$competitionId]);

        $insert = $pdo->prepare(
            'INSERT INTO club_standings
             (club_id, competition_id, position, team_name, played, won, drawn, lost,
              goals_for, goals_against, points, is_own_team)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        foreach ($rows as $i => $row) {
            $teamName = trim((string)($row['teamName'] ?? ''));
            if ($teamName === '') continue;
            $insert->execute([
                $clubId,
                $competitionId,
                (int)($row['position'] ?? ($i + 1)),
                $teamName,
                (int)($row['played'] ?? 0),
                (int)($row['won'] ?? 0),
                (int)($row['drawn'] ?? 0),
                (int)($row['lost'] ?? 0),
                (int)($row['goalsFor'] ?? 0),
                (int)($row['goalsAgainst'] ?? 0),
                (int)($row['points'] ?? 0),
                (int)(bool)($row['isOwnTeam'] ?? false),
            ]);
        }

        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        jsonOut(['success' => false, 'message' => 'Failed to save standings'], 500);
    }

    jsonOut(['success' => true]);
}

jsonOut(['success' => false, 'message' => 'Method not allowed'], 405);
