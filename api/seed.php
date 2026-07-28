<?php
/**
 * NextKick — Demo Seed Script
 * Inserts realistic mock data (players + sessions) for the logged-in club.
 *
 * Usage:
 *   GET  /api/seed.php                → insert data (safe: skips if data exists)
 *   GET  /api/seed.php?reset=1        → DELETE existing club data first, then re-seed
 *   GET  /api/seed.php?only=players   → seed players only
 *   GET  /api/seed.php?only=sessions  → seed sessions only
 *
 * Requires: Authorization: Bearer <token>
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once 'db.php';

// ── Auth ─────────────────────────────────────────────────────────────────────

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

$token = bearerToken();
if (!$token) {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized — send Bearer token']);
    exit;
}

$stmt = $pdo->prepare(
    'SELECT u.id, u.name, u.role FROM users u
     JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
);
$stmt->execute([$token]);
$user = $stmt->fetch();

if (!$user) {
    http_response_code(401);
    echo json_encode(['error' => 'Invalid or expired token']);
    exit;
}
if (in_array($user['role'], ['player', 'parent'], true)) {
    http_response_code(403);
    echo json_encode(['error' => 'Forbidden — coaches/clubs only']);
    exit;
}

$uid  = (int) $user['id'];
$only  = $_GET['only']  ?? null;   // 'players' | 'sessions' | null
$reset = ($_GET['reset'] ?? '0') === '1';

// ── Optional reset ────────────────────────────────────────────────────────────

$deleted = [];
if ($reset) {
    if ($only !== 'sessions') {
        $r = $pdo->prepare('DELETE FROM club_players WHERE user_id = ?');
        $r->execute([$uid]);
        $deleted['players'] = $r->rowCount();
    }
    if ($only !== 'players') {
        $r = $pdo->prepare('DELETE FROM club_sessions WHERE user_id = ?');
        $r->execute([$uid]);
        $deleted['sessions'] = $r->rowCount();
    }
}

// ── Helper ────────────────────────────────────────────────────────────────────

function uuid(): string {
    return sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
        mt_rand(0, 0xffff), mt_rand(0, 0xffff),
        mt_rand(0, 0xffff),
        mt_rand(0, 0x0fff) | 0x4000,
        mt_rand(0, 0x3fff) | 0x8000,
        mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
    );
}

function daysAgo(int $n): string {
    return date('Y-m-d H:i:s', strtotime("-$n days"));
}
function daysFromNow(int $n): string {
    return date('Y-m-d', strtotime("+$n days"));
}

// ── Players seed ──────────────────────────────────────────────────────────────

$insertedPlayers = 0;

if ($only !== 'sessions') {

    $existing = $pdo->prepare('SELECT COUNT(*) FROM club_players WHERE user_id = ?');
    $existing->execute([$uid]);
    $hasPlayers = (int)$existing->fetchColumn() > 0;

    if ($hasPlayers && !$reset) {
        // skip silently — don't duplicate
    } else {

        $players = [

            // ── الفريق الأول — حراس المرمى ─────────────────────────────────
            [
                'name'          => 'محمد عبدالله الشيخ',
                'number'        => '1',
                'position'      => 'حارس مرمى',
                'team'          => 'الفريق الأول',
                'dob'           => '1995-03-12',
                'height'        => 188,
                'weight'        => 82,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 84.5,
                'movement'      => 82.0,
                'stability'     => 88.0,
                'symmetry'      => 85.0,
                'control'       => 83.0,
                'assessed_days' => 5,
            ],
            [
                'name'          => 'أحمد حسين مطر',
                'number'        => '23',
                'position'      => 'حارس مرمى',
                'team'          => 'تحت 21',
                'dob'           => '2003-07-20',
                'height'        => 185,
                'weight'        => 78,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => null,
                'assessed_days' => null,
            ],

            // ── الفريق الأول — المدافعون ─────────────────────────────────────
            [
                'name'          => 'كرشوم إبراهيم علي',
                'number'        => '4',
                'position'      => 'مدافع',
                'team'          => 'الفريق الأول',
                'dob'           => '1997-11-08',
                'height'        => 182,
                'weight'        => 79,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 91.2,
                'movement'      => 90.0,
                'stability'     => 93.0,
                'symmetry'      => 91.0,
                'control'       => 90.5,
                'assessed_days' => 2,
            ],
            [
                'name'          => 'ولي الدين عمر',
                'number'        => '5',
                'position'      => 'مدافع',
                'team'          => 'الفريق الأول',
                'dob'           => '1998-04-22',
                'height'        => 180,
                'weight'        => 76,
                'foot'          => 'left',
                'nationality'   => 'سوداني',
                'status'        => 'injured',
                'score'         => 78.3,
                'movement'      => 76.0,
                'stability'     => 80.0,
                'symmetry'      => 79.0,
                'control'       => 78.0,
                'assessed_days' => 18,
                'injury_notes'  => 'إصابة في الركبة اليسرى — شد عضلي',
                'return_date'   => daysFromNow(12),
            ],
            [
                'name'          => 'سيف تيري محمد',
                'number'        => '6',
                'position'      => 'ظهير أيسر',
                'team'          => 'الفريق الأول',
                'dob'           => '1999-09-15',
                'height'        => 176,
                'weight'        => 72,
                'foot'          => 'left',
                'nationality'   => 'سوداني',
                'status'        => 'recovering',
                'score'         => 72.8,
                'movement'      => 70.0,
                'stability'     => 75.0,
                'symmetry'      => 73.0,
                'control'       => 73.0,
                'assessed_days' => 10,
                'injury_notes'  => 'إجهاد في العضلة الخلفية للفخذ — في مرحلة التعافي',
                'return_date'   => daysFromNow(5),
            ],
            [
                'name'          => 'أنس أحمد البشير',
                'number'        => '2',
                'position'      => 'ظهير أيمن',
                'team'          => 'الفريق الأول',
                'dob'           => '1996-06-30',
                'height'        => 175,
                'weight'        => 70,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 86.0,
                'movement'      => 84.0,
                'stability'     => 88.0,
                'symmetry'      => 86.0,
                'control'       => 86.0,
                'assessed_days' => 7,
            ],
            [
                'name'          => 'تبنّي إبراهيم خليل',
                'number'        => '3',
                'position'      => 'مدافع',
                'team'          => 'الفريق الأول',
                'dob'           => '2000-01-14',
                'height'        => 184,
                'weight'        => 80,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 79.5,
                'movement'      => 78.0,
                'stability'     => 81.0,
                'symmetry'      => 80.0,
                'control'       => 79.0,
                'assessed_days' => 14,
            ],

            // ── الفريق الأول — الوسط ─────────────────────────────────────────
            [
                'name'          => 'مجتبى عبدالله المهدي',
                'number'        => '8',
                'position'      => 'وسط دفاعي',
                'team'          => 'الفريق الأول',
                'dob'           => '1994-12-05',
                'height'        => 178,
                'weight'        => 74,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 88.7,
                'movement'      => 87.0,
                'stability'     => 90.0,
                'symmetry'      => 89.0,
                'control'       => 89.0,
                'assessed_days' => 3,
            ],
            [
                'name'          => 'ياسر عثمان علي',
                'number'        => '10',
                'position'      => 'وسط هجومي',
                'team'          => 'الفريق الأول',
                'dob'           => '1997-08-19',
                'height'        => 174,
                'weight'        => 69,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 93.1,
                'movement'      => 92.0,
                'stability'     => 94.0,
                'symmetry'      => 93.0,
                'control'       => 93.5,
                'assessed_days' => 1,
            ],
            [
                'name'          => 'الحارث إسحاق موسى',
                'number'        => '7',
                'position'      => 'وسط',
                'team'          => 'الفريق الأول',
                'dob'           => '2001-03-28',
                'height'        => 172,
                'weight'        => 68,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 77.4,
                'movement'      => 76.0,
                'stability'     => 79.0,
                'symmetry'      => 78.0,
                'control'       => 76.5,
                'assessed_days' => 21,
            ],
            [
                'name'          => 'دانيال يوسف حسن',
                'number'        => '14',
                'position'      => 'وسط',
                'team'          => 'تحت 21',
                'dob'           => '2003-11-11',
                'height'        => 170,
                'weight'        => 66,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => null,
                'assessed_days' => null,
            ],

            // ── الفريق الأول — الهجوم ─────────────────────────────────────────
            [
                'name'          => 'بكري أحمد خليفة',
                'number'        => '11',
                'position'      => 'جناح أيسر',
                'team'          => 'الفريق الأول',
                'dob'           => '1998-02-07',
                'height'        => 171,
                'weight'        => 67,
                'foot'          => 'left',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 81.9,
                'movement'      => 80.0,
                'stability'     => 84.0,
                'symmetry'      => 82.0,
                'control'       => 81.5,
                'assessed_days' => 9,
            ],
            [
                'name'          => 'صلاح الدين عبدالرحمن',
                'number'        => '22',
                'position'      => 'جناح أيمن',
                'team'          => 'الفريق الأول',
                'dob'           => '1999-07-03',
                'height'        => 173,
                'weight'        => 70,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'suspended',
                'score'         => 75.2,
                'movement'      => 74.0,
                'stability'     => 77.0,
                'symmetry'      => 75.0,
                'control'       => 75.0,
                'assessed_days' => 15,
                'injury_notes'  => 'موقوف بسبب الإنذارات',
            ],
            [
                'name'          => 'عمر الشيخ أحمد',
                'number'        => '9',
                'position'      => 'مهاجم',
                'team'          => 'الفريق الأول',
                'dob'           => '1993-05-25',
                'height'        => 183,
                'weight'        => 80,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 89.4,
                'movement'      => 88.0,
                'stability'     => 91.0,
                'symmetry'      => 89.0,
                'control'       => 90.0,
                'assessed_days' => 4,
            ],

            // ── تحت 21 ───────────────────────────────────────────────────────
            [
                'name'          => 'آدم فضل الله',
                'number'        => '15',
                'position'      => 'مهاجم',
                'team'          => 'تحت 21',
                'dob'           => '2004-08-17',
                'height'        => 179,
                'weight'        => 73,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 68.3,
                'movement'      => 67.0,
                'stability'     => 70.0,
                'symmetry'      => 68.0,
                'control'       => 68.0,
                'assessed_days' => 6,
            ],
            [
                'name'          => 'عبدالله طارق سليمان',
                'number'        => '16',
                'position'      => 'وسط دفاعي',
                'team'          => 'تحت 21',
                'dob'           => '2004-01-09',
                'height'        => 177,
                'weight'        => 71,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => 71.0,
                'movement'      => 70.0,
                'stability'     => 73.0,
                'symmetry'      => 71.0,
                'control'       => 70.0,
                'assessed_days' => 8,
            ],
            [
                'name'          => 'محمد خالد النيل',
                'number'        => '17',
                'position'      => 'ظهير أيسر',
                'team'          => 'تحت 21',
                'dob'           => '2005-04-03',
                'height'        => 174,
                'weight'        => 68,
                'foot'          => 'left',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => null,
                'assessed_days' => null,
            ],
            [
                'name'          => 'إبراهيم حمزة محمد',
                'number'        => '18',
                'position'      => 'مدافع',
                'team'          => 'تحت 21',
                'dob'           => '2004-09-22',
                'height'        => 181,
                'weight'        => 77,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'recovering',
                'score'         => 65.5,
                'movement'      => 64.0,
                'stability'     => 67.0,
                'symmetry'      => 66.0,
                'control'       => 65.0,
                'assessed_days' => 25,
                'injury_notes'  => 'كدمة في الكاحل الأيمن',
                'return_date'   => daysFromNow(3),
            ],
            [
                'name'          => 'عمر فاروق النور',
                'number'        => '19',
                'position'      => 'جناح أيمن',
                'team'          => 'تحت 21',
                'dob'           => '2005-12-01',
                'height'        => 172,
                'weight'        => 67,
                'foot'          => 'right',
                'nationality'   => 'سوداني',
                'status'        => 'active',
                'score'         => null,
                'assessed_days' => null,
            ],
        ];

        $sql = "INSERT INTO club_players
            (id, user_id, name, number, position, team_name, date_of_birth, height_cm,
             weight_kg, dominant_foot, nationality, status, is_active, player_type,
             latest_score, movement_score, stability_score, symmetry_score, control_score,
             expected_return_date, injury_notes, last_assessment_at, created_at)
            VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'club',
             ?, ?, ?, ?, ?, ?, ?, ?, NOW())";

        $stmt = $pdo->prepare($sql);

        foreach ($players as $p) {
            $assessedAt = null;
            if (isset($p['assessed_days']) && $p['assessed_days'] !== null) {
                $assessedAt = daysAgo($p['assessed_days']);
            }

            $stmt->execute([
                uuid(), $uid,
                $p['name'], $p['number'], $p['position'], $p['team'],
                $p['dob'] ?? null,
                $p['height'] ?? null, $p['weight'] ?? null,
                $p['foot'] ?? 'right',
                $p['nationality'] ?? 'سوداني',
                $p['status'],
                $p['score'] ?? null,
                $p['movement'] ?? null, $p['stability'] ?? null,
                $p['symmetry'] ?? null, $p['control'] ?? null,
                $p['return_date'] ?? null,
                $p['injury_notes'] ?? null,
                $assessedAt,
            ]);
            $insertedPlayers++;
        }
    }
}

// ── Sessions seed ─────────────────────────────────────────────────────────────

$insertedSessions = 0;

if ($only !== 'players') {

    $existS = $pdo->prepare('SELECT COUNT(*) FROM club_sessions WHERE user_id = ?');
    $existS->execute([$uid]);
    $hasSessions = (int)$existS->fetchColumn() > 0;

    if ($hasSessions && !$reset) {
        // skip
    } else {

        $sessions = [
            [
                'id'        => uuid(),
                'title'     => 'تقييم اللياقة البدنية — الفريق الأول',
                'type'      => 'physicalAssessment',
                'status'    => 'completed',
                'date'      => date('Y-m-d', strtotime('-3 days')),
                'time'      => '08:30',
                'duration'  => 90,
                'team'      => 'الفريق الأول',
                'location'  => 'الملعب الرئيسي',
                'intensity' => 'medium',
                'players'   => 13,
                'completed' => 13,
                'ai'        => 1,
            ],
            [
                'id'        => uuid(),
                'title'     => 'حصة قوة واللياقة — الفريق الأول',
                'type'      => 'strength',
                'status'    => 'completed',
                'date'      => date('Y-m-d', strtotime('-7 days')),
                'time'      => '09:00',
                'duration'  => 75,
                'team'      => 'الفريق الأول',
                'location'  => 'القاعة المغلقة',
                'intensity' => 'high',
                'players'   => 12,
                'completed' => 10,
                'ai'        => 0,
            ],
            [
                'id'        => uuid(),
                'title'     => 'حصة تقييم — تحت 21',
                'type'      => 'physicalAssessment',
                'status'    => 'completed',
                'date'      => date('Y-m-d', strtotime('-5 days')),
                'time'      => '10:00',
                'duration'  => 60,
                'team'      => 'تحت 21',
                'location'  => 'الملعب الفرعي',
                'intensity' => 'medium',
                'players'   => 7,
                'completed' => 5,
                'ai'        => 1,
            ],
            [
                'id'        => uuid(),
                'title'     => 'حصة إعادة تأهيل',
                'type'      => 'recovery',
                'status'    => 'scheduled',
                'date'      => date('Y-m-d'),
                'time'      => '17:30',
                'duration'  => 45,
                'team'      => 'الفريق الأول',
                'location'  => 'صالة العلاج الطبيعي',
                'intensity' => 'low',
                'players'   => 3,
                'completed' => 0,
                'ai'        => 0,
            ],
            [
                'id'        => uuid(),
                'title'     => 'تقييم شامل — الفريق الأول',
                'type'      => 'physicalAssessment',
                'status'    => 'scheduled',
                'date'      => date('Y-m-d', strtotime('+2 days')),
                'time'      => '08:00',
                'duration'  => 120,
                'team'      => 'الفريق الأول',
                'location'  => 'الملعب الرئيسي',
                'intensity' => 'medium',
                'players'   => 13,
                'completed' => 0,
                'ai'        => 1,
            ],
            [
                'id'        => uuid(),
                'title'     => 'تقييم رشاقة وسرعة — تحت 21',
                'type'      => 'physicalAssessment',
                'status'    => 'scheduled',
                'date'      => date('Y-m-d', strtotime('+5 days')),
                'time'      => '09:30',
                'duration'  => 90,
                'team'      => 'تحت 21',
                'location'  => 'الملعب الفرعي',
                'intensity' => 'medium',
                'players'   => 7,
                'completed' => 0,
                'ai'        => 1,
            ],
            [
                'id'        => uuid(),
                'title'     => 'حصة تعافي وإطالة',
                'type'      => 'recovery',
                'status'    => 'completed',
                'date'      => date('Y-m-d', strtotime('-10 days')),
                'time'      => '11:00',
                'duration'  => 50,
                'team'      => 'الفريق الأول',
                'location'  => 'القاعة المغلقة',
                'intensity' => 'low',
                'players'   => 8,
                'completed' => 8,
                'ai'        => 0,
            ],
        ];

        $sSql = "INSERT INTO club_sessions
            (id, user_id, title, type, status, date, start_time, duration_min,
             team_name, location, intensity, player_count,
             completed_player_ids, ai_enabled, player_ids)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        $sStmt = $pdo->prepare($sSql);

        foreach ($sessions as $s) {
            $completedIds = array_fill(0, $s['completed'], 'mock');
            $allIds       = array_fill(0, $s['players'], 'mock');
            $sStmt->execute([
                $s['id'], $uid, $s['title'], $s['type'], $s['status'],
                $s['date'], $s['time'], $s['duration'],
                $s['team'], $s['location'], $s['intensity'],
                $s['players'],
                json_encode($completedIds),
                $s['ai'],
                json_encode($allIds),
            ]);
            $insertedSessions++;
        }
    }
}

// ── Response ──────────────────────────────────────────────────────────────────

$countP = $pdo->prepare('SELECT COUNT(*) FROM club_players WHERE user_id = ?');
$countP->execute([$uid]);
$totalPlayers = (int) $countP->fetchColumn();

$countS = $pdo->prepare('SELECT COUNT(*) FROM club_sessions WHERE user_id = ?');
$countS->execute([$uid]);
$totalSessions = (int) $countS->fetchColumn();

echo json_encode([
    'success'    => true,
    'user'       => $user['name'],
    'reset'      => $reset,
    'inserted'   => [
        'players'  => $insertedPlayers,
        'sessions' => $insertedSessions,
    ],
    'deleted'    => $deleted,
    'totals'     => [
        'players'  => $totalPlayers,
        'sessions' => $totalSessions,
    ],
    'message'    => 'تم إدخال البيانات التجريبية بنجاح 🎉',
], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
