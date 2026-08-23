<?php
/**
 * Server-side notification text translation.
 *
 * Notifications are triggered by whichever staff member happens to be using
 * the app at that moment, but the recipient reading them may have a
 * different language selected. This renders a stable "type" + param bag
 * into the recipient's own language (ar/en/fr) instead of shipping whatever
 * language the trigger happened to be hardcoded in.
 *
 * Free-text content the coach/staff actually typed (an injury note, a task
 * description, a chat comment) is never machine-translated — only the
 * surrounding template wording is.
 */

/** Reads and caches the recipient's preferred language for this request. */
function notificationLang(PDO $pdo, int $userId): string {
    static $cache = [];
    if (array_key_exists($userId, $cache)) return $cache[$userId];
    $stmt = $pdo->prepare('SELECT language FROM users WHERE id = ?');
    $stmt->execute([$userId]);
    $lang = $stmt->fetchColumn();
    $lang = in_array($lang, ['ar', 'en', 'fr'], true) ? $lang : 'ar';
    return $cache[$userId] = $lang;
}

// Mirrors RTP_PHASES in api/club/rehab_phases.php (phase number → coded key).
// Duplicated locally so this file has no load-order dependency on that one.
const RTP_PHASE_NUMBER_KEYS = [
    1 => 'pain_control',
    2 => 'rom',
    3 => 'strength',
    4 => 'balance_control',
    5 => 'running',
    6 => 'football_specific',
    7 => 'partial_training',
    8 => 'full_return',
];

const RTP_PHASE_LABELS = [
    'pain_control'       => ['ar' => 'التحكم بالألم',            'en' => 'Pain control',            'fr' => 'Contrôle de la douleur'],
    'rom'                => ['ar' => 'مدى الحركة',               'en' => 'Range of motion',          'fr' => 'Amplitude de mouvement'],
    'strength'           => ['ar' => 'القوة',                    'en' => 'Strength',                 'fr' => 'Force'],
    'balance_control'    => ['ar' => 'التوازن والتحكم',           'en' => 'Balance & control',        'fr' => 'Équilibre et contrôle'],
    'running'            => ['ar' => 'الجري',                    'en' => 'Running',                  'fr' => 'Course'],
    'football_specific'  => ['ar' => 'تدريبات خاصة بكرة القدم',   'en' => 'Football-specific drills',  'fr' => 'Exercices spécifiques au football'],
    'partial_training'   => ['ar' => 'تدريب جزئي',                'en' => 'Partial training',         'fr' => 'Entraînement partiel'],
    'full_return'        => ['ar' => 'عودة كاملة',                'en' => 'Full return',              'fr' => 'Retour complet'],
];

const PHYSIO_REASON_LABELS = [
    'recovery'         => ['ar' => 'استشفاء',        'en' => 'Recovery',        'fr' => 'Récupération'],
    'pain'             => ['ar' => 'ألم',            'en' => 'Pain',            'fr' => 'Douleur'],
    'muscle_tightness' => ['ar' => 'شد عضلي',        'en' => 'Muscle tightness', 'fr' => 'Tension musculaire'],
    'pre_match'        => ['ar' => 'قبل المباراة',    'en' => 'Pre-match',       'fr' => 'Avant-match'],
    'post_match'       => ['ar' => 'بعد المباراة',    'en' => 'Post-match',      'fr' => 'Après-match'],
];

function rtpPhaseLabel(?int $phaseNumber, string $lang): string {
    $key = RTP_PHASE_NUMBER_KEYS[$phaseNumber] ?? null;
    if (!$key) return '';
    return RTP_PHASE_LABELS[$key][$lang] ?? RTP_PHASE_LABELS[$key]['ar'] ?? $key;
}

function physioReasonLabel(string $reason, string $lang): string {
    return PHYSIO_REASON_LABELS[$reason][$lang] ?? PHYSIO_REASON_LABELS[$reason]['ar'] ?? $reason;
}

/**
 * Renders a notification's title/body for one recipient language.
 * $params holds whatever the template needs — dates, names, counts, plus
 * any raw free-text ($params['raw_body']) that should pass through
 * untranslated.
 */
function notificationText(string $type, array $params, string $lang): array {
    $p = static fn(string $key): string => (string)($params[$key] ?? '');

    switch ($type) {
        case 'readiness_reminder':
            return match ($lang) {
                'en' => ['title' => 'Daily readiness reminder', 'body' => "Please submit your readiness for {$p('date')}."],
                'fr' => ['title' => 'Rappel de disponibilité quotidienne', 'body' => "Merci de soumettre votre disponibilité du {$p('date')}."],
                default => ['title' => 'تذكير الجاهزية اليومية', 'body' => "يرجى تسجيل الجاهزية لليوم {$p('date')}."],
            };

        case 'session_scheduled':
            return match ($lang) {
                'en' => ['title' => 'Training session scheduled', 'body' => "{$p('title')} — {$p('when')}"],
                'fr' => ['title' => 'Séance d\'entraînement programmée', 'body' => "{$p('title')} — {$p('when')}"],
                default => ['title' => 'تم جدولة جلسة تدريبية', 'body' => "{$p('title')} — {$p('when')}"],
            };

        case 'session_scheduled_coach':
            return match ($lang) {
                'en' => ['title' => 'New session scheduled', 'body' => "{$p('title')} — {$p('when')}"],
                'fr' => ['title' => 'Nouvelle séance programmée', 'body' => "{$p('title')} — {$p('when')}"],
                default => ['title' => 'تم جدولة جلسة جديدة', 'body' => "{$p('title')} — {$p('when')}"],
            };

        case 'injury_created':
            return match ($lang) {
                'en' => ['title' => "New injury: {$p('player_name')}", 'body' => $p('raw_body')],
                'fr' => ['title' => "Nouvelle blessure : {$p('player_name')}", 'body' => $p('raw_body')],
                default => ['title' => 'إصابة جديدة: ' . $p('player_name'), 'body' => $p('raw_body')],
            };

        case 'rtp_phase_completed':
        case 'rtp_phase_started':
            $completed = $type === 'rtp_phase_completed';
            $eventLabel = match ($lang) {
                'en' => $completed ? 'Phase completed' : 'New phase started',
                'fr' => $completed ? 'Phase terminée' : 'Nouvelle phase commencée',
                default => $completed ? 'مرحلة مكتملة' : 'مرحلة جديدة بدأت',
            };
            $phaseLabel = rtpPhaseLabel($params['phase_number'] ?? null, $lang);
            $phaseWord = match ($lang) {
                'en' => 'Phase',
                'fr' => 'Phase',
                default => 'المرحلة',
            };
            return [
                'title' => "$eventLabel: {$p('player_name')}",
                'body' => "$phaseWord {$p('phase_number')} — $phaseLabel",
            ];

        case 'physio_session_scheduled':
            $reasonLabel = physioReasonLabel($p('reason'), $lang);
            return match ($lang) {
                'en' => ['title' => 'Physio session booked', 'body' => "$reasonLabel session at {$p('scheduled_at')}"],
                'fr' => ['title' => 'Séance de kiné réservée', 'body' => "Séance de $reasonLabel à {$p('scheduled_at')}"],
                default => ['title' => 'تم حجز جلسة علاج طبيعي', 'body' => "جلسة $reasonLabel في {$p('scheduled_at')}"],
            };

        case 'physio_session_assigned':
            $count = (int)($params['player_count'] ?? 1);
            return match ($lang) {
                'en' => [
                    'title' => 'New physio session assigned',
                    'body' => $count > 1 ? "Session for $count players at {$p('scheduled_at')}" : "Session at {$p('scheduled_at')}",
                ],
                'fr' => [
                    'title' => 'Nouvelle séance de kiné assignée',
                    'body' => $count > 1 ? "Séance pour $count joueurs à {$p('scheduled_at')}" : "Séance à {$p('scheduled_at')}",
                ],
                default => [
                    'title' => 'تم تعيين جلسة علاج طبيعي جديدة',
                    'body' => $count > 1 ? "جلسة لعدد $count لاعبين في {$p('scheduled_at')}" : "جلسة في {$p('scheduled_at')}",
                ],
            };

        case 'physio_session_updated':
            $cancelled = ($params['status'] ?? '') === 'cancelled';
            return match ($lang) {
                'en' => [
                    'title' => $cancelled ? 'Physio session cancelled' : 'Physio session updated',
                    'body' => $cancelled ? 'Your physio session was cancelled.' : "Your physio session is at {$p('scheduled_at')}",
                ],
                'fr' => [
                    'title' => $cancelled ? 'Séance de kiné annulée' : 'Séance de kiné mise à jour',
                    'body' => $cancelled ? 'Votre séance de kiné a été annulée.' : "Votre séance de kiné est à {$p('scheduled_at')}",
                ],
                default => [
                    'title' => $cancelled ? 'تم إلغاء جلسة العلاج الطبيعي' : 'تم تحديث جلسة العلاج الطبيعي',
                    'body' => $cancelled ? 'تم إلغاء جلسة العلاج الطبيعي الخاصة بك.' : "موعد جلسة العلاج الطبيعي: {$p('scheduled_at')}",
                ],
            };

        case 'physio_doctor_followup':
            return match ($lang) {
                'en' => ['title' => 'Doctor follow-up recommended', 'body' => 'A physio session flagged a player for doctor follow-up.'],
                'fr' => ['title' => 'Suivi médical recommandé', 'body' => 'Une séance de kiné a signalé un joueur pour un suivi médical.'],
                default => ['title' => 'يُنصح بمتابعة طبية', 'body' => 'أشارت جلسة علاج طبيعي إلى ضرورة متابعة طبية لأحد اللاعبين.'],
            };

        case 'task_assigned':
            return match ($lang) {
                'en' => ['title' => 'New task: ' . $p('task_title'), 'body' => $p('raw_body')],
                'fr' => ['title' => 'Nouvelle tâche : ' . $p('task_title'), 'body' => $p('raw_body')],
                default => ['title' => 'مهمة جديدة: ' . $p('task_title'), 'body' => $p('raw_body')],
            };

        case 'task_comment':
            return match ($lang) {
                'en' => ['title' => 'New comment on task: ' . $p('task_title'), 'body' => $p('raw_body')],
                'fr' => ['title' => 'Nouveau commentaire sur la tâche : ' . $p('task_title'), 'body' => $p('raw_body')],
                default => ['title' => 'تعليق جديد على مهمة: ' . $p('task_title'), 'body' => $p('raw_body')],
            };

        case 'match_scheduled':
            return match ($lang) {
                'en' => ['title' => "Match vs {$p('opponent')}", 'body' => $p('when')],
                'fr' => ['title' => "Match contre {$p('opponent')}", 'body' => $p('when')],
                default => ['title' => "مباراة ضد {$p('opponent')}", 'body' => $p('when')],
            };

        case 'match_scheduled_coach':
            return match ($lang) {
                'en' => ['title' => 'New match scheduled', 'body' => "vs {$p('opponent')} — {$p('when')}"],
                'fr' => ['title' => 'Nouveau match programmé', 'body' => "contre {$p('opponent')} — {$p('when')}"],
                default => ['title' => 'تم جدولة مباراة جديدة', 'body' => "ضد {$p('opponent')} — {$p('when')}"],
            };

        case 'post_session_alert':
            $pain = !empty($params['pain_reported']);
            $rpe = $p('rpe');
            return match ($lang) {
                'en' => [
                    'title' => 'Post-session feedback alert',
                    'body' => $pain
                        ? 'A player reported pain in their post-session feedback.'
                        : "A player logged a high RPE ($rpe/10) after their session.",
                ],
                'fr' => [
                    'title' => 'Alerte retour post-séance',
                    'body' => $pain
                        ? 'Un joueur a signalé une douleur dans son retour post-séance.'
                        : "Un joueur a enregistré un RPE élevé ($rpe/10) après sa séance.",
                ],
                default => [
                    'title' => 'تنبيه ملاحظات ما بعد الجلسة',
                    'body' => $pain
                        ? 'أبلغ لاعب عن شعوره بألم في ملاحظاته بعد الجلسة.'
                        : "سجّل لاعب معدل جهد مرتفع (RPE $rpe/10) بعد الجلسة.",
                ],
            };

        case 'readiness_alert':
            return match ($lang) {
                'en' => ['title' => 'Low readiness: ' . $p('player_name'), 'body' => "Hooper Index: {$p('hooper')}"],
                'fr' => ['title' => 'Faible disponibilité : ' . $p('player_name'), 'body' => "Indice Hooper : {$p('hooper')}"],
                default => ['title' => 'جاهزية منخفضة: ' . $p('player_name'), 'body' => "مؤشر Hooper: {$p('hooper')}"],
            };

        default:
            return ['title' => $p('title'), 'body' => $p('raw_body')];
    }
}
