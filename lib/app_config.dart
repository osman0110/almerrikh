// ─── Environment config ───────────────────────────────────────────────────────
// BEFORE DEMO / PROD BUILD: set _kProd = true
// LOCAL DEV:                 set _kProd = false
// ─────────────────────────────────────────────────────────────────────────────
const bool _kProd = true; // PRODUCTION — points to nextkick.me

const String _apiBaseOverride =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String kApiBase = _apiBaseOverride != ''
    ? _apiBaseOverride
    : _kProd
        ? 'https://nextkick.me/api'
        : 'http://localhost/academy/nextkickwebsite/api';

// Base URL for web-accessible pages (survey, QR links)
const String _webBaseOverride =
    String.fromEnvironment('WEB_BASE_URL', defaultValue: '');
const String kWebBase = _webBaseOverride != ''
    ? _webBaseOverride
    : _kProd
        ? 'https://nextkick.me'
        : 'http://localhost/academy/nextkickwebsite';

// ─── App version — keep in sync with pubspec.yaml ────────────────────────────
const String kAppVersion = '1.0.0+1';

// ─── Sentry DSN ───────────────────────────────────────────────────────────────
// Injected at build time — never hardcode in source control:
//   flutter build apk --release --dart-define=SENTRY_DSN=https://xxx@sentry.io/project
// Leave empty to disable crash reporting (safe default).
const String kSentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
