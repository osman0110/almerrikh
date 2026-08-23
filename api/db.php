<?php
// ── Database credentials ──────────────────────────────────────────────────────
// Priority: db_credentials.php > environment variables > localhost dev fallback
$_credFile = __DIR__ . '/db_credentials.php';
if (file_exists($_credFile)) require_once $_credFile;

$_requestHost = strtolower((string)($_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? ''));
$_requestHost = preg_replace('/:\d+$/', '', $_requestHost);
$_isProduction = !in_array(
    $_requestHost,
    ['localhost', '127.0.0.1', ''],
    true
);

$host     = getenv('DB_HOST') ?: (defined('_DB_HOST') ? _DB_HOST : 'localhost');
$dbname   = getenv('DB_NAME') ?: (defined('_DB_NAME') ? _DB_NAME : 'smart_sport');
$username = getenv('DB_USER') ?: (defined('_DB_USER') ? _DB_USER : ($_isProduction ? null : 'root'));
$password = getenv('DB_PASS') ?: (defined('_DB_PASS') ? _DB_PASS : ($_isProduction ? null : ''));

if ($_isProduction && (!$username || !$password)) {
    header('Content-Type: application/json');
    http_response_code(503);
    echo json_encode(['error' => 'DB credentials missing. Upload db_credentials.php to api/mobile/']);
    exit;
}

// ── AI config — set ANTHROPIC_API_KEY in environment or api/ai/config.php ────
if (file_exists(__DIR__ . '/ai/config.php')) require_once __DIR__ . '/ai/config.php';
if (!defined('ANTHROPIC_API_KEY')) define('ANTHROPIC_API_KEY', getenv('ANTHROPIC_API_KEY') ?: '');
if (!defined('ANTHROPIC_MODEL'))   define('ANTHROPIC_MODEL',   'claude-sonnet-4-6');

function jsonError(string $message, int $code = 500): void {
    http_response_code($code);
    echo json_encode(['error' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

function createPdo(string $dsn, string $username, string $password): PDO {
    $connection = new PDO($dsn, $username, $password, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
        PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci",
    ]);
    // Store/read DB timestamps in UTC. Sports-period calculations convert
    // explicitly through FitnessConfig::TIMEZONE (Africa/Kigali).
    $connection->exec("SET time_zone = '+00:00'");
    return $connection;
}

function ensureSchema(PDO $pdo): void {
    // Disable FK checks so tables can be created in any order on any MySQL config
    $pdo->exec("SET FOREIGN_KEY_CHECKS = 0");

    $pdo->exec("CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(255) NOT NULL UNIQUE,
        phone VARCHAR(32) NULL,
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY users_phone_unique (phone)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    ensureColumn($pdo, 'users', 'phone', 'VARCHAR(32) NULL AFTER email');
    ensureIndex($pdo, 'users', 'users_phone_unique', 'CREATE UNIQUE INDEX users_phone_unique ON users (phone)');

    // ── users extended fields (users table is created first, so safe here) ──────
    // name may be missing on servers created before it was in the initial schema.
    ensureColumn($pdo, 'users', 'name',             "VARCHAR(100) NOT NULL DEFAULT ''");
    ensureColumn($pdo, 'users', 'role',             "VARCHAR(20) DEFAULT 'club'");
    ensureColumn($pdo, 'users', 'account_type',     "VARCHAR(50) DEFAULT 'club'");
    ensureColumn($pdo, 'users', 'player_type',      'VARCHAR(20) NULL');
    ensureColumn($pdo, 'users', 'club_user_id',     'INT         NULL');
    ensureColumn($pdo, 'users', 'linked_player_id', 'VARCHAR(64) NULL');
    ensureColumn($pdo, 'users', 'avatar_url',       'VARCHAR(500) NULL');
    ensureColumn($pdo, 'users', 'trial_started_at', 'DATETIME NULL');
    ensureColumn($pdo, 'users', 'trial_ends_at',    'DATETIME NULL');
    // Preferred app language ('ar'|'en'|'fr') — synced from the Flutter app's
    // local language setting so server-generated notifications/push text can
    // be translated per-recipient instead of always shipping in one language.
    ensureColumn($pdo, 'users', 'language',         "VARCHAR(5) NOT NULL DEFAULT 'ar'");

    // ── Account lifecycle columns — shared with the web admin panel's users
    //    table shape (installed via install_unified.sql there); ensured here
    //    too so a split "Flutter app DB" (legacy mode) still has them, since
    //    api/auth.php reads/writes all three on every register/login.
    ensureColumn($pdo, 'users', 'is_active',           'TINYINT(1) NOT NULL DEFAULT 1');
    ensureColumn($pdo, 'users', 'status',              "VARCHAR(20) NOT NULL DEFAULT 'active'");
    ensureColumn($pdo, 'users', 'subscription_status', "VARCHAR(20) NOT NULL DEFAULT 'trial'");

    // ── Soft-delete: admin "Delete" must make the account actually disappear
    // from the admin list, not just deactivate it under a mangled email.
    ensureColumn($pdo, 'users', 'deleted_at', 'DATETIME NULL');

    // ── Club invites ───────────────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS club_invites (
        code            VARCHAR(16)  PRIMARY KEY,
        club_user_id    INT          NOT NULL,
        team_name       VARCHAR(100) NULL,
        player_name     VARCHAR(255) NULL,
        note            TEXT         NULL,
        expires_at      TIMESTAMP    NULL,
        used_at         TIMESTAMP    NULL,
        used_by_user_id INT          NULL,
        created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── user_profiles extended fields ────────────────────────────────────────
    ensureColumn($pdo, 'user_profiles', 'height',              'DECIMAL(5,1) NULL');
    ensureColumn($pdo, 'user_profiles', 'weight',              'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'user_profiles', 'gender',              'VARCHAR(10)  NULL');
    ensureColumn($pdo, 'user_profiles', 'fitness_level',       'VARCHAR(20)  NULL');
    ensureColumn($pdo, 'user_profiles', 'skill_level',         'VARCHAR(20)  NULL');
    ensureColumn($pdo, 'user_profiles', 'goal',                'VARCHAR(50)  NULL');
    ensureColumn($pdo, 'user_profiles', 'days_per_week',       'TINYINT      NULL');
    ensureColumn($pdo, 'user_profiles', 'preferred_duration',  'SMALLINT     NULL');
    ensureColumn($pdo, 'user_profiles', 'injury_limitations',  'TEXT         NULL');
    ensureColumn($pdo, 'user_profiles', 'training_path',       'VARCHAR(30)  NULL');

    // ── assessments wellness + session fields ─────────────────────────────────
    ensureColumn($pdo, 'assessments', 'session_id',       'VARCHAR(64) NULL');
    ensureColumn($pdo, 'assessments', 'pre_hooper_index', 'TINYINT NULL');
    ensureColumn($pdo, 'assessments', 'pre_rpe',          'TINYINT NULL');
    ensureColumn($pdo, 'assessments', 'post_rpe',         'TINYINT NULL');
    ensureColumn($pdo, 'assessments', 'pain_reported',    'TINYINT DEFAULT 0');
    ensureColumn($pdo, 'assessments', 'difficulty',       'VARCHAR(20) NULL');
    ensureColumn($pdo, 'assessments', 'mood_after',       'TINYINT NULL');
    ensureIndex($pdo, 'assessments', 'idx_assessments_session',
        'CREATE INDEX idx_assessments_session ON assessments (session_id)');

    // ── Attempts: group multiple captures of the same test together ──────────
    ensureColumn($pdo, 'assessments', 'attempt_group_id', 'VARCHAR(64) NULL');
    ensureColumn($pdo, 'assessments', 'attempt_number',   'TINYINT NOT NULL DEFAULT 1');
    ensureColumn($pdo, 'assessments', 'is_valid',         'TINYINT NOT NULL DEFAULT 1');
    ensureColumn($pdo, 'assessments', 'invalid_reason',   'VARCHAR(50) NULL');
    ensureIndex($pdo, 'assessments', 'idx_assessments_attempt_group',
        'CREATE INDEX idx_assessments_attempt_group ON assessments (attempt_group_id)');

    // ── Coach manual override of a test score, with a logged reason ──────────
    ensureColumn($pdo, 'assessments', 'override_score',      'INT NULL');
    ensureColumn($pdo, 'assessments', 'override_reason',     'VARCHAR(255) NULL');
    ensureColumn($pdo, 'assessments', 'overridden_by_user_id', 'INT NULL');
    ensureColumn($pdo, 'assessments', 'overridden_at',       'TIMESTAMP NULL');

    // ── Coach review/certification workflow: AI result starts pending_review,
    // coach edits (override above) then approves; the on-device capture video
    // is only kept locally until this flips to 'approved'. ────────────────────
    ensureColumn($pdo, 'assessments', 'status',              "VARCHAR(20) NOT NULL DEFAULT 'pending_review'");
    ensureColumn($pdo, 'assessments', 'approved_by_user_id', 'INT NULL');
    ensureColumn($pdo, 'assessments', 'approved_at',         'TIMESTAMP NULL');

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_tokens (
        token      VARCHAR(64) PRIMARY KEY,
        user_id    INT         NOT NULL,
        expires_at TIMESTAMP   NULL,
        created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user_tokens_user_id  (user_id),
        INDEX idx_user_tokens_expires  (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Add expires_at to existing deployments that predate this column
    ensureColumn($pdo, 'user_tokens', 'expires_at', 'TIMESTAMP NULL AFTER user_id');
    ensureIndex($pdo, 'user_tokens', 'idx_user_tokens_expires',
        'CREATE INDEX idx_user_tokens_expires ON user_tokens (expires_at)');

    // ── Auth rate-limiting table ──────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS auth_rate_limit (
        id              INT AUTO_INCREMENT PRIMARY KEY,
        ip              VARCHAR(45)  NOT NULL,
        identifier_hash CHAR(64)     NOT NULL,
        failed_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_rl_ip       (ip, failed_at),
        INDEX idx_rl_id_hash  (identifier_hash, failed_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS user_profiles (
        user_id INT PRIMARY KEY,
        player_name VARCHAR(100),
        age INT,
        position VARCHAR(20),
        foot VARCHAR(20),
        weaknesses TEXT,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS assessments (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        player_id VARCHAR(255) NOT NULL,
        player_name VARCHAR(255) DEFAULT '',
        type VARCHAR(50) NOT NULL,
        overall_score INT NOT NULL DEFAULT 0,
        movement_quality_score INT DEFAULT 0,
        stability_score INT DEFAULT 0,
        symmetry_score INT DEFAULT 0,
        control_score INT DEFAULT 0,
        quality_score INT DEFAULT 0,
        issues_json TEXT,
        tips_json TEXT,
        drills_json TEXT,
        angle_metrics_json TEXT,
        notes TEXT,
        status VARCHAR(20) NOT NULL DEFAULT 'pending_review',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_assessments_user (user_id),
        INDEX idx_assessments_player (player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── FMS (Functional Movement Screen) ──────────────────────────────────────
    // Header: one row per screening session. total_score is the sum of the
    // 7 movements' final scores (each 0-3, bilateral movements use min(L,R)).
    $pdo->exec("CREATE TABLE IF NOT EXISTS fms_assessments (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        player_id VARCHAR(64) NOT NULL,
        player_name VARCHAR(255) DEFAULT '',
        session_id VARCHAR(64) NULL,
        total_score TINYINT NOT NULL DEFAULT 0,
        notes TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_fms_user (user_id),
        INDEX idx_fms_player (player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Per-movement rows: 7 per assessment. left_score/right_score are NULL
    // for the two unilateral movements (Deep Squat, Trunk Stability Push-Up).
    $pdo->exec("CREATE TABLE IF NOT EXISTS fms_movement_scores (
        id INT AUTO_INCREMENT PRIMARY KEY,
        assessment_id VARCHAR(64) NOT NULL,
        movement VARCHAR(30) NOT NULL,
        left_score TINYINT NULL,
        right_score TINYINT NULL,
        final_score TINYINT NOT NULL,
        pain TINYINT NOT NULL DEFAULT 0,
        notes VARCHAR(255) NULL,
        UNIQUE KEY uq_fms_movement (assessment_id, movement),
        INDEX idx_fms_scores_assessment (assessment_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Denormalized assessor display name (same pattern as player_name above) —
    // avoids a join against users just to show "اسم المقيم" in the FMS UI.
    ensureColumn($pdo, 'fms_assessments', 'assessor_name', 'VARCHAR(255) NULL');

    // ── Player Monitoring Tables ─────────────────────────────────────────────

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_body_metrics (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        weight_kg DECIMAL(5,2) NOT NULL,
        height_cm DECIMAL(5,1) NOT NULL,
        body_fat_percent DECIMAL(5,2) NOT NULL,
        bmi DECIMAL(5,2) NULL,
        measured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_body_metrics_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Body metrics — additional fields ──────────────────────────────────────
    ensureColumn($pdo, 'player_body_metrics', 'fat_mass_kg',        'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'lean_mass_kg',       'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'waist_cm',           'DECIMAL(5,1) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'bmi_for_age_category', 'VARCHAR(20) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'measurement_method', 'VARCHAR(30) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'device_name',        'VARCHAR(100) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'measured_by',        'VARCHAR(100) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'specialist_notes',   'TEXT NULL');
    // linked_player_id lets a coach record metrics for a roster player who has
    // no login account of their own (mirrors player_hooper_index/player_rpe below)
    ensureColumn($pdo, 'player_body_metrics', 'linked_player_id',   'VARCHAR(64) NULL');
    ensureColumn($pdo, 'player_body_metrics', 'recorded_by',        "VARCHAR(10) NOT NULL DEFAULT 'self'");

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_hooper_index (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        training_session_id VARCHAR(64) NULL,
        sleep_quality TINYINT NOT NULL DEFAULT 1,
        fatigue TINYINT NOT NULL DEFAULT 1,
        stress TINYINT NOT NULL DEFAULT 1,
        muscle_soreness TINYINT NOT NULL DEFAULT 1,
        sleep_hours DECIMAL(3,1) NULL,
        hooper_score TINYINT NOT NULL,
        notes TEXT NULL,
        submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_hooper_user (user_id),
        INDEX idx_hooper_submitted (user_id, submitted_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_rpe (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        training_session_id VARCHAR(64) NULL,
        session_type VARCHAR(50) NULL,
        rpe_score TINYINT NOT NULL DEFAULT 1,
        duration_minutes SMALLINT NOT NULL DEFAULT 0,
        training_load SMALLINT NOT NULL DEFAULT 0,
        notes TEXT NULL,
        submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_rpe_user (user_id),
        INDEX idx_rpe_submitted (user_id, submitted_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Training Flow linking — Phase 1 ─────────────────────────────────────
    ensureColumn($pdo, 'player_hooper_index', 'pre_rpe',          'TINYINT NULL');
    ensureColumn($pdo, 'player_hooper_index', 'pain_today',       'TINYINT DEFAULT 0');
    ensureColumn($pdo, 'player_hooper_index', 'pain_location',    'VARCHAR(100) NULL');
    ensureColumn($pdo, 'player_hooper_index', 'mood',             'TINYINT NULL');
    ensureColumn($pdo, 'player_hooper_index', 'assessment_id',    'VARCHAR(64) NULL');
    ensureColumn($pdo, 'player_hooper_index', 'linked_player_id', 'VARCHAR(64) NULL');
    ensureColumn($pdo, 'player_hooper_index', 'club_id',          'INT NULL');
    ensureColumn($pdo, 'player_hooper_index', 'recorded_by',      "VARCHAR(10) NOT NULL DEFAULT 'self'");
    ensureColumn($pdo, 'player_rpe',          'recorded_by',      "VARCHAR(10) NOT NULL DEFAULT 'self'");
    ensureColumn($pdo, 'player_rpe',          'rpe_type',         "VARCHAR(4) NOT NULL DEFAULT 'post'");
    ensureColumn($pdo, 'player_rpe',          'pain_reported',    'TINYINT DEFAULT 0');
    ensureColumn($pdo, 'player_rpe',          'difficulty',       'VARCHAR(10) NULL');
    ensureColumn($pdo, 'player_rpe',          'mood_after',       'TINYINT NULL');
    ensureColumn($pdo, 'player_rpe',          'completed_full_session', 'TINYINT NOT NULL DEFAULT 1');
    ensureColumn($pdo, 'player_rpe',          'actual_duration_minutes', 'SMALLINT NULL');
    ensureColumn($pdo, 'player_rpe',          'incomplete_reason', 'VARCHAR(255) NULL');
    ensureColumn($pdo, 'player_rpe',          'assessment_id',    'VARCHAR(64) NULL');
    ensureColumn($pdo, 'player_rpe',          'linked_player_id', 'VARCHAR(64) NULL');
    ensureColumn($pdo, 'player_rpe',          'club_id',          'INT NULL');
    // ── Training Load — decimal RPE support (RPE APR Rwanda spec allows values like 5.5) ──
    // Nullable (rather than NOT NULL DEFAULT) so a genuinely missing RPE or
    // duration can be told apart from a legitimately recorded zero — see
    // TrainingLoadCalculator::DAY_MISSING_RPE / DAY_MISSING_DURATION.
    ensureColumnType($pdo, 'player_rpe', 'rpe_score',        'decimal(3,1)', true,  "DECIMAL(3,1) NULL");
    ensureColumnType($pdo, 'player_rpe', 'duration_minutes',  'smallint',     true,  "SMALLINT NULL");
    ensureColumnType($pdo, 'player_rpe', 'training_load',     'decimal(8,2)', false, "DECIMAL(8,2) NOT NULL DEFAULT 0.00");
    // session_id = explicit link to training_sessions.id (training_session_id kept for backwards compat)
    ensureColumn($pdo, 'player_hooper_index', 'session_id', 'VARCHAR(64) NULL');
    ensureColumn($pdo, 'player_rpe',          'session_id', 'VARCHAR(64) NULL');
    ensureIndex($pdo,  'player_hooper_index', 'idx_hooper_assessment',
        'CREATE INDEX idx_hooper_assessment ON player_hooper_index (assessment_id)');
    ensureIndex($pdo,  'player_rpe',          'idx_rpe_assessment',
        'CREATE INDEX idx_rpe_assessment ON player_rpe (assessment_id)');
    ensureIndex($pdo,  'player_hooper_index', 'idx_hooper_session_id',
        'CREATE INDEX idx_hooper_session_id ON player_hooper_index (session_id)');
    ensureIndex($pdo,  'player_rpe',          'idx_rpe_session_id',
        'CREATE INDEX idx_rpe_session_id ON player_rpe (session_id)');
    ensureIndex($pdo,  'player_body_metrics', 'idx_body_metrics_linked_player',
        'CREATE INDEX idx_body_metrics_linked_player ON player_body_metrics (linked_player_id)');

    // ── Body Composition & Body Fat Assessment ───────────────────────────────
    // Append-only: every submission is a new row, history is never overwritten
    // (mirrors fms_assessments — an assessment id is a permanent record).
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_body_composition_assessments (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        club_id INT NOT NULL,
        linked_player_id VARCHAR(64) NULL,
        recorded_by VARCHAR(10) NOT NULL DEFAULT 'self',
        team_name VARCHAR(100) NULL,
        position VARCHAR(50) NULL,
        assessment_date DATE NOT NULL,
        assessment_time VARCHAR(5) NULL,
        assessment_type VARCHAR(20) NOT NULL DEFAULT 'periodic',
        height_cm DECIMAL(5,1) NOT NULL,
        weight_kg DECIMAL(5,2) NOT NULL,
        age_at_assessment TINYINT NULL,
        biceps_attempt_1_mm DECIMAL(4,1) NULL,
        biceps_attempt_2_mm DECIMAL(4,1) NULL,
        biceps_attempt_3_mm DECIMAL(4,1) NULL,
        biceps_mm DECIMAL(4,1) NULL,
        triceps_attempt_1_mm DECIMAL(4,1) NULL,
        triceps_attempt_2_mm DECIMAL(4,1) NULL,
        triceps_attempt_3_mm DECIMAL(4,1) NULL,
        triceps_mm DECIMAL(4,1) NULL,
        subscapular_attempt_1_mm DECIMAL(4,1) NULL,
        subscapular_attempt_2_mm DECIMAL(4,1) NULL,
        subscapular_attempt_3_mm DECIMAL(4,1) NULL,
        subscapular_mm DECIMAL(4,1) NULL,
        suprailiac_attempt_1_mm DECIMAL(4,1) NULL,
        suprailiac_attempt_2_mm DECIMAL(4,1) NULL,
        suprailiac_attempt_3_mm DECIMAL(4,1) NULL,
        suprailiac_mm DECIMAL(4,1) NULL,
        skinfold_sum_mm DECIMAL(5,1) NULL,
        calculation_formula_code VARCHAR(30) NULL,
        calculation_age_group VARCHAR(20) NULL,
        body_fat_percentage DECIMAL(5,2) NULL,
        fat_mass_kg DECIMAL(5,2) NULL,
        fat_free_mass_kg DECIMAL(5,2) NULL,
        bmi DECIMAL(5,2) NULL,
        notes TEXT NULL,
        assessed_by VARCHAR(255) NULL,
        created_by INT NULL,
        updated_by INT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted_at TIMESTAMP NULL,
        INDEX idx_bc_linked_player (linked_player_id),
        INDEX idx_bc_user (user_id),
        INDEX idx_bc_date (assessment_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // One active goal per player — upserted, not history (unlike the
    // assessments table above, a goal is a current target, not a measurement).
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_body_composition_goals (
        id VARCHAR(64) PRIMARY KEY,
        linked_player_id VARCHAR(64) NOT NULL,
        club_id INT NOT NULL,
        target_weight_kg DECIMAL(5,2) NULL,
        target_body_fat_percentage DECIMAL(5,2) NULL,
        target_fat_mass_kg DECIMAL(5,2) NULL,
        min_acceptable_body_fat DECIMAL(5,2) NULL,
        max_acceptable_body_fat DECIMAL(5,2) NULL,
        target_date DATE NULL,
        notes TEXT NULL,
        created_by INT NULL,
        updated_by INT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_bc_goal_player (linked_player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Data-only formula config (coefficients, not evaluated expressions) —
    // BodyFat% = coefficient_a * LOG10(skinfold_sum) + coefficient_b.
    // New age bands/genders are added as rows, no code change required.
    $pdo->exec("CREATE TABLE IF NOT EXISTS body_composition_formulas (
        formula_code VARCHAR(30) PRIMARY KEY,
        formula_name VARCHAR(100) NOT NULL,
        gender VARCHAR(10) NOT NULL DEFAULT 'male',
        min_age TINYINT NOT NULL,
        max_age TINYINT NOT NULL,
        coefficient_a DECIMAL(10,4) NOT NULL,
        coefficient_b DECIMAL(10,4) NOT NULL,
        required_sites VARCHAR(100) NOT NULL DEFAULT 'biceps,triceps,subscapular,suprailiac',
        version INT NOT NULL DEFAULT 1,
        is_active TINYINT NOT NULL DEFAULT 1,
        source_reference VARCHAR(255) NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("INSERT IGNORE INTO body_composition_formulas
        (formula_code, formula_name, gender, min_age, max_age, coefficient_a, coefficient_b, source_reference) VALUES
        ('age_17_19', 'Durnin-Womersley 17-19', 'male', 17, 19, 27.409, -26.789, 'Durnin & Womersley 1974'),
        ('age_20_29', 'Durnin-Womersley 20-29', 'male', 20, 29, 27.775, -27.203, 'Durnin & Womersley 1974'),
        ('age_30_39', 'Durnin-Womersley 30-39', 'male', 30, 39, 26.781, -27.203, 'Durnin & Womersley 1974')");

    // ── Phase 4 — AI Plan columns ─────────────────────────────────────────────
    ensureColumn($pdo, 'training_sessions', 'week_number',       'TINYINT NULL');
    ensureColumn($pdo, 'training_sessions', 'intensity',         'VARCHAR(6) NULL');
    ensureColumn($pdo, 'training_plans',    'recovery_notes',    'TEXT NULL');
    ensureColumn($pdo, 'training_plans',    'progression_rules', 'TEXT NULL');
    ensureColumn($pdo, 'training_plans',    'num_weeks',         'TINYINT NULL');

    // ── Club Players & Sessions ──────────────────────────────────────────────

    $pdo->exec("CREATE TABLE IF NOT EXISTS club_players (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        name VARCHAR(255) NOT NULL,
        position VARCHAR(50) NULL,
        team_name VARCHAR(100) NULL,
        category VARCHAR(50) NULL,
        dominant_foot VARCHAR(10) NULL,
        height_cm INT NULL,
        weight_kg INT NULL,
        injury_notes TEXT NULL,
        photo_url VARCHAR(500) NULL,
        is_active TINYINT DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_club_players_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── club_players extended fields (AFTER CREATE TABLE) ────────────────────
    ensureColumn($pdo, 'club_players', 'player_type',    "VARCHAR(20) DEFAULT 'club'");
    ensureColumn($pdo, 'club_players', 'linked_user_id', 'INT NULL');
    // ── club_players MVP fields ──────────────────────────────────────────────
    ensureColumn($pdo, 'club_players', 'number',         'VARCHAR(10) NULL');
    ensureColumn($pdo, 'club_players', 'nickname',       'VARCHAR(255) NULL');
    ensureColumn($pdo, 'club_players', 'name_ar',        'VARCHAR(255) NULL');
    ensureColumn($pdo, 'club_players', 'name_en',        'VARCHAR(255) NULL');
    ensureColumn($pdo, 'club_players', 'date_of_birth',  'DATE NULL');
    ensureColumn($pdo, 'club_players', 'nationality',    'VARCHAR(80) NULL');
    ensureColumn($pdo, 'club_players', 'physical_notes', 'TEXT NULL');
    ensureColumn($pdo, 'club_players', 'medical_notes',  'TEXT NULL');
    ensureColumn($pdo, 'club_players', 'status',         "VARCHAR(20) DEFAULT 'active'");
    ensureColumn($pdo, 'club_players', 'latest_score',        'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'club_players', 'movement_score',      'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'club_players', 'stability_score',     'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'club_players', 'symmetry_score',      'DECIMAL(5,2) NULL');
    ensureColumn($pdo, 'club_players', 'control_score',       'DECIMAL(5,2) NULL');
    // ── Availability & Assessment tracking fields ────────────────────────────
    ensureColumn($pdo, 'club_players', 'expected_return_date','DATE NULL');
    ensureColumn($pdo, 'club_players', 'unavailable_reason',  'VARCHAR(255) NULL');
    ensureColumn($pdo, 'club_players', 'last_assessment_at',  'DATETIME NULL');

    // ── one-time migration guard ───────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS system_meta (
        key_name VARCHAR(64) PRIMARY KEY,
        value    TEXT NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $migrated = $pdo->query("SELECT value FROM system_meta WHERE key_name='migration_v3'")->fetchColumn();
    if (!$migrated) {
        // Users without a role were created before role field existed.
        // They are coach/club accounts (original app was club-only).
        // Users with player_type already set are players — give them 'player' role.
        $pdo->exec("UPDATE users SET role = 'player' WHERE role IS NULL AND player_type IS NOT NULL");
        $pdo->exec("UPDATE users SET role = 'club'   WHERE role IS NULL AND player_type IS NULL");
        // All pre-existing club_players rows were coach-managed → 'club'
        $pdo->exec("UPDATE club_players SET player_type = 'club' WHERE player_type IS NULL");
        $pdo->prepare("INSERT IGNORE INTO system_meta (key_name, value) VALUES ('migration_v3', '1')")
            ->execute();
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS club_sessions (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        type VARCHAR(50) NOT NULL DEFAULT 'team_training',
        scope VARCHAR(20) NOT NULL DEFAULT 'team',
        status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
        date DATE NOT NULL,
        start_time VARCHAR(5) NOT NULL DEFAULT '08:00',
        end_time VARCHAR(5) NULL,
        duration_min INT NOT NULL DEFAULT 90,
        location VARCHAR(255) NOT NULL DEFAULT '',
        player_count INT NOT NULL DEFAULT 0,
        intensity VARCHAR(20) NOT NULL DEFAULT 'medium',
        ai_enabled TINYINT DEFAULT 0,
        attendance_required TINYINT DEFAULT 0,
        rpe_required TINYINT DEFAULT 0,
        wellness_required TINYINT DEFAULT 0,
        coach_name VARCHAR(100) NULL,
        notes TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_club_sessions_user (user_id),
        INDEX idx_club_sessions_date (user_id, date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── club_sessions MVP fields ─────────────────────────────────────────────
    ensureColumn($pdo, 'club_sessions', 'team_name',            'VARCHAR(100) NULL');
    ensureColumn($pdo, 'club_sessions', 'player_ids',           'TEXT NULL');
    ensureColumn($pdo, 'club_sessions', 'completed_player_ids', 'TEXT NULL');
    ensureColumn($pdo, 'club_sessions', 'assessment_count',     'INT DEFAULT 0');
    // Optional bridge to the wellness/RPE workflow's own session table — lets
    // a real attendance mark (e.g. "absent") activate that player's
    // session_players.status there instead of the two systems staying
    // completely unaware of each other.
    ensureColumn($pdo, 'club_sessions', 'linked_training_session_id', 'VARCHAR(64) NULL');
    // club_sessions was originally scoped only by user_id (the creating
    // coach) — a club with several coaches/staff needs every session visible
    // club-wide, not just to whoever created it. Backfill existing rows'
    // club_id from their creator's resolved club so nothing already saved
    // goes dark once queries switch to filtering by club_id.
    ensureColumn($pdo, 'club_sessions', 'club_id', 'INT NULL');
    ensureColumn($pdo, 'club_sessions', 'actual_started_at', 'DATETIME NULL');
    ensureColumn($pdo, 'club_sessions', 'actual_ended_at', 'DATETIME NULL');
    $pdo->exec("UPDATE club_sessions cs
        LEFT JOIN club_staff st ON st.user_id = cs.user_id AND st.status = 'active'
        LEFT JOIN users u ON u.id = cs.user_id
        SET cs.club_id = COALESCE(st.club_id, u.club_id, cs.user_id)
        WHERE cs.club_id IS NULL");
    ensureIndex($pdo, 'club_sessions', 'idx_club_sessions_club',
        'ALTER TABLE club_sessions ADD INDEX idx_club_sessions_club (club_id)');

    // ── Audit log — who changed sensitive fields (weight/body-fat/injury/pain) ──
    $pdo->exec("CREATE TABLE IF NOT EXISTS audit_logs (
        id           INT AUTO_INCREMENT PRIMARY KEY,
        entity_type  VARCHAR(40)  NOT NULL,
        entity_id    VARCHAR(64)  NOT NULL,
        field_name   VARCHAR(60)  NOT NULL,
        old_value    TEXT NULL,
        new_value    TEXT NULL,
        changed_by_user_id INT NOT NULL,
        created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_audit_entity (entity_type, entity_id),
        INDEX idx_audit_user (changed_by_user_id),
        INDEX idx_audit_created (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Injury / Rehab / Return-to-Play file (roadmap item 3) ────────────────
    // Clinical detail, gated behind medical_detail.read/write (doctor,
    // physiotherapist only) — separate from the legacy club_players.status/
    // injury_notes fields that coach still edits unchanged.
    $pdo->exec("CREATE TABLE IF NOT EXISTS injury_cases (
        id                    INT AUTO_INCREMENT PRIMARY KEY,
        club_id               INT NOT NULL,
        player_id             VARCHAR(64) NOT NULL,
        injury_date           DATE NOT NULL,
        body_location         VARCHAR(100) NULL,
        injury_type           VARCHAR(100) NULL,
        severity              VARCHAR(10) NOT NULL DEFAULT 'moderate',
        diagnosis             TEXT NULL,
        exam_notes            TEXT NULL,
        case_status           VARCHAR(20) NOT NULL DEFAULT 'open',
        rtp_stage             VARCHAR(30) NULL,
        expected_return_date  DATE NULL,
        actual_return_date    DATE NULL,
        created_by_user_id    INT NOT NULL,
        created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_injury_club (club_id),
        INDEX idx_injury_player (player_id),
        INDEX idx_injury_status (case_status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS injury_updates (
        id               INT AUTO_INCREMENT PRIMARY KEY,
        injury_case_id   INT NOT NULL,
        author_user_id   INT NOT NULL,
        note             TEXT NULL,
        rtp_stage        VARCHAR(30) NULL,
        case_status      VARCHAR(20) NULL,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_injury_updates_case (injury_case_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Physiotherapy & Massage Scheduling (roadmap item 4) ──────────────────
    // Independent treatment-session log — doctor/physiotherapist/massage
    // specialist only. Coach-visible availability stays on club_players.
    // physio_sessions is session-level (one row per booking, shared time/
    // room/reason/therapist); per-player status/notes live in
    // physio_session_players (see below) — mirrors club_sessions +
    // session_attendance. session_name is an optional free-text title.
    $pdo->exec("CREATE TABLE IF NOT EXISTS physio_sessions (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        club_id             INT NOT NULL,
        therapist_user_id   INT NOT NULL,
        scheduled_at        DATETIME NOT NULL,
        duration_minutes    INT NOT NULL DEFAULT 30,
        room                VARCHAR(60) NULL,
        body_area           VARCHAR(100) NULL,
        session_reason      VARCHAR(20) NOT NULL DEFAULT 'recovery',
        treatment_type      VARCHAR(100) NULL,
        intensity           VARCHAR(10) NOT NULL DEFAULT 'moderate',
        contraindications   TEXT NULL,
        created_by_user_id  INT NOT NULL,
        session_name        VARCHAR(150) NULL,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_physio_club (club_id),
        INDEX idx_physio_therapist (therapist_user_id),
        INDEX idx_physio_scheduled (scheduled_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS physio_session_players (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        session_id          INT NOT NULL,
        player_id           VARCHAR(64) NOT NULL,
        status              VARCHAR(12) NOT NULL DEFAULT 'scheduled',
        specialist_notes    TEXT NULL,
        player_response     TEXT NULL,
        recommendation      VARCHAR(20) NULL,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_physio_sp_session_player (session_id, player_id),
        INDEX idx_physio_sp_player (player_id),
        CONSTRAINT fk_physio_sp_session FOREIGN KEY (session_id)
            REFERENCES physio_sessions(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Nutrition, Hydration & Supplements (roadmap item 5) ───────────────────
    // Doctor/nutritionist only. Body-composition goals stay on the existing
    // player_body_composition_goals table above — not duplicated here.
    $pdo->exec("CREATE TABLE IF NOT EXISTS nutrition_profiles (
        id                    INT AUTO_INCREMENT PRIMARY KEY,
        club_id               INT NOT NULL,
        player_id             VARCHAR(64) NOT NULL,
        allergies             TEXT NULL,
        dietary_restrictions  TEXT NULL,
        calorie_target        INT NULL,
        protein_target_g      INT NULL,
        carb_target_g         INT NULL,
        fluid_target_ml       INT NULL,
        notes                 TEXT NULL,
        updated_by_user_id    INT NOT NULL,
        created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_nutrition_profile_player (player_id),
        INDEX idx_nutrition_profile_club (club_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS nutrition_day_plans (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        club_id             INT NOT NULL,
        player_id           VARCHAR(64) NOT NULL,
        plan_type           VARCHAR(20) NOT NULL,
        calorie_target      INT NULL,
        protein_target_g    INT NULL,
        carb_target_g       INT NULL,
        fluid_target_ml     INT NULL,
        hydration_before    TEXT NULL,
        hydration_during    TEXT NULL,
        hydration_after     TEXT NULL,
        notes               TEXT NULL,
        updated_by_user_id  INT NOT NULL,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_nutrition_plan (player_id, plan_type),
        INDEX idx_nutrition_plan_club (club_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS supplements (
        id                        INT AUTO_INCREMENT PRIMARY KEY,
        club_id                   INT NOT NULL,
        player_id                 VARCHAR(64) NOT NULL,
        supplement_name           VARCHAR(150) NOT NULL,
        dosage                    VARCHAR(100) NULL,
        reason                    TEXT NULL,
        doctor_signoff            TINYINT NOT NULL DEFAULT 0,
        doctor_signoff_by         INT NULL,
        doctor_signoff_at         TIMESTAMP NULL,
        nutritionist_signoff      TINYINT NOT NULL DEFAULT 0,
        nutritionist_signoff_by   INT NULL,
        nutritionist_signoff_at   TIMESTAMP NULL,
        status                    VARCHAR(12) NOT NULL DEFAULT 'pending',
        created_by_user_id        INT NOT NULL,
        created_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_supplements_club (club_id),
        INDEX idx_supplements_player (player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS nutrition_compliance_logs (
        id                INT AUTO_INCREMENT PRIMARY KEY,
        club_id           INT NOT NULL,
        player_id         VARCHAR(64) NOT NULL,
        log_date          DATE NOT NULL,
        status            VARCHAR(15) NOT NULL DEFAULT 'compliant',
        notes             TEXT NULL,
        logged_by_user_id INT NOT NULL,
        created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_nutrition_compliance (player_id, log_date),
        INDEX idx_nutrition_compliance_club (club_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Unified Daily Readiness & Intervention Dashboard (roadmap item 6) ────
    // The day-specific participation call — separate from club_players.status,
    // which is the longer-running injury/availability state. Coach-safe: only
    // ever exposes status/duration/restrictions, never diagnosis fields.
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_daily_decisions (
        id                       INT AUTO_INCREMENT PRIMARY KEY,
        club_id                  INT NOT NULL,
        player_id                VARCHAR(64) NOT NULL,
        decision_date            DATE NOT NULL,
        participation_status     VARCHAR(20) NOT NULL DEFAULT 'fully_available',
        allowed_duration_minutes INT NULL,
        restrictions             TEXT NULL,
        decided_by_user_id       INT NOT NULL,
        created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_daily_decision (player_id, decision_date),
        INDEX idx_daily_decision_club_date (club_id, decision_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Real per-player attendance record for club_sessions ──────────────────
    // Replaces the completed_player_ids JSON blob as the source of truth:
    // one row per (session, player) with a real present/absent/late status.
    $pdo->exec("CREATE TABLE IF NOT EXISTS session_attendance (
        id          INT AUTO_INCREMENT PRIMARY KEY,
        session_id  VARCHAR(64) NOT NULL,
        player_id   VARCHAR(64) NOT NULL,
        user_id     INT NOT NULL,
        status      VARCHAR(10) NOT NULL DEFAULT 'pending',
        marked_at   TIMESTAMP NULL,
        created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_session_attendance (session_id, player_id),
        INDEX idx_session_attendance_session (session_id),
        INDEX idx_session_attendance_player (player_id),
        INDEX idx_session_attendance_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    ensureColumn($pdo, 'session_attendance', 'timer_started_at', 'DATETIME NULL');
    ensureColumn($pdo, 'session_attendance', 'timer_ended_at', 'DATETIME NULL');
    ensureColumn($pdo, 'session_attendance', 'elapsed_seconds', 'INT NOT NULL DEFAULT 0');

    // ── Training Plans & Sessions — Phase 1 ────────────────────────────────────

    $pdo->exec("CREATE TABLE IF NOT EXISTS training_plans (
        id               VARCHAR(64)  PRIMARY KEY,
        plan_type        VARCHAR(6)   NOT NULL DEFAULT 'manual',
        owner_type       VARCHAR(10)  NOT NULL,
        club_id          INT          NULL,
        coach_user_id    INT          NULL,
        player_user_id   INT          NULL,
        linked_player_id VARCHAR(64)  NULL,
        title            VARCHAR(255) NOT NULL,
        goal             VARCHAR(100) NULL,
        status           VARCHAR(10)  NOT NULL DEFAULT 'draft',
        ai_provider      VARCHAR(50)  NULL,
        ai_prompt_snapshot    TEXT    NULL,
        ai_response_snapshot  LONGTEXT NULL,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_tp_club   (club_id),
        INDEX idx_tp_coach  (coach_user_id),
        INDEX idx_tp_player (player_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS training_sessions (
        id               VARCHAR(64)  PRIMARY KEY,
        plan_id          VARCHAR(64)  NULL,
        club_id          INT          NULL,
        coach_user_id    INT          NULL,
        title            VARCHAR(255) NOT NULL,
        description      TEXT         NULL,
        session_date     DATE         NOT NULL,
        duration_minutes SMALLINT     NOT NULL DEFAULT 60,
        objective        VARCHAR(15)  NOT NULL DEFAULT 'mixed',
        source           VARCHAR(6)   NOT NULL DEFAULT 'manual',
        status           VARCHAR(15)  NOT NULL DEFAULT 'draft',
        wellness_required TINYINT     DEFAULT 1,
        rpe_required      TINYINT     DEFAULT 1,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_ts_plan  (plan_id),
        INDEX idx_ts_club  (club_id),
        INDEX idx_ts_date  (session_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS session_players (
        id               INT AUTO_INCREMENT PRIMARY KEY,
        session_id       VARCHAR(64) NOT NULL,
        club_id          INT         NULL,
        player_user_id   INT         NOT NULL,
        linked_player_id VARCHAR(64) NULL,
        status           VARCHAR(15) NOT NULL DEFAULT 'assigned',
        pre_check_completed_at TIMESTAMP NULL,
        started_at             TIMESTAMP NULL,
        completed_at           TIMESTAMP NULL,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_session_player (session_id, player_user_id),
        INDEX idx_sp_session (session_id),
        INDEX idx_sp_player  (player_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS session_exercises (
        id               INT AUTO_INCREMENT PRIMARY KEY,
        session_id       VARCHAR(64)  NOT NULL,
        exercise_name    VARCHAR(255) NOT NULL,
        category         VARCHAR(15)  NOT NULL DEFAULT 'fitness',
        sets             TINYINT      NULL,
        reps             TINYINT      NULL,
        duration_seconds SMALLINT     NULL,
        rest_seconds     SMALLINT     NULL,
        intensity        VARCHAR(6)   NOT NULL DEFAULT 'medium',
        instructions     TEXT         NULL,
        video_url        VARCHAR(500) NULL,
        requires_pose_detection TINYINT DEFAULT 0,
        assessment_type  VARCHAR(50)  NULL,
        sort_order       TINYINT      NOT NULL DEFAULT 0,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_se_session (session_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS post_training_feedback (
        id               INT AUTO_INCREMENT PRIMARY KEY,
        session_id       VARCHAR(64) NULL,
        assessment_id    VARCHAR(64) NULL,
        club_id          INT         NULL,
        player_user_id   INT         NOT NULL,
        linked_player_id VARCHAR(64) NULL,
        post_rpe         TINYINT     NOT NULL,
        pain_reported    TINYINT     DEFAULT 0,
        difficulty       VARCHAR(10) NULL,
        mood_after       TINYINT     NULL,
        notes            TEXT        NULL,
        created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_ptf_session    (session_id),
        INDEX idx_ptf_assessment (assessment_id),
        INDEX idx_ptf_player     (player_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    ensureColumn($pdo, 'post_training_feedback', 'completed_full_session', 'TINYINT NOT NULL DEFAULT 1');
    ensureColumn($pdo, 'post_training_feedback', 'actual_duration_minutes', 'SMALLINT NULL');
    ensureColumn($pdo, 'post_training_feedback', 'incomplete_reason', 'VARCHAR(255) NULL');

    // ── Club Teams ───────────────────────────────────────────────────────────────

    $pdo->exec("CREATE TABLE IF NOT EXISTS club_teams (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        name VARCHAR(100) NOT NULL,
        category VARCHAR(50) DEFAULT 'firstTeam',
        coach_name VARCHAR(100) DEFAULT '',
        physical_coach_name VARCHAR(100) DEFAULT '',
        season VARCHAR(20) DEFAULT '',
        notes TEXT NULL,
        is_active TINYINT(1) DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_club_teams_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── club_sessions: Phase 2 fields ────────────────────────────────────────────
    ensureColumn($pdo, 'club_sessions', 'position_filter',  'VARCHAR(50) NULL');
    ensureColumn($pdo, 'club_sessions', 'assessment_types', 'TEXT NULL');  // JSON array

    // ── Club Session Exercises ─────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS club_session_exercises (
        id INT AUTO_INCREMENT PRIMARY KEY,
        session_id VARCHAR(64) NOT NULL,
        exercise_type VARCHAR(10) NOT NULL DEFAULT 'manual',
        exercise_name VARCHAR(255) NOT NULL,
        category VARCHAR(50) NULL,
        sets TINYINT NULL,
        reps TINYINT NULL,
        duration_seconds SMALLINT NULL,
        rest_seconds SMALLINT NULL,
        intensity VARCHAR(20) NOT NULL DEFAULT 'medium',
        assessment_type VARCHAR(50) NULL,
        notes TEXT NULL,
        sort_order TINYINT NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_cse_session (session_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Matches ────────────────────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS matches (
        id VARCHAR(64) PRIMARY KEY,
        user_id INT NOT NULL,
        opponent VARCHAR(255) NOT NULL,
        match_date DATE NOT NULL,
        match_time VARCHAR(5) NOT NULL DEFAULT '16:00',
        location VARCHAR(255) NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
        player_ids TEXT NULL,
        player_minutes TEXT NULL,
        wellness_required TINYINT NOT NULL DEFAULT 0,
        rpe_required TINYINT NOT NULL DEFAULT 0,
        notes TEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_matches_user (user_id),
        INDEX idx_matches_date (user_id, match_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    ensureColumn($pdo, 'matches', 'actual_started_at', 'DATETIME NULL');
    ensureColumn($pdo, 'matches', 'actual_ended_at', 'DATETIME NULL');
    ensureColumn($pdo, 'match_participations', 'timer_started_at', 'DATETIME NULL');
    ensureColumn($pdo, 'match_participations', 'accumulated_seconds', 'INT NOT NULL DEFAULT 0');

    // ── Coach Evaluations ──────────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS coach_evaluations (
        id INT AUTO_INCREMENT PRIMARY KEY,
        session_id VARCHAR(64) NULL,
        match_id VARCHAR(64) NULL,
        player_id VARCHAR(64) NOT NULL,
        user_id INT NOT NULL,
        fitness_level TINYINT NULL,
        effort TINYINT NULL,
        speed TINYINT NULL,
        strength TINYINT NULL,
        agility TINYINT NULL,
        endurance TINYINT NULL,
        notes TEXT NULL,
        evaluated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_eval_session (session_id),
        INDEX idx_eval_match (match_id),
        INDEX idx_eval_player (player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Survey Responses (QR/Web) ──────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS survey_responses (
        id INT AUTO_INCREMENT PRIMARY KEY,
        session_id VARCHAR(64) NULL,
        match_id VARCHAR(64) NULL,
        player_name VARCHAR(255) NOT NULL,
        player_id VARCHAR(64) NULL,
        response_type VARCHAR(10) NOT NULL,
        responses_json TEXT NOT NULL,
        submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_survey_session (session_id),
        INDEX idx_survey_match (match_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Wearable Device Integration (Future: Catapult, STATSports, Apple Watch, etc.) ─

    $pdo->exec("CREATE TABLE IF NOT EXISTS player_wearable_data (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        device_id VARCHAR(100) NOT NULL,
        device_type VARCHAR(50) NOT NULL,
        heart_rate INT NULL,
        distance_m DECIMAL(8,2) NULL,
        sprint_count INT NULL,
        top_speed DECIMAL(5,2) NULL,
        max_acceleration DECIMAL(5,2) NULL,
        distance_at_high_intensity INT NULL,
        rpe_device_estimate INT NULL,
        recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_wearable_user (user_id),
        INDEX idx_wearable_device (device_id),
        INDEX idx_wearable_recorded (user_id, recorded_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Phase 8: Multi-app data contract (007) ───────────────────────────────────
    // club_players
    ensureColumn($pdo, 'club_players', 'source_app',          "VARCHAR(50) NOT NULL DEFAULT 'legacy'");
    ensureColumn($pdo, 'club_players', 'external_player_ref', 'VARCHAR(100) NULL');
    ensureColumn($pdo, 'club_players', 'club_id',             'INT NULL');
    ensureColumn($pdo, 'club_players', 'team_id',             'INT NULL');
    ensureIndex($pdo, 'club_players', 'idx_cp_source',
        'CREATE INDEX idx_cp_source ON club_players (user_id, source_app)');
    ensureIndex($pdo, 'club_players', 'idx_cp_ext_ref',
        'CREATE INDEX idx_cp_ext_ref ON club_players (user_id, source_app, external_player_ref)');

    // club_sessions
    ensureColumn($pdo, 'club_sessions', 'source_app',            "VARCHAR(50) NOT NULL DEFAULT 'legacy'");
    ensureColumn($pdo, 'club_sessions', 'external_session_ref',  'VARCHAR(100) NULL');
    ensureColumn($pdo, 'club_sessions', 'club_id',               'INT NULL');
    ensureColumn($pdo, 'club_sessions', 'team_id',               'INT NULL');
    ensureIndex($pdo, 'club_sessions', 'idx_cs_source',
        'CREATE INDEX idx_cs_source ON club_sessions (user_id, source_app)');

    // assessments
    ensureColumn($pdo, 'assessments', 'source_app',               "VARCHAR(50) NOT NULL DEFAULT 'legacy'");
    ensureColumn($pdo, 'assessments', 'external_assessment_ref',  'VARCHAR(100) NULL');
    ensureColumn($pdo, 'assessments', 'club_id',                  'INT NULL');
    ensureColumn($pdo, 'assessments', 'team_id',                  'INT NULL');
    ensureColumn($pdo, 'assessments', 'normalized_type',          'VARCHAR(50) NULL');
    ensureIndex($pdo, 'assessments', 'idx_assessments_source',
        'CREATE INDEX idx_assessments_source ON assessments (user_id, source_app)');
    ensureIndex($pdo, 'assessments', 'idx_assessments_normalized',
        'CREATE INDEX idx_assessments_normalized ON assessments (user_id, normalized_type)');
    ensureIndex($pdo, 'assessments', 'idx_assessments_ext_ref',
        'CREATE INDEX idx_assessments_ext_ref ON assessments (user_id, source_app, external_assessment_ref)');

    // player_hooper_index (club_id already exists; add source_app, external_entry_ref, team_id)
    ensureColumn($pdo, 'player_hooper_index', 'source_app',         "VARCHAR(50) NOT NULL DEFAULT 'legacy'");
    ensureColumn($pdo, 'player_hooper_index', 'external_entry_ref', 'VARCHAR(100) NULL');
    ensureColumn($pdo, 'player_hooper_index', 'team_id',            'INT NULL');
    ensureIndex($pdo, 'player_hooper_index', 'idx_hooper_source',
        'CREATE INDEX idx_hooper_source ON player_hooper_index (user_id, source_app)');

    // player_rpe (club_id already exists; add source_app, external_entry_ref, team_id)
    ensureColumn($pdo, 'player_rpe', 'source_app',         "VARCHAR(50) NOT NULL DEFAULT 'legacy'");
    ensureColumn($pdo, 'player_rpe', 'external_entry_ref', 'VARCHAR(100) NULL');
    ensureColumn($pdo, 'player_rpe', 'team_id',            'INT NULL');
    ensureIndex($pdo, 'player_rpe', 'idx_rpe_source',
        'CREATE INDEX idx_rpe_source ON player_rpe (user_id, source_app)');

    // ── Phase 9: club_id isolation completion — tables that only had user_id ─────
    // (kept alongside user_id — nothing that already filters by user_id breaks).
    // Backfilled in api/club/_schema.php alongside the Phase-8 tables above.
    foreach ([
        'fms_assessments', 'player_body_metrics', 'coach_evaluations',
        'matches', 'player_wearable_data', 'session_attendance',
    ] as $table) {
        ensureColumn($pdo, $table, 'club_id', 'INT NULL');
        ensureIndex($pdo, $table, "idx_{$table}_club", "CREATE INDEX idx_{$table}_club ON {$table} (club_id)");
    }

    // ── Competition classification: link matches to a club_competitions row ─────
    ensureColumn($pdo, 'matches', 'competition_id', 'INT NULL');
    ensureIndex($pdo, 'matches', 'idx_matches_competition',
        'CREATE INDEX idx_matches_competition ON matches (competition_id)');

    // Competition discipline rules and the durable card-cycle/suspension ledger.
    foreach ([
        'yellow_card_threshold' => 'INT NOT NULL DEFAULT 3',
        'suspension_matches' => 'INT NOT NULL DEFAULT 1',
        'reset_yellow_cycle' => 'TINYINT NOT NULL DEFAULT 1',
        'carry_cards_between_stages' => 'TINYINT NOT NULL DEFAULT 1',
        'carry_suspensions_forward' => 'TINYINT NOT NULL DEFAULT 0',
        'direct_red_suspension_matches' => 'INT NOT NULL DEFAULT 2',
        'two_yellows_suspension_matches' => 'INT NOT NULL DEFAULT 1',
        'allow_admin_override' => 'TINYINT NOT NULL DEFAULT 1',
    ] as $column => $definition) {
        ensureColumn($pdo, 'club_competitions', $column, $definition);
    }
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_discipline_cycles (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        club_id INT NOT NULL, player_id VARCHAR(64) NOT NULL,
        competition_id INT NOT NULL, season_id BIGINT UNSIGNED NULL,
        cycle_number INT NOT NULL DEFAULT 1, current_yellow_cards INT NOT NULL DEFAULT 0,
        started_at DATE NOT NULL, completed_at DATE NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_discipline_cycle (player_id, competition_id, cycle_number),
        INDEX idx_discipline_cycle_current (club_id, player_id, competition_id, completed_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_suspensions (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        club_id INT NOT NULL, player_id VARCHAR(64) NOT NULL,
        competition_id INT NOT NULL, season_id BIGINT UNSIGNED NULL,
        reason_type VARCHAR(40) NOT NULL, reason TEXT NULL, source_card_id INT NULL,
        matches_total INT NOT NULL, matches_remaining INT NOT NULL,
        status VARCHAR(20) NOT NULL DEFAULT 'active', administrative_decision TEXT NULL,
        decision_document VARCHAR(500) NULL, created_by_user_id INT NOT NULL,
        executed_at DATE NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_suspensions_player (club_id, player_id, status),
        INDEX idx_suspensions_competition (competition_id, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    $pdo->exec("CREATE TABLE IF NOT EXISTS suspension_match_executions (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        suspension_id BIGINT UNSIGNED NOT NULL, match_id VARCHAR(64) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_suspension_match (suspension_id, match_id), INDEX idx_execution_match (match_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── player_notes: coach notes attached to a club player ──────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_notes (
        id           INT AUTO_INCREMENT PRIMARY KEY,
        player_id    VARCHAR(64) NOT NULL,
        coach_user_id INT NOT NULL,
        author_name  VARCHAR(255) NOT NULL DEFAULT 'Coach',
        note_text    TEXT NOT NULL,
        created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_player_notes_player (player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── club_standings: admin-entered league table rows per competition ──────────
    // Read by everyone in the club (players + all staff roles); written by
    // owner/admin/performance_manager only (mirrors club_competitions' write gate).
    $pdo->exec("CREATE TABLE IF NOT EXISTS club_standings (
        id            INT AUTO_INCREMENT PRIMARY KEY,
        club_id       INT NOT NULL,
        competition_id INT NOT NULL,
        position      SMALLINT NOT NULL DEFAULT 0,
        team_name     VARCHAR(255) NOT NULL,
        played        SMALLINT NOT NULL DEFAULT 0,
        won           SMALLINT NOT NULL DEFAULT 0,
        drawn         SMALLINT NOT NULL DEFAULT 0,
        lost          SMALLINT NOT NULL DEFAULT 0,
        goals_for     SMALLINT NOT NULL DEFAULT 0,
        goals_against SMALLINT NOT NULL DEFAULT 0,
        points        SMALLINT NOT NULL DEFAULT 0,
        is_own_team   TINYINT(1) NOT NULL DEFAULT 0,
        updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_club_standings_competition (competition_id, position)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── app_settings: key-value store for runtime toggles ────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS app_settings (
        key_name   VARCHAR(100) PRIMARY KEY,
        value      TEXT        NOT NULL DEFAULT '',
        updated_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // ── Club Entity Layer — formalizes "club" as a real organization (clubs
    //    table), linked to the legacy per-user club_players/teams/sessions.
    require_once __DIR__ . '/club/_schema.php';
    ensureClubSchema($pdo);

    // ── Club Staff Layer — staff roles (owner/admin/coach/doctor/analyst)
    //    attached to a club, built on top of the clubs table above.
    require_once __DIR__ . '/club/_staff_schema.php';
    ensureClubStaffSchema($pdo);

    // ── Cross-department task system (Phase 1 platform expansion) ───────────
    // Any staff role can create/be assigned a task, optionally linked to a
    // player and/or another record (injury case, physio session, match) via
    // linked_entity_type/linked_entity_id. Gated by 'tasks.manage' (everyone)
    // and 'tasks.assign_others' (admin/coach/doctor only) in club_auth.php.
    $pdo->exec("CREATE TABLE IF NOT EXISTS tasks (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        club_id             INT NOT NULL,
        title               VARCHAR(200) NOT NULL,
        description         TEXT NULL,
        created_by_user_id  INT NOT NULL,
        assigned_to_user_id INT NOT NULL,
        linked_player_id    VARCHAR(64) NULL,
        linked_entity_type  VARCHAR(30) NULL,
        linked_entity_id    VARCHAR(64) NULL,
        priority            VARCHAR(10) NOT NULL DEFAULT 'normal',
        status              VARCHAR(20) NOT NULL DEFAULT 'new',
        due_date            DATE NULL,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_tasks_club (club_id),
        INDEX idx_tasks_assignee (assigned_to_user_id),
        INDEX idx_tasks_creator (created_by_user_id),
        INDEX idx_tasks_player (linked_player_id),
        INDEX idx_tasks_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS task_comments (
        id              INT AUTO_INCREMENT PRIMARY KEY,
        task_id         INT NOT NULL,
        author_user_id  INT NOT NULL,
        comment         TEXT NOT NULL,
        attachment_url  VARCHAR(500) NULL,
        created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_task_comments_task (task_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── In-app notification center (Phase 1 platform expansion) ─────────────
    // Persisted, per-user notifications — separate from
    // NotificationService's local device reminders in the Flutter app
    // (survey nudges), which keep working unchanged. linked_route lets the
    // client jump straight to the relevant screen on tap.
    $pdo->exec("CREATE TABLE IF NOT EXISTS notifications (
        id           INT AUTO_INCREMENT PRIMARY KEY,
        club_id      INT NOT NULL,
        user_id      INT NOT NULL,
        type         VARCHAR(40) NOT NULL,
        title        VARCHAR(200) NOT NULL,
        body         TEXT NULL,
        linked_route VARCHAR(200) NULL,
        is_read      TINYINT(1) NOT NULL DEFAULT 0,
        created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_notifications_user (user_id, is_read),
        INDEX idx_notifications_club (club_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Push notification device tokens ──────────────────────────────────────
    // FCM registration tokens per user/device. A user can have multiple rows
    // (multiple devices); token is unique so re-registering on a new account
    // (shared device) simply reassigns user_id instead of creating a dupe.
    $pdo->exec("CREATE TABLE IF NOT EXISTS device_tokens (
        id         INT AUTO_INCREMENT PRIMARY KEY,
        user_id    INT NOT NULL,
        club_id    INT NULL,
        token      VARCHAR(255) NOT NULL,
        platform   VARCHAR(10) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_device_token (token),
        INDEX idx_device_tokens_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Player status change history (Phase 1 platform expansion) ───────────
    // club_players.status changes in place today with no trail — this adds
    // one without touching the existing column's read/write paths.
    $pdo->exec("CREATE TABLE IF NOT EXISTS player_status_history (
        id                 INT AUTO_INCREMENT PRIMARY KEY,
        player_id          VARCHAR(64) NOT NULL,
        old_status         VARCHAR(30) NULL,
        new_status         VARCHAR(30) NOT NULL,
        changed_by_user_id INT NOT NULL,
        reason             VARCHAR(255) NULL,
        changed_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_status_history_player (player_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Return-to-Play phases (Phase 2 platform expansion) ──────────────────
    // One row per RTP stage per injury_cases row — the 8-stage progression
    // from the original spec (pain/swelling → ROM → strength → balance →
    // running → football-specific → partial training → full return). This
    // sits alongside injury_cases.rtp_stage (a single free-text field) —
    // that field stays the coach-visible "current stage" summary, this
    // table is the detailed phase-by-phase record behind it.
    $pdo->exec("CREATE TABLE IF NOT EXISTS rehabilitation_phases (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        injury_case_id      INT NOT NULL,
        phase_number        TINYINT NOT NULL,
        phase_key           VARCHAR(30) NOT NULL,
        status              VARCHAR(20) NOT NULL DEFAULT 'in_progress',
        start_date          DATE NULL,
        expected_end_date   DATE NULL,
        actual_end_date     DATE NULL,
        goals               TEXT NULL,
        exercises           TEXT NULL,
        completion_percent  TINYINT NOT NULL DEFAULT 0,
        pain_score          TINYINT NULL,
        player_notes        TEXT NULL,
        specialist_notes    TEXT NULL,
        approved_by_user_id INT NULL,
        created_by_user_id  INT NOT NULL,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_rehab_phase_case (injury_case_id, phase_number),
        INDEX idx_rehab_phases_case (injury_case_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Medical attachments (Phase 2 platform expansion) ────────────────────
    // Reference links (images/X-rays/reports already hosted elsewhere) on an
    // injury case — this app has no binary file-upload pipeline anywhere
    // else (photo_url/video_url fields are all URL references too), so this
    // stores a URL + type + description rather than raw file bytes.
    $pdo->exec("CREATE TABLE IF NOT EXISTS medical_attachments (
        id                   INT AUTO_INCREMENT PRIMARY KEY,
        injury_case_id       INT NOT NULL,
        uploaded_by_user_id  INT NOT NULL,
        file_url             VARCHAR(500) NOT NULL,
        file_type            VARCHAR(20) NOT NULL DEFAULT 'other',
        description          VARCHAR(255) NULL,
        created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_medical_attachments_case (injury_case_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Individual program weekly reviews (Phase 3 platform expansion) ──────
    // training_plans already covers the "individual program" itself
    // (owner_type/num_weeks/progression_rules columns, manual creation via
    // api/coach/plans/create-manual.php) — this just adds the weekly
    // completion%/notes review layer that was missing on top of it.
    $pdo->exec("CREATE TABLE IF NOT EXISTS individual_program_reviews (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        plan_id             VARCHAR(64) NOT NULL,
        week_number         TINYINT NOT NULL DEFAULT 1,
        review_date         DATE NOT NULL,
        completion_percent  TINYINT NOT NULL DEFAULT 0,
        coach_notes         TEXT NULL,
        player_feedback     TEXT NULL,
        reviewed_by_user_id INT NOT NULL,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_program_reviews_plan (plan_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Hydration logs (Phase 4 platform expansion) ─────────────────────────
    // Actual daily ml intake — nutrition_profiles.fluid_target_ml and
    // nutrition_day_plans.hydration_before/during/after are targets/
    // instructions only, nothing before this logged what the player actually
    // drank. One row per player per day (self-logged or staff-logged).
    $pdo->exec("CREATE TABLE IF NOT EXISTS hydration_logs (
        id                INT AUTO_INCREMENT PRIMARY KEY,
        club_id           INT NOT NULL,
        player_id         VARCHAR(64) NOT NULL,
        log_date          DATE NOT NULL,
        amount_ml         INT NOT NULL,
        logged_by_user_id INT NOT NULL,
        created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_hydration_log (player_id, log_date),
        INDEX idx_hydration_club (club_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("SET FOREIGN_KEY_CHECKS = 1");
}

function ensureColumn(PDO $pdo, string $table, string $column, string $definition): void {
    // Skip silently if the table doesn't exist yet — ensureSchema creates it later
    $tbl = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?'
    );
    $tbl->execute([$table]);
    if ((int) $tbl->fetchColumn() === 0) return;

    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );
    $stmt->execute([$table, $column]);
    if ((int) $stmt->fetchColumn() === 0) {
        $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$column` $definition");
    }
}

// Widens an existing column's type/nullability when it doesn't already match
// — used to migrate rpe_score/training_load from integer to decimal so RPE
// values like 5.5 (a real value in the reference RPE APR Rwanda sheet)
// survive intact, and to allow NULL where a column must distinguish "not
// entered" from a legitimate recorded zero.
function ensureColumnType(PDO $pdo, string $table, string $column, string $expectedColumnType, bool $expectedNullable, string $alterDefinition): void {
    $tbl = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?'
    );
    $tbl->execute([$table]);
    if ((int) $tbl->fetchColumn() === 0) return;

    $stmt = $pdo->prepare(
        'SELECT COLUMN_TYPE, IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );
    $stmt->execute([$table, $column]);
    $row = $stmt->fetch();
    if ($row === false) return; // column missing entirely — ensureColumn() handles creation

    $typeMatches     = strtolower($row['COLUMN_TYPE']) === strtolower($expectedColumnType);
    $nullableMatches = ($row['IS_NULLABLE'] === 'YES') === $expectedNullable;
    if ($typeMatches && $nullableMatches) return; // already migrated

    $pdo->exec("ALTER TABLE `$table` MODIFY COLUMN `$column` $alterDefinition");
}

function ensureIndex(PDO $pdo, string $table, string $index, string $ddl): void {
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?'
    );
    $stmt->execute([$table, $index]);
    if ((int) $stmt->fetchColumn() === 0) {
        $pdo->exec($ddl);
    }
}

try {
    $allowRuntimeBootstrap = getenv('ALLOW_RUNTIME_SCHEMA_BOOTSTRAP') === '1';
    if ($allowRuntimeBootstrap) {
        $serverPdo = createPdo(
            "mysql:host=$host;charset=utf8mb4",
            $username,
            $password
        );
        $serverPdo->exec("CREATE DATABASE IF NOT EXISTS `$dbname` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    }

    $pdo = createPdo(
        "mysql:host=$host;dbname=$dbname;charset=utf8mb4",
        $username,
        $password
    );
    if ($allowRuntimeBootstrap) {
        ensureSchema($pdo);
    } else {
        require_once __DIR__ . '/includes/runtime_schema.php';
        validateRuntimeSchema($pdo);
    }
} catch (Throwable $e) {
    jsonError('Database connection failed: ' . $e->getMessage());
}

// ── Central CORS — overrides the wildcard set at the top of each API file.
// Mobile apps send no Origin header so CORS doesn't apply to them.
// Browser-based requests (survey, web admin) are restricted to nextkick.me.
(function () {
    $allowed = ['https://nextkick.me', 'https://www.nextkick.me'];
    $origin  = $_SERVER['HTTP_ORIGIN'] ?? '';
    if ($origin !== '' && in_array($origin, $allowed, true)) {
        header("Access-Control-Allow-Origin: $origin");
    } elseif ($origin === '') {
        // Direct call (mobile app) — no origin restriction needed
    } else {
        // Unknown browser origin — deny by not echoing the origin back
        header('Access-Control-Allow-Origin: https://nextkick.me');
    }
})();
