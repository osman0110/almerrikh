<?php
// ─────────────────────────────────────────────────────────────────────────────
// Real push notifications (FCM HTTP v1). No Composer/vendor deps in this repo,
// so the OAuth2 service-account exchange is hand-rolled with openssl + curl
// rather than pulling in firebase-admin.
//
// Requires a Firebase service-account JSON key, generated once from
// Firebase Console → Project Settings → Service Accounts → Generate new
// private key, saved OUTSIDE the web root and referenced via
// FCM_SERVICE_ACCOUNT_PATH (env var) or the fallback path below. This file
// is a no-op (fails silently, logs a warning) until that key is in place —
// it must never block the caller's main request (e.g. saving a session).
// ─────────────────────────────────────────────────────────────────────────────

require_once __DIR__ . '/notification_i18n.php';

function fcmServiceAccountPath(): string {
    return getenv('FCM_SERVICE_ACCOUNT_PATH') ?: (__DIR__ . '/../config/fcm-service-account.json');
}

function fcmAccessTokenCachePath(): string {
    return sys_get_temp_dir() . '/merr_fcm_access_token.json';
}

function base64UrlEncode(string $data): string {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

/** Exchanges the service-account key for a short-lived OAuth2 access token, caching it. */
function getFcmAccessToken(): ?array {
    $keyPath = fcmServiceAccountPath();
    if (!is_file($keyPath)) {
        error_log('[push] FCM service account key not found at ' . $keyPath);
        return null;
    }

    $cachePath = fcmAccessTokenCachePath();
    if (is_file($cachePath)) {
        $cached = json_decode(file_get_contents($cachePath), true);
        if (is_array($cached) && ($cached['expires_at'] ?? 0) > time() + 60) {
            return ['access_token' => $cached['access_token'], 'project_id' => $cached['project_id']];
        }
    }

    $account = json_decode(file_get_contents($keyPath), true);
    if (!is_array($account) || empty($account['private_key']) || empty($account['client_email'])) {
        error_log('[push] FCM service account key is malformed');
        return null;
    }

    $now = time();
    $header = base64UrlEncode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $claims = base64UrlEncode(json_encode([
        'iss'   => $account['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud'   => 'https://oauth2.googleapis.com/token',
        'iat'   => $now,
        'exp'   => $now + 3600,
    ]));
    $signingInput = "$header.$claims";

    $signature = '';
    $signed = openssl_sign($signingInput, $signature, $account['private_key'], OPENSSL_ALGO_SHA256);
    if (!$signed) {
        error_log('[push] Failed to sign FCM JWT');
        return null;
    }
    $jwt = $signingInput . '.' . base64UrlEncode($signature);

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => $jwt,
        ]),
        CURLOPT_TIMEOUT        => 10,
    ]);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    $data = json_decode((string)$response, true);
    if ($httpCode !== 200 || empty($data['access_token'])) {
        error_log('[push] FCM token exchange failed: ' . $response);
        return null;
    }

    file_put_contents($cachePath, json_encode([
        'access_token' => $data['access_token'],
        'project_id'   => $account['project_id'],
        'expires_at'   => $now + (int)($data['expires_in'] ?? 3300),
    ]));

    return ['access_token' => $data['access_token'], 'project_id' => $account['project_id']];
}

/** Sends one FCM v1 message to a single token. Returns true on success. */
function fcmSendToToken(string $accessToken, string $projectId, string $token, string $title, string $body, array $data = []): bool {
    $payload = [
        'message' => [
            'token' => $token,
            'notification' => ['title' => $title, 'body' => $body],
            'data' => array_map('strval', $data),
        ],
    ];

    $ch = curl_init("https://fcm.googleapis.com/v1/projects/$projectId/messages:send");
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST           => true,
        CURLOPT_HTTPHEADER     => [
            'Authorization: Bearer ' . $accessToken,
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS     => json_encode($payload),
        CURLOPT_TIMEOUT        => 10,
    ]);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode === 200) return true;

    if (in_array($httpCode, [400, 404], true) && str_contains((string)$response, 'UNREGISTERED')) {
        // Stale token — caller prunes it.
        return false;
    }
    error_log("[push] FCM send failed ($httpCode): $response");
    return false;
}

/** Sends a push to every device registered for a user, pruning dead tokens. */
function sendPushToUser(PDO $pdo, int $userId, string $title, string $body, array $data = []): void {
    $auth = getFcmAccessToken();
    if (!$auth) return;

    $stmt = $pdo->prepare('SELECT id, token FROM device_tokens WHERE user_id = ?');
    $stmt->execute([$userId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (!$rows) return;

    foreach ($rows as $row) {
        $ok = fcmSendToToken($auth['access_token'], $auth['project_id'], $row['token'], $title, $body, $data);
        if (!$ok) {
            $pdo->prepare('DELETE FROM device_tokens WHERE id = ?')->execute([$row['id']]);
        }
    }
}

/**
 * Sends a push to every active staff member with a given staff_role in a
 * club — translated per-recipient via notificationText(), since a role
 * broadcast fans out to staff who may each have a different app language.
 */
function notifyClubRole(PDO $pdo, int $clubId, string $staffRole, string $type, array $params, array $data = []): void {
    $stmt = $pdo->prepare(
        "SELECT user_id FROM club_staff WHERE club_id = ? AND staff_role = ? AND status = 'active'"
    );
    $stmt->execute([$clubId, $staffRole]);
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $userId) {
        $userId = (int)$userId;
        $lang = notificationLang($pdo, $userId);
        $text = notificationText($type, $params, $lang);
        sendPushToUser($pdo, $userId, $text['title'], $text['body'], $data);
    }
}
