<?php
// Pure regression test — no DB, no network.
//
// Locks two production-readiness fixes (2026-09-19):
//  1. Notification helpers never throw into the caller. Every notification is
//     a side effect of a business write that is already committed; a broken
//     notifications table / device_tokens table / FCM must never turn a saved
//     session/task/injury into a reported "save failed" (→ user retries →
//     duplicate rows).
//  2. Push tokens are pruned ONLY when FCM says the token is invalid — never
//     on network errors, FCM outages or auth problems (previously any non-200
//     deleted the device token, silently disabling push for that device).

putenv('FCM_SERVICE_ACCOUNT_PATH=' . sys_get_temp_dir() . '/definitely-missing-fcm-key.json');
require_once dirname(__DIR__) . '/includes/notifications.php';

$failures = [];
$check = function (bool $cond, string $msg) use (&$failures) {
    if (!$cond) $failures[] = $msg;
};

// A PDO whose every statement fails, like a missing/broken table in prod.
final class ExplodingPdo extends PDO {
    public function __construct() { parent::__construct('sqlite::memory:'); }
    #[\ReturnTypeWillChange]
    public function prepare($query, $options = []) {
        throw new PDOException('simulated failure: ' . substr($query, 0, 40));
    }
}

ini_set('error_log', sys_get_temp_dir() . '/p1_notification_isolation_test.log');

// 1a. createNotification: DB insert fails → returns false, does not throw.
try {
    $result = createNotification(new ExplodingPdo(), 1, 2, 'session_scheduled', ['title' => 'T', 'when' => 'now'], '/x');
    $check($result === false, 'createNotification should return false when the insert fails');
} catch (Throwable $e) {
    $failures[] = 'createNotification threw: ' . $e->getMessage();
}

// 1b. notifyClubRole: lookup fails → returns false, does not throw.
try {
    $result = notifyClubRole(new ExplodingPdo(), 1, 'coach', 'session_scheduled_coach', ['title' => 'T', 'when' => 'now']);
    $check($result === false, 'notifyClubRole should return false when the staff lookup fails');
} catch (Throwable $e) {
    $failures[] = 'notifyClubRole threw: ' . $e->getMessage();
}

// 1c. createNotification with a working DB but FCM credentials missing →
// in-app row saved, returns true (push is skipped, not an error).
$sqlite = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$sqlite->exec('CREATE TABLE notifications (id INTEGER PRIMARY KEY, club_id INT, user_id INT, type TEXT, title TEXT, body TEXT, linked_route TEXT)');
$sqlite->exec('CREATE TABLE users (id INTEGER PRIMARY KEY, language TEXT)');
try {
    $result = createNotification($sqlite, 1, 2, 'session_scheduled', ['title' => 'T', 'when' => 'now'], '/x');
    $check($result === true, 'createNotification should return true when the in-app row is saved');
    $count = (int)$sqlite->query('SELECT COUNT(*) FROM notifications')->fetchColumn();
    $check($count === 1, "expected 1 notifications row, got $count");
} catch (Throwable $e) {
    $failures[] = 'createNotification (working DB) threw: ' . $e->getMessage();
}

// 2. FCM response classification — only explicit invalid-token answers prune.
$cases = [
    [200, '{}', '', 'sent'],
    [0, '', 'Could not resolve host', 'error'],                 // network
    [500, '{"error":{"status":"INTERNAL"}}', '', 'error'],        // FCM outage
    [503, '{"error":{"status":"UNAVAILABLE"}}', '', 'error'],
    [401, '{"error":{"status":"UNAUTHENTICATED"}}', '', 'error'], // our credentials
    [403, '{"error":{"status":"PERMISSION_DENIED"}}', '', 'error'],
    [404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}', '', 'invalid_token'],
    [400, '{"error":{"status":"INVALID_ARGUMENT","message":"The registration token is not a valid FCM registration token"}}', '', 'invalid_token'],
    [400, '{"error":{"status":"INVALID_ARGUMENT","message":"Invalid JSON payload"}}', '', 'error'],
];
foreach ($cases as [$code, $body, $curlErr, $expected]) {
    $actual = fcmClassifyResponse($code, $body, $curlErr);
    $check($actual === $expected, "fcmClassifyResponse($code) expected $expected, got $actual");
}

if ($failures) {
    fwrite(STDERR, "p1_notification_isolation_test: FAIL\n" . implode("\n", $failures) . "\n");
    exit(1);
}
echo "p1_notification_isolation_test: OK\n";
