<?php
// ─────────────────────────────────────────────────────────────────────────────
// Club Staff Layer — schema
//
// Phase 2 of the club entity work started in _schema.php: a real staff/roles
// table so a club can have more than one account attached to it (owner,
// admin, coach, doctor, performance analyst) instead of every endpoint
// treating "the club" as a single coach's user_id.
//
// Additive + idempotent, like _schema.php: nothing existing is renamed or
// dropped, so endpoints still scoped by user_id keep working unchanged while
// they're migrated to club_id scoping over time.
// ─────────────────────────────────────────────────────────────────────────────

function ensureClubStaffSchema(PDO $pdo): void {
    $pdo->exec("CREATE TABLE IF NOT EXISTS club_staff (
        id                  INT AUTO_INCREMENT PRIMARY KEY,
        club_id             INT          NOT NULL,
        user_id             INT          NOT NULL,
        staff_role          VARCHAR(20)  NOT NULL DEFAULT 'coach', -- owner, admin, coach, doctor, analyst
        status              VARCHAR(20)  NOT NULL DEFAULT 'active', -- active, pending, suspended
        invited_by_user_id  INT          NULL,
        created_at          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_club_staff (club_id, user_id),
        INDEX idx_club_staff_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec("CREATE TABLE IF NOT EXISTS club_staff_invites (
        code            VARCHAR(16)  PRIMARY KEY,
        club_id         INT          NOT NULL,
        staff_role      VARCHAR(20)  NOT NULL DEFAULT 'coach',
        note            TEXT         NULL,
        expires_at      TIMESTAMP    NULL,
        used_at         TIMESTAMP    NULL,
        used_by_user_id INT          NULL,
        created_by_user_id INT       NULL,
        created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // ── Unified access codes — supersedes club_invites (players) and
    // club_staff_invites (staff) above. One code, one account_type ('player'
    // or a staff role), reusable by many people until deactivated/deleted —
    // no per-registration single-use consumption, matching how a real club
    // wants to onboard: hand out one code per role and keep it running.
    $pdo->exec("CREATE TABLE IF NOT EXISTS club_access_codes (
        code               VARCHAR(16)  PRIMARY KEY,
        club_id            INT          NOT NULL,
        club_user_id       INT          NOT NULL, -- club owner's users.id, for legacy user_id-scoped player linking
        account_type       VARCHAR(30)  NOT NULL, -- 'player', or a club_staff.staff_role value
        note               VARCHAR(255) NULL,
        is_active          TINYINT(1)   NOT NULL DEFAULT 1,
        use_count          INT          NOT NULL DEFAULT 0,
        last_used_at       TIMESTAMP    NULL,
        created_by_user_id INT          NULL,
        created_at         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_cac_club (club_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Backfill: every club owner gets an 'owner' row in club_staff, mirroring
    // the clubs-table backfill in ensureClubSchema(). Safe to re-run — the
    // unique key on (club_id, user_id) makes the insert idempotent.
    $owners = $pdo->query("
        SELECT c.id AS club_id, c.owner_user_id
        FROM clubs c
        LEFT JOIN club_staff s ON s.club_id = c.id AND s.user_id = c.owner_user_id
        WHERE c.owner_user_id IS NOT NULL AND s.id IS NULL
    ")->fetchAll(PDO::FETCH_ASSOC);

    foreach ($owners as $row) {
        $pdo->prepare(
            "INSERT INTO club_staff (club_id, user_id, staff_role, status)
             VALUES (?, ?, 'owner', 'active')
             ON DUPLICATE KEY UPDATE id = id"
        )->execute([$row['club_id'], $row['owner_user_id']]);
    }

    // Backfill club_id onto assessments (needed once an endpoint starts
    // querying it by club_id instead of user_id) — same pattern as the
    // club_players/club_teams/club_sessions backfill in _schema.php.
    if (_club_schema_table_exists($pdo, 'assessments') && _club_schema_column_exists($pdo, 'assessments', 'club_id')) {
        $pdo->exec(
            "UPDATE assessments a
             JOIN users u ON u.id = a.user_id
             SET a.club_id = u.club_id
             WHERE a.club_id IS NULL AND u.club_id IS NOT NULL"
        );
    }
}
