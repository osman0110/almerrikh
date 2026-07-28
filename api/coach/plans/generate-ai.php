<?php
/**
 * POST /api/coach/plans/generate-ai.php
 * Allowed roles: club, coach, academy
 * Generates an AI training plan draft for one or more club players.
 */
require_once dirname(__DIR__, 2) . '/db.php';
require_once dirname(__DIR__, 2) . '/includes/club_auth.php';

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
    if (!$a && function_exists('apache_request_headers')) {
        $h = apache_request_headers();
        $a = $h['Authorization'] ?? $h['authorization'] ?? '';
    }
    return stripos($a, 'Bearer ') === 0 ? trim(substr($a, 7)) : trim($a);
}
function getAuthUser(PDO $pdo): array {
    $tok = bearerToken();
    if (!$tok) jsonOut(['error' => 'Unauthorized'], 401);
    $s = $pdo->prepare('SELECT u.id, u.role FROM users u JOIN user_tokens t ON u.id=t.user_id WHERE t.token=?');
    $s->execute([$tok]);
    $u = $s->fetch();
    if (!$u) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $u;
}

// ── Auth + role guard ────────────────────────────────────────────────────────
$user = getAuthUser($pdo);
if (!in_array($user['role'], ['club','coach','academy'], true)) jsonOut(['error' => 'Forbidden'], 403);
$coachId = (int)$user['id'];
// Roster scope is the club (shared across every coach/staff member), not
// whichever coach is logged in — a player never belongs to a single coach.
$ctx = requireClubPermission($pdo, $user, 'players.read');
$clubId = $ctx['club_id'];

$body = json_decode(file_get_contents('php://input'), true) ?? [];

// ── Input validation ─────────────────────────────────────────────────────────
$allowedTargets = ['single_player','selected_players','team'];
$targetType = in_array($body['target_type'] ?? '', $allowedTargets, true) ? $body['target_type'] : null;
if (!$targetType) jsonOut(['error' => 'target_type must be: '.implode(', ',$allowedTargets)], 400);

$allowedGoals = ['speed','endurance','strength','agility','football_skill','injury_prevention','recovery','mixed'];
$goal = in_array($body['goal'] ?? '', $allowedGoals, true) ? $body['goal'] : null;
if (!$goal) jsonOut(['error' => 'goal must be: '.implode(', ',$allowedGoals)], 400);

$durationMin = (int)($body['duration_minutes'] ?? 60);
if ($durationMin < 15 || $durationMin > 120) jsonOut(['error' => 'duration_minutes must be 15–120'], 400);

$daysPerWeek = (int)($body['days_per_week'] ?? 3);
if ($daysPerWeek < 1 || $daysPerWeek > 7) jsonOut(['error' => 'days_per_week must be 1–7'], 400);

$numWeeks = (int)($body['weeks'] ?? 4);
if ($numWeeks < 1 || $numWeeks > 8) jsonOut(['error' => 'weeks must be 1–8'], 400);

$allowedIntensity = ['low','medium','high','adaptive'];
$intensityPref = in_array($body['intensity_preference'] ?? '', $allowedIntensity, true) ? $body['intensity_preference'] : 'medium';

$equipment  = is_array($body['equipment'] ?? null) ? array_map('strval', $body['equipment']) : ['bodyweight'];
$coachNotes = substr(trim((string)($body['coach_notes'] ?? '')), 0, 2000);

// ── Resolve target player IDs ────────────────────────────────────────────────
$playerIds = [];
if ($targetType === 'team') {
    $teamName = trim((string)($body['team_name'] ?? ''));
    if (!$teamName) jsonOut(['error' => 'team_name required for target_type=team'], 400);
    $ts = $pdo->prepare('SELECT id FROM club_players WHERE club_id=? AND team_name=? AND is_active=1');
    $ts->execute([$clubId, $teamName]);
    $playerIds = array_column($ts->fetchAll(), 'id');
    if (empty($playerIds)) jsonOut(['error' => 'No active players found in team'], 400);
} else {
    $raw = is_array($body['player_ids'] ?? null) ? $body['player_ids'] : [];
    $playerIds = array_map('strval', $raw);
}
if (empty($playerIds)) jsonOut(['error' => 'At least one player required'], 400);

// ── Gather player data (ownership-verified) ──────────────────────────────────
$playersPayload = [];
$verifyStmt = $pdo->prepare(
    'SELECT cp.id, cp.name, cp.position, cp.height_cm, cp.weight_kg,
            cp.injury_notes, cp.linked_user_id
     FROM club_players cp WHERE cp.id=? AND cp.club_id=? AND cp.is_active=1'
);
foreach ($playerIds as $pid) {
    $verifyStmt->execute([$pid, $clubId]);
    $cp = $verifyStmt->fetch();
    if (!$cp) jsonOut(['error' => 'Forbidden — player not in your scope'], 403);

    $lu = $cp['linked_user_id'] ? (int)$cp['linked_user_id'] : null;

    $profile = [];
    if ($lu) {
        $s = $pdo->prepare('SELECT age,position,fitness_level,skill_level,injury_limitations FROM user_profiles WHERE user_id=?');
        $s->execute([$lu]); $profile = $s->fetch() ?: [];
    }
    $metrics = [];
    if ($lu) {
        $s = $pdo->prepare('SELECT weight_kg,height_cm,body_fat_percent FROM player_body_metrics WHERE user_id=? ORDER BY measured_at DESC LIMIT 1');
        $s->execute([$lu]); $metrics = $s->fetch() ?: [];
    }
    $hooper = null;
    $painRep = false;
    if ($lu) {
        $s = $pdo->prepare('SELECT hooper_score,pain_reported FROM player_hooper_index WHERE user_id=? ORDER BY created_at DESC LIMIT 1');
        $s->execute([$lu]); $row = $s->fetch();
        $hooper = $row ? (int)$row['hooper_score'] : null;
        $painRep= $row ? (bool)$row['pain_reported'] : false;
    }
    $preRpe = null;
    if ($lu) {
        $s = $pdo->prepare("SELECT rpe_score FROM player_rpe WHERE user_id=? AND rpe_type='pre' ORDER BY created_at DESC LIMIT 1");
        $s->execute([$lu]); $row = $s->fetch(); $preRpe = $row ? (float)$row['rpe_score'] : null;
    }
    $postRpe = null;
    if ($lu) {
        $s = $pdo->prepare("SELECT rpe_score FROM player_rpe WHERE user_id=? AND rpe_type='post' ORDER BY created_at DESC LIMIT 1");
        $s->execute([$lu]); $row = $s->fetch(); $postRpe = $row ? (float)$row['rpe_score'] : null;
    }
    $assessScore = null;
    if ($lu) {
        $s = $pdo->prepare('SELECT overall_score FROM assessments WHERE user_id=? ORDER BY created_at DESC LIMIT 1');
        $s->execute([$lu]); $row = $s->fetch(); $assessScore = $row ? (int)$row['overall_score'] : null;
    }
    $completionRate = null;
    if ($lu) {
        $s = $pdo->prepare("SELECT COUNT(*) total, SUM(status='completed') done FROM session_players WHERE player_user_id=? AND created_at >= DATE_SUB(NOW(),INTERVAL 30 DAY)");
        $s->execute([$lu]); $row = $s->fetch();
        if ($row && (int)$row['total'] > 0) $completionRate = (int)round($row['done'] / $row['total'] * 100);
    }

    $playersPayload[] = [
        'linked_player_id'       => $pid,
        'name'                   => $cp['name'],
        'age'                    => isset($profile['age'])          ? (int)$profile['age'] : null,
        'position'               => $profile['position']            ?? $cp['position']     ?? null,
        'height_cm'              => isset($metrics['height_cm'])    ? (float)$metrics['height_cm']  : (isset($cp['height_cm'])  ? (float)$cp['height_cm']  : null),
        'weight_kg'              => isset($metrics['weight_kg'])    ? (float)$metrics['weight_kg']  : (isset($cp['weight_kg'])  ? (float)$cp['weight_kg']  : null),
        'fat_percentage'         => isset($metrics['body_fat_percent']) ? (float)$metrics['body_fat_percent'] : null,
        'fitness_level'          => $profile['fitness_level']       ?? 'intermediate',
        'football_skill_level'   => $profile['skill_level']         ?? 'intermediate',
        'injury_limitations'     => $profile['injury_limitations']  ?? $cp['injury_notes'] ?? '',
        'latest_assessment_score'=> $assessScore,
        'latest_hooper_index'    => $hooper,
        'latest_pre_rpe'         => $preRpe,
        'latest_post_rpe'        => $postRpe,
        'pain_reported'          => $painRep,
        'completion_rate'        => $completionRate,
    ];
}

// ── Build request snapshot ───────────────────────────────────────────────────
$requestSnapshot = [
    'mode'    => 'club_coach_plan',
    'request' => [
        'target_type'          => $targetType,
        'goal'                 => $goal,
        'duration_minutes'     => $durationMin,
        'days_per_week'        => $daysPerWeek,
        'weeks'                => $numWeeks,
        'intensity_preference' => $intensityPref,
        'equipment'            => $equipment,
        'coach_notes'          => $coachNotes ?: null,
    ],
    'players' => $playersPayload,
];

// ── Mock mode (env AI_PLAN_MOCK=true  or  body mock:true in local/dev only) ──
$mockMode = (getenv('AI_PLAN_MOCK') === 'true')
         || (!empty($body['mock']) && getenv('APP_ENV') !== 'production');

$aiText   = '';
$planData = null;

if ($mockMode) {
    $planData = buildMockPlan($numWeeks, $daysPerWeek, $durationMin, $goal);
    $aiText   = 'mock';
} else {
    if (!ANTHROPIC_API_KEY) jsonOut(['success' => false, 'error' => 'AI provider not configured'], 503);

    $schema = json_encode([
        'plan_title' => 'string',
        'summary'    => 'string — 2-3 sentences',
        'weeks' => [[
            'week' => 1,
            'sessions' => [[
                'title' => 'string', 'objective' => 'fitness|football|recovery|assessment|mixed',
                'duration_minutes' => $durationMin, 'intensity' => 'low|medium|high',
                'exercises' => [[
                    'exercise_name' => 'string',
                    'category'      => 'football|fitness|mobility|recovery|assessment',
                    'sets' => null, 'reps' => null,
                    'duration_seconds' => null, 'rest_seconds' => null,
                    'instructions' => 'string',
                    'requires_pose_detection' => false,
                    'assessment_type' => null,
                ]],
            ]],
        ]],
        'recovery_notes'    => 'string',
        'progression_rules' => 'string',
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

    $pc = count($playersPayload);
    $ps = $pc === 1 ? "1 player: {$playersPayload[0]['name']}" : "{$pc} players";

    $prompt  = "You are a professional football fitness and conditioning coach AI.\n\n";
    $prompt .= "Create a club/coach {$numWeeks}-week football training plan for {$ps}.\n\n";
    $prompt .= "Request:\n" . json_encode($requestSnapshot['request'], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n\n";
    $prompt .= "Players:\n" . json_encode($playersPayload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n\n";
    $prompt .= "Rules:\n";
    $prompt .= "- Each week must have exactly {$daysPerWeek} sessions.\n";
    $prompt .= "- Session duration ≈ {$durationMin} min. Include warm-up and cool-down.\n";
    $prompt .= "- Adapt loads to fitness_level and football_skill_level.\n";
    $prompt .= "- If any player has pain_reported=true: avoid high-impact exercises that week.\n";
    $prompt .= "- If hooper_index > 14: add recovery focus in week 1.\n";
    $prompt .= "- Do NOT set requires_pose_detection=true unless category=assessment.\n";
    $prompt .= "- summary: 2-3 sentences about the overall approach.\n";
    $prompt .= "- recovery_notes: 1-2 sentences.\n";
    $prompt .= "- progression_rules: 1-2 sentences.\n\n";
    $prompt .= "Return ONLY valid JSON (no markdown, no text outside JSON):\n" . $schema;

    $ch = curl_init('https://api.anthropic.com/v1/messages');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_TIMEOUT        => 90,
        CURLOPT_HTTPHEADER     => [
            'x-api-key: '         . ANTHROPIC_API_KEY,
            'anthropic-version: 2023-06-01',
            'content-type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode([
            'model'      => ANTHROPIC_MODEL,
            'max_tokens' => 8192,
            'messages'   => [['role' => 'user', 'content' => $prompt]],
        ]),
    ]);
    $rawRes   = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr  = curl_error($ch);
    curl_close($ch);

    if (!$rawRes || $httpCode !== 200) {
        jsonOut(['success' => false, 'error' => 'AI API call failed', 'detail' => $curlErr ?: substr((string)$rawRes, 0, 300)], 502);
    }
    $apiRes = json_decode($rawRes, true);
    $aiText = $apiRes['content'][0]['text'] ?? '';
    if (!$aiText) jsonOut(['success' => false, 'error' => 'AI returned empty response'], 502);

    $aiText = trim(preg_replace(['/^```(?:json)?\s*/m', '/\s*```$/m'], '', $aiText));
    $planData = json_decode($aiText, true);

    if (!$planData || !isset($planData['weeks']) || !is_array($planData['weeks'])) {
        jsonOut(['success' => false, 'error' => 'AI returned invalid structure', 'raw' => substr($aiText, 0, 500)], 502);
    }
    foreach ($planData['weeks'] as $w) {
        foreach (($w['sessions'] ?? []) as $s) {
            if (empty($s['exercises'])) jsonOut(['success' => false, 'error' => 'AI plan: session missing exercises'], 502);
        }
    }
}

// ── Persist draft plan ───────────────────────────────────────────────────────
$planId           = bin2hex(random_bytes(16));
$planTitle        = substr(trim($planData['plan_title'] ?? (ucfirst($goal).' Plan')), 0, 255);
$planSummary      = substr(trim($planData['summary']           ?? ''), 0, 2000);
$recoveryNotes    = substr(trim($planData['recovery_notes']    ?? ''), 0, 2000);
$progressionRules = substr(trim($planData['progression_rules'] ?? ''), 0, 2000);
$startDate        = new DateTime('+1 day');
$totalSessions    = 0;
$sessionsMeta     = [];

$pdo->beginTransaction();
try {
    $pdo->prepare(
        'INSERT INTO training_plans
         (id,plan_type,owner_type,club_id,coach_user_id,title,goal,status,
          target_type,ai_provider,ai_prompt_snapshot,ai_response_snapshot,
          plan_summary,recovery_notes,progression_rules,num_weeks)
         VALUES (?,\'ai\',?,?,?,?,?,\'draft\',?,?,?,?,?,?,?,?)'
    )->execute([
        $planId, $user['role'], $coachId, $coachId, $planTitle, $goal,
        $targetType, 'anthropic',
        substr(json_encode($requestSnapshot), 0, 10000),
        $mockMode ? 'mock' : substr($aiText, 0, 20000),
        $planSummary, $recoveryNotes, $progressionRules, $numWeeks,
    ]);

    // Store intended players
    $ppStmt = $pdo->prepare('INSERT IGNORE INTO plan_players (plan_id,club_player_id,player_user_id) VALUES (?,?,?)');
    $luStmt = $pdo->prepare('SELECT linked_user_id FROM club_players WHERE id=?');
    foreach ($playerIds as $pid) {
        $luStmt->execute([$pid]);
        $lr = $luStmt->fetch();
        $ppStmt->execute([$planId, $pid, $lr ? (int)$lr['linked_user_id'] : null]);
    }

    // Sessions + exercises (draft)
    $exStmt = $pdo->prepare(
        'INSERT INTO session_exercises
         (session_id,exercise_name,category,sets,reps,
          duration_seconds,rest_seconds,instructions,
          requires_pose_detection,assessment_type,sort_order)
         VALUES (?,?,?,?,?,?,?,?,?,?,?)'
    );

    foreach ($planData['weeks'] as $weekData) {
        $weekNum  = max(1, (int)($weekData['week'] ?? 1));
        $sessions = is_array($weekData['sessions']) ? $weekData['sessions'] : [];
        $weekBase = clone $startDate;
        $weekBase->modify('+' . (($weekNum - 1) * 7) . ' days');
        $interval = $daysPerWeek > 0 ? (int)floor(7 / $daysPerWeek) : 1;

        foreach ($sessions as $si => $sessData) {
            $sessId   = bin2hex(random_bytes(16));
            $dayOff   = min(6, $si * $interval);
            $sessDate = (clone $weekBase)->modify("+{$dayOff} days");

            $obj   = in_array($sessData['objective'] ?? '', ['fitness','football','recovery','assessment','mixed'])
                ? $sessData['objective'] : 'mixed';
            $int   = in_array($sessData['intensity'] ?? '', ['low','medium','high']) ? $sessData['intensity'] : 'medium';
            $dur   = max(15, min(180, (int)($sessData['duration_minutes'] ?? $durationMin)));
            $title = substr(trim($sessData['title'] ?? 'Training Session'), 0, 255);

            $pdo->prepare(
                'INSERT INTO training_sessions
                 (id,plan_id,club_id,coach_user_id,title,session_date,duration_minutes,
                  objective,source,status,wellness_required,rpe_required,week_number,intensity)
                 VALUES (?,?,?,?,?,?,?,?,\'ai\',\'draft\',1,1,?,?)'
            )->execute([$sessId,$planId,$coachId,$coachId,$title,$sessDate->format('Y-m-d'),$dur,$obj,$weekNum,$int]);

            foreach (($sessData['exercises'] ?? []) as $i => $ex) {
                $exName = substr(trim($ex['exercise_name'] ?? ''), 0, 255);
                if (!$exName) continue;
                $exCat = in_array($ex['category'] ?? '', ['football','fitness','mobility','recovery','assessment']) ? $ex['category'] : 'fitness';
                $exStmt->execute([
                    $sessId, $exName, $exCat,
                    isset($ex['sets'])             ? (int)$ex['sets']             : null,
                    isset($ex['reps'])             ? (int)$ex['reps']             : null,
                    isset($ex['duration_seconds']) ? (int)$ex['duration_seconds'] : null,
                    isset($ex['rest_seconds'])     ? (int)$ex['rest_seconds']     : null,
                    isset($ex['instructions'])     ? substr(trim($ex['instructions']), 0, 1000) : null,
                    empty($ex['requires_pose_detection']) ? 0 : 1,
                    isset($ex['assessment_type'])  ? (string)$ex['assessment_type'] : null,
                    (int)$i,
                ]);
            }

            $totalSessions++;
            $sessionsMeta[] = [
                'session_id'       => $sessId,
                'title'            => $title,
                'session_date'     => $sessDate->format('Y-m-d'),
                'week'             => $weekNum,
                'duration_minutes' => $dur,
                'intensity'        => $int,
                'exercise_count'   => count($sessData['exercises'] ?? []),
            ];
        }
    }
    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    jsonOut(['success' => false, 'error' => 'Failed to save plan: ' . $e->getMessage()], 500);
}

jsonOut([
    'success'           => true,
    'plan_id'           => $planId,
    'plan_title'        => $planTitle,
    'summary'           => $planSummary,
    'recovery_notes'    => $recoveryNotes,
    'progression_rules' => $progressionRules,
    'num_weeks'         => $numWeeks,
    'total_sessions'    => $totalSessions,
    'sessions'          => $sessionsMeta,
    'plan'              => $planData,
    'mock'              => $mockMode,
]);

// ── Mock plan builder ─────────────────────────────────────────────────────────
function buildMockPlan(int $weeks, int $days, int $dur, string $goal): array {
    $sessions = [];
    for ($d = 0; $d < $days; $d++) {
        $sessions[] = [
            'title'            => 'Day ' . ($d + 1) . ' — ' . ucfirst($goal),
            'objective'        => in_array($goal, ['recovery','injury_prevention']) ? 'recovery' : 'fitness',
            'duration_minutes' => $dur,
            'intensity'        => 'medium',
            'exercises'        => [
                ['exercise_name' => 'Dynamic Warm-Up', 'category' => 'fitness', 'sets' => null, 'reps' => null, 'duration_seconds' => 300, 'rest_seconds' => 0, 'instructions' => 'Light jog, leg swings, arm circles.', 'requires_pose_detection' => false, 'assessment_type' => null],
                ['exercise_name' => 'Cone Dribbling Drill', 'category' => 'football', 'sets' => 3, 'reps' => null, 'duration_seconds' => 60, 'rest_seconds' => 30, 'instructions' => 'Dribble through 6 cones at medium pace.', 'requires_pose_detection' => false, 'assessment_type' => null],
                ['exercise_name' => 'Bodyweight Squat', 'category' => 'fitness', 'sets' => 3, 'reps' => 15, 'duration_seconds' => null, 'rest_seconds' => 45, 'instructions' => 'Feet shoulder-width, controlled descent to 90°.', 'requires_pose_detection' => false, 'assessment_type' => null],
                ['exercise_name' => 'Lateral Band Walk', 'category' => 'fitness', 'sets' => 3, 'reps' => 12, 'duration_seconds' => null, 'rest_seconds' => 30, 'instructions' => 'Step laterally against band resistance.', 'requires_pose_detection' => false, 'assessment_type' => null],
                ['exercise_name' => 'Cool-Down Stretch', 'category' => 'mobility', 'sets' => null, 'reps' => null, 'duration_seconds' => 300, 'rest_seconds' => 0, 'instructions' => 'Static stretching — quads, hamstrings, calves.', 'requires_pose_detection' => false, 'assessment_type' => null],
            ],
        ];
    }
    $weekData = [];
    for ($w = 1; $w <= $weeks; $w++) {
        $weekData[] = ['week' => $w, 'sessions' => $sessions];
    }
    return [
        'plan_title'        => ucfirst(str_replace('_', ' ', $goal)) . ' Training Plan (Mock)',
        'summary'           => "This {$weeks}-week plan targets {$goal} with {$days} sessions/week. Loads progress 10% each week. Adapted to each player's profile and recent wellness data.",
        'weeks'             => $weekData,
        'recovery_notes'    => 'Rest 48 h between high-intensity sessions. Prioritise sleep ≥ 8 h and hydration.',
        'progression_rules' => 'Increase intensity or volume by 10 % each week. Deload if hooper score drops below 8.',
    ];
}
