    <?php
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Headers: Authorization, Content-Type');
    header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

    require_once 'db.php';
    require_once 'includes/audit_log.php';
    require_once 'includes/player_status.php';
    require_once 'includes/club_auth.php';

    function jsonOut(array $data, int $code = 200): void {
        http_response_code($code);
        echo json_encode($data, JSON_UNESCAPED_UNICODE);
        exit;
    }

    function bearerToken(): string {
        $auth = $_SERVER['HTTP_AUTHORIZATION']
            ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
            ?? $_SERVER['Authorization'] ?? '';
        if (!$auth && function_exists('apache_request_headers')) {
            $h = apache_request_headers();
            $auth = $h['Authorization'] ?? $h['authorization'] ?? '';
        }
        if (stripos($auth, 'Bearer ') === 0) return trim(substr($auth, 7));
        return trim($auth);
    }

    function getAuthUser(PDO $pdo): array {
        $token = bearerToken();
        if (!$token) jsonOut(['error' => 'Unauthorized'], 401);
        $stmt = $pdo->prepare(
            'SELECT u.id FROM users u JOIN user_tokens t ON u.id = t.user_id WHERE t.token = ? AND (t.expires_at IS NULL OR t.expires_at > NOW())'
        );
        $stmt->execute([$token]);
        $user = $stmt->fetch();
        if (!$user) jsonOut(['error' => 'Invalid or expired token'], 401);
        return $user;
    }

    function existingIds(
        PDO $pdo,
        string $table,
        string $idColumn,
        string $whereColumn,
        $value
    ): array {
        foreach ([$table, $idColumn, $whereColumn] as $identifier) {
            if (!preg_match('/^[A-Za-z0-9_]+$/', $identifier)) return [];
        }
        $stmt = $pdo->prepare(
            "SELECT `$idColumn` FROM `$table` WHERE `$whereColumn` = ?"
        );
        $stmt->execute([$value]);
        return array_values(array_filter(
            $stmt->fetchAll(PDO::FETCH_COLUMN),
            static fn($id) => $id !== null && $id !== ''
        ));
    }

    function deleteByIds(
        PDO $pdo,
        string $table,
        string $column,
        array $ids
    ): void {
        if (!$ids || !preg_match('/^[A-Za-z0-9_]+$/', $table) ||
            !preg_match('/^[A-Za-z0-9_]+$/', $column)) {
            return;
        }
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $pdo->prepare("DELETE FROM `$table` WHERE `$column` IN ($placeholders)")
            ->execute(array_values($ids));
    }

    function deleteDirectPlayerReferences(PDO $pdo, string $playerId): void {
        $stmt = $pdo->query(
            "SELECT c.TABLE_NAME, c.COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS c
            JOIN INFORMATION_SCHEMA.TABLES t
            ON t.TABLE_SCHEMA = c.TABLE_SCHEMA
            AND t.TABLE_NAME = c.TABLE_NAME
            AND t.TABLE_TYPE = 'BASE TABLE'
            WHERE c.TABLE_SCHEMA = DATABASE()
            AND c.COLUMN_NAME IN ('player_id', 'linked_player_id', 'club_player_id')
            AND c.TABLE_NAME NOT IN ('club_players', 'users')"
        );
        $columnsByTable = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $column) {
            $columnsByTable[$column['TABLE_NAME']][] = $column['COLUMN_NAME'];
        }

        foreach ($columnsByTable as $table => $columns) {
            if (!preg_match('/^[A-Za-z0-9_]+$/', $table)) continue;
            $where = [];
            $params = [];
            foreach ($columns as $column) {
                if (!preg_match('/^[A-Za-z0-9_]+$/', $column)) continue;
                $where[] = "`$column` = ?";
                $params[] = $playerId;
            }
            if ($where) {
                $pdo->prepare(
                    "DELETE FROM `$table` WHERE " . implode(' OR ', $where)
                )->execute($params);
            }
        }
    }

    function deleteUserRows(PDO $pdo, string $table, string $column, int $userId): void {
        $exists = $pdo->prepare(
            'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
        );
        $exists->execute([$table, $column]);
        if (!$exists->fetchColumn()) return;
        $pdo->prepare("DELETE FROM `$table` WHERE `$column` = ?")->execute([$userId]);
    }

    function removePlayerFromJsonRoster(
        PDO $pdo,
        string $table,
        string $column,
        int $clubId,
        string $playerId
    ): void {
        $exists = $pdo->prepare(
            'SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
        );
        $exists->execute([$table, $column]);
        if (!$exists->fetchColumn()) return;

        $stmt = $pdo->prepare(
            "SELECT id, `$column` FROM `$table`
            WHERE club_id = ? AND `$column` IS NOT NULL AND `$column` != ''"
        );
        $stmt->execute([$clubId]);
        $update = $pdo->prepare("UPDATE `$table` SET `$column` = ? WHERE id = ?");
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $ids = json_decode((string)$row[$column], true);
            if (!is_array($ids)) continue;
            $changed = false;
            if (array_key_exists($playerId, $ids)) {
                unset($ids[$playerId]);
                $filtered = $ids;
                $changed = true;
            } else {
                $filtered = array_values(array_filter(
                    $ids,
                    static fn($value) => (string)$value !== $playerId
                ));
                $changed = count($filtered) !== count($ids);
            }
            if ($changed) {
                $update->execute([
                    json_encode($filtered, JSON_UNESCAPED_UNICODE),
                    $row['id'],
                ]);
            }
        }
    }

    $method = $_SERVER['REQUEST_METHOD'];
    $user   = getAuthUser($pdo);

    // ── GET: list players ─────────────────────────────────────────────────────────
    if ($method === 'GET') {
        $filterId = isset($_GET['id']) ? trim($_GET['id']) : '';
        $showArchived = ($_GET['archived'] ?? '') === '1';

        // Status change history — small "status log" section on the player
        // profile page. Same 'players.read' scope as everything else here.
        if ($filterId !== '' && ($_GET['status_history'] ?? '') === '1') {
            $ctx = requireClubPermission($pdo, $user, 'players.read');
            $ownStmt = $pdo->prepare('SELECT 1 FROM club_players WHERE id = ? AND club_id = ?');
            $ownStmt->execute([$filterId, $ctx['club_id']]);
            if (!$ownStmt->fetchColumn()) jsonOut(['error' => 'Not found'], 404);

            $stmt = $pdo->prepare(
                'SELECT h.old_status, h.new_status, h.reason, h.changed_at, u.name AS changed_by_name
                FROM player_status_history h
                JOIN users u ON u.id = h.changed_by_user_id
                WHERE h.player_id = ?
                ORDER BY h.changed_at DESC'
            );
            $stmt->execute([$filterId]);
            jsonOut(['history' => $stmt->fetchAll()]);
        }

        // Fast single-player lookup (used by profile page)
        if ($filterId !== '') {
            // Scoped to the caller's club (any staff member — coach/doctor/analyst/admin/owner)
            $ctx = requireClubPermission($pdo, $user, 'players.read');
            $stmt = $pdo->prepare(
                "SELECT * FROM club_players WHERE id = ? AND club_id = ? AND is_active = 1 LIMIT 1"
            );
            $stmt->execute([$filterId, $ctx['club_id']]);
            $rows = $stmt->fetchAll();

            foreach ($rows as &$r) {
                $r['height_cm']            = $r['height_cm'] !== null ? (float)$r['height_cm'] : null;
                $r['weight_kg']            = $r['weight_kg'] !== null ? (float)$r['weight_kg'] : null;
                $r['is_active']            = (bool)$r['is_active'];
                $r['status']               = $r['status'] ?? 'active';
                $r['expected_return_date'] = $r['expected_return_date'] ?? null;
                $r['unavailable_reason']   = $r['unavailable_reason'] ?? null;
                $r['last_assessment_at']   = $r['last_assessment_at'] ?? null;
                $r['latest_score']         = $r['latest_score'] !== null ? (float)$r['latest_score'] : null;
                $r['movement_score']       = $r['movement_score'] !== null ? (float)$r['movement_score'] : null;
                $r['stability_score']      = $r['stability_score'] !== null ? (float)$r['stability_score'] : null;
                $r['symmetry_score']       = $r['symmetry_score'] !== null ? (float)$r['symmetry_score'] : null;
                $r['control_score']        = $r['control_score'] !== null ? (float)$r['control_score'] : null;
            }
            unset($r);
            jsonOut(['players' => $rows]);
        }

        // Determine if the caller is a player (needs to see their own record)
        // or a coach/admin (sees only their club's players)
        $roleStmt = $pdo->prepare('SELECT role, player_type FROM users WHERE id = ?');
        $roleStmt->execute([$user['id']]);
        $callerInfo = $roleStmt->fetch();
        $callerIsPlayer = ($callerInfo['player_type'] !== null && $callerInfo['player_type'] !== '');

        if ($callerIsPlayer) {
            // Players see ONLY their own linked record (independent or club)
            $stmt = $pdo->prepare(
                "SELECT * FROM club_players
                WHERE (linked_user_id = ?
                        OR (user_id = ? AND player_type = 'independent'))
                AND is_active = 1
                ORDER BY name ASC"
            );
            $stmt->execute([$user['id'], $user['id']]);
        } else {
            // Coaches/admins/doctors/analysts see their club's players; never independent
            $ctx = requireClubPermission($pdo, $user, 'players.read');
            $activeValue = $showArchived ? 0 : 1;
            $stmt = $pdo->prepare(
                "SELECT * FROM club_players
                WHERE club_id = ?
                AND is_active = ?
                AND (player_type IS NULL OR player_type = 'club')
                ORDER BY name ASC"
            );
            $stmt->execute([$ctx['club_id'], $activeValue]);
        }
        $rows = $stmt->fetchAll();
        foreach ($rows as &$r) {
            $r['height_cm']            = $r['height_cm'] !== null ? (float)$r['height_cm'] : null;
            $r['weight_kg']            = $r['weight_kg'] !== null ? (float)$r['weight_kg'] : null;
            $r['is_active']            = (bool)$r['is_active'];
            $r['status']               = $r['status'] ?? 'active';
            $r['expected_return_date'] = $r['expected_return_date'] ?? null;
            $r['unavailable_reason']   = $r['unavailable_reason'] ?? null;
            $r['last_assessment_at']   = $r['last_assessment_at'] ?? null;
            $r['latest_score']         = $r['latest_score'] !== null ? (float)$r['latest_score'] : null;
            $r['movement_score']       = $r['movement_score'] !== null ? (float)$r['movement_score'] : null;
            $r['stability_score']      = $r['stability_score'] !== null ? (float)$r['stability_score'] : null;
            $r['symmetry_score']       = $r['symmetry_score'] !== null ? (float)$r['symmetry_score'] : null;
            $r['control_score']        = $r['control_score'] !== null ? (float)$r['control_score'] : null;
        }
        unset($r);
        jsonOut(['players' => $rows]);
    }

    // ── POST: create / update player (ownership-checked upsert) ─────────────────
    if ($method === 'POST') {
        // Players cannot manage player records via this endpoint
        $roleStmt2 = $pdo->prepare('SELECT role FROM users WHERE id = ?');
        $roleStmt2->execute([$user['id']]);
        $callerRole = $roleStmt2->fetchColumn();
        if ($callerRole === 'player' || $callerRole === 'parent') {
            jsonOut(['error' => 'Forbidden — coaches only'], 403);
        }

        $ctx = resolveClubContext($pdo, $user);
        if (!$ctx['club_id']) jsonOut(['error' => 'Not a member of a club'], 403);

        $canFullWrite    = clubStaffCan($ctx['staff_role'], 'players.write');
        $canMedicalWrite = clubStaffCan($ctx['staff_role'], 'medical.write');
        if (!$canFullWrite && !$canMedicalWrite) {
            jsonOut(['error' => 'Forbidden — insufficient staff role'], 403);
        }

        $body = json_decode(file_get_contents('php://input'), true) ?? [];
        $id   = trim($body['id'] ?? '');
        $name = trim($body['name'] ?? '');
        $nameArabic = trim($body['name_ar'] ?? $body['nameArabic'] ?? '');
        $nameEnglish = trim($body['name_en'] ?? $body['nameEnglish'] ?? '');

        if (!$id)   jsonOut(['error' => 'id is required'], 400);

        if (($body['action'] ?? '') === 'restore') {
            $manageCtx = requireClubPermission($pdo, $user, 'players.delete');
            $playerStmt = $pdo->prepare(
                'SELECT linked_user_id FROM club_players WHERE id = ? AND club_id = ?'
            );
            $playerStmt->execute([$id, $manageCtx['club_id']]);
            $player = $playerStmt->fetch(PDO::FETCH_ASSOC);
            if (!$player) jsonOut(['error' => 'Player not found'], 404);

            $pdo->prepare(
                'UPDATE club_players SET is_active = 1 WHERE id = ? AND club_id = ?'
            )->execute([$id, $manageCtx['club_id']]);
            if (!empty($player['linked_user_id'])) {
                $pdo->prepare(
                    "UPDATE users
                    SET is_active = 1, status = 'active', deleted_at = NULL
                    WHERE id = ? AND linked_player_id = ?"
                )->execute([(int)$player['linked_user_id'], $id]);
            }
            jsonOut(['success' => true, 'restored' => true]);
        }

        if (!$name) jsonOut(['error' => 'name is required'], 400);

        // Ownership check: if record already exists, verify it belongs to this club
        $existStmt = $pdo->prepare('SELECT * FROM club_players WHERE id = ?');
        $existStmt->execute([$id]);
        $existing = $existStmt->fetch(PDO::FETCH_ASSOC) ?: null;
        if ($existing && (int)$existing['club_id'] !== (int)$ctx['club_id']) {
            jsonOut(['error' => 'Forbidden — not your player'], 403);
        }

        // Partial legacy updates (for example score updates) do not carry the
        // bilingual fields; keep the stored values instead of clearing them.
        if ($existing) {
            if (!array_key_exists('name_ar', $body) && !array_key_exists('nameArabic', $body)) {
                $nameArabic = $existing['name_ar'] ?? '';
            }
            if (!array_key_exists('name_en', $body) && !array_key_exists('nameEnglish', $body)) {
                $nameEnglish = $existing['name_en'] ?? '';
            }
        }

        // Roles limited to medical.write only (doctor) can edit an existing
        // player's medical/injury fields, but cannot create players or change
        // identity/roster fields (name, number, position, team, etc.).
        if (!$canFullWrite) {
            if (!$existing) jsonOut(['error' => 'Forbidden — cannot create players'], 403);
            $body['name']         = $existing['name'];
            $body['name_ar']      = $existing['name_ar'] ?? '';
            $body['name_en']      = $existing['name_en'] ?? '';
            $body['nickname']     = $existing['nickname'] ?? null;
            $body['number']       = $existing['number'];
            $body['position']     = $existing['position'];
            $body['team']         = $existing['team_name'];
            $body['category']     = $existing['category'];
            $body['dominantFoot'] = $existing['dominant_foot'];
            $body['heightCm']     = $existing['height_cm'];
            $body['weightKg']     = $existing['weight_kg'];
            $body['dateOfBirth']  = $existing['date_of_birth'];
            $body['nationality']  = $existing['nationality'];
            $body['photoUrl']     = $existing['photo_url'];
            $body['email']        = '';
            $body['password']     = '';
            $name = $existing['name'];
            $nameArabic = $existing['name_ar'] ?? '';
            $nameEnglish = $existing['name_en'] ?? '';
        }

        // ── Optional: coach provisions a direct login for this player ────────────
        // Only meaningful when the player has no linked account yet — never
        // silently overwrite an existing player's credentials via this endpoint.
        $email    = trim($body['email']    ?? '');
        $password = (string)($body['password'] ?? '');
        $wantsLogin = ($email !== '' || $password !== '');
        $alreadyLinked = $existing && !empty($existing['linked_user_id']);

        if ($wantsLogin && $alreadyLinked) {
            jsonOut(['error' => 'This player already has a login account'], 409);
        }

        if ($wantsLogin) {
            $email = strtolower($email);
            if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 255) {
                jsonOut(['error' => 'Invalid email address'], 400);
            }
            if (strlen($password) < 6 || strlen($password) > 128) {
                jsonOut(['error' => 'Password must be 6–128 characters'], 400);
            }
            $dupStmt = $pdo->prepare('SELECT id FROM users WHERE email = ?');
            $dupStmt->execute([$email]);
            if ($dupStmt->fetch()) {
                jsonOut(['error' => 'Email is already registered'], 409);
            }
        }

        $statusVal = trim($body['status'] ?? 'active');
        $isAvailable = ($statusVal === 'active');

        // When player is available, clear injury/suspension fields automatically
        $expectedReturn  = $isAvailable ? null
            : ($body['expected_return_date'] ?? $body['expectedReturnDate'] ?? null);
        $unavailReason   = $isAvailable ? null
            : ($body['unavailable_reason'] ?? $body['unavailableReason'] ?? null);
        // injury_notes: keep even when active (historical record)
        $injuryNotes     = $body['injury_notes']   ?? $body['injuryNotes']   ?? null;
        $physicalNotes   = $body['physical_notes'] ?? $body['physicalNotes'] ?? null;
        $medicalNotes    = $body['medical_notes']  ?? $body['medicalNotes']  ?? null;

        // club_players.user_id historically means "the owning coach account" —
        // preserved as-is (not the acting staff member) so the many endpoints
        // still scoped by user_id keep resolving to the same owner.
        if ($existing) {
            $ownerUserId = (int)$existing['user_id'];
        } else {
            $ownerStmt = $pdo->prepare('SELECT owner_user_id FROM clubs WHERE id = ?');
            $ownerStmt->execute([$ctx['club_id']]);
            $ownerUserId = (int)($ownerStmt->fetchColumn() ?: $user['id']);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO club_players
                (id, user_id, club_id, name, name_ar, name_en, nickname, number, position, team_name, category,
                dominant_foot, height_cm, weight_kg, date_of_birth, nationality,
                injury_notes, physical_notes, medical_notes, status, photo_url,
                expected_return_date, unavailable_reason)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                name                 = VALUES(name),
                name_ar              = VALUES(name_ar),
                name_en              = VALUES(name_en),
                nickname             = VALUES(nickname),
                number               = VALUES(number),
                position             = VALUES(position),
                team_name            = VALUES(team_name),
                category             = VALUES(category),
                dominant_foot        = VALUES(dominant_foot),
                height_cm            = VALUES(height_cm),
                weight_kg            = VALUES(weight_kg),
                date_of_birth        = VALUES(date_of_birth),
                nationality          = VALUES(nationality),
                injury_notes         = VALUES(injury_notes),
                physical_notes       = VALUES(physical_notes),
                medical_notes        = VALUES(medical_notes),
                status               = VALUES(status),
                photo_url            = VALUES(photo_url),
                expected_return_date = VALUES(expected_return_date),
                unavailable_reason   = VALUES(unavailable_reason),
                is_active            = 1'
        );
        $heightCm = isset($body['heightCm']) ? (float)$body['heightCm'] : (isset($body['height_cm']) ? (float)$body['height_cm'] : null);
        $weightKg = isset($body['weightKg']) ? (float)$body['weightKg'] : (isset($body['weight_kg']) ? (float)$body['weight_kg'] : null);

        $stmt->execute([
            $id,
            $ownerUserId,
            $ctx['club_id'],
            $name,
            $nameArabic,
            $nameEnglish,
            trim($body['nickname'] ?? '') !== '' ? trim($body['nickname']) : null,
            $body['number']       ?? null,
            $body['position']     ?? null,
            $body['team']         ?? $body['team_name'] ?? null,
            $body['category']     ?? null,
            $body['dominantFoot'] ?? $body['dominant_foot'] ?? null,
            $heightCm,
            $weightKg,
            $body['dateOfBirth']  ?? $body['date_of_birth'] ?? null,
            $body['nationality']  ?? null,
            $injuryNotes,
            $physicalNotes,
            $medicalNotes,
            $statusVal,
            $body['photoUrl']     ?? $body['photo_url'] ?? null,
            $expectedReturn,
            $unavailReason,
        ]);

        // Audit sensitive fields — only meaningful for edits to an existing
        // player, not the initial creation of the record.
        if ($existing !== null) {
            logAuditDiff($pdo, 'club_players', $id, $existing, [
                'weight_kg'     => $weightKg,
                'height_cm'     => $heightCm,
                'injury_notes'  => $injuryNotes,
                'medical_notes' => $medicalNotes,
                'status'        => $statusVal,
            ], (int)$user['id']);

            if (($existing['status'] ?? null) !== $statusVal) {
                recordPlayerStatusChange($pdo, $id, $existing['status'] ?? null, $statusVal, (int)$user['id']);
            }
        }

        // ── Provision the player's own login, if requested above ─────────────────
        if ($wantsLogin) {
            $hash = password_hash($password, PASSWORD_BCRYPT, ['cost' => 11]);
            $loginName = $nameEnglish !== '' ? $nameEnglish : $name;
            $pdo->prepare(
                'INSERT INTO users (name, email, password_hash, role, account_type,
                                    player_type, club_user_id, linked_player_id, is_active, status)
                VALUES (?, ?, ?, \'player\', \'player\', \'club\', ?, ?, 1, \'active\')'
            )->execute([$loginName, $email, $hash, $ownerUserId, $id]);
            $newUserId = (int)$pdo->lastInsertId();

            $pdo->prepare('UPDATE club_players SET linked_user_id = ? WHERE id = ?')
                ->execute([$newUserId, $id]);
        }

        jsonOut(['success' => true, 'id' => $id, 'login_created' => $wantsLogin]);
    }

    // ── DELETE: archive by default; permanent purge requires ?permanent=1 ─────────
    if ($method === 'DELETE') {
        $id = $_GET['id'] ?? (json_decode(file_get_contents('php://input'), true)['id'] ?? '');
        if (!$id) jsonOut(['error' => 'id is required'], 400);

        $ctx = requireClubPermission($pdo, $user, 'players.delete');
        $playerStmt = $pdo->prepare(
            'SELECT linked_user_id FROM club_players WHERE id = ? AND club_id = ?'
        );
        $playerStmt->execute([$id, $ctx['club_id']]);
        $player = $playerStmt->fetch(PDO::FETCH_ASSOC);
        if (!$player) jsonOut(['error' => 'Player not found'], 404);

        if (($_GET['permanent'] ?? '') === '1') {
            $linkedUserId = !empty($player['linked_user_id'])
                ? (int)$player['linked_user_id']
                : null;

            try {
                $pdo->beginTransaction();

                $injuryIds = existingIds($pdo, 'injury_cases', 'id', 'player_id', $id);
                deleteByIds($pdo, 'injury_updates', 'injury_case_id', $injuryIds);
                deleteByIds($pdo, 'rehabilitation_phases', 'injury_case_id', $injuryIds);
                deleteByIds($pdo, 'medical_attachments', 'injury_case_id', $injuryIds);

                $fmsIds = existingIds($pdo, 'fms_assessments', 'id', 'player_id', $id);
                deleteByIds($pdo, 'fms_movement_scores', 'assessment_id', $fmsIds);

                $taskIds = existingIds($pdo, 'tasks', 'id', 'linked_player_id', $id);
                deleteByIds($pdo, 'task_comments', 'task_id', $taskIds);

                $planIds = existingIds(
                    $pdo,
                    'training_plans',
                    'id',
                    'linked_player_id',
                    $id
                );
                if ($linkedUserId !== null) {
                    $planIds = array_values(array_unique(array_merge(
                        $planIds,
                        existingIds(
                            $pdo,
                            'training_plans',
                            'id',
                            'player_user_id',
                            $linkedUserId
                        )
                    )));
                }
                deleteByIds($pdo, 'individual_program_reviews', 'plan_id', $planIds);
                $trainingSessionIds = [];
                foreach ($planIds as $planId) {
                    $trainingSessionIds = array_merge(
                        $trainingSessionIds,
                        existingIds(
                            $pdo,
                            'training_sessions',
                            'id',
                            'plan_id',
                            $planId
                        )
                    );
                }
                $trainingSessionIds = array_values(array_unique($trainingSessionIds));
                deleteByIds(
                    $pdo,
                    'session_exercises',
                    'session_id',
                    $trainingSessionIds
                );
                deleteByIds(
                    $pdo,
                    'session_players',
                    'session_id',
                    $trainingSessionIds
                );
                deleteByIds(
                    $pdo,
                    'post_training_feedback',
                    'session_id',
                    $trainingSessionIds
                );
                deleteByIds(
                    $pdo,
                    'training_sessions',
                    'id',
                    $trainingSessionIds
                );

                deleteDirectPlayerReferences($pdo, $id);

                $pdo->prepare(
                    "DELETE FROM audit_logs
                    WHERE entity_type = 'club_players' AND entity_id = ?"
                )->execute([$id]);

                removePlayerFromJsonRoster(
                    $pdo,
                    'club_sessions',
                    'player_ids',
                    (int)$ctx['club_id'],
                    $id
                );
                removePlayerFromJsonRoster(
                    $pdo,
                    'club_sessions',
                    'completed_player_ids',
                    (int)$ctx['club_id'],
                    $id
                );
                removePlayerFromJsonRoster(
                    $pdo,
                    'matches',
                    'player_ids',
                    (int)$ctx['club_id'],
                    $id
                );
                removePlayerFromJsonRoster(
                    $pdo,
                    'matches',
                    'player_minutes',
                    (int)$ctx['club_id'],
                    $id
                );

                if ($linkedUserId !== null) {
                    foreach ([
                        ['user_tokens', 'user_id'],
                        ['user_profiles', 'user_id'],
                        ['notifications', 'user_id'],
                        ['player_body_metrics', 'user_id'],
                        ['player_hooper_index', 'user_id'],
                        ['player_rpe', 'user_id'],
                        ['player_wearable_data', 'user_id'],
                        ['survey_responses', 'user_id'],
                        ['assessments', 'user_id'],
                        ['ai_plans', 'user_id'],
                        ['training_plans', 'player_user_id'],
                        ['session_players', 'player_user_id'],
                        ['post_training_feedback', 'player_user_id'],
                    ] as [$table, $column]) {
                        deleteUserRows($pdo, $table, $column, $linkedUserId);
                    }
                    $pdo->prepare(
                        "DELETE FROM users
                        WHERE id = ? AND linked_player_id = ?
                        AND (role = 'player' OR player_type IS NOT NULL)"
                    )->execute([$linkedUserId, $id]);
                }

                $pdo->prepare(
                    'DELETE FROM club_players WHERE id = ? AND club_id = ?'
                )->execute([$id, $ctx['club_id']]);
                $pdo->commit();
                jsonOut(['success' => true, 'deleted_permanently' => true]);
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) $pdo->rollBack();
                error_log('Permanent player deletion failed: ' . $e->getMessage());
                jsonOut(['error' => 'Unable to permanently delete player records'], 500);
            }
        }

        $stmt = $pdo->prepare(
            'UPDATE club_players SET is_active = 0 WHERE id = ? AND club_id = ?'
        );
        $stmt->execute([$id, $ctx['club_id']]);
        if (!empty($player['linked_user_id'])) {
            $pdo->prepare(
                "UPDATE users SET is_active = 0, status = 'archived'
                WHERE id = ? AND linked_player_id = ?"
            )->execute([(int)$player['linked_user_id'], $id]);
            $pdo->prepare('DELETE FROM user_tokens WHERE user_id = ?')
                ->execute([(int)$player['linked_user_id']]);
        }
        jsonOut(['success' => true, 'archived' => true]);
    }

    jsonOut(['error' => 'Method not allowed'], 405);
