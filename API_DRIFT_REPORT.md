# API Drift Report — `merr/api` vs `academy/nextkickwebsite/api`

**Method:** `diff -rq` (full recursive byte-for-byte comparison) across every file in both trees, followed by full unified diffs of every file that differed, cross-checked against the corresponding Flutter model classes in `lib/models/club_models.dart`.

**Authority:** `academy/nextkickwebsite/api` is the deployed/production copy (per project record and the prior commit message "Sync merr/api with nextkickwebsite (source of truth)"); file mtimes confirm its copies are newer in all four cases. Direction of sync throughout this report is nextkickwebsite → merr.

---

## Result: only 4 files differed content-wise across the entire tree

`diff -rq` found **zero** other content differences anywhere in `api/club/`, `api/player/`, `api/coach/`, `api/includes/`, `api/mobile/`, `api/team/`, `api/session/`, `api/sessions/`, `api/players/`, `api/config/`, `api/fms/`, `api/ai/`, `api/alerts/`, or root-level `*.php` — those trees are byte-identical. The scope of drift is narrow, not systemic.

| Endpoint | MERR (before fix) | Deployed API | Difference | Impact | Action |
|---|---|---|---|---|---|
| `api/club/report-archive.php` | Old ad-hoc bucketing, computed on every GET, no persistence, no team scope, string-composite `id` | Persists to `report_period_archives` (migration `0014_report_period_archive.sql`), team-scoped, timezone-correct bucketing (`FitnessConfig::timezone()`), adds `player_count`/`data_completeness`/`generated_at`/`last_refreshed_at`, numeric `BIGINT` `id` | Response is a strict superset (all old fields retained; `id` type changes from a composite string to a stringifiable number, but is consumed via `.toString()` client-side so this is compatible) | **Was HIGH** — stale/unpersisted reports, no team scoping. Flutter's `ReportArchiveEntry.fromJson` (`lib/models/club_models.dart:1785-1800`) already reads `player_count`/`data_completeness`/`last_refreshed_at` — the client was already built against the newer contract merr's API hadn't caught up to. | **Synced.** Copied file + migrations `0014_report_period_archive.sql/.down.sql` into `merr/api`. |
| `api/matches.php` | Missing `rating`, `injured` on participations; missing `stage`, `round_label`, `group_name`, `our_score`, `opponent_score` on the match itself | Persists all of the above (migration `0020_match_stage_and_result.sql`) | Pure additive columns/fields, no removed/renamed fields | **Was HIGH — real data loss.** `MatchParticipation.fromJson` (`club_models.dart:1543-1559`) already parses `rating`/`injured` from the response; the Flutter UI could submit these values and they'd silently vanish server-side. | **Synced.** Copied file + migration `0020_match_stage_and_result.sql/.down.sql`. |
| `api/club/competitions.php` | Missing `format_type`, `stages_count`, `win_points`, `draw_points`, `loss_points`, `tie_break_rule`, `competition_status` | Persists all of the above (migration `0019_competition_format.sql`) | Pure additive columns/fields | **Was MEDIUM.** `ClubCompetition.fromJson` (`club_models.dart:378-384`) already declares `tieBreakRule`/`competitionStatus` fields — client ahead of stale API. | **Synced.** Copied file + migration `0019_competition_format.sql/.down.sql`. |
| `api/sessions.php` (`action=attendance`) | Legacy summary UPDATE scoped by `user_id` (session creator only) | Scoped by `club_id` | One-line WHERE-clause fix (see RB2) | **Was HIGH — silent no-op** for any non-creator staff marking attendance. | **Synced** (see RB2 remediation — merr's copy was fixed directly, matching the already-correct nextkickwebsite version; no file copy needed here since only this one clause differed). |

## Files present only on one side (not drift — confirmed non-applicable to merr)

| Path | Only in | Why it's not a drift issue |
|---|---|---|
| `admin/`, `academy/`, `parent/`, `analysis/jobs.php`, `db_credentials.php` (expected, gitignored), `health.php`, `serve_upload.php`, `club/admin-executive-report.php`, `club/admin-player-report.php` | nextkickwebsite only | nextkickwebsite-specific portals/modules (academy management, org admin, parent portal) that merr's Flutter app has no screens for. Not part of MERR's API contract. |
| `cli/test_push.php` | nextkickwebsite only | Generic manual push-notification CLI smoke tool; depends on `includes/push.php`, which doesn't exist in merr's tree (merr uses `includes/notifications.php`). Not wired to any merr endpoint. |
| `tests/payment_verification_test.php` | nextkickwebsite only | Tests `academy/payment_verification/PaymentVerification.php` — nextkickwebsite's academy payment-parsing module. Entirely unrelated to Al Merrikh SC. |
| `config/.htaccess` | nextkickwebsite only | Web-server config, not an API contract file; not evaluated here (infra concern, not app-layer drift). |
| `migrations/p0/0018_medical_module_tables.sql/.down.sql` | nextkickwebsite only | No merr PHP endpoint currently reads/writes these tables (medical module is explicitly post-MVP per CLAUDE.md). Copied into `merr/api/migrations/p0/` anyway for schema-tracking consistency with the shared deployed DB, but not wired to any code path — no functional impact from copying it. |

## Post-sync verification performed

- **JSON response schemas**: `report-archive.php`'s new response is additive-only (verified via full diff — no field removed or renamed); `matches.php` and `competitions.php` are additive-only (verified same way).
- **Nullable fields**: new fields (`rating`, `injured`, `stage`, `round_label`, `group_name`, `our_score`, `opponent_score`, `format_type`, etc.) are all nullable/defaulted in both the SQL migrations and the PHP `??`-guarded reads — no new NOT NULL constraint without a default.
- **Numeric types**: `report_period_archives.id` is `BIGINT UNSIGNED`; Flutter's `ReportArchiveEntry.id` reads it via `.toString()`, not `int.parse()`, so the type change from composite-string to numeric ID is compatible.
- **Dates**: `report-archive.php` now uses `FitnessConfig::timezone()`-aware `DateTimeImmutable` bucketing instead of implicit server-timezone dates — verified this doesn't change the *type* returned (`Y-m-d` strings both before and after), only the correctness of which calendar day a submission is bucketed into.
- **Authentication**: unchanged — all three files still use the same bearer-token `getAuthUser()`/`user_tokens` pattern already in place elsewhere.
- **RBAC**: `report-archive.php`'s permission check is now stricter — it 403s outright if the caller has neither `fitness.training_load.view` nor `fitness.body_composition.view`, versus the old version's `players.read`-gated-then-silently-empty-list behavior. This is a deliberate, documented behavior change in the authoritative version, not a regression — flagged here for visibility, not reverted.
- **Pagination**: `report-archive.php` caps at `LIMIT 200` (new); the old version had no persisted store and thus no pagination concept. Not a regression — 200 covers ~4 years of weekly reports.
- **Error responses**: new `report-archive.php` returns `503 REPORT_ARCHIVE_MIGRATION_REQUIRED` if `report_period_archives` doesn't exist — this is why the backing migration was copied over in the same change, not just the PHP file.
- **PHP syntax**: `php -l` run against all three synced files — no syntax errors.

## Regression coverage added

See `MERR_PRODUCTION_READINESS_REPORT.md` → Remediation Status for the attendance-scope tests (`p0_sessions_write_permission_test.php`, `p0_attendance_scope_test.php`). No PHP unit-test harness exists for `report-archive.php`/`matches.php`/`competitions.php` specifically (they require a live/test DB with seeded fixtures matching the new schema); this is called out as a remaining gap in Phase 3 of the remediation report rather than silently left uncovered.

## Process recommendation

This is the second time `merr/api` has drifted from the deployed copy after a "sync" commit. Recommend a pre-commit or CI check that runs `diff -rq merr/api academy/nextkickwebsite/api` (excluding known nextkickwebsite-only paths) and fails the build if any shared-path file differs, so drift is caught before it reaches another audit cycle.
