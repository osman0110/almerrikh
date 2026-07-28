<?php
/**
 * Source-app validation helpers.
 * All new data writes must pass through nk_require_valid_source_app().
 * Old data reads accept 'legacy' silently.
 */

function nk_allowed_source_apps(): array
{
    static $sources = null;
    if ($sources === null) {
        $sources = require __DIR__ . '/../config/app_sources.php';
    }
    return $sources;
}

/**
 * Validates and returns the canonical source_app string.
 * Used for reads only — unknown sources become 'legacy'.
 */
function nk_normalize_source_app(string $source): string
{
    $sources = nk_allowed_source_apps();
    $source  = strtolower(trim($source));
    return array_key_exists($source, $sources) ? $source : 'legacy';
}

/**
 * Returns the human-readable label for a source_app identifier.
 */
function nk_source_app_label(string $source): string
{
    $sources = nk_allowed_source_apps();
    return $sources[$source]['label'] ?? ucwords(str_replace('_', ' ', $source));
}

/**
 * Enforces that $source is a known, active source_app.
 * Call this on every write endpoint before inserting data.
 * Exits with HTTP 400 if invalid or disabled.
 */
function nk_require_valid_source_app(string $source): void
{
    $sources = nk_allowed_source_apps();
    $source  = strtolower(trim($source));

    if (!array_key_exists($source, $sources)) {
        http_response_code(400);
        echo json_encode([
            'error'   => "Unknown source_app: '$source'",
            'allowed' => array_keys($sources),
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }

    if (!($sources[$source]['active'] ?? false)) {
        http_response_code(400);
        echo json_encode([
            'error' => "source_app '$source' is currently disabled.",
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
}

/**
 * Returns WHERE/AND fragment + params array for filtering by source_app.
 * $source = 'all' → no filter; otherwise → AND source_app = ?
 *
 * Usage:
 *   [$clause, $params] = nk_source_sql_filter('nextkick_mobile', 'a');
 *   // $clause = "AND a.source_app = ?"
 *   // $params = ['nextkick_mobile']
 */
function nk_source_sql_filter(string $source, string $alias = ''): array
{
    if ($source === 'all') return ['', []];
    $col = $alias !== '' ? "{$alias}.source_app" : 'source_app';
    return ["AND {$col} = ?", [$source]];
}
