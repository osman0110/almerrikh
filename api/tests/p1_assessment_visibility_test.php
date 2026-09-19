<?php
// Pure regression test — no DB server needed.
// Player assessment visibility must never 500: with the review column it is
// "approved OR self-recorded"; if the schema check itself fails (column or
// information_schema unavailable) it falls back to "saved = final" with the
// SAME single placeholder, so call sites keep binding [.., user_id].
require_once dirname(__DIR__) . '/includes/assessment_visibility.php';

final class BrokenSchemaPdo extends PDO {
    public function __construct() { parent::__construct('sqlite::memory:'); }
    #[\ReturnTypeWillChange]
    public function prepare($query, $options = []) { throw new PDOException('no information_schema'); }
    #[\ReturnTypeWillChange]
    public function query($query, $fetchMode = null, ...$args) { throw new PDOException('no information_schema'); }
}

$sql = playerAssessmentVisibilitySql(new BrokenSchemaPdo());
$failures = [];
if ($sql !== '(1 = 1 OR user_id = ?)') $failures[] = "fallback clause unexpected: $sql";
if (substr_count($sql, '?') !== 1) $failures[] = 'fallback must keep exactly one placeholder';

if ($failures) { fwrite(STDERR, "p1_assessment_visibility_test: FAIL\n" . implode("\n", $failures) . "\n"); exit(1); }
echo "p1_assessment_visibility_test: OK\n";
