# P0 implementation report

## Implemented

1. Central Kigali timezone/week configuration.
2. Central ACWR calculator with 28-day completeness and formula version.
3. Unified eligible-player repository independent of player login accounts.
4. Unified body-composition repository:
   - approved new system first;
   - legacy fallback;
   - explicit source and read-only legacy markers;
   - `muscle_mass_kg = null` unless truly measured.
5. Club/team scoping for body list, detail, compare, write, import and goals.
6. Correct `club_id` on new bulk rows.
7. Partial-import transaction, row results and batch tracking.
8. Skinfold required-site validation; incomplete rows remain drafts and have no
   calculated body-fat percentage.
9. Body approval/unapproval endpoint and revision/audit support.
10. Training-load quality statuses, expected/completed counts, reasons,
    approval eligibility and preliminary statistics.
11. Historical status is never inferred from the current player status.
12. ACWR consumes the deduplicated quality-aware daily load source.
13. Hooper/RPE/load team reports share one club/team roster population.
14. RPE logical identity, idempotency key, in-place correction and revisions.
15. Placeholder load/attendance/readiness values removed from
    `api/coach/players.php`.
16. Normal requests no longer execute `ensureSchema()`; an explicit legacy
    bootstrap flag remains for controlled transition.
17. Flutter compatibility handling for nullable/insufficient data and
    read-only legacy body rows.

## Central services added

- `api/includes/fitness/FitnessConfig.php`
- `api/includes/fitness/AcwrCalculator.php`
- `api/includes/fitness/ActiveSeasonResolver.php`
- `api/includes/fitness/EligiblePlayerRepository.php`
- `api/includes/fitness/BodyCompositionRepository.php`
- `api/includes/fitness/TrainingLoadDataQuality.php`
- `api/includes/fitness/RpeIdentity.php`
- `api/includes/fitness/SchemaInspector.php`

## Main existing files changed

- `api/db.php`
- `api/includes/club_auth.php`
- `api/includes/audit_log.php`
- `api/includes/body_composition_calculator.php`
- `api/player/training-load/TrainingLoadCalculator.php`
- `api/player/training-load/weekly.php`
- `api/player/monitoring/dashboard.php`
- `api/coach/monitoring/dashboard.php`
- `api/club/team-wellness.php`
- `api/club/wellness_summary.php`
- `api/club/body-composition/team-summary.php`
- body-composition save/update/list/bulk/detail/history/compare/delete/goal endpoints
- `api/player/rpe/save.php`
- `api/player/rpe/history.php`
- `api/coach/players.php`
- `api/report_helpers.php`
- player/club profile body-measurement reads
- minimal Flutter models/screens that must distinguish missing values from zero

## New endpoints/tools

- `api/club/active-season.php`
- `api/player/body-composition/approve.php`
- `api/cli/migrations.php`
- `api/migrations/p0/preflight_data_audit.sql`

## Expected report impact

- Stable complete four-week load: ACWR remains `1.0`.
- Missing/unknown day: ACWR becomes `null / INSUFFICIENT_DATA`, not zero.
- Acute load now means the 7-day total.
- Chronic load now means the 28-day total divided by four.
- Duplicate RPE rows no longer silently qualify a weekly report for approval.
- Monotony and Strain move to `preliminary_stats` when the week is incomplete.
- Unscheduled/no-record days are not silently converted into rest days.
- New incomplete Skinfold submissions have no body-fat calculation and are
  excluded from approved summaries.
- Team body reports use approved new data, with explicit legacy fallback.
- Missing coach-player KPIs return `null` and `NO_DATA`, not 50/85/80.

## Verification performed

- PHP syntax-only validation passed for the changed PHP files.
- UTF-8 BOM inspection passed for the P0 file set.
- Insert placeholder counts were reviewed for the changed body/RPE writes.

No unit test, integration test, Flutter build, migration, data correction or
database audit query was executed.

## Reports unavailable until approved execution

The following counts cannot be truthfully supplied without running the
read-only preflight against the target/test database:

- RPE duplicate count and affected players/sessions;
- load inflation amount;
- wrong body `club_id` count;
- incomplete Skinfold records with an existing calculation;
- old/new cross-system likely duplicates;
- players missing accounts and Hooper/load population difference.

Use `preflight_data_audit.sql` with a read-only account. Do not run migrations
0005 or 0006 until the respective result sets are reviewed.
