<?php

function disciplineSettings(PDO $pdo, int $competitionId): ?array
{
    $stmt = $pdo->prepare('SELECT * FROM club_competitions WHERE id = ? AND is_active = 1');
    $stmt->execute([$competitionId]);
    return $stmt->fetch() ?: null;
}

function disciplineActiveSuspension(PDO $pdo, int $clubId, string $playerId, int $competitionId): ?array
{
    $stmt = $pdo->prepare("SELECT * FROM player_suspensions WHERE club_id = ? AND player_id = ? AND competition_id = ? AND status = 'active' ORDER BY id DESC LIMIT 1");
    $stmt->execute([$clubId, $playerId, $competitionId]);
    return $stmt->fetch() ?: null;
}

function disciplineEnsureCycle(PDO $pdo, array $match, array $competition, string $playerId): int
{
    $stmt = $pdo->prepare('SELECT id FROM player_discipline_cycles WHERE player_id = ? AND competition_id = ? AND completed_at IS NULL ORDER BY cycle_number DESC LIMIT 1');
    $stmt->execute([$playerId, (int)$competition['id']]);
    $id = $stmt->fetchColumn();
    if ($id) return (int)$id;
    $stmt = $pdo->prepare('SELECT COALESCE(MAX(cycle_number), 0) + 1 FROM player_discipline_cycles WHERE player_id = ? AND competition_id = ?');
    $stmt->execute([$playerId, (int)$competition['id']]);
    $number = (int)$stmt->fetchColumn();
    $stmt = $pdo->prepare('INSERT INTO player_discipline_cycles (club_id, player_id, competition_id, season_id, cycle_number, started_at) VALUES (?, ?, ?, ?, ?, ?)');
    $stmt->execute([(int)$match['club_id'], $playerId, (int)$competition['id'], $competition['season_id'] ?? null, $number, $match['match_date']]);
    return (int)$pdo->lastInsertId();
}

function disciplineCreateSuspension(PDO $pdo, array $match, array $competition, string $playerId, string $reasonType, string $reason, int $matches, int $userId, ?int $sourceCardId = null): void
{
    if ($matches < 1 || disciplineActiveSuspension($pdo, (int)$match['club_id'], $playerId, (int)$competition['id'])) return;
    $stmt = $pdo->prepare('INSERT INTO player_suspensions (club_id, player_id, competition_id, season_id, reason_type, reason, source_card_id, matches_total, matches_remaining, created_by_user_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    $stmt->execute([(int)$match['club_id'], $playerId, (int)$competition['id'], $competition['season_id'] ?? null, $reasonType, $reason, $sourceCardId, $matches, $matches, $userId]);
}

function disciplineProcessCards(PDO $pdo, array $match, int $userId): void
{
    $competitionId = (int)($match['competition_id'] ?? 0);
    if (!$competitionId || !($competition = disciplineSettings($pdo, $competitionId))) return;
    $stmt = $pdo->prepare('SELECT id, player_id, card_type, reason FROM match_cards WHERE match_id = ?');
    $stmt->execute([$match['id']]);
    $byPlayer = [];
    $newIds = $match['_new_card_ids'] ?? null;
    foreach ($stmt->fetchAll() as $card) {
        if ($newIds !== null && !in_array((int)$card['id'], $newIds, true)) continue;
        $byPlayer[$card['player_id']][] = $card;
    }
    foreach ($byPlayer as $playerId => $cards) {
        $cycleId = disciplineEnsureCycle($pdo, $match, $competition, (string)$playerId);
        $yellowCount = 0; $yellowCardId = null;
        foreach ($cards as $card) if ($card['card_type'] === 'yellow') { $yellowCount++; $yellowCardId = (int)$card['id']; }
        if ($yellowCount) $pdo->prepare('UPDATE player_discipline_cycles SET current_yellow_cards = current_yellow_cards + ? WHERE id = ?')->execute([$yellowCount, $cycleId]);
        $currentStmt = $pdo->prepare('SELECT current_yellow_cards FROM player_discipline_cycles WHERE id = ?');
        $currentStmt->execute([$cycleId]);
        $current = (int)$currentStmt->fetchColumn();
        if ($current >= max(1, (int)$competition['yellow_card_threshold'])) disciplineCreateSuspension($pdo, $match, $competition, (string)$playerId, 'yellow_threshold', $current . ' yellow cards reached the competition threshold', max(1, (int)$competition['suspension_matches']), $userId, $yellowCardId);
        if ($yellowCount >= 2) {
            disciplineCreateSuspension($pdo, $match, $competition, (string)$playerId, 'two_yellows_match', 'Two yellow cards in one match', max(1, (int)$competition['two_yellows_suspension_matches']), $userId, $yellowCardId);
            $redCheck = $pdo->prepare("SELECT id FROM match_cards WHERE match_id = ? AND player_id = ? AND card_type = 'red' AND reason = 'Second yellow in the same match' LIMIT 1");
            $redCheck->execute([$match['id'], $playerId]);
            if (!$redCheck->fetchColumn()) {
                $pdo->prepare("INSERT INTO match_cards (match_id, player_id, card_type, reason, created_by_user_id) VALUES (?, ?, 'red', 'Second yellow in the same match', ?)")->execute([$match['id'], $playerId, $userId]);
            }
        }
        foreach ($cards as $card) if ($card['card_type'] === 'red') disciplineCreateSuspension($pdo, $match, $competition, (string)$playerId, 'direct_red', $card['reason'] ?: 'Direct red card', max(1, (int)$competition['direct_red_suspension_matches']), $userId, (int)$card['id']);
    }
}

function disciplineAdvanceForCompletedMatch(PDO $pdo, array $match): void
{
    if (($match['status'] ?? '') !== 'completed' || !(int)($match['competition_id'] ?? 0)) return;
    $stmt = $pdo->prepare("SELECT id, player_id, competition_id FROM player_suspensions WHERE club_id = ? AND competition_id = ? AND status = 'active'");
    $stmt->execute([(int)$match['club_id'], (int)$match['competition_id']]);
    foreach ($stmt->fetchAll() as $suspension) {
        $insert = $pdo->prepare('INSERT IGNORE INTO suspension_match_executions (suspension_id, match_id) VALUES (?, ?)');
        $insert->execute([(int)$suspension['id'], $match['id']]);
        if ($insert->rowCount() !== 1) continue;
        $pdo->prepare("UPDATE player_suspensions SET matches_remaining = GREATEST(matches_remaining - 1, 0), status = IF(matches_remaining <= 1, 'completed', 'active'), executed_at = IF(matches_remaining <= 1, CURDATE(), executed_at) WHERE id = ? AND status = 'active'")->execute([(int)$suspension['id']]);
        $done = $pdo->prepare('SELECT status FROM player_suspensions WHERE id = ?');
        $done->execute([(int)$suspension['id']]);
        if ($done->fetchColumn() === 'completed') {
            $settings = disciplineSettings($pdo, (int)$suspension['competition_id']);
            if (!$settings || (int)$settings['reset_yellow_cycle'] === 1) {
                $pdo->prepare('UPDATE player_discipline_cycles SET current_yellow_cards = 0, completed_at = CURDATE() WHERE player_id = ? AND competition_id = ? AND completed_at IS NULL')->execute([$suspension['player_id'], (int)$suspension['competition_id']]);
            }
        }
    }
}

function disciplineAssertPlayersEligible(PDO $pdo, int $clubId, ?int $competitionId, array $playerIds): void
{
    if (!$competitionId || !$playerIds) return;
    $placeholders = implode(',', array_fill(0, count($playerIds), '?'));
    $stmt = $pdo->prepare("SELECT player_id FROM player_suspensions WHERE club_id = ? AND competition_id = ? AND status = 'active' AND player_id IN ($placeholders)");
    $stmt->execute(array_merge([$clubId, $competitionId], $playerIds));
    $blocked = $stmt->fetchColumn();
    if ($blocked !== false) throw new RuntimeException('Player ' . $blocked . ' has an active suspension in this competition');
}
