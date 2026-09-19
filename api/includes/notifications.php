<?php
// ─────────────────────────────────────────────────────────────────────────────
// In-app notification helper — single choke point for writing a row to the
// `notifications` table (see api/db.php). Callers pass the recipient user id,
// a short type tag, and a param bag; the title/body text is rendered in the
// recipient's own language via notificationText() (notification_i18n.php)
// before being stored and pushed. This is separate from
// lib/services/notification_service.dart (local device reminders for
// surveys) — that keeps working unchanged.
//
// Also fans out to a real FCM push (api/includes/push.php) so every existing
// call site gets push for free. Push failures never block the in-app write.
// ─────────────────────────────────────────────────────────────────────────────

require_once __DIR__ . '/push.php';
require_once __DIR__ . '/notification_i18n.php';

function createNotification(
    PDO $pdo,
    int $clubId,
    int $userId,
    string $type,
    array $params,
    ?string $linkedRoute = null
): bool {
    // Notifications are always a side effect of some other, already-saved
    // business write (session, task, injury…). They must NEVER throw back
    // into the caller: a failure here is logged and reported as `false`, so
    // an endpoint can still answer "saved" (optionally with a warning).
    try {
        $lang = notificationLang($pdo, $userId);
        $text = notificationText($type, $params, $lang);
        $title = $text['title'];
        $body = $text['body'];

        $pdo->prepare(
            'INSERT INTO notifications (club_id, user_id, type, title, body, linked_route)
             VALUES (?, ?, ?, ?, ?, ?)'
        )->execute([$clubId, $userId, $type, $title, $body, $linkedRoute]);
    } catch (Throwable $e) {
        error_log("[notify] in-app notification '$type' for user $userId not saved: " . $e->getMessage());
        return false;
    }

    try {
        sendPushToUser($pdo, $userId, $title, $body ?? '', array_filter([
            'type'         => $type,
            'linked_route' => $linkedRoute,
        ]));
    } catch (Throwable $e) {
        error_log('[push] sendPushToUser failed: ' . $e->getMessage());
    }
    return true;
}
