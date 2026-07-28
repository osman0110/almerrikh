<?php
/**
 * Player deduplication helpers.
 * Priority order for matching:
 *   1. user_id + source_app + external_player_ref
 *   2. user_id + date_of_birth + normalized name
 *   3. Create new
 *
 * Name-only matching is intentionally skipped when birth_date is absent
 * to avoid merging two different players with the same common name.
 */

function nk_normalize_name(string $name): string
{
    $name = mb_strtolower(trim($name), 'UTF-8');
    return preg_replace('/\s+/', ' ', $name);
}

/**
 * Finds an existing active player record for the given user.
 *
 * @param  PDO        $pdo          smart_sport DB connection
 * @param  int        $user_id      coach/club user ID (from token)
 * @param  string     $source_app   canonical source_app identifier
 * @param  string|null $external_ref optional external reference from the app
 * @param  string     $name         player display name
 * @param  string|null $birth_date  YYYY-MM-DD — required for name-based dedup
 * @return array|null existing row or null if not found
 */
function nk_find_existing_player(
    PDO    $pdo,
    int    $user_id,
    string $source_app,
    ?string $external_ref,
    string $name,
    ?string $birth_date = null
): ?array {
    // ── Priority 1: external ref ──────────────────────────────────────────────
    if ($external_ref !== null && $external_ref !== '') {
        $stmt = $pdo->prepare(
            'SELECT * FROM club_players
             WHERE user_id = ? AND source_app = ? AND external_player_ref = ?
               AND is_active = 1
             LIMIT 1'
        );
        $stmt->execute([$user_id, $source_app, $external_ref]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) return $row;
    }

    // ── Priority 2: name + birth_date ─────────────────────────────────────────
    if ($birth_date) {
        $norm = nk_normalize_name($name);
        $stmt = $pdo->prepare(
            'SELECT * FROM club_players
             WHERE user_id = ? AND date_of_birth = ? AND is_active = 1
             LIMIT 10'
        );
        $stmt->execute([$user_id, $birth_date]);
        $candidates = $stmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($candidates as $row) {
            if (nk_normalize_name($row['name']) === $norm) {
                return $row;
            }
        }
    }

    return null;
}

/**
 * Upserts a player record applying dedup logic.
 * Returns ['player_id' => string, 'action' => 'created|updated|matched'].
 *
 * @param PDO   $pdo      smart_sport DB connection
 * @param int      $user_id  coach/club user ID from token (never from client)
 * @param int|null $club_id  resolved club_id for the caller (never from client)
 * @param array    $data     player fields — source_app and name are required
 */
function nk_upsert_player(PDO $pdo, int $user_id, ?int $club_id, array $data): array
{
    $source_app   = trim($data['source_app']          ?? 'nextkick_mobile');
    $external_ref = isset($data['external_player_ref']) && $data['external_player_ref'] !== ''
                        ? trim($data['external_player_ref']) : null;
    $name         = trim($data['name'] ?? '');
    $birth_date   = !empty($data['date_of_birth']) ? $data['date_of_birth'] : null;

    if ($name === '') {
        return ['error' => 'name is required'];
    }

    $existing = nk_find_existing_player($pdo, $user_id, $source_app, $external_ref, $name, $birth_date);

    if ($existing) {
        $player_id = $existing['id'];
        $stmt = $pdo->prepare(
            'UPDATE club_players SET
                name                = ?,
                position            = COALESCE(?, position),
                team_name           = COALESCE(?, team_name),
                category            = COALESCE(?, category),
                dominant_foot       = COALESCE(?, dominant_foot),
                height_cm           = COALESCE(?, height_cm),
                weight_kg           = COALESCE(?, weight_kg),
                date_of_birth       = COALESCE(?, date_of_birth),
                nationality         = COALESCE(?, nationality),
                external_player_ref = COALESCE(?, external_player_ref),
                source_app          = ?,
                club_id             = COALESCE(club_id, ?),
                updated_at          = NOW()
             WHERE id = ? AND user_id = ?'
        );
        $stmt->execute([
            $name,
            $data['position']      ?? null,
            $data['team_name']     ?? null,
            $data['category']      ?? null,
            $data['dominant_foot'] ?? null,
            isset($data['height_cm'])  ? (float)$data['height_cm']  : null,
            isset($data['weight_kg'])  ? (float)$data['weight_kg']  : null,
            $birth_date,
            $data['nationality']   ?? null,
            $external_ref,
            $source_app,
            $club_id,
            $player_id,
            $user_id,
        ]);
        $action = ($external_ref && $existing['external_player_ref'] === $external_ref) ? 'updated' : 'matched';
        return ['player_id' => $player_id, 'action' => $action];
    }

    // Create new
    $player_id = 'cp-' . $user_id . '-' . substr(uniqid('', true), -10);
    $stmt = $pdo->prepare(
        "INSERT INTO club_players
         (id, user_id, club_id, name, position, team_name, category, dominant_foot,
          height_cm, weight_kg, date_of_birth, nationality,
          source_app, external_player_ref,
          player_type, is_active, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'club', 1, 'active')"
    );
    $stmt->execute([
        $player_id, $user_id, $club_id, $name,
        $data['position']      ?? null,
        $data['team_name']     ?? null,
        $data['category']      ?? null,
        $data['dominant_foot'] ?? null,
        isset($data['height_cm'])  ? (float)$data['height_cm']  : null,
        isset($data['weight_kg'])  ? (float)$data['weight_kg']  : null,
        $birth_date,
        $data['nationality']   ?? null,
        $source_app,
        $external_ref,
    ]);

    return ['player_id' => $player_id, 'action' => 'created'];
}
