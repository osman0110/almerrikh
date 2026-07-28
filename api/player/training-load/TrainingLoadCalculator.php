<?php
require_once dirname(__DIR__, 2) . '/includes/fitness/FitnessConfig.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/SchemaInspector.php';
require_once dirname(__DIR__, 2) . '/includes/fitness/TrainingLoadDataQuality.php';
/**
 * TrainingLoadCalculator — single source of truth for sRPE / Training
 * Monotony / Training Strain math (RPE APR Rwanda rules).
 *
 * Consumers: api/player/training-load/weekly.php, api/club/team-wellness.php,
 * and any future export/dashboard. Do NOT recompute these formulas anywhere
 * else — call this class instead.
 *
 * Data source of truth: player_rpe (rpe_score, actual_duration_minutes,
 * duration_minutes, training_load, session_id). club_sessions /
 * training_sessions are read ONLY for session date/time/type/name via
 * resolveSession() — never for load math.
 *
 * This class does NOT touch player_hooper_index. ACWR consumes its daily
 * quality output through the central AcwrCalculator.
 */
class TrainingLoadCalculator
{
    const VERSION = '2.0.0-p0-data-quality';
    const DEFAULT_TIMEZONE = FitnessConfig::TIMEZONE;

    // Per-day participation status. Minimum-safe set (see CLAUDE conversation
    // 2026-07-20): PARTICIPATED/ABSENT/INJURED/NO_EXPOSURE require wiring to
    // an attendance/injury system that does not exist yet — deferred to a
    // later phase. For now:
    const DAY_COMPLETE          = 'COMPLETE';           // valid RPE + duration recorded
    const DAY_REST              = 'REST';                // explicitly scheduled rest/recovery only
    const DAY_MISSING_RPE       = 'MISSING_RPE';         // duration present (or attendance confirms presence), RPE missing/invalid
    const DAY_MISSING_DURATION  = 'MISSING_DURATION';    // RPE present, duration missing/invalid
    const DAY_ABSENT            = 'ABSENT';               // session_attendance = 'absent' for a scheduled session that day
    const DAY_UNAVAILABLE       = 'UNAVAILABLE';          // historical status confirms unavailable on this date
    const DAY_MATCH_NO_RPE      = 'MATCH_MISSING_RPE';
    const DAY_NO_RECORD         = 'SCHEDULED_SESSION_MISSING_RECORD';
    const DAY_UNKNOWN           = 'UNKNOWN_DAY_STATUS';
    const DAY_HISTORICAL_UNKNOWN = 'HISTORICAL_STATUS_UNKNOWN';

    const CALC_OK                     = 'OK';
    const CALC_NO_LOAD                = 'NO_LOAD';
    const CALC_CONSTANT_NON_ZERO_LOAD = 'CONSTANT_NON_ZERO_LOAD';

    const COMPLETENESS_COMPLETE   = 'COMPLETE';
    const COMPLETENESS_INCOMPLETE = 'INCOMPLETE';

    // ── Pure math (no DB) — unit-testable in isolation ─────────────────────

    /** session_load = rpe_score × actual_duration_minutes. Returns null if either input is missing/invalid. */
    public static function sessionLoad($rpeScore, $durationMinutes): ?float
    {
        if ($rpeScore === null || $durationMinutes === null) return null;
        $rpe = (float)$rpeScore;
        $dur = (float)$durationMinutes;
        if ($rpe < 0 || $rpe > 10 || $dur < 0) return null;
        return $rpe * $dur;
    }

    /**
     * Core week statistics from exactly 7 ordered daily loads (Mon..Sun).
     * No rounding is applied here — round only at display time.
     */
    public static function computeWeekStats(array $dailyLoads): array
    {
        if (count($dailyLoads) !== 7) {
            throw new InvalidArgumentException('computeWeekStats expects exactly 7 daily loads (Mon..Sun)');
        }
        $loads = array_map('floatval', array_values($dailyLoads));
        $n = 7;
        $weeklyLoad = array_sum($loads);
        $dailyMean  = $weeklyLoad / $n;

        $sumSquaredDiff = 0.0;
        foreach ($loads as $load) {
            $diff = $load - $dailyMean;
            $sumSquaredDiff += $diff * $diff;
        }
        // Sample standard deviation (STDEV.S), divisor n-1 — matches Excel, NOT STDEV.P.
        $variance = $sumSquaredDiff / ($n - 1);
        $stdDev   = sqrt($variance);

        $allZero = $weeklyLoad == 0.0;
        // Treat sd below a tiny epsilon as zero to avoid float noise producing
        // a huge-but-finite monotony instead of the documented ∞ display.
        $sdIsZero = $stdDev < 1e-9;

        if ($sdIsZero) {
            $monotony = null;
            $strain   = null;
            if ($allZero) {
                $status = self::CALC_NO_LOAD;
                $monotonyDisplay = null;
            } else {
                $status = self::CALC_CONSTANT_NON_ZERO_LOAD;
                $monotonyDisplay = '∞';
            }
        } else {
            $monotony = $dailyMean / $stdDev;
            $strain   = $weeklyLoad * $monotony;
            $status   = self::CALC_OK;
            $monotonyDisplay = round($monotony, 2);
        }

        return [
            'weekly_load'          => $weeklyLoad,
            'daily_mean'           => $dailyMean,
            'standard_deviation'   => $stdDev,
            'monotony'             => $monotony,           // full precision, null if undefined
            'strain'               => $strain,             // full precision, null if undefined
            'monotony_display'     => $monotonyDisplay,     // rounded number or "∞" or null
            'calculation_status'   => $status,
        ];
    }

    /** Monday..Sunday calendar-week bounds (inclusive) for the week containing $anyDateInWeek, in $timezone. */
    public static function weekBounds(string $anyDateInWeek, string $timezone = self::DEFAULT_TIMEZONE): array
    {
        $tz = new DateTimeZone($timezone);
        $d  = new DateTime($anyDateInWeek, $tz);
        $isoDow = (int)$d->format('N'); // 1=Mon .. 7=Sun
        $start = (clone $d)->modify('-' . ($isoDow - 1) . ' days');
        $end   = (clone $start)->modify('+6 days');
        return [
            'week_start' => $start->format('Y-m-d'),
            'week_end'   => $end->format('Y-m-d'),
        ];
    }

    // ── Session source resolver (club_sessions vs training_sessions) ───────

    /**
     * Resolve a player_rpe.session_id to its canonical session identity and
     * metadata, deduplicating the two parallel session systems so a session
     * linked via club_sessions.linked_training_session_id is never counted
     * as two different sessions.
     *
     * $cache is an in-memory map keyed by raw session_id, passed by
     * reference so a single weekly report only queries each id once.
     */
    public static function resolveSession(PDO $pdo, ?string $sessionId, array &$cache): array
    {
        if (!$sessionId) {
            return [
                'canonical_key'  => 'row:' . uniqid('', true),
                'session_source' => 'none',
                'session_type'   => null,
                'session_name'   => null,
                'session_date'   => null,
            ];
        }
        if (isset($cache[$sessionId])) return $cache[$sessionId];

        $result = null;

        $stmt = $pdo->prepare('SELECT id, title, type, date, linked_training_session_id FROM club_sessions WHERE id = ? LIMIT 1');
        $stmt->execute([$sessionId]);
        $cs = $stmt->fetch();

        if ($cs) {
            if (!empty($cs['linked_training_session_id'])) {
                // Bridged — canonical identity is the training_sessions row so
                // an RPE logged against either id resolves to the same key.
                $result = [
                    'canonical_key'  => 'ts:' . $cs['linked_training_session_id'],
                    'session_source' => 'club_sessions(linked)',
                    'session_type'   => $cs['type'],
                    'session_name'   => $cs['title'],
                    'session_date'   => $cs['date'],
                ];
            } else {
                $result = [
                    'canonical_key'  => 'cs:' . $cs['id'],
                    'session_source' => 'club_sessions',
                    'session_type'   => $cs['type'],
                    'session_name'   => $cs['title'],
                    'session_date'   => $cs['date'],
                ];
            }
        } else {
            $stmt = $pdo->prepare('SELECT id, title, objective, session_date FROM training_sessions WHERE id = ? LIMIT 1');
            $stmt->execute([$sessionId]);
            $ts = $stmt->fetch();
            if ($ts) {
                $result = [
                    'canonical_key'  => 'ts:' . $ts['id'],
                    'session_source' => 'training_sessions',
                    'session_type'   => $ts['objective'],
                    'session_name'   => $ts['title'],
                    'session_date'   => $ts['session_date'],
                ];
            }
        }

        if ($result === null) {
            $result = [
                'canonical_key'  => 'raw:' . $sessionId,
                'session_source' => 'unknown',
                'session_type'   => null,
                'session_name'   => null,
                'session_date'   => null,
            ];
        }

        $cache[$sessionId] = $result;
        return $result;
    }

    /**
     * Elapsed minutes from session_players.started_at/completed_at for a
     * training_sessions-backed session, as a last-resort duration fallback
     * when the RPE form supplied neither duration_minutes nor
     * actual_duration_minutes. Returns null if the session isn't a
     * training_sessions row, or the player never started/completed it.
     */
    private static function resolveExposureMinutes(
        PDO $pdo, string $canonicalKey, string $linkedPlayerId, array &$cache
    ): ?int {
        if (strpos($canonicalKey, 'ts:') !== 0) return null;
        $tsId = substr($canonicalKey, 3);
        $cacheKey = $tsId . '|' . $linkedPlayerId;
        if (array_key_exists($cacheKey, $cache)) return $cache[$cacheKey];

        $stmt = $pdo->prepare(
            'SELECT started_at, completed_at FROM session_players
             WHERE session_id = ? AND linked_player_id = ? LIMIT 1'
        );
        $stmt->execute([$tsId, $linkedPlayerId]);
        $row = $stmt->fetch();

        $minutes = null;
        if ($row && $row['started_at'] && $row['completed_at']) {
            $diff = strtotime($row['completed_at']) - strtotime($row['started_at']);
            if ($diff > 0) $minutes = (int)round($diff / 60);
        }
        $cache[$cacheKey] = $minutes;
        return $minutes;
    }

    private static function isRestType(?string $sessionType): bool
    {
        if (!$sessionType) return false;
        $t = mb_strtolower($sessionType);
        return (strpos($t, 'rest') !== false) || (strpos($t, 'recovery') !== false);
    }

    // ── DB-backed weekly report ─────────────────────────────────────────────

    /**
     * Build a full calendar-week (Mon..Sun) training-load report for one
     * player, sourced entirely from player_rpe.
     *
     * Scoping note: when a coach logs RPE on behalf of a roster player (the
     * common case — most club players never sign in themselves, see
     * api/player/rpe/save.php), the row's user_id is the COACH's id and
     * linked_player_id (club_players.id) is the actual player. So this scopes
     * by linked_player_id when available, falling back to user_id only for
     * legacy/self-only rows that never had linked_player_id populated.
     *
     * @param string|null $linkedPlayerId club_players.id for this player, if known
     * @param bool $withComparison include a previous_week summary block
     */
    public static function getPlayerWeeklyReport(
        PDO $pdo,
        int $userId,
        ?string $linkedPlayerId,
        string $referenceDate,
        string $timezone = self::DEFAULT_TIMEZONE,
        bool $withComparison = true
    ): array {
        $bounds = self::weekBounds($referenceDate, $timezone);
        $weekStart = $bounds['week_start'];
        $weekEnd   = $bounds['week_end'];
        $tz = new DateTimeZone($timezone);

        // player_rpe.submitted_at is stored in server time (UTC-ish, per
        // existing ACWR logic in dashboard.php). We bucket rows by calendar
        // date in the academy's timezone using CONVERT_TZ would require the
        // DB tz tables; instead we fetch a slightly wider raw window and
        // bucket by PHP DateTime in $timezone for correctness.
        $activeFilter = SchemaInspector::hasColumn($pdo, 'player_rpe', 'is_active_record')
            ? ' AND is_active_record = 1'
            : '';
        $logicalSelect = SchemaInspector::hasColumn($pdo, 'player_rpe', 'logical_key')
            ? ', logical_key'
            : '';
        $stmt = $pdo->prepare(
            'SELECT id, session_id, session_type, rpe_score, duration_minutes,
                    actual_duration_minutes, completed_full_session, training_load,
                    submitted_at, revision_number, last_edited_at' . $logicalSelect . '
             FROM player_rpe
             WHERE (linked_player_id = ? OR (linked_player_id IS NULL AND user_id = ?))
               AND submitted_at >= DATE_SUB(?, INTERVAL 1 DAY)
               AND submitted_at <  DATE_ADD(?, INTERVAL 2 DAY)' . $activeFilter . '
             ORDER BY submitted_at ASC'
        );
        $stmt->execute([$linkedPlayerId, $userId, $weekStart, $weekEnd]);
        $rows = $stmt->fetchAll();

        // ── Disambiguation data for days with no player_rpe row ─────────────────
        // (attendance / injury status / scheduled sessions / match exposure —
        // see class doc comment: this closes the previously-deferred gap).
        $clubId = null;
        $attendanceByDate = [];
        $scheduledDates = [];
        $scheduledRecordsByDate = [];
        $officialRestDates = [];
        $matchMinutesByDate = [];
        $historicalStatusByDate = [];
        $statusHistoryTableExists = SchemaInspector::hasTable($pdo, 'player_status_periods');
        $hasStatusHistory = false;

        if ($linkedPlayerId) {
            $pStmt = $pdo->prepare('SELECT club_id FROM club_players WHERE id = ?');
            $pStmt->execute([$linkedPlayerId]);
            $pRow = $pStmt->fetch();
            if ($pRow) {
                $clubId = $pRow['club_id'] !== null ? (int)$pRow['club_id'] : null;
            }

            if ($statusHistoryTableExists) {
                $hStmt = $pdo->prepare(
                    'SELECT status, effective_from, effective_to
                     FROM player_status_periods
                     WHERE player_id = ? AND effective_from <= ?
                       AND (effective_to IS NULL OR effective_to >= ?)'
                );
                $hStmt->execute([$linkedPlayerId, $weekEnd, $weekStart]);
                $historyRows = $hStmt->fetchAll();
                $hasStatusHistory = !empty($historyRows);
                foreach ($historyRows as $history) {
                    $fromDate = max($weekStart, substr((string)$history['effective_from'], 0, 10));
                    $toDate = min(
                        $weekEnd,
                        $history['effective_to'] ? substr((string)$history['effective_to'], 0, 10) : $weekEnd
                    );
                    $cursor = new DateTimeImmutable($fromDate, $tz);
                    $last = new DateTimeImmutable($toDate, $tz);
                    while ($cursor <= $last) {
                        $historicalStatusByDate[$cursor->format('Y-m-d')] = $history['status'];
                        $cursor = $cursor->modify('+1 day');
                    }
                }
            }

            $aStmt = $pdo->prepare(
                'SELECT cs.date, sa.status FROM session_attendance sa
                 JOIN club_sessions cs ON cs.id = sa.session_id
                 WHERE sa.player_id = ? AND cs.date BETWEEN ? AND ?'
            );
            $aStmt->execute([$linkedPlayerId, $weekStart, $weekEnd]);
            foreach ($aStmt->fetchAll() as $a) {
                $attendanceByDate[$a['date']] = $a['status'];
            }

            if ($clubId) {
                $csStmt = $pdo->prepare(
                    'SELECT id, date, type, linked_training_session_id
                     FROM club_sessions WHERE club_id = ? AND date BETWEEN ? AND ?'
                );
                $csStmt->execute([$clubId, $weekStart, $weekEnd]);
                $scheduledKeys = [];
                foreach ($csStmt->fetchAll() as $r) {
                    $scheduledDates[$r['date']] = true;
                    $key = !empty($r['linked_training_session_id'])
                        ? 'ts:' . $r['linked_training_session_id']
                        : 'cs:' . $r['id'];
                    $scheduledKeys[$r['date']][$key] = true;
                    if (self::isRestType($r['type'])) $officialRestDates[$r['date']] = true;
                }

                $tsStmt = $pdo->prepare(
                    'SELECT id, session_date, objective
                     FROM training_sessions WHERE club_id = ? AND session_date BETWEEN ? AND ?'
                );
                $tsStmt->execute([$clubId, $weekStart, $weekEnd]);
                foreach ($tsStmt->fetchAll() as $r) {
                    $scheduledDates[$r['session_date']] = true;
                    $scheduledKeys[$r['session_date']]['ts:' . $r['id']] = true;
                    if (self::isRestType($r['objective'])) $officialRestDates[$r['session_date']] = true;
                }
                foreach ($scheduledKeys as $date => $keys) {
                    $scheduledRecordsByDate[$date] = count($keys);
                }

                $mStmt = $pdo->prepare('SELECT match_date, player_minutes FROM matches WHERE club_id = ? AND match_date BETWEEN ? AND ?');
                $mStmt->execute([$clubId, $weekStart, $weekEnd]);
                foreach ($mStmt->fetchAll() as $m) {
                    $minutes = json_decode($m['player_minutes'] ?? '{}', true) ?? [];
                    $mins = (float)($minutes[$linkedPlayerId] ?? 0);
                    if ($mins > 0) $matchMinutesByDate[$m['match_date']] = $mins;
                }
            }
        }

        // Bucket by calendar date (in $timezone) and filter to [weekStart, weekEnd]
        $byDate = [];
        for ($i = 0; $i < 7; $i++) {
            $d = (new DateTime($weekStart, $tz))->modify("+{$i} days")->format('Y-m-d');
            $byDate[$d] = [];
        }

        $sessionCache = [];
        $exposureCache = [];
        foreach ($rows as $row) {
            $submitted = new DateTime($row['submitted_at'], new DateTimeZone('UTC'));
            $submitted->setTimezone($tz);
            $dateKey = $submitted->format('Y-m-d');
            if (!array_key_exists($dateKey, $byDate)) continue; // outside this calendar week

            $resolved = self::resolveSession($pdo, $row['session_id'], $sessionCache);
            if (!$row['session_id'] && !empty($row['logical_key'])) {
                $resolved['canonical_key'] = 'logical:' . $row['logical_key'];
            }

            $effectiveDuration = (!(int)$row['completed_full_session'] && $row['actual_duration_minutes'] !== null)
                ? $row['actual_duration_minutes']
                : $row['duration_minutes'];

            // Last-resort fallback: neither duration field was submitted with the
            // RPE, but the pre-check/start/complete flow already recorded real
            // check-in/out timestamps for this session — use elapsed minutes
            // rather than leaving the day MISSING_DURATION. Never overrides a
            // duration the RPE form actually supplied.
            $durationFromExposure = false;
            if ($effectiveDuration === null && $row['duration_minutes'] === null && $linkedPlayerId) {
                $effectiveDuration = self::resolveExposureMinutes(
                    $pdo, $resolved['canonical_key'], $linkedPlayerId, $exposureCache
                );
                $durationFromExposure = $effectiveDuration !== null;
            }

            $rpeValid      = $row['rpe_score'] !== null
                && (float)$row['rpe_score'] >= 0
                && (float)$row['rpe_score'] <= 10;
            $durationValid = $effectiveDuration !== null && (float)$effectiveDuration > 0
                && ($row['duration_minutes'] !== null || $durationFromExposure);

            $sessionLoad = ($rpeValid && $durationValid)
                ? self::sessionLoad($row['rpe_score'], $effectiveDuration)
                : null;

            $byDate[$dateKey][] = [
                'rpe_row_id'      => (int)$row['id'],
                'canonical_key'   => $resolved['canonical_key'],
                'session_id'      => $row['session_id'],
                'session_source'  => $resolved['session_source'],
                'session_type'    => $resolved['session_type'] ?? $row['session_type'],
                'session_name'    => $resolved['session_name'],
                'rpe'             => $rpeValid ? (float)$row['rpe_score'] : null,
                'actual_duration_minutes' => $durationValid ? (int)$effectiveDuration : null,
                'session_load'    => $sessionLoad,
                'submitted_at'    => $row['submitted_at'],
                'record_status'   => (int)($row['revision_number'] ?? 1) > 1
                    ? 'edited'
                    : 'original',
                'last_edited_at'  => $row['last_edited_at'] ?? null,
                'rpe_valid'       => $rpeValid,
                'duration_valid'  => $durationValid,
                'rpe_issue'       => $row['rpe_score'] === null ? 'MISSING_RPE' : ($rpeValid ? null : 'INVALID_RPE'),
                'duration_issue'  => $effectiveDuration === null
                    ? (!(int)$row['completed_full_session']
                        ? 'PARTIAL_SESSION_MISSING_DURATION'
                        : 'MISSING_DURATION')
                    : ($durationValid ? null : 'INVALID_DURATION'),
            ];
        }

        $dailyLoadsOrdered = [];
        $days = [];
        $missingFields = [];
        $dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

        $i = 0;
        foreach ($byDate as $date => $entries) {
            // De-duplicate: if two RPE rows resolve to the SAME real session
            // (e.g. logged once against club_sessions.id and once against its
            // linked_training_session_id), keep only the most recently
            // submitted one so the session is never counted twice.
            $bySession = [];
            $duplicateDetected = false;
            foreach ($entries as $e) {
                $key = $e['canonical_key'];
                if (isset($bySession[$key])) $duplicateDetected = true;
                if (!isset($bySession[$key]) || $e['submitted_at'] > $bySession[$key]['submitted_at']) {
                    $bySession[$key] = $e;
                }
            }
            $sessions = array_values($bySession);

            $dailyLoad = 0.0;
            $hasMissingRpe = false;
            $hasMissingDuration = false;
            $issues = [];
            foreach ($sessions as $s) {
                if ($s['session_load'] !== null) {
                    $dailyLoad += $s['session_load'];
                } else {
                    if (!$s['rpe_valid']) {
                        $hasMissingRpe = true;
                        $issues[] = $s['rpe_issue'];
                    }
                    if (!$s['duration_valid']) {
                        $hasMissingDuration = true;
                        $issues[] = $s['duration_issue'];
                    }
                }
            }
            if ($duplicateDetected) $issues[] = 'DUPLICATE_RPE';

            if (count($sessions) === 0) {
                $status = self::resolveNoRecordDayStatus(
                    $date,
                    $hasStatusHistory,
                    $historicalStatusByDate,
                    $attendanceByDate,
                    $scheduledDates,
                    $officialRestDates,
                    $matchMinutesByDate
                );
                if (in_array($status, [
                    self::DAY_MISSING_RPE,
                    self::DAY_MATCH_NO_RPE,
                    self::DAY_NO_RECORD,
                    self::DAY_UNKNOWN,
                    self::DAY_HISTORICAL_UNKNOWN,
                ], true)) $issues[] = $status;
                if ($status === self::DAY_NO_RECORD && !isset($attendanceByDate[$date])) {
                    $issues[] = 'UNRESOLVED_ATTENDANCE';
                }
            } elseif ($hasMissingRpe) {
                $status = self::DAY_MISSING_RPE;
            } elseif ($hasMissingDuration) {
                $status = self::DAY_MISSING_DURATION;
            } elseif ($dailyLoad == 0.0 && self::anyRestType($sessions)) {
                $status = self::DAY_REST;
            } else {
                $status = self::DAY_COMPLETE;
            }

            $issues = array_values(array_unique(array_filter($issues)));
            foreach ($issues as $issue) {
                $missingFields[] = ['date' => $date, 'status' => $issue];
            }

            $expectedRecords = max(
                count($sessions),
                (int)($scheduledRecordsByDate[$date] ?? 0),
                isset($matchMinutesByDate[$date]) ? 1 : 0
            );
            $completedRecords = count(array_filter(
                $sessions,
                fn(array $session) => $session['session_load'] !== null
            ));
            if (in_array($status, [self::DAY_REST, self::DAY_ABSENT, self::DAY_UNAVAILABLE], true)) {
                $completedRecords = $expectedRecords;
            }

            $days[] = [
                'date'                => $date,
                'day_name'            => $dayNames[$i],
                'daily_load'          => $dailyLoad,
                'participation_status'=> $status,
                'sessions_count'      => count($sessions),
                'expected_records'    => $expectedRecords,
                'completed_records'   => $completedRecords,
                'data_quality_issues' => $issues,
                'sessions'            => array_map(function ($s) {
                    return [
                        'session_id'              => $s['session_id'],
                        'session_source'           => $s['session_source'],
                        'session_type'             => $s['session_type'],
                        'session_name'             => $s['session_name'],
                        'rpe'                      => $s['rpe'],
                        'actual_duration_minutes'  => $s['actual_duration_minutes'],
                        'session_load'             => $s['session_load'],
                    ];
                }, $sessions),
            ];

            $dailyLoadsOrdered[] = $dailyLoad;
            $i++;
        }

        $stats = self::computeWeekStats($dailyLoadsOrdered);
        $dataQuality = TrainingLoadDataQuality::summarize($days);
        $completeness = $dataQuality['report_approvable']
            ? self::COMPLETENESS_COMPLETE
            : self::COMPLETENESS_INCOMPLETE;
        if (!$dataQuality['can_calculate_monotony_strain']) {
            $preliminaryStats = $stats;
            $stats['monotony'] = null;
            $stats['strain'] = null;
            $stats['monotony_display'] = null;
            $stats['calculation_status'] = 'INCOMPLETE_DATA';
        } else {
            $preliminaryStats = null;
        }

        $report = [
            'week_start'                => $weekStart,
            'week_end'                  => $weekEnd,
            'timezone'                  => $timezone,
            'calculation_method_version'=> self::VERSION,
            'days'                      => $days,
            'weekly_load'               => $stats['weekly_load'],
            'daily_mean'                => $stats['daily_mean'],
            'standard_deviation'        => $stats['standard_deviation'],
            'monotony'                  => $stats['monotony'],
            'strain'                    => $stats['strain'],
            'monotony_display'          => $stats['monotony_display'],
            'calculation_status'        => $stats['calculation_status'],
            'completeness_status'       => $completeness,
            'missing_fields'            => $missingFields,
            'data_quality'              => $dataQuality,
            'preliminary_stats'         => $preliminaryStats,
        ];

        if ($withComparison) {
            $prevRefDate = (new DateTime($weekStart, $tz))->modify('-7 days')->format('Y-m-d');
            $prevReport = self::getPlayerWeeklyReport($pdo, $userId, $linkedPlayerId, $prevRefDate, $timezone, false);
            $report['previous_week'] = [
                'week_start'  => $prevReport['week_start'],
                'week_end'    => $prevReport['week_end'],
                'weekly_load' => $prevReport['weekly_load'],
                'monotony'    => $prevReport['monotony'],
                'strain'      => $prevReport['strain'],
                'change_percent' => ($prevReport['weekly_load'] > 0)
                    ? (($stats['weekly_load'] - $prevReport['weekly_load']) / $prevReport['weekly_load']) * 100.0
                    : null,
            ];
        }

        return $report;
    }

    private static function anyRestType(array $sessions): bool
    {
        foreach ($sessions as $s) {
            if (self::isRestType($s['session_type'])) return true;
        }
        return false;
    }

    /**
     * Disambiguates a day with zero player_rpe rows using attendance/injury/
     * schedule/match data, instead of always falling back to the ambiguous
     * DAY_NO_RECORD. See class doc comment for the resolution order.
     */
    private static function resolveNoRecordDayStatus(
        string $date,
        bool $hasStatusHistory,
        array $historicalStatusByDate,
        array $attendanceByDate,
        array $scheduledDates,
        array $officialRestDates,
        array $matchMinutesByDate
    ): string {
        $historicalStatus = $historicalStatusByDate[$date] ?? null;
        if ($historicalStatus !== null && in_array($historicalStatus, ['injured', 'recovering', 'suspended'], true)) {
            return self::DAY_UNAVAILABLE;
        }
        if (($attendanceByDate[$date] ?? null) === 'absent') {
            return self::DAY_ABSENT;
        }
        if (in_array($attendanceByDate[$date] ?? null, ['present', 'late'], true)) {
            return self::DAY_MISSING_RPE;
        }
        if (($matchMinutesByDate[$date] ?? 0) > 0) {
            return self::DAY_MATCH_NO_RPE;
        }
        if (isset($officialRestDates[$date])) {
            return self::DAY_REST;
        }
        if (isset($scheduledDates[$date])) return self::DAY_NO_RECORD;
        if (!$hasStatusHistory) return self::DAY_HISTORICAL_UNKNOWN;
        // Nothing scheduled, no attendance, no match, and the roster history
        // confirms the player was active that day — this is an ordinary day
        // off, not a data gap. Treating it as REST (load 0, no issue) instead
        // of UNKNOWN lets ACWR actually compute across a normal 28-day window
        // instead of requiring every single day to have an explicit record.
        return self::DAY_REST;
    }
}
