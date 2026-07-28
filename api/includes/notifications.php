<?php
// ─────────────────────────────────────────────────────────────────────────────
// In-app notification helper — single choke point for writing a row to the
// `notifications` table (see api/db.php). Callers pass the recipient user id,
// a short type tag, title/body text, and an optional route the client should
// open on tap. This is separate from lib/services/notification_service.dart
// (local device reminders for surveys) — that keeps working unchanged.
// ─────────────────────────────────────────────────────────────────────────────

function createNotification(
    PDO $pdo,
    int $clubId,
    int $userId,
    string $type,
    string $title,
    ?string $body = null,
    ?string $linkedRoute = null
): void {
    $pdo->prepare(
        'INSERT INTO notifications (club_id, user_id, type, title, body, linked_route)
         VALUES (?, ?, ?, ?, ?, ?)'
    )->execute([$clubId, $userId, $type, $title, $body, $linkedRoute]);
}
