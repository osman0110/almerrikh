<?php
// Which assessments a PLAYER may see about themselves (rule 2026-09-19):
// only coach-approved results, plus rows the player recorded themselves.
//
// assessments.status is created by migration 0021 (and by the legacy
// ensureSchema bootstrap). If a database does not have the column yet there
// is no approval workflow at all, so a saved assessment is final and stays
// visible — never a 500 for the player. The fallback keeps the same single
// `?` placeholder (the caller's user id) so call sites bind identically.
require_once __DIR__ . '/fitness/SchemaInspector.php';

function playerAssessmentVisibilitySql(PDO $pdo): string {
    static $hasStatus = null;
    if ($hasStatus === null) {
        try {
            $hasStatus = SchemaInspector::hasColumn($pdo, 'assessments', 'status');
        } catch (Throwable $e) {
            $hasStatus = false;
        }
    }
    return $hasStatus
        ? '(status = "approved" OR user_id = ?)'
        : '(1 = 1 OR user_id = ?)';
}
