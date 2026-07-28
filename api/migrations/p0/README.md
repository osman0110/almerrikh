# P0 fitness data-integrity package

Status: files prepared for review only. No migration or test command has been
run by Codex.

## Approved calculation change

Old implementation:

`(7-day total / 7) / (28-day total / 28)`

This happened to produce the same ratio as the desired formula only when both
windows were treated as daily averages, but the endpoint also returned the
misleading daily values as acute/chronic and treated missing data as zero.
Earlier audited variants also divided the 7-day total directly by the 28-day
total, producing `0.25` for stable load.

P0 implementation:

`ACWR = 7-day total / (28-day total / 4)`

The result is `null` with `INSUFFICIENT_DATA` unless all 28 daily statuses are
resolved. Formula version:

`rolling_7_over_rolling_28_weekly_average_v1`

Classification thresholds are centralized in `FitnessConfig.php`. ACWR remains
an advisory indicator and is not an injury diagnosis or automatic exclusion.

## Migration order

| Order | Migration | Purpose | Main risk | Rollback |
|---|---|---|---|---|
| 1 | `0001_fitness_configuration_and_migration_tracking.sql` | Migration history, Kigali timezone/week settings, seasons, staff team scope | Short metadata lock on `club_staff` | Matching `.down.sql` |
| 2 | `0002_body_composition_workflow.sql` | Completeness, provenance, approval, revisions and import batches | Assessment table rebuild on older MySQL | Matching `.down.sql` |
| 3 | `0003_audit_and_player_status_history.sql` | Rich audit context and period-correct player status | Audit table metadata lock | Matching `.down.sql` |
| 4 | `0004_rpe_revision_and_idempotency.sql` | Logical keys, revisions and reversible archive fields | RPE table rebuild/backfill | Matching `.down.sql` |
| 5 | `0005_archive_rpe_duplicates_and_add_unique_key.sql` | Archive duplicates, then enforce uniqueness | Data-changing; requires explicit report approval | Matching `.down.sql` |
| 6 | `0006_correct_body_composition_club_scope.sql` | Correct proven body-measurement club scope with ledger/audit | Data-changing; requires wrong-scope report approval | Matching `.down.sql` |

Migration 0005 must not run until its duplicate report is exported and the
retained rows are approved. It keeps the newest valid row, archives the rest in
place, logs each archive, and does not delete any row.

Migration 0006 must not run until the wrong-`club_id` report is approved. It
keeps every original value in a correction ledger and has a data rollback.

Existing body-composition rows are backfilled as `legacy_unreviewed`, not
silently approved. Official reads use approved new-system rows first and then
legacy fallback.

## Selected import policy

Bulk body-composition import uses `PARTIAL_IMPORT`:

- each row is validated independently;
- accepted rows and rejected-row reasons are returned;
- the whole operation is wrapped in a transaction against unexpected server
  failure;
- a fatal error rolls the whole batch back;
- normal validation failures do not reject otherwise valid rows;
- `import_batch_id` links saved records, the batch summary and audit entry.

## Read-only preflight

Run with a read-only DB account:

```powershell
mysql --host=<host> --user=<readonly-user> --database=<test-db> --table < api/migrations/p0/preflight_data_audit.sql
```

The report returns:

- old/new body-measurement counts;
- likely cross-system duplicates;
- wrong body `club_id` values;
- partial Skinfold records with calculated body fat;
- RPE duplicate groups and load inflation;
- players without accounts;
- Hooper/RPE population differences;
- scheduled sessions and matches missing RPE.

Static search for remaining production placeholders:

```powershell
rg -n "load_pct.*[0-9]|attendance_pct.*[0-9]|readiness_pct.*[0-9]|demo|mock" api --glob "*.php"
```

## Migration commands — do not run before approval

```powershell
php api/cli/migrations.php status
php api/cli/migrations.php up 0001_fitness_configuration_and_migration_tracking.sql
php api/cli/migrations.php up 0002_body_composition_workflow.sql
php api/cli/migrations.php up 0003_audit_and_player_status_history.sql
php api/cli/migrations.php up 0004_rpe_revision_and_idempotency.sql
php api/cli/migrations.php up 0005_archive_rpe_duplicates_and_add_unique_key.sql
php api/cli/migrations.php up 0006_correct_body_composition_club_scope.sql
```

Rollback one reviewed migration:

```powershell
php api/cli/migrations.php down 0004_rpe_revision_and_idempotency.sql
```

DDL auto-commits on MySQL. Take a tested backup before `up`, and validate each
migration before proceeding to the next.

## Post-migration validation

```sql
SELECT migration_name, checksum_sha256, applied_at
FROM schema_migrations ORDER BY migration_name;

SELECT approval_status, calculation_status, COUNT(*)
FROM player_body_composition_assessments
GROUP BY approval_status, calculation_status;

SELECT logical_key, COUNT(*)
FROM player_rpe
WHERE logical_key IS NOT NULL AND is_active_record = 1
GROUP BY logical_key HAVING COUNT(*) > 1;

SELECT COUNT(*) AS archived_without_replacement
FROM player_rpe
WHERE is_active_record = 0 AND replaced_by_rpe_id IS NULL;
```

## Test commands — test database only, approval required

Pure regression tests:

```powershell
php api/tests/p0_acwr_calculator_test.php
php api/tests/p0_body_composition_completeness_test.php
php api/tests/p0_rpe_identity_test.php
php api/tests/p0_training_load_quality_test.php
```

Integration test:

```powershell
$env:APP_ENV = "test"
$env:TEST_DB_NAME = "<isolated-test-db>"
php api/tests/p0_scope_integration_test.php
```

The integration test refuses to run unless `APP_ENV=test` and
`TEST_DB_NAME` are both present.

## Runtime schema transition

Normal API requests now validate schema and do not call `ensureSchema()`.
`ALLOW_RUNTIME_SCHEMA_BOOTSTRAP=1` is a temporary compatibility escape hatch
for an explicitly controlled legacy bootstrap only. It must not be enabled in
normal production request handling.

The remaining historical DDL inside `ensureSchema()` is inventoried in
`runtime_schema_inventory.md`. It was not rewritten into one dangerous
migration as part of this P0 package.

## Decisions still requiring approval

1. Populate and activate the first `club_seasons` row; the resolver returns
   `NO_ACTIVE_SEASON` until administration does so.
2. Confirm ACWR threshold values currently centralized as 0.79, 1.30 and 1.50.
3. Decide which `legacy_unreviewed` body assessments may be approved.
4. Approve the RPE duplicate retain/archive report before migration 0005.
5. Confirm the `PARTIAL_IMPORT` policy instead of all-or-nothing.
