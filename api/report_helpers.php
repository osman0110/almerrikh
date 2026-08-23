<?php
// Shared data helpers for Phase 6A report endpoints.
// Auth helpers use function_exists guards for safe inclusion alongside existing files.

if (!function_exists('jsonOut')) {
    function jsonOut(array $data, int $code = 200): void {
        http_response_code($code);
        echo json_encode($data, JSON_UNESCAPED_UNICODE);
        exit;
    }
}

require_once __DIR__ . '/includes/club_auth.php';
require_once __DIR__ . '/includes/fitness/BodyCompositionRepository.php';

function rptActiveRpeFilter(PDO $pdo, string $alias = ''): string {
    if (!SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')) return '';
    return ' AND ' . ($alias !== '' ? $alias . '.' : '') . 'is_active_record = 1';
}

if (!function_exists('bearerToken')) {
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
}

// Returns id, role, linked_player_id, club_user_id
function rptAuthUser(PDO $pdo): array {
    $token = bearerToken();
    if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
    $stmt = $pdo->prepare(
        'SELECT u.id, u.role, u.linked_player_id, u.club_user_id
         FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
    );
    $stmt->execute([$token]);
    $u = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$u) jsonOut(['error' => 'Invalid or expired token'], 401);
    return $u;
}

// Verify a player_id belongs to this coach/club/academy scope.
// Blocks independent players. Exits 403 if not found.
function rptScopedPlayer(PDO $pdo, string $playerId, int $clubId): array {
    $stmt = $pdo->prepare(
        "SELECT id, name, position, team_name, player_type, linked_user_id
         FROM club_players
         WHERE id = ? AND club_id = ? AND is_active = 1
           AND (player_type IS NULL OR player_type != 'independent')"
    );
    $stmt->execute([$playerId, $clubId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) jsonOut(['error' => 'Player not found or access denied'], 403);
    return $row;
}

// Latest body metrics for a player by their linked user account ID.
function rptBodyMetrics(PDO $pdo, ?int $linkedUserId, ?string $linkedPlayerId = null): array {
    $empty = [
        'latest_weight'         => null,
        'latest_height'         => null,
        'latest_fat_percentage' => null,
        'latest_bmi'            => null,
        'latest_lean_body_mass' => null,
    ];
    $m = BodyCompositionRepository::latestForPlayer($pdo, $linkedPlayerId, $linkedUserId, true);
    if (!$m) return $empty;
    return [
        'latest_weight'         => $m['weight_kg']        !== null ? (float)$m['weight_kg']        : null,
        'latest_height'         => $m['height_cm']        !== null ? (float)$m['height_cm']        : null,
        'latest_fat_percentage' => $m['body_fat_percentage'] !== null ? (float)$m['body_fat_percentage'] : null,
        'latest_bmi'            => $m['raw']['bmi'] !== null ? (float)$m['raw']['bmi'] : null,
        'latest_lean_body_mass' => $m['fat_free_mass_kg'],
        'latest_muscle_mass'    => $m['muscle_mass_kg'],
        'source_system'         => $m['source_system'],
    ];
}

// Hooper score trend by linked_player_id, chronological order (oldest→newest).
function rptHooperTrend(PDO $pdo, string $linkedPlayerId, int $limit = 30): array {
    $stmt = $pdo->prepare(
        'SELECT DATE(submitted_at) AS date, hooper_score AS score
         FROM player_hooper_index WHERE linked_player_id = ?
         ORDER BY submitted_at DESC LIMIT ?'
    );
    $stmt->execute([$linkedPlayerId, $limit]);
    $rows = array_reverse($stmt->fetchAll(PDO::FETCH_ASSOC));
    $out = [];
    foreach ($rows as $r) {
        $out[] = ['date' => $r['date'], 'score' => (int)$r['score']];
    }
    return $out;
}

// Pre/post RPE trend by linked_player_id, grouped by day, chronological order.
function rptRpeTrend(PDO $pdo, string $linkedPlayerId, int $limit = 30): array {
    $activeFilter = rptActiveRpeFilter($pdo);
    $stmt = $pdo->prepare(
        "SELECT DATE(submitted_at) AS date,
                MAX(CASE WHEN rpe_type = 'pre'  THEN rpe_score END) AS pre_rpe,
                MAX(CASE WHEN rpe_type = 'post' THEN rpe_score END) AS post_rpe
         FROM player_rpe WHERE linked_player_id = ?$activeFilter
         GROUP BY DATE(submitted_at)
         ORDER BY date DESC LIMIT ?"
    );
    $stmt->execute([$linkedPlayerId, $limit]);
    $rows = array_reverse($stmt->fetchAll(PDO::FETCH_ASSOC));
    $out = [];
    foreach ($rows as $r) {
        $out[] = [
            'date'     => $r['date'],
            'pre_rpe'  => $r['pre_rpe']  !== null ? (float)$r['pre_rpe']  : null,
            'post_rpe' => $r['post_rpe'] !== null ? (float)$r['post_rpe'] : null,
        ];
    }
    return $out;
}

// Assessment history for a club player (newest first), basic fields for player.php.
function rptAssessmentHistory(PDO $pdo, string $playerId, int $clubId, int $limit = 30): array {
    $stmt = $pdo->prepare(
        'SELECT DATE(created_at) AS date, type AS assessment_type,
                overall_score, stability_score, symmetry_score, control_score
         FROM assessments WHERE player_id = ? AND club_id = ?
         ORDER BY created_at DESC LIMIT ?'
    );
    $stmt->execute([$playerId, $clubId, $limit]);
    $out = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $out[] = [
            'date'            => $r['date'],
            'assessment_type' => $r['assessment_type'],
            'overall_score'   => (int)$r['overall_score'],
            'stability_score' => (int)$r['stability_score'],
            'symmetry_score'  => (int)$r['symmetry_score'],
            'control_score'   => (int)$r['control_score'],
        ];
    }
    return $out;
}

// Full assessment list with all score fields (for assessments.php endpoint).
function rptFullAssessmentList(PDO $pdo, string $playerId, int $clubId, int $limit = 30): array {
    $stmt = $pdo->prepare(
        'SELECT DATE(created_at) AS date, type AS assessment_type,
                overall_score, movement_quality_score AS movement_score,
                stability_score, symmetry_score, control_score, quality_score
         FROM assessments WHERE player_id = ? AND club_id = ?
         ORDER BY created_at DESC LIMIT ?'
    );
    $stmt->execute([$playerId, $clubId, $limit]);
    $out = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $out[] = [
            'date'            => $r['date'],
            'assessment_type' => $r['assessment_type'],
            'overall_score'   => (int)$r['overall_score'],
            'movement_score'  => (int)$r['movement_score'],
            'stability_score' => (int)$r['stability_score'],
            'symmetry_score'  => (int)$r['symmetry_score'],
            'control_score'   => (int)$r['control_score'],
            'quality_score'   => (int)$r['quality_score'],
        ];
    }
    return $out;
}

// Session history for a player scoped to a club (newest first).
function rptSessionHistory(PDO $pdo, string $linkedPlayerId, int $clubId, int $limit = 30): array {
    $stmt = $pdo->prepare(
        'SELECT ts.session_date AS date, ts.title, sp.status, ts.duration_minutes
         FROM session_players sp
         JOIN training_sessions ts ON sp.session_id = ts.id
         WHERE sp.linked_player_id = ?
           AND ts.club_id = ?
         ORDER BY ts.session_date DESC LIMIT ?'
    );
    $stmt->execute([$linkedPlayerId, $clubId, $limit]);
    $out = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $out[] = [
            'date'             => $r['date'],
            'title'            => $r['title'],
            'status'           => $r['status'],
            'duration_minutes' => (int)$r['duration_minutes'],
        ];
    }
    return $out;
}

// Summary for a scoped player. Defaults to the original 30-day window (7-day
// for training load) when $from/$to aren't given — pass both to make every
// figure share one custom range instead (used by coach/reports/team.php's
// date-range picker).
function rptPlayerSummary(
    PDO $pdo, string $linkedPlayerId, string $assessmentPlayerId, int $clubId,
    ?string $from = null, ?string $to = null
): array {
    $customRange = $from !== null && $to !== null;
    $since30 = $customRange ? "$from 00:00:00" : date('Y-m-d H:i:s', strtotime('-30 days'));
    $since7  = $customRange ? "$from 00:00:00" : date('Y-m-d H:i:s', strtotime('-7 days'));
    $until   = $customRange ? "$to 23:59:59"   : null;
    $periodDays = $customRange
        ? ((new DateTimeImmutable($from))->diff(new DateTimeImmutable($to))->days + 1)
        : 7;

    // Completion rate
    $stmt = $pdo->prepare(
        "SELECT COUNT(*) AS total,
                SUM(CASE WHEN sp.status IN ('completed','pre_checked','started') THEN 1 ELSE 0 END) AS done
         FROM session_players sp
         INNER JOIN training_sessions ts ON sp.session_id = ts.id
         WHERE sp.linked_player_id = ?
           AND ts.club_id = ?
           AND ts.session_date >= ?" . ($until ? ' AND ts.session_date <= ?' : '')
    );
    $stmt->execute($until ? [$linkedPlayerId, $clubId, $since30, $to] : [$linkedPlayerId, $clubId, $since30]);
    $row   = $stmt->fetch(PDO::FETCH_ASSOC);
    $total = (int)($row['total'] ?? 0);
    $done  = (int)($row['done']  ?? 0);

    // Avg hooper
    $stmt = $pdo->prepare(
        'SELECT AVG(hooper_score) FROM player_hooper_index WHERE linked_player_id = ? AND submitted_at >= ?'
        . ($until ? ' AND submitted_at <= ?' : '')
    );
    $stmt->execute($until ? [$linkedPlayerId, $since30, $until] : [$linkedPlayerId, $since30]);
    $v = $stmt->fetchColumn();
    $avgHooper = ($v !== false && $v !== null) ? round((float)$v, 1) : null;

    // Avg post RPE
    $activeRpeFilter = rptActiveRpeFilter($pdo);
    $stmt = $pdo->prepare(
        "SELECT AVG(rpe_score) FROM player_rpe WHERE linked_player_id = ? AND rpe_type = 'post' AND submitted_at >= ?$activeRpeFilter"
        . ($until ? ' AND submitted_at <= ?' : '')
    );
    $stmt->execute($until ? [$linkedPlayerId, $since30, $until] : [$linkedPlayerId, $since30]);
    $v = $stmt->fetchColumn();
    $avgRpe = ($v !== false && $v !== null) ? round((float)$v, 1) : null;

    // Training load
    $stmt = $pdo->prepare(
        "SELECT COALESCE(SUM(training_load), 0) FROM player_rpe WHERE linked_player_id = ? AND submitted_at >= ?$activeRpeFilter"
        . ($until ? ' AND submitted_at <= ?' : '')
    );
    $stmt->execute($until ? [$linkedPlayerId, $since7, $until] : [$linkedPlayerId, $since7]);
    $load7d = (int)$stmt->fetchColumn();

    // Pain reports
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM player_hooper_index WHERE linked_player_id = ? AND pain_today = 1 AND submitted_at >= ?'
        . ($until ? ' AND submitted_at <= ?' : '')
    );
    $stmt->execute($until ? [$linkedPlayerId, $since30, $until] : [$linkedPlayerId, $since30]);
    $painCount = (int)$stmt->fetchColumn();

    // Best assessment score (club-scoped, all-time regardless of range —
    // "best ever" is more useful here than "best in range")
    $stmt = $pdo->prepare(
        'SELECT MAX(overall_score) FROM assessments WHERE player_id = ? AND club_id = ?'
    );
    $stmt->execute([$assessmentPlayerId, $clubId]);
    $v = $stmt->fetchColumn();
    $bestScore = ($v !== false && $v !== null) ? (int)$v : null;

    return [
        'completion_rate_30d'   => $total > 0 ? round($done / $total * 100) : 0,
        'average_hooper_30d'    => $avgHooper,
        'average_post_rpe_30d'  => $avgRpe,
        // Keep the legacy 7-day field only for the default 7-day summary.
        // Custom ranges use the explicit period field so they cannot be
        // displayed as 7-day load.
        'training_load_7d'      => $customRange ? null : $load7d,
        'training_load_period'  => $load7d,
        'training_load_period_days' => $periodDays,
        'pain_reports_30d'      => $painCount,
        'best_assessment_score' => $bestScore,
    ];
}

// Trend from newest-first assessment list (compare last 2).
function rptAssessmentTrend(array $assessments): string {
    if (count($assessments) < 2) return 'insufficient_data';
    $diff = (int)$assessments[0]['overall_score'] - (int)$assessments[1]['overall_score'];
    if ($diff >= 5)  return 'improving';
    if ($diff <= -5) return 'declining';
    return 'stable';
}
