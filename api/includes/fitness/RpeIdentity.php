<?php

final class RpeIdentity
{
    public static function logicalKey(
        ?string $linkedPlayerId,
        int $userId,
        ?string $sessionId,
        string $rpeType,
        string $activityDate,
        ?string $sessionType,
        ?string $externalReference
    ): string {
        $identity = $linkedPlayerId ? 'p:' . $linkedPlayerId : 'u:' . $userId;
        if ($sessionId) {
            return implode('|', [$identity, 'session:' . $sessionId, 'rpe:' . $rpeType]);
        }
        return implode('|', [
            $identity,
            'date:' . $activityDate,
            'activity:' . ($sessionType ?: 'unspecified'),
            'external:' . ($externalReference ?: 'default'),
            'rpe:' . $rpeType,
        ]);
    }
}
