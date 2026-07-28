<?php
/**
 * POST /api/mobile/ai/generate-plan.php
 * Generates a training plan using Anthropic Claude API.
 * Stores the plan in MySQL and returns it.
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once '../db.php';

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
        'SELECT u.id, u.name FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $user = $stmt->fetch();
    if (!$user) jsonOut(['error' => 'Invalid token'], 401);
    return $user;
}

// ── Ensure ai_plans table ────────────────────────────────────────────────────
ensureColumn($pdo, 'users', 'id', 'INT AUTO_INCREMENT PRIMARY KEY'); // trigger ensureSchema if needed
$pdo->exec("CREATE TABLE IF NOT EXISTS ai_plans (
    id VARCHAR(64) PRIMARY KEY,
    user_id INT NOT NULL,
    plan_json LONGTEXT NOT NULL,
    hooper_index INT NULL,
    pre_rpe INT NULL,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ai_plans_user (user_id),
    CONSTRAINT fk_ai_plans_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

$user = getAuthUser($pdo);

// ── GET: return latest plan ──────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $pdo->prepare(
        'SELECT * FROM ai_plans WHERE user_id = ? ORDER BY generated_at DESC LIMIT 1'
    );
    $stmt->execute([$user['id']]);
    $row = $stmt->fetch();
    if (!$row) {
        jsonOut(['plan' => null]);
    }
    jsonOut([
        'plan'         => json_decode($row['plan_json'], true),
        'generated_at' => $row['generated_at'],
        'hooper_index' => $row['hooper_index'],
        'pre_rpe'      => $row['pre_rpe'],
    ]);
}

// ── POST: generate plan ──────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonOut(['error' => 'Method not allowed'], 405);
}

$body = json_decode(file_get_contents('php://input'), true) ?? [];

// Fetch user profile from DB
$stmt = $pdo->prepare('SELECT * FROM user_profiles WHERE user_id = ?');
$stmt->execute([$user['id']]);
$profile = $stmt->fetch() ?? [];

// Fetch latest body metrics
$stmt = $pdo->prepare(
    'SELECT * FROM player_body_metrics WHERE user_id = ? ORDER BY measured_at DESC LIMIT 1'
);
$stmt->execute([$user['id']]);
$metrics = $stmt->fetch() ?? [];

// Fetch latest Hooper
$stmt = $pdo->prepare(
    'SELECT * FROM player_hooper_index WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1'
);
$stmt->execute([$user['id']]);
$hooper = $stmt->fetch() ?? [];

// Fetch latest RPE
$stmt = $pdo->prepare(
    'SELECT * FROM player_rpe WHERE user_id = ? ORDER BY submitted_at DESC LIMIT 1'
);
$stmt->execute([$user['id']]);
$rpe = $stmt->fetch() ?? [];

// Fetch latest assessment score
$stmt = $pdo->prepare(
    'SELECT overall_score, type FROM assessments WHERE user_id = ? ORDER BY created_at DESC LIMIT 1'
);
$stmt->execute([$user['id']]);
$assessment = $stmt->fetch() ?? [];

// Build payload for AI
$weight    = (float)($metrics['weight_kg']         ?? $profile['weight'] ?? 0);
$height    = (float)($metrics['height_cm']         ?? $profile['height'] ?? 0);
$fat       = (float)($metrics['body_fat_percent']  ?? 0);
$lbm       = $weight > 0 && $fat > 0
    ? round($weight * (1 - $fat / 100), 1)
    : null;

$hooperIndex = isset($hooper['hooper_score']) ? (int)$hooper['hooper_score'] : null;
$preRpe      = isset($rpe['rpe_score'])       ? (float)$rpe['rpe_score']     : null;

// ── Build Claude prompt ──────────────────────────────────────────────────────
$prompt = buildPrompt([
    'name'              => $user['name'],
    'age'               => (int)($profile['age']            ?? 22),
    'gender'            => $profile['gender']               ?? 'male',
    'height_cm'         => $height,
    'weight_kg'         => $weight,
    'fat_percentage'    => $fat,
    'lean_body_mass'    => $lbm,
    'fitness_level'     => $profile['fitness_level']        ?? 'intermediate',
    'football_skill'    => $profile['skill_level']          ?? 'amateur',
    'goal'              => $profile['goal']                 ?? 'improve_skills',
    'position'          => $profile['position']             ?? '—',
    'available_days'    => (int)($profile['days_per_week']  ?? 4),
    'preferred_min'     => (int)($profile['preferred_duration'] ?? 60),
    'injury'            => $profile['injury_limitations']   ?? 'none',
    'hooper_index'      => $hooperIndex,
    'pre_rpe'           => $preRpe,
    'ai_score'          => isset($assessment['overall_score']) ? (int)$assessment['overall_score'] : null,
    'last_test'         => $assessment['type'] ?? null,
]);

// ── Call Anthropic API ────────────────────────────────────────────────────────
$apiKey = getenv('ANTHROPIC_API_KEY') ?: '';
if (!$apiKey) {
    // Return a rule-based fallback plan if no API key configured
    jsonOut([
        'plan'    => buildFallbackPlan($hooperIndex, $preRpe, $profile),
        'source'  => 'fallback',
        'message' => 'AI key not configured — using rule-based plan.',
    ]);
}

$ch = curl_init('https://api.anthropic.com/v1/messages');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_HTTPHEADER     => [
        'x-api-key: '       . $apiKey,
        'anthropic-version: 2023-06-01',
        'content-type: application/json',
    ],
    CURLOPT_POSTFIELDS => json_encode([
        'model'      => 'claude-haiku-4-5-20251001',
        'max_tokens' => 1024,
        'messages'   => [
            ['role' => 'user', 'content' => $prompt],
        ],
    ]),
    CURLOPT_TIMEOUT => 30,
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($httpCode !== 200 || !$response) {
    jsonOut([
        'plan'    => buildFallbackPlan($hooperIndex, $preRpe, $profile),
        'source'  => 'fallback',
        'message' => 'AI request failed — using rule-based plan.',
    ]);
}

$aiResponse = json_decode($response, true);
$planText   = $aiResponse['content'][0]['text'] ?? '';

// Try to parse JSON from response
$planData = null;
if (preg_match('/\{.*\}/s', $planText, $matches)) {
    $planData = json_decode($matches[0], true);
}
if (!$planData) {
    $planData = ['summary' => $planText, 'source' => 'ai_text'];
}

// Save to DB
$planId = 'plan-' . $user['id'] . '-' . time();
$stmt = $pdo->prepare(
    'INSERT INTO ai_plans (id, user_id, plan_json, hooper_index, pre_rpe)
     VALUES (?, ?, ?, ?, ?)'
);
$stmt->execute([
    $planId, $user['id'], json_encode($planData, JSON_UNESCAPED_UNICODE),
    $hooperIndex, $preRpe,
]);

jsonOut([
    'plan'         => $planData,
    'plan_id'      => $planId,
    'source'       => 'ai',
    'generated_at' => date('Y-m-d H:i:s'),
]);

// ── Helpers ──────────────────────────────────────────────────────────────────

function buildPrompt(array $d): string {
    $hooperInfo = $d['hooper_index'] !== null
        ? "Hooper Index today: {$d['hooper_index']} (fatigue indicator, scale 4-28)"
        : "No Hooper data today";
    $rpeInfo = $d['pre_rpe'] !== null
        ? "Pre-session RPE: {$d['pre_rpe']}/10"
        : "No RPE data";
    $scoreInfo = $d['ai_score'] !== null
        ? "Latest movement assessment score: {$d['ai_score']}/100 ({$d['last_test']})"
        : "No movement assessment yet";
    $fatInfo = $d['fat_percentage'] > 0
        ? "Body fat: {$d['fat_percentage']}%, LBM: {$d['lean_body_mass']} kg"
        : "No body composition data";

    return <<<PROMPT
You are a professional football physical coach. Create a personalized weekly training plan.

PLAYER PROFILE:
- Name: {$d['name']}, Age: {$d['age']}, Gender: {$d['gender']}
- Height: {$d['height_cm']} cm, Weight: {$d['weight_kg']} kg, {$fatInfo}
- Position: {$d['position']}
- Fitness level: {$d['fitness_level']}, Football skill: {$d['football_skill']}
- Goal: {$d['goal']}
- Available: {$d['available_days']} days/week, {$d['preferred_min']} min/session
- Injury limitations: {$d['injury']}

READINESS TODAY:
- {$hooperInfo}
- {$rpeInfo}
- {$scoreInfo}

Generate a structured weekly plan as JSON with this format:
{
  "week_summary": "brief summary in Arabic",
  "readiness_note": "note about today's readiness in Arabic",
  "intensity_adjustment": "normal|reduced|recovery",
  "days": [
    {
      "day": 1,
      "title": "session title in Arabic",
      "type": "fitness|technical|strength|recovery",
      "duration_min": 60,
      "intensity": "low|medium|high",
      "exercises": ["exercise 1", "exercise 2"],
      "notes": "optional note in Arabic"
    }
  ]
}

Rules:
- If Hooper Index >= 17: recommend recovery/light session, set intensity_adjustment to "recovery"
- If Hooper Index 11-16: reduce intensity 20%, set intensity_adjustment to "reduced"
- If Hooper Index <= 10: normal session
- Keep exercises practical for football players
- All text in Arabic
PROMPT;
}

function buildFallbackPlan(?int $hooper, ?int $rpe, array $profile): array {
    $days  = (int)($profile['days_per_week'] ?? 4);
    $goal  = $profile['goal'] ?? 'improve_skills';
    $adj   = 'normal';
    $note  = 'جاهزية ممتازة. تابع الخطة كما هو مخطط.';

    if ($hooper !== null) {
        if ($hooper >= 17) {
            $adj  = 'recovery';
            $note = 'مؤشر Hooper مرتفع. يُنصح بجلسة استشفاء خفيفة اليوم.';
        } elseif ($hooper >= 11) {
            $adj  = 'reduced';
            $note = 'تعب متوسط. قلّل الشدة بنسبة 20% هذه الجلسة.';
        }
    }

    $templates = [
        ['day' => 1, 'title' => 'تدريب القوة والسرعة', 'type' => 'strength',
         'duration_min' => 60, 'intensity' => $adj === 'recovery' ? 'low' : 'high',
         'exercises'    => ['إحماء ديناميكي 10 دقيقة', 'سباق سرعة 4×20م', 'قفز عمق 3×8', 'تمارين المقاومة'],
         'notes'        => ''],
        ['day' => 2, 'title' => 'تدريب بدني بالكرة', 'type' => 'technical',
         'duration_min' => 60, 'intensity' => 'medium',
         'exercises'    => ['تمرير 3-2-1', 'التنطيط سلالم الرشاقة', 'ضربات الكرة من زوايا', 'لعبة مصغرة'],
         'notes'        => ''],
        ['day' => 3, 'title' => 'استشفاء نشط', 'type' => 'recovery',
         'duration_min' => 30, 'intensity' => 'low',
         'exercises'    => ['مشي خفيف 15 دقيقة', 'تمديد عضلي', 'تمارين التنفس'],
         'notes'        => 'يوم راحة نشطة'],
        ['day' => 4, 'title' => 'رشاقة وتوازن', 'type' => 'fitness',
         'duration_min' => 50, 'intensity' => 'medium',
         'exercises'    => ['حواجز الرشاقة', 'توازن أحادي القدم', 'تمارين الركبة', 'HIIT قصير'],
         'notes'        => ''],
    ];

    return [
        'week_summary'        => 'خطة تدريب أسبوعية مبنية على مستواك الحالي',
        'readiness_note'      => $note,
        'intensity_adjustment'=> $adj,
        'days'                => array_slice($templates, 0, min($days, 4)),
    ];
}
