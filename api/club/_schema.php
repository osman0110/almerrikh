<?php
// ─────────────────────────────────────────────────────────────────────────────
// Club Entity Layer — schema
//
// Formalizes "club" as a real organization entity (mirroring `academies`)
// instead of a bare `users.account_type = 'club'` row. Phase 1: the entity
// itself + linkage to the existing legacy club tables (club_players,
// club_teams, club_sessions), which today are scoped only by `user_id`.
//
// Idempotent, backward-compatible DDL. Invoked from ensureSchema() in
// api/db.php so it auto-applies on every request, exactly like the academy
// schema. Uses the global ensureColumn()/ensureIndex() helpers from db.php.
// ─────────────────────────────────────────────────────────────────────────────

// This module is invoked from ensureSchema() in api/db.php, which — depending
// on deployment (split DB vs. unified DB) — may run against either the "web"
// users table shape (full_name, org_name, account_type) or the leaner
// "mobile" shape (name, account_type, no org_name at all). Never assume a
// column exists; check first.
function _club_schema_table_exists(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?'
    );
    $stmt->execute([$table]);
    return ((int) $stmt->fetchColumn()) > 0;
}

function _club_schema_column_exists(PDO $pdo, string $table, string $column): bool
{
    if (!_club_schema_table_exists($pdo, $table)) return false;
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );
    $stmt->execute([$table, $column]);
    return ((int) $stmt->fetchColumn()) > 0;
}

function ensureClubSchema(PDO $pdo): void {

    // 1) clubs ────────────────────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS clubs (
        id            INT AUTO_INCREMENT PRIMARY KEY,
        owner_user_id INT          NULL,           -- users.id of the club admin/owner
        name          VARCHAR(200) NOT NULL,
        logo          VARCHAR(500) NULL,
        country       VARCHAR(80)  NULL,
        city          VARCHAR(100) NULL,
        address       TEXT         NULL,
        phone         VARCHAR(40)  NULL,
        email         VARCHAR(255) NULL,
        currency      CHAR(3)      DEFAULT 'USD',
        status        VARCHAR(20)  DEFAULT 'active', -- active, pending, suspended, rejected
        created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
        updated_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY uq_clubs_owner (owner_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // 2) users: club linkage column (mirrors academy_id/branch_id) ─────────────
    ensureColumn($pdo, 'users', 'club_id', 'INT NULL');
    ensureIndex($pdo, 'users', 'idx_users_club', 'CREATE INDEX idx_users_club ON users (club_id)');

    // 3) legacy per-user club tables gain a club_id for entity-scoped queries ──
    // (kept alongside user_id — nothing that already filters by user_id breaks).
    // Skipped gracefully if a given legacy table doesn't exist on this DB yet.
    foreach (['club_players', 'club_teams', 'club_sessions'] as $table) {
        if (!_club_schema_table_exists($pdo, $table)) continue;
        ensureColumn($pdo, $table, 'club_id', 'INT NULL');
        ensureIndex($pdo, $table, "idx_{$table}_club", "CREATE INDEX idx_{$table}_club ON {$table} (club_id)");
    }

    // 4) Auto-heal: every existing account_type='club' user gets a clubs row ───
    // so the entity isn't limited to accounts created after this migration.
    // Pick whichever "display name" column this users table shape actually has.
    $nameCol = _club_schema_column_exists($pdo, 'users', 'org_name')
        ? 'org_name'
        : (_club_schema_column_exists($pdo, 'users', 'full_name') ? 'full_name' : 'name');
    $hasCountry = _club_schema_column_exists($pdo, 'users', 'country');

    $owners = $pdo->query("
        SELECT u.id, u.`$nameCol` AS display_name, u.email" . ($hasCountry ? ', u.country' : '') . "
        FROM users u
        LEFT JOIN clubs c ON c.owner_user_id = u.id
        WHERE u.account_type = 'club' AND c.id IS NULL
    ")->fetchAll(PDO::FETCH_ASSOC);

    foreach ($owners as $owner) {
        $stmt = $pdo->prepare("
            INSERT INTO clubs (owner_user_id, name, email, country, status)
            VALUES (?, ?, ?, ?, 'active')
        ");
        $stmt->execute([
            $owner['id'],
            $owner['display_name'] ?: ('Club #' . $owner['id']),
            $owner['email'],
            $owner['country'] ?? null,
        ]);
        $clubId = (int) $pdo->lastInsertId();

        $pdo->prepare('UPDATE users SET club_id = ? WHERE id = ?')->execute([$clubId, $owner['id']]);
        foreach ([
            'club_players', 'club_teams', 'club_sessions',
            'assessments', 'player_hooper_index', 'player_rpe',
            'fms_assessments', 'player_body_metrics', 'coach_evaluations',
            'matches', 'player_wearable_data', 'session_attendance',
        ] as $table) {
            if (!_club_schema_table_exists($pdo, $table)) continue;
            $pdo->prepare("UPDATE `$table` SET club_id = ? WHERE user_id = ? AND club_id IS NULL")
                ->execute([$clubId, $owner['id']]);
        }
    }

    // 5) Backfill unconditionally from users.club_id, for clubs healed by an
    // earlier deploy (step 4 above only runs for brand-new `clubs` rows, so
    // tables added after a club already existed never got backfilled there).
    // Cheap once caught up — WHERE club_id IS NULL uses the idx_{table}_club index.
    foreach ([
        'club_players', 'club_teams', 'club_sessions',
        'assessments', 'player_hooper_index', 'player_rpe',
        'fms_assessments', 'player_body_metrics', 'coach_evaluations',
        'matches', 'player_wearable_data', 'session_attendance',
    ] as $table) {
        if (!_club_schema_table_exists($pdo, $table)) continue;
        $pdo->exec("
            UPDATE `$table` t
            JOIN users u ON u.id = t.user_id
            SET t.club_id = u.club_id
            WHERE t.club_id IS NULL AND u.club_id IS NOT NULL
        ");
    }
}
