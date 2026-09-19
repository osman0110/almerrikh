<?php
// Manual push-notification smoke test.
// Usage: php api/cli/test_push.php <email>
// Sends one real FCM push to every device_tokens row registered for that
// user, using the same sendPushToUser() helper the app's real events call.

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "CLI only.\n");
    exit(1);
}

require_once dirname(__DIR__) . '/db.php';
require_once dirname(__DIR__) . '/includes/push.php';

$email = $argv[1] ?? null;
if (!$email) {
    fwrite(STDERR, "Usage: php api/cli/test_push.php <email>\n");
    exit(1);
}

$stmt = $pdo->prepare('SELECT id, name FROM users WHERE email = ?');
$stmt->execute([$email]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);
if (!$user) {
    fwrite(STDERR, "No user found for email: $email\n");
    exit(1);
}

$tokens = $pdo->prepare('SELECT token, platform, created_at FROM device_tokens WHERE user_id = ?');
$tokens->execute([$user['id']]);
$rows = $tokens->fetchAll(PDO::FETCH_ASSOC);

if (!$rows) {
    fwrite(STDERR, "User {$user['name']} (#{$user['id']}) has no registered device_tokens rows.\n");
    fwrite(STDERR, "Open the app and sign in on a real device first so NotificationService.registerPush() runs.\n");
    exit(1);
}

echo "Found " . count($rows) . " device token(s) for {$user['name']} (#{$user['id']}):\n";
foreach ($rows as $row) {
    echo "  - {$row['platform']} token registered {$row['created_at']}\n";
}

$auth = getFcmAccessToken();
if (!$auth) {
    fwrite(STDERR, "\nFCM service account key not found/invalid — see fcmServiceAccountPath() in includes/push.php.\n");
    exit(1);
}
echo "\nFCM OAuth token acquired for project {$auth['project_id']}. Sending test push...\n";

$outcome = sendPushToUser($pdo, (int)$user['id'], 'Test notification', 'If you can see this, push notifications are working.', [
    'linked_route' => '/club/sessions',
]);

echo "Outcome: $outcome\n";
echo "Done. Check the device for the notification (and PHP error log for any [push] failures).\n";
