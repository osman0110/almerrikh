<?php
require_once dirname(__DIR__, 2) . '/db.php';

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
        'SELECT u.id, u.role, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $user;
}

$user = getAuthUser($pdo);
if ($user['role'] !== 'player') jsonOut(['error' => 'Forbidden — players only'], 403);
if (!ANTHROPIC_API_KEY) jsonOut(['error' => 'AI service not configured. Set ANTHROPIC_API_KEY.'], 503);

$body = json_decode(file_get_contents('php://input'), true) ?? [];

// ── Validate ──────────────────────────────────────────────────────────────────
$goal = trim((string)($body['goal'] ?? ''));
if (!$goal) jsonOut(['error' => 'goal is required'], 400);

$availableDays = (int)($body['available_days'] ?? 0);
if ($availableDays < 1 || $availableDays > 7)
    jsonOut(['error' => 'available_days must be 1–7'], 400);

$preferredDuration = (int)($body['preferred_duration'] ?? 60);
if ($preferredDuration < 15 || $preferredDuration > 180)
    jsonOut(['error' => 'preferred_duration must be 15–180'], 400);

$numWeeks = max(2, min(8, (int)($body['num_weeks'] ?? 4)));
$equipment = is_array($body['equipment'] ?? null) ? $body['equipment'] : ['bodyweight'];
$injuryLimitations = trim((string)($body['injury_limitations'] ?? '')) ?: 'none';
$difficultyPref    = trim((string)($body['difficulty_preference'] ?? 'intermediate'));

$userId         = (int)$user['id'];
$linkedPlayerId = $user['linked_player_id'] ?? null;

// ── Fetch player data ─────────────────────────────────────────────────────────
$profileRow = $pdo->prepare(
    'SELECT age, position, fitness_level, skill_level, injury_limitations
     FROM user_profiles WHERE user_id = ?'
);
$profileRow->execute([$userId]);
$profile = $profileRow->fetch() ?: [];

$metricsRow = $pdo->prepare(
    'SELECT weight_kg, height_cm, body_fat_percent
     FROM player_body_metrics WHERE user_id = ? ORDER BY measured_at DESC LIMIT 1'
);
$metricsRow->execute([$userId]);
$metrics = $metricsRow->fetch() ?: [];

$hoooperRow = $pdo->prepare(
    'SELECT hooper_score FROM player_hooper_index WHERE user_id = ? ORDER BY created_at DESC LIMIT 1'
);
$hoooperRow->execute([$userId]);
$hoooper = $hoooperRow->fetch() ?: [];

$rpeRow = $pdo->prepare(
    "SELECT rpe_score FROM player_rpe WHERE user_id = ? AND rpe_type='post' ORDER BY created_at DESC LIMIT 1"
);
$rpeRow->execute([$userId]);
$rpe = $rpeRow->fetch() ?: [];

$assessRow = $pdo->prepare(
    'SELECT overall_score FROM assessments WHERE user_id = ? ORDER BY created_at DESC LIMIT 1'
);
$assessRow->execute([$userId]);
$assess = $assessRow->fetch() ?: [];

// ── Build payload ─────────────────────────────────────────────────────────────
$playerPayload = [
    'goal'                     => $goal,
    'available_days_per_week'  => $availableDays,
    'preferred_duration_min'   => $preferredDuration,
    'num_weeks'                => $numWeeks,
    'equipment'                => $equipment,
    'difficulty_preference'    => $difficultyPref,
    'injury_limitations'       => $profile['injury_limitations'] ?? $injuryLimitations,
    'profile' => [
        'age'                  => isset($profile['age']) ? (int)$profile['age'] : null,
        'position'             => $profile['position'] ?? null,
        'height_cm'            => isset($metrics['height_cm']) ? (float)$metrics['height_cm'] : null,
        'weight_kg'            => isset($metrics['weight_kg']) ? (float)$metrics['weight_kg'] : null,
        'fat_percentage'       => isset($metrics['body_fat_percent']) ? (float)$metrics['body_fat_percent'] : null,
        'fitness_level'        => $profile['fitness_level'] ?? $difficultyPref,
        'football_skill_level' => $profile['skill_level'] ?? 'intermediate',
    ],
    'monitoring' => [
        'latest_hooper_index'    => isset($hoooper['hooper_score'])  ? (int)$hoooper['hooper_score']  : null,
        'latest_post_rpe'        => isset($rpe['rpe_score'])         ? (float)$rpe['rpe_score']       : null,
        'latest_assessment_score'=> isset($assess['overall_score'])  ? (int)$assess['overall_score']  : null,
    ],
];

// ── Claude prompt ─────────────────────────────────────────────────────────────
$schemaExample = json_encode([
    'plan_title' => 'string',
    'weeks' => [[
        'week' => 1,
        'sessions' => [[
            'title' => 'string', 'objective' => 'fitness|football|recovery|mixed',
            'day_offset' => 0, 'duration_minutes' => $preferredDuration,
            'intensity' => 'low|medium|high',
            'exercises' => [[
                'exercise_name' => 'string',
                'category' => 'football|fitness|mobility|recovery',
                'sets' => null, 'reps' => null,
                'duration_seconds' => null, 'rest_seconds' => null,
                'intensity' => 'low|medium|high',
                'instructions' => 'string',
                'requires_pose_detection' => false,
            ]],
        ]],
    ]],
    'recovery_notes' => 'string',
    'progression_rules' => 'string',
]);

$prompt  = "You are a professional football fitness and conditioning coach AI.\n\n";
$prompt .= "Create a personalized {$numWeeks}-week football training plan.\n\n";
$prompt .= "Player data:\n" . json_encode($playerPayload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n\n";
$prompt .= "Rules:\n";
$prompt .= "- Each week must have exactly {$availableDays} sessions.\n";
$prompt .= "- Sessions duration ≈ {$preferredDuration} minutes each.\n";
$prompt .= "- day_offset: 0 = first day of the week, distribute evenly across 7 days.\n";
$prompt .= "- Include warm-up and cool-down in every session (5–10 min each).\n";
$prompt .= "- If fitness_level is beginner: lighter loads, more rest, simpler exercises.\n";
$prompt .= "- If hooper_index > 14: add a recovery session in week 1.\n";
$prompt .= "- Week over week: increase intensity or complexity by ~10–15%.\n";
$prompt .= "- Do NOT use requires_pose_detection: true unless category is 'assessment'.\n";
$prompt .= "- recovery_notes: 1–2 sentences on rest and nutrition.\n";
$prompt .= "- progression_rules: 1–2 sentences on how to advance.\n\n";
$prompt .= "Return ONLY valid JSON matching this schema (no markdown, no text before/after):\n";
$prompt .= $schemaExample;

// ── Call Anthropic API ────────────────────────────────────────────────────────
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
        'max_tokens' => 4096,
        'messages'   => [['role' => 'user', 'content' => $prompt]],
    ]),
]);
$rawRes   = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr  = curl_error($ch);
curl_close($ch);

if (!$rawRes || $httpCode !== 200) {
    jsonOut(['error' => 'AI API call failed', 'detail' => $curlErr ?: substr((string)$rawRes, 0, 300)], 502);
}

$apiRes = json_decode($rawRes, true);
$aiText = $apiRes['content'][0]['text'] ?? '';
if (!$aiText) jsonOut(['error' => 'AI returned empty response'], 502);

// Strip markdown fences if present
$aiText = preg_replace('/^```(?:json)?\s*/m', '', $aiText);
$aiText = preg_replace('/\s*```$/m', '', $aiText);
$aiText = trim($aiText);

$planData = json_decode($aiText, true);
if (!$planData || !isset($planData['weeks']) || !is_array($planData['weeks'])) {
    jsonOut(['error' => 'AI returned invalid structure', 'raw' => substr($aiText, 0, 500)], 502);
}

// ── Save to DB ────────────────────────────────────────────────────────────────
$planTitle        = substr(trim($planData['plan_title'] ?? ($goal . ' Plan')), 0, 255);
$recoveryNotes    = substr(trim($planData['recovery_notes'] ?? ''), 0, 2000);
$progressionRules = substr(trim($planData['progression_rules'] ?? ''), 0, 2000);
$planId           = bin2hex(random_bytes(16));
$startDate        = new DateTime('+1 day');
$totalSessions    = 0;
$sessionsMeta     = [];

$pdo->beginTransaction();
try {
    $pdo->prepare(
        'INSERT INTO training_plans
         (id, plan_type, owner_type, club_id, coach_user_id, player_user_id, linked_player_id,
          title, goal, status, ai_provider, ai_prompt_snapshot, ai_response_snapshot,
          recovery_notes, progression_rules, num_weeks)
         VALUES (?,\'ai\',\'player\',NULL,NULL,?,?,?,?,\'published\',?,?,?,?,?,?)'
    )->execute([
        $planId, $userId, $linkedPlayerId,
        $planTitle, $goal, 'anthropic',
        substr(json_encode($playerPayload), 0, 10000),
        substr($aiText, 0, 20000),
        $recoveryNotes, $progressionRules, $numWeeks,
    ]);

    $exStmt = $pdo->prepare(
        'INSERT INTO session_exercises
         (session_id, exercise_name, category, sets, reps,
          duration_seconds, rest_seconds, intensity, instructions,
          requires_pose_detection, sort_order)
         VALUES (?,?,?,?,?,?,?,?,?,?,?)'
    );

    foreach ($planData['weeks'] as $weekData) {
        $weekNum  = max(1, (int)($weekData['week'] ?? 1));
        $sessions = is_array($weekData['sessions']) ? $weekData['sessions'] : [];
        $weekBase = clone $startDate;
        $weekBase->modify('+' . (($weekNum - 1) * 7) . ' days');

        foreach ($sessions as $sessData) {
            $sessId    = bin2hex(random_bytes(16));
            $dayOff    = max(0, min(6, (int)($sessData['day_offset'] ?? 0)));
            $sessDate  = clone $weekBase;
            $sessDate->modify('+' . $dayOff . ' days');

            $obj  = in_array($sessData['objective'] ?? '', ['fitness','football','recovery','assessment','mixed'])
                ? $sessData['objective'] : 'mixed';
            $int  = in_array($sessData['intensity'] ?? '', ['low','medium','high'])
                ? $sessData['intensity'] : 'medium';
            $dur  = max(15, min(180, (int)($sessData['duration_minutes'] ?? $preferredDuration)));
            $title= substr(trim($sessData['title'] ?? 'Training Session'), 0, 255);

            $pdo->prepare(
                'INSERT INTO training_sessions
                 (id, plan_id, coach_user_id, title, session_date, duration_minutes,
                  objective, source, status, wellness_required, rpe_required,
                  week_number, intensity)
                 VALUES (?,?,NULL,?,?,?,?,\'ai\',\'assigned\',1,1,?,?)'
            )->execute([$sessId, $planId, $title, $sessDate->format('Y-m-d'),
                        $dur, $obj, $weekNum, $int]);

            $pdo->prepare(
                'INSERT INTO session_players
                 (session_id, club_id, player_user_id, linked_player_id, status)
                 VALUES (?,NULL,?,?,\'assigned\')'
            )->execute([$sessId, $userId, $linkedPlayerId]);

            $exercises = is_array($sessData['exercises']) ? $sessData['exercises'] : [];
            foreach ($exercises as $i => $ex) {
                $exName = substr(trim($ex['exercise_name'] ?? ''), 0, 255);
                if (!$exName) continue;
                $exCat = in_array($ex['category'] ?? '', ['football','fitness','mobility','recovery','assessment'])
                    ? $ex['category'] : 'fitness';
                $exInt = in_array($ex['intensity'] ?? '', ['low','medium','high']) ? $ex['intensity'] : 'medium';
                $exStmt->execute([
                    $sessId, $exName, $exCat,
                    isset($ex['sets'])             ? (int)$ex['sets']             : null,
                    isset($ex['reps'])             ? (int)$ex['reps']             : null,
                    isset($ex['duration_seconds']) ? (int)$ex['duration_seconds'] : null,
                    isset($ex['rest_seconds'])     ? (int)$ex['rest_seconds']     : null,
                    $exInt,
                    isset($ex['instructions']) ? substr(trim($ex['instructions']), 0, 1000) : null,
                    empty($ex['requires_pose_detection']) ? 0 : 1,
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
                'exercise_count'   => count($exercises),
            ];
        }
    }

    $pdo->commit();
} catch (Exception $e) {
    $pdo->rollBack();
    jsonOut(['error' => 'Failed to save plan: ' . $e->getMessage()], 500);
}

jsonOut([
    'success'           => true,
    'plan_id'           => $planId,
    'plan_title'        => $planTitle,
    'total_sessions'    => $totalSessions,
    'num_weeks'         => $numWeeks,
    'recovery_notes'    => $recoveryNotes,
    'progression_rules' => $progressionRules,
    'sessions'          => $sessionsMeta,
]);
