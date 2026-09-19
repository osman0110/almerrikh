# MERR Production Readiness Report
**Scope:** Al Merrikh SC Flutter app + PHP/MySQL API (`merr/api` and its deployed twin `academy/nextkickwebsite/api`)
**Method:** Static source review across architecture, API contracts, calculations, security/RBAC, UI/UX, localization/RTL, and tests. No destructive testing performed.

---

## 1. Executive Summary

The MVP workflow (Login → Dashboard → Players → Assessment → Camera → Results → Save) is genuinely built, not scaffolding — screens are deep, calculations (training load, ACWR, monotony/strain, Hooper) are textbook-correct with real edge-case guards, server-side authorization is centralized and actually enforces club/role isolation (not just UI hiding), and Arabic/RTL + PDF export are solid. This is a materially better foundation than the average "MVP demo."

It is **not production-ready today**, for three concrete reasons, not vibes:

1. **Two of the three MVP-required physical tests are disabled in the running code.** `player_selection_page.dart` gates Single Leg Balance and Jump Landing behind a "coming soon" snackbar — only Squat is reachable end-to-end. This directly contradicts CLAUDE.md's strict MVP scope and would be visible in the first five minutes of any coach demo.
2. **The deployed API (`nextkickwebsite/api`) and the local copy (`merr/api`) are still not fully synced** despite a recent sync commit — `report-archive.php` and `matches.php` diverge in ways that mean fields the Flutter client sends (match rating, injury flag, stage, scores) are silently dropped by the older logic, and session attendance updates are scoped to the wrong column (`user_id` instead of `club_id`), causing silent no-ops for any staff member who isn't the session's original creator.
3. **No CI, and effectively no test coverage of anything except the pose/biomechanics math.** Auth, API parsing, calculations end-to-end, forms, and navigation have zero automated tests; `flutter_test` isn't even declared in `pubspec.yaml` (it currently resolves only by accident via the lockfile).

None of this requires a rewrite. Every P0/P1 below is a targeted fix, consistent with CLAUDE.md's "minimal patches, no rewrites" mandate.

---

## 2. Overall Readiness

**Score: 64/100 — 🟡 READY WITH REQUIRED FIXES**

The gap between "looks demo-ready" and "is production-ready" is concentrated in a small number of fixable items (Section 15/Release Blockers), not systemic rot.

| Category | Score |
|---|---:|
| Functional correctness | 60/100 |
| Data accuracy | 75/100 |
| Sports calculations | 90/100 |
| API/backend integration | 65/100 |
| UX/UI | 68/100 |
| Responsive design | 78/100 |
| Arabic/RTL | 80/100 |
| Accessibility | 45/100 |
| Performance | 60/100 |
| Security | 62/100 |
| Authentication/RBAC | 78/100 |
| Error handling | 50/100 |
| Testing | 20/100 |
| Production configuration | 45/100 |
| **Overall (weighted)** | **64/100** |

---

## 3. Critical Findings (P0/P1)

| ID | Sev | Area | Finding |
|---|---|---|---|
| F1 | P0 | Functional/Scope | Single Leg Balance and Jump Landing assessments are disabled ("coming soon") — only Squat works end-to-end, contradicting CLAUDE.md's 3-test MVP scope. `player_selection_page.dart:222-249`. |
| F2 | P1 | API sync | `api/club/report-archive.php` in `merr/api` runs an older, unpersisted, non-team-scoped implementation vs. the deployed `nextkickwebsite/api` version. |
| F3 | P1 | API sync / data loss | `api/matches.php` in `merr/api` silently drops `rating`, `injured`, `stage`, `round_label`, `group_name`, `our_score`, `opponent_score` that the deployed version persists. |
| F4 | P1 | Correctness bug | `api/sessions.php:365-367` scopes the attendance-summary UPDATE by `user_id` (session creator) instead of `club_id` — any other staff member marking attendance silently updates 0 rows, no error surfaced. |
| F5 | P1 | Error handling | Detail screens (`match_detail_page.dart`, `session_detail_page.dart`, `match_form_page.dart`, `assessment_hub_page.dart`) wrap initial data loads in `catch (_) {}` with no error state or retry — failures are invisible to the user. |
| F6 | P1 | Error handling / demo risk | Native camera-init failure in `assessment_camera_page.dart:253-267` has an empty catch — the code comment itself documents "UI shows black preview" as known behavior, on the single most demo-critical screen. |
| F7 | P1 | Security | Auth token and role/club identifiers stored in plaintext `SharedPreferences`/`localStorage`, no `flutter_secure_storage`; combined with Android `allowBackup` defaulting to `true`, the token is extractable via `adb backup` on a debuggable/rooted device. |
| F8 | P1 | Production build | Android release build has no `minifyEnabled`/`shrinkResources`/ProGuard config — ships unobfuscated; `key.properties` missing silently produces an unsigned/misconfigured release with no build-time error. |
| F9 | P1 | Testing/CI | No CI workflow runs tests or `flutter analyze`; `flutter_test` isn't declared in `pubspec.yaml` (works today only via a stale lockfile entry); zero tests for auth, API/model parsing, or calculations end-to-end. |
| F10 | P1 | Localization | `assessment_result_page.dart`'s manual score-edit/approve dialog has ~15 hardcoded Arabic (and stray English "DEBUG") strings bypassing the app's ar/en/fr localization system, on a core MVP screen. |
| F11 | P1 | Architecture | No state-management framework — global mutable variables in `app_state.dart` (currentUserRole, currentClubName, etc.) with no notification mechanism; `ClubService` (56KB) and `ReportService` (116KB) are god classes mixing networking/formatting/business logic. |

---

## 4. Functional Audit

| Module | Status | Problems | Priority |
|---|---|---|---|
| Club Dashboard | Working | Best-implemented error/loading pattern in the app (`club_dashboard.dart:698-793`); use as the template for other screens. | — |
| Player Management | Working | No major issues found in sampled review. | — |
| Player Profiles | Working | `club_player_profile_page.dart` (5589 lines) is deep and fully localized (155 loc calls). | P3 (size/maintainability) |
| Session Management | Partially broken | Attendance update bug (F4) causes silent data loss for non-creator staff. | P1 |
| AI Physical Assessment | Partially broken | Only Squat test reachable; other two MVP tests gated "coming soon" (F1). Native camera failure has no user feedback (F6). | P0/P1 |
| Reports | Working | `ReportService` (3083 lines) fully implemented, PDF generation with correct Arabic font + RTL, charts (`fl_chart`) driven by real data with proper empty states. | P3 (god-class size; hardcoded Arabic chart empty-state strings) |
| Post-MVP modules present in code | Scope violation | `nutrition_screen.dart`, `massage_dashboard.dart`, `injury_case_screen.dart`, `doctor_dashboard.dart`, `physio_session_screen.dart` already exist despite CLAUDE.md marking these post-MVP. Not a bug, but a scope-discipline flag. | P3 |

---

## 5. Calculation Audit

| Calculation | Current Logic | Risk | Recommendation |
|---|---|---|---|
| sRPE / session load | `TrainingLoadCalculator.php`: `session_load = rpe × duration`, null-guards missing inputs, guards `rpe<=0`/`dur<0` | Low — correct | None needed |
| ACWR | `AcwrCalculator.php`: acute 7-day sum ÷ chronic 28-day weekly average; requires strictly complete 28/28 days or returns `INSUFFICIENT_DATA`; explicit `NO_CHRONIC_LOAD` guard on zero denominator | Low — conservative, correct | None needed. (Uses rolling-average couplet, not EWMA — acceptable for this tier.) |
| Monotony / Strain | Sample SD (n−1), `NO_LOAD` vs `CONSTANT_NON_ZERO_LOAD` (displays `'∞'`) states instead of crashing on zero-variance weeks | Low — better than typical implementations | None needed |
| Hooper Index | Sum of 4 items (sleep/fatigue/stress/soreness), each validated 1–7 server-side, thresholds ≤10/≤16/>16 | Low, but note: uses 4 of the classic 5 Hooper items (some references add DOMS separately) | Confirm banding thresholds against the sports-science reference the coach expects; not a bug as-is |
| Body composition (BMI/skinfold) | Formula not located server-side — `body_fat_percentage` is read as a stored value, implying entry/computation elsewhere | Unverified | Locate and audit the actual formula (client-side or manual entry) in a follow-up pass |
| Frontend/backend agreement | `training_load_models.dart` parses PHP's snake_case output directly, with an explicit code comment forbidding Flutter-side recomputation | Low — single source of truth maintained | None needed |

---

## 6. API Audit

| Endpoint / Area | Status | Problem | Priority |
|---|---|---|---|
| `api/auth.php` | Solid | bcrypt cost 11, timing-safe verify, 256-bit tokens, 30-day TTL enforced on every lookup, IP+identifier rate limiting, generic error on bad login (no enumeration) | — |
| `api/includes/club_auth.php` | Solid | Centralized capability map (`clubStaffCan()`), club context resolved from the authenticated user's own staff record (never client-supplied), `COACH_ONLY_ACTIONS` carve-out even overrides owner/admin wildcard | — |
| `api/club/report-archive.php` (merr copy) | Diverged | Old ad-hoc weekly/monthly bucketing, no persistence, no team scoping vs. deployed version | P1 |
| `api/matches.php` (merr copy) | Diverged | Drops rating/injured/stage/scores fields the deployed copy persists | P1 |
| `api/sessions.php` | Bug | Attendance UPDATE scoped by `user_id` instead of `club_id` (F4) | P1 |
| `api/club/competitions.php` (merr copy) | Behind | Missing `format_type`, `stages_count`, points/tie-break fields present in deployed copy | P2 |
| SQL injection | Clean | All data-path queries use `PDO::prepare()`; no string-concatenated user input found | — |
| CORS | Inconsistent | `auth.php` uses a proper origin allowlist; ~105 other endpoints use `Access-Control-Allow-Origin: *`. Low real risk (Bearer-token, no credentials flag) but inconsistent | P3 |
| Duplicated auth helpers | Debt | `bearerToken()`/`getAuthUser()`/`jsonOut()` copy-pasted across `auth.php`, `hooper/save.php`, `report_helpers.php` instead of shared include | P3 |
| Error-response consistency | Mostly good | Correct status codes (400/401/403/404/409/422/429/503) across sampled endpoints; some endpoints (e.g. `hooper/save.php`) lack a top-level try/catch, so a raw `PDOException` could surface as a PHP fatal instead of JSON | P3 |

---

## 7. UX/UI Audit

- **Loading/error/empty states**: Club Dashboard is the gold-standard pattern (explicit `_loading`/`_loadError` flags, error branch with retry). Several detail screens (match, session, form, assessment-hub) do not follow this pattern and swallow errors silently (F5).
- **Forms**: consistent `_saving`/`_submitting` flag pattern across player, session, RPE, and Hooper forms correctly disables submit buttons during in-flight requests — no duplicate-submission risk found. No unsaved-changes guard (`PopScope`) on any form — low priority given MVP speed goals.
- **Navigation**: MVP flow is structurally intact end-to-end (modulo F1); a few "deprecated, redirect" dead route branches in `main.dart` should be pruned before store release.
- **Camera/assessment flow**: this is the app's centerpiece and its weakest link on error handling (F6) — worth a dedicated pass before any live coach demo.

---

## 8. Responsive Audit

- No large hardcoded pixel widths found in the three biggest club screens; layout relies on `Expanded`/`MediaQuery` (used in 20/64 club screens).
- Both `DataTable` usages (`standings_page.dart`, `team_performance_report_screen.dart`) are correctly wrapped in horizontal `SingleChildScrollView` — no table overflow risk.
- No specific overflow bugs identified in the sampled screens — this dimension is in reasonably good shape for MVP; a full landscape/tablet pass was not performed (out of scope for static review) and should happen once F1/F5/F6 are fixed.

---

## 9. Arabic/RTL Audit

- **Solid**: `Directionality` is applied consistently at the shell level and re-applied per-screen (~50 screens); PDF reports load `Cairo.ttf` and set `pw.TextDirection.rtl/ltr` at 16+ call sites — Arabic reports should render correctly, not reversed.
- **P1**: `assessment_result_page.dart`'s score-edit dialog hardcodes Arabic strings and stray English debug labels (F10) — breaks the non-Arabic experience on a core screen.
- **P2**: ~107 occurrences of `EdgeInsets.only(left:/right:)`/`fromLTRB` instead of `EdgeInsetsDirectional(start:/end:)` across `lib/screens/**` — icon/label spacing will sit on the visually wrong side in Arabic. Fix incrementally as files are touched, not as a mass refactor (per CLAUDE.md).
- **P3**: `report_charts.dart` empty-state strings are hardcoded Arabic literals — non-Arabic users see Arabic text on empty charts.
- **P3**: no `intl` package anywhere — dates/numbers are manually formatted, not locale-aware. Acceptable for current MVP priorities.

---

## 10. Security Audit

| Finding | Severity | Location | Recommendation |
|---|---|---|---|
| Token stored in plaintext SharedPreferences/localStorage, no secure storage, Android backup not disabled | MEDIUM (elevated to P1 in context of medical data roadmap) | `lib/storage_stub.dart:34-38`, `lib/storage_web.dart:7-13` | Move to `flutter_secure_storage`; set `android:allowBackup="false"` |
| No global 401 handler | MEDIUM | `lib/api_service.dart` | Add interceptor: clear token + redirect to login on any 401 |
| Release build unminified/unobfuscated | LOW→P1 (build config) | `android/app/build.gradle.kts:55-60` | Enable `isMinifyEnabled`/`isShrinkResources` + ProGuard rules |
| CORS wildcard on ~105 endpoints | LOW | most `api/**/*.php` | Mirror `auth.php`'s origin allowlist |
| Firebase API keys in source | INFO (expected) | `lib/firebase_options.dart` | Confirm Firestore/Storage security rules and GCP key restrictions separately if Firebase holds any medical data |
| DB credentials | Clean | `api/db.php` | Gitignored, hard-fails in prod if missing — no action needed |
| Password hashing | Clean | `api/auth.php:409,699` | bcrypt cost 11 — no action needed |
| Token generation/lifecycle | Clean | `api/auth.php:54-56` | 256-bit CSPRNG, 30-day TTL enforced — no action needed |
| Rate limiting | Clean | `api/auth.php:100-141` | IP + hashed-identifier sliding window — no action needed |
| Server-side authorization | Clean | `api/includes/club_auth.php` | Genuine tenant isolation, not client-trust — no action needed |
| Network transport | Clean | `lib/app_config.dart:12` | HTTPS in prod, cleartext blocked by Android default — no action needed |
| Sentry PII scrubbing | Clean | `lib/main.dart:595` | Explicitly tags role only, no PII — no action needed |

---

## 11. RBAC Audit

Roles found in `api/includes/club_auth.php`: `owner`, `admin`, `coach`, `doctor`, `physiotherapist`, `massage_specialist`, `nutritionist`, `performance_manager`, `analyst`, `tactical_coach`, `player`.

| Feature | Owner/Admin | Coach | Doctor/Physio/Massage | Analyst/Perf Manager | Player |
|---|---|---|---|---|---|
| Player CRUD | Full | Full (except `COACH_ONLY_ACTIONS` carve-outs) | No | Read | Own profile only |
| Medical detail (diagnosis/notes) | Full | **No** (`medical.read` only, not `medical_detail.read`) | Full | No | No |
| FMS / body-composition writes | Full (wildcard bypassed by `COACH_ONLY_ACTIONS`) | Yes (deliberate carve-out) | No | No | No |
| Reports | Full | Yes | Scoped | Yes | Own only |
| Sessions/attendance | Full | Yes | No | Read | Own only |

Enforcement is server-side (`requireClubPermission()`), not UI-only — confirmed by direct code inspection of `injuries.php` and others, which filter every query by the resolved `club_id`/role rather than trusting client input. This matches CLAUDE.md's roadmap intent that coaches shouldn't see medical detail, even though full medical-module separation is officially "post-MVP."
**Follow-up**: what plain `medical.read` (coach's actual grant) exposes wasn't fully traced — verify no diagnosis-level text leaks through it.

---

## 12. Performance Audit

- `app_state.dart` global mutable variables with no notification mechanism will keep causing stale-UI bugs as the app grows (already evidenced by a documented org-role fallback workaround in `storage_stub.dart:73-77`).
- `ListView(` (fixed children) used 66 times vs `ListView.builder` 11 times repo-wide — check the larger roster/session lists specifically for unbounded-list scroll cost.
- `cached_network_image` is used for avatars — avoids the common raw `Image.network` re-fetch problem.
- `ReportService` (116KB) and `ClubService` (56KB) as single classes make targeted performance profiling and testing harder than necessary.
- No `print()` calls found (clean); only 4 files use `debugPrint`; no structured logging framework beyond Sentry.

---

## 13. Testing Audit

**Present**: `jump_measurement_test.dart`, `jump_state_machine_test.dart`, `one_euro_filter_test.dart`, `pose_quality_gate_test.dart`, `metric_formatter_test.dart`, `fitness_reports_pdf_test.dart` — solid coverage of the pose/biomechanics pipeline specifically.

**Absent** (in priority order):
1. Authentication flow — zero tests.
2. API JSON/model parsing — zero tests, despite 14 model files with `fromJson`.
3. Sports calculations end-to-end (training load, ACWR, Hooper) — zero tests (only the pose-math side is tested).
4. Form validation — zero tests.
5. Navigation/critical workflows — one boot-only smoke test.
6. CI — no `.github/workflows` runs tests or `flutter analyze` at all.
7. `flutter_test` not declared in `pubspec.yaml` dev_dependencies — test suite integrity is fragile (works today only via a stale lockfile entry).

---

## 14. Technical Debt

1. `ClubService`/`ReportService`/`jump_analysis_service.dart` god classes (P2) — not urgent to split, but any future change to them carries elevated regression risk.
2. Global mutable state in `app_state.dart` instead of a listenable container (P1 architecturally, low urgency for MVP demo).
3. Duplicated auth helper functions across PHP files (P3).
4. `merr/api` vs `nextkickwebsite/api` drift (P1) — needs a process fix (always diff before assuming sync), not just a one-time re-sync.
5. 17 silent `catch (_) {}` blocks across services/screens (P2) — no logging, hard to diagnose field issues.

---

## 15. Release Blockers

| ID | Severity | File | Module | Problem | Risk | Required Fix | Verification |
|---|---|---|---|---|---|---|---|
| RB1 | P0 | `lib/screens/physical_assessment/player_selection_page.dart:222-249` | AI Assessment | Single Leg Balance & Jump Landing gated "coming soon" | Coach demo/production shows only 1 of 3 promised tests | Wire up the two remaining tests, or explicitly re-scope MVP to Squat-only | Manually run all 3 test flows end-to-end |
| RB2 | P1 | `api/sessions.php:365-367` | Session Management | Attendance UPDATE scoped by `user_id` not `club_id` | Silent data loss for any non-creator staff marking attendance | Change WHERE clause to `club_id = ?` using resolved club context (nextkickwebsite already has the fix) | Have two different staff accounts mark attendance on the same session; verify both persist |
| RB3 | P1 | `api/club/report-archive.php`, `api/matches.php` (merr copy) | Reports / Competitions | Diverged from deployed nextkickwebsite logic; dropped fields | Data loss / stale reports if deployed as-is | Re-sync from nextkickwebsite (verify directionality via git history first) | Diff both trees post-fix; confirm zero remaining diffs in `club/`, root `*.php` |
| RB4 | P1 | `assessment_camera_page.dart:253-267` | AI Assessment | Native camera init failure has empty catch, silent black screen | Demo-breaking, undiagnosable in the field | Mirror the web branch's `_cameraError` state + retry UI | Force a camera permission denial/init failure and confirm visible error state |
| RB5 | P1 | `android/app/build.gradle.kts:55-60` | Build | No minify/shrink/ProGuard in release; missing `key.properties` fails silently | Unoptimized, unsigned/misconfigured release possible with no build error | Enable `isMinifyEnabled`/`isShrinkResources`; add explicit failure if `key.properties` missing | Build release APK from clean checkout without `key.properties`, confirm build fails loudly |
| RB6 | P2 | `lib/storage_stub.dart`, `lib/storage_web.dart` | Security | Token in plaintext storage, no secure storage, backup not disabled | Token extractable via adb backup on rooted/debuggable device | Migrate to `flutter_secure_storage`; set `allowBackup=false` | Confirm token absent from `adb backup` extraction |
| RB7 | P2 | `lib/screens/physical_assessment/assessment_result_page.dart` | Localization | Hardcoded Arabic/debug strings bypass l10n | Non-Arabic users see broken UI in a core screen | Route all strings through `AppLocalizations.get()` | Switch app language to EN/FR and open the score-edit dialog |
| RB8 | P2 | Testing/CI | Project-wide | No CI, `flutter_test` not declared | Regressions ship undetected; test suite could silently stop working | Add `flutter_test` to `pubspec.yaml`, add a CI workflow running `flutter analyze` + `flutter test` | Confirm `flutter test` runs green from a fresh `pub get` |

---

## 16. Recommended Roadmap

### Phase 1 — Before Release (P0/P1)
RB1–RB5 above, plus F5 (silent-failure detail screens) and F11's minimal fix (wrap `app_state.dart` in a single `ChangeNotifier` — not a rewrite).

### Phase 2 — First Production Update (P2)
RB6–RB8, RTL directional-padding cleanup (touch files as edited), CORS allowlist consistency, split `ClubService`/`ReportService` if further growth is planned, duplicated auth-helper consolidation.

### Phase 3 — Product Improvements (P3)
`intl` adoption for locale-aware formatting, unsaved-changes form guards, chart empty-state localization, dead route pruning, `camera` package version bump, structured logging framework.

---

## 17. Quick Wins

- RB2 (session attendance fix) — one-line WHERE clause change, high real-world impact.
- RB5 (build config) — a few lines in `build.gradle.kts`, prevents shipping an unsigned/unobfuscated release by accident.
- RB4 — mirror an already-existing web-branch pattern to the native branch; the fix already exists in the same file.
- RB8 — add one line to `pubspec.yaml` (`flutter_test: sdk: flutter`) plus a minimal GitHub Actions workflow — cheap insurance against the test suite silently breaking.

---

## 18. Strategic Recommendations

- Formalize the `merr/api` ↔ `nextkickwebsite/api` sync as a checked process (diff before every "sync" commit, not just a one-time pass) — this has already caused two real divergence bugs (RB3).
- Once RB1 is resolved and the app stabilizes past demo stage, invest in the state-management fix (F11) before the screen count grows further — 105 screens on manual `setState` + global mutables is the one architectural item likely to compound into real pain, though it does not block the current release.

---

## 19. Final Verdict

**Can MERR be released to real users today? No.**

The core engineering — calculations, server-side authorization, PDF/RTL, and the bulk of the UI — is solid and well above what's typical for an MVP at this stage. But RB1 (2 of 3 promised assessment tests non-functional) alone is disqualifying for a coach-facing release, and RB2–RB5 are concrete, evidenced defects that would cause silent data loss or a broken demo, not hypothetical risks.

**What must be fixed first:** RB1 through RB5 (Section 15), in that order. These are targeted, minimal-patch fixes consistent with CLAUDE.md's "no rewrites" mandate — realistically a few days of focused work, not a re-architecture. RB6–RB8 should follow immediately after for a genuinely safe production release.

---

## Top 10 Problems
1. Only 1 of 3 MVP assessment tests functional (RB1)
2. Session attendance updates silently fail for non-creator staff (RB2)
3. `merr/api` diverged from the deployed API in `report-archive.php`/`matches.php` (RB3)
4. Silent native camera-init failure on the core demo screen (RB4)
5. Release Android build unminified, and can ship unsigned with no build error (RB5)
6. Auth token in plaintext storage, backup not disabled (RB6)
7. Hardcoded Arabic/debug strings on a core screen bypass localization (RB7)
8. No CI, no auth/API/calculation test coverage, fragile test-suite dependency (RB8)
9. Multiple detail screens silently swallow load errors with no retry (F5)
10. Global mutable app state with no listener mechanism (F11)

## Top 10 Recommended Improvements
1. Wire up Single Leg Balance and Jump Landing tests
2. Fix `sessions.php` attendance WHERE clause
3. Re-sync and lock down the `merr/api`/`nextkickwebsite/api` diffing process
4. Add native camera error state + retry UI
5. Enable release minification/ProGuard + fail loudly on missing signing config
6. Move auth token to `flutter_secure_storage`, disable Android backup
7. Localize `assessment_result_page.dart` fully
8. Stand up CI running `flutter analyze` + `flutter test`, fix `pubspec.yaml` dev_dependencies
9. Add error+retry states to match/session/form detail screens
10. Wrap `app_state.dart` in a `ChangeNotifier`

## Top 10 Release Tests
1. Run all three assessment tests (Squat, Single Leg Balance, Jump Landing) end-to-end on a physical device
2. Mark attendance on a shared session as two different staff accounts; confirm both persist
3. Force a camera permission denial on native Android; confirm visible error state, not black screen
4. Build a release APK from a clean checkout with no `key.properties`; confirm the build fails loudly
5. Diff `merr/api` and `nextkickwebsite/api` post-fix; confirm zero remaining divergence
6. Switch language to English/French and open the assessment score-edit dialog; confirm no Arabic leaks through
7. Attempt to extract the auth token via `adb backup` on a debuggable build
8. Run `flutter test` from a completely fresh `pub get` (no cached lockfile) and confirm it passes
9. Trigger a network failure on match/session detail screens; confirm a visible error+retry, not a blank/stale screen
10. Verify a coach role account cannot retrieve medical diagnosis text from any endpoint (spot-check beyond `injuries.php`)

## All Release Blockers
See Section 15 (RB1–RB8) in full.

## Overall Readiness Score
**64/100**

## Final GO / NO-GO Recommendation
**NO-GO** until RB1–RB5 are fixed (targeted, days not weeks); **GO** for a controlled coach demo once RB1, RB4, and RB5 specifically are resolved, with RB2/RB3/RB6-RB8 following before any real multi-staff production usage.

---

# Remediation Round 1 — Status (2026-08-09)

**Scope of this round:** RB1 (AI assessment tests) was explicitly deferred to a future update per direct instruction — not attempted here. RB2–RB5 were fixed and verified. Phase 2 (secure token storage, 401 handling, localization sweep), Phase 3 (high-value regression tests), and Phase 4 (minimal CI) were completed to the extent possible in a sandboxed environment with no live database, no attached physical device, and no GitHub Actions execution.

## Remediation Status

| Blocker | Before | After | Verification |
|---|---|---|---|
| RB1 — AI assessment tests | Only Squat reachable; Single Leg Balance/Jump Landing gated "coming soon" | **Deferred to next update** (explicit instruction this round) | Not attempted |
| RB2 — Attendance scoped by `user_id` | Non-creator staff silently failed to update attendance | Fixed: `api/sessions.php` now scopes the legacy summary UPDATE by `club_id` (already-resolved `$ctx['club_id']`), matching the deployed copy | PASS — new pure test `p0_sessions_write_permission_test.php` (role matrix) executed, 0 failures. New DB-integration test `p0_attendance_scope_test.php` written per project convention but **BLOCKED** — no local test DB in this environment (needs `APP_ENV=test`+`TEST_DB_NAME` per `api/migrations/p0/README.md`) |
| RB3 — API drift (`merr/api` vs deployed) | `report-archive.php`, `matches.php`, `competitions.php` diverged from the deployed/authoritative copy; fields silently dropped | Fixed: all three files synced from `nextkickwebsite/api` (confirmed authoritative), plus 4 backing migrations copied for schema-tracking consistency. Full drift audit in `API_DRIFT_REPORT.md` — confirmed these were the *only* 4 differing files in the entire API tree | PASS — `php -l` clean on all 3 synced files; diffs confirmed additive-only (no removed/renamed fields); cross-checked against `lib/models/club_models.dart` and confirmed the Flutter client already expected the new fields (client was ahead of the stale API, not the other way round). Live DB write-path (`report_period_archives` inserts) **BLOCKED** — no local DB |
| RB4 — Silent camera failure | Native camera init failure showed a black screen with no feedback; unsupported-device case (no cameras) didn't even throw | Fixed: camera services now throw typed exceptions (`CameraUnsupportedException`, `CameraPermissionDeniedException`) across mobile/web/stub; page classifies failures into 4 states (permission/init-failed/unsupported/runtime) with localized title+body, Retry, conditional "Open Settings", and Go Back; runtime stream errors are now caught via `onError` instead of being unhandled | PASS — `flutter analyze` clean (0 issues) on all touched files; `flutter test` 29/29 passing. Manual on-device permission-denial/black-screen reproduction **BLOCKED** — no attached device/emulator in this environment |
| RB5 — Unsafe release build config | Missing `key.properties` silently produced an unsigned/misconfigured "release" build with no error; no minification/shrinking | Fixed: signing config now throws a `GradleException` with a clear message when `key.properties` is missing and a release task is requested; `isMinifyEnabled`/`isShrinkResources` enabled with a conservative `proguard-rules.pro` (MLKit/Firebase/camera/notifications keep-rules); `android:allowBackup="false"` added | PASS — **actually executed**, not just written: (1) with the real local `key.properties` present, `gradlew assembleRelease -m` configured successfully; (2) `key.properties` was moved aside and `gradlew assembleRelease -m` **correctly failed** with the new explicit error message; (3) the file was restored and its timestamp confirmed unchanged. Full `assembleRelease` execution (not just configuration/dry-run) was not completed — flagged below as a remaining verification gap, not claimed as done |
| Phase 2 — Secure token storage | Auth token in plaintext `SharedPreferences`/`localStorage`; no migration path | Fixed: token moved to `flutter_secure_storage` (Android Keystore-backed / IndexedDB+WebCrypto on web) in both `storage_stub.dart` and `storage_web.dart`, with a one-time migration for existing installs that had a plaintext token | PASS for compile/test (`flutter analyze` clean, `flutter test` 29/29). Runtime keystore behavior on an actual device **BLOCKED** — no device in this environment |
| Phase 2 — No global 401 handling | Expired/revoked token failed silently per-screen | Fixed: `ApiService._decodeResponse` now detects 401 and invokes a settable `onUnauthorized` callback, wired in `main.dart` to clear the session and route to `/onboarding` | PASS for compile (`flutter analyze` clean). Live-request verification against a real revoked token **BLOCKED** — no reachable API server/DB in this environment |
| Phase 2 — Hardcoded strings | `assessment_result_page.dart` had ~15 hardcoded Arabic/debug strings bypassing l10n; `report_charts.dart` had 5 hardcoded Arabic empty-state strings | Fixed for both flagged files: all hardcoded strings replaced with `AppLocalizations.get()`/`.format()` calls, new keys added to all three language maps (en/ar/fr) | PASS — grep-verified zero remaining hardcoded Arabic literals in `assessment_result_page.dart`; `flutter analyze` clean. **Not exhaustive** — a full-codebase hardcoded-string sweep beyond the two audit-flagged files was not performed this round (see Remaining P2 Issues) |
| Phase 3 — Test suite | Zero coverage for auth, RBAC edge cases beyond the one bug just found | Added: `p0_sessions_write_permission_test.php` (role matrix for the RB2 fix), `p0_attendance_scope_test.php` (DB-gated regression for RB2), `p0_rbac_capability_matrix_test.php` (medical-detail access, analyst read-only guarantee, coach-only FMS/body-composition carve-out, player-deletion restriction, unrecognized-role rejection) | PASS — all pure (no-DB) tests executed directly, 0 failures. Re-ran the full existing suite as a regression check: all pre-existing pure PHP tests (`p0_acwr_calculator_test.php`, `p0_body_composition_completeness_test.php`, `p0_rpe_identity_test.php`, `p0_training_load_quality_test.php`, `training_load_calculator_pure_test.php`) still pass; full `flutter test` suite 29/29 passing (1 intentionally skipped, needs a live audit API) |
| Phase 4 — CI | No `.github/workflows` at all; `flutter_test` not even declared in `pubspec.yaml` | Added `.github/workflows/ci.yml` (format check, analyze, unit tests, debug build validation for Flutter; syntax lint + pure regression tests for PHP). Added `flutter_test` to `pubspec.yaml` dev_dependencies | Workflow steps mirror commands already verified locally in this round (analyze clean, tests passing). The workflow itself has **not** run on GitHub Actions yet — **BLOCKED**, nothing has been pushed. DB-integration PHP tests are deliberately excluded from CI per the project's own "test database only, approval required" convention — documented, not silently dropped |
| F5 — Silent-failure detail screens | `match_detail_page.dart`, `session_detail_page.dart`, `match_form_page.dart`, `assessment_hub_page.dart` all wrapped their initial data load in `catch (_) {}` with no error state or retry | Fixed all 4: `match_detail_page.dart`/`session_detail_page.dart` gained a distinct `_loadError` state (separate from "not found") with an error message + retry button; `match_form_page.dart` shows a SnackBar with a retry action; `assessment_hub_page.dart` shows an inline error banner with retry when the player profile fails to load. All four now log via `AppLogger.e` instead of swallowing silently | PASS — `flutter analyze` clean (0 issues) on all 4 files |

## Verification Table (Phase 5)

| ID | Fix | Test | Result | Evidence |
|---|---|---|---|---|
| RB2 | `sessions.php` `club_id` scoping | `p0_sessions_write_permission_test.php` | **PASS** | `php api/tests/p0_sessions_write_permission_test.php` → `p0_sessions_write_permission_test: OK` |
| RB2 | `sessions.php` `club_id` scoping | `p0_attendance_scope_test.php` (DB integration) | **BLOCKED** | No local test DB (`APP_ENV=test`/`TEST_DB_NAME` unset); test written and ready, matches existing integration-test convention |
| RB3 | API sync (3 files) | `php -l` syntax check | **PASS** | All 3 synced files: "No syntax errors detected" |
| RB3 | API sync (3 files) | Flutter model compatibility cross-check | **PASS** | `ReportArchiveEntry`, `MatchParticipation`, `ClubCompetition` in `club_models.dart` already parse the new fields — confirmed by direct read of the model source |
| RB3 | API sync (3 files) | Full tree diff, no other drift | **PASS** | `diff -rq merr/api academy/nextkickwebsite/api` — only the 4 known files (now including `sessions.php`) differed prior to this fix; zero after |
| RB4 | Camera error states | `flutter analyze` | **PASS** | "No issues found!" across all touched camera/page files |
| RB4 | Camera error states | `flutter test` | **PASS** | 29/29 passing, includes pose/camera-adjacent unit tests |
| RB4 | Camera error states | On-device manual reproduction | **BLOCKED** | No attached device/emulator in this environment |
| RB5 | Missing signing config fails loudly | `gradlew assembleRelease -m` with `key.properties` removed | **PASS** | Actual Gradle output: `FAILURE: ... Release build requested but android/key.properties is missing...` |
| RB5 | Signing happy path unaffected | `gradlew assembleRelease -m` with `key.properties` present | **PASS** | `BUILD SUCCESSFUL in 26s` |
| RB5 | Minify/shrink/ProGuard config | Full `assembleRelease` execution | **PASS** | Full release build actually executed (not a dry run): `BUILD SUCCESSFUL in 11m 50s`, including `minifyReleaseWithR8`, `shrinkReleaseRes`, `packageRelease`. Signed artifact confirmed on disk: `build/app/outputs/apk/release/app-release.apk`, 154.9MB, timestamped to this build run |
| Phase 2 | Secure token storage | `flutter analyze` + `flutter test` | **PASS** | Clean analyze, 29/29 tests |
| Phase 2 | Secure token storage | On-device keystore behavior | **BLOCKED** | No device in this environment |
| Phase 2 | 401 handler | `flutter analyze` | **PASS** | Clean |
| Phase 2 | 401 handler | Live revoked-token request | **BLOCKED** | No reachable API/DB in this environment |
| Phase 2 | Localization sweep (2 files) | grep for remaining Arabic literals | **PASS** | Zero hits in `assessment_result_page.dart` after the fix |
| Phase 3 | Regression + RBAC tests | Direct execution | **PASS** | All new and pre-existing pure PHP tests pass; full Dart suite passes |
| Phase 4 | CI workflow | GitHub Actions run | **BLOCKED** | Nothing pushed yet; steps mirror locally-verified commands only |
| F5 | Silent-failure detail screens | `flutter analyze` | **PASS** | "No issues found!" across all 4 touched files |

No item above was marked PASS without direct command output as evidence; every BLOCKED item is BLOCKED specifically because this environment lacks a live database, an attached device, or a remote CI runner — not because the fix wasn't attempted.

## CI/CD Signing Configuration (required, per RB5)

Signing could not be completed in CI in this round (no secrets store access here). To enable `assembleRelease` in `.github/workflows/ci.yml` or any future release pipeline, the repository needs:

1. Base64-encode the release keystore and store it as a GitHub Actions secret (e.g. `ANDROID_KEYSTORE_BASE64`).
2. Store `keyAlias`, `keyPassword`, and `storePassword` as secrets (`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`).
3. In the release workflow step, decode the keystore to a file and write `android/key.properties` from the secrets before invoking `flutter build apk --release` / `flutter build appbundle --release` — this is exactly what `build.gradle.kts`'s existing `keystoreProperties` loader already expects, so no gradle changes are needed beyond what RB5 already fixed.
4. Never commit the keystore or `key.properties` — both are already gitignored (verified: `key.properties` is untracked, confirmed via `git status`).

This is documented rather than implemented because it requires access to the team's actual release keystore and GitHub repository secrets, neither of which is available in this environment.

## Changed Files (this remediation round)

**API (PHP):**
- `api/sessions.php` — RB2 fix
- `api/club/report-archive.php`, `api/matches.php`, `api/club/competitions.php` — RB3 sync
- `api/migrations/p0/0014_report_period_archive.sql`/`.down.sql`, `0018_medical_module_tables.sql`/`.down.sql`, `0019_competition_format.sql`/`.down.sql`, `0020_match_stage_and_result.sql`/`.down.sql` — new, RB3
- `api/migrations/p0/README.md` — updated test-command docs
- `api/tests/p0_sessions_write_permission_test.php`, `api/tests/p0_attendance_scope_test.php`, `api/tests/p0_rbac_capability_matrix_test.php` — new regression tests

**Flutter (Dart):**
- `lib/screens/physical_assessment/assessment_camera_page.dart` — RB4 error states
- `lib/services/camera_service_mobile.dart`, `camera_service_web.dart`, `camera_service_stub.dart` — RB4 typed exceptions
- `lib/app_localizations.dart` — new keys for camera errors + assessment/chart localization
- `lib/screens/physical_assessment/assessment_result_page.dart`, `lib/widgets/report_charts.dart` — localization sweep
- `lib/storage_stub.dart`, `lib/storage_web.dart` — secure token storage
- `lib/api_service.dart`, `lib/main.dart` — 401 handler wiring
- `pubspec.yaml` — added `flutter_secure_storage`, `flutter_test`
- `lib/screens/club/match_detail_page.dart`, `session_detail_page.dart`, `match_form_page.dart`, `lib/screens/physical_assessment/assessment_hub_page.dart` — F5 error+retry states

**Android:**
- `android/app/build.gradle.kts` — RB5 signing-failure + minify/shrink
- `android/app/proguard-rules.pro` — new
- `android/app/src/main/AndroidManifest.xml` — `allowBackup="false"`

**CI / docs:**
- `.github/workflows/ci.yml` — new
- `API_DRIFT_REPORT.md` — new (RB3)
- `MERR_PRODUCTION_READINESS_REPORT.md` — this section

**Note:** this working tree had substantial *pre-existing* uncommitted changes from before this remediation round began (asset deletions, other file modifications) — those are not part of this round's work and are not described above.

## Tests Added
`p0_sessions_write_permission_test.php`, `p0_attendance_scope_test.php`, `p0_rbac_capability_matrix_test.php` (PHP, pure + 1 DB-gated); no new Dart tests were added this round (existing 29 were re-verified, not extended — Phase 3 prioritized the RBAC/attendance gap the audit specifically flagged).

## Tests Passed
29/29 Dart (`flutter test`); 7/7 executable PHP pure tests (`p0_acwr_calculator_test`, `p0_body_composition_completeness_test`, `p0_rpe_identity_test`, `p0_training_load_quality_test`, `p0_sessions_write_permission_test`, `p0_rbac_capability_matrix_test`, `training_load_calculator_pure_test`).

## Tests Failed
None.

## Remaining Blockers
- **RB1** — AI assessment tests (Single Leg Balance, Jump Landing) — explicitly deferred to next update, not attempted this round.

## Remaining P1/P2 Issues
- Full-codebase hardcoded-string sweep beyond `assessment_result_page.dart`/`report_charts.dart` not performed — the original audit's "start with assessment results but don't stop there" instruction was only partially honored due to scope/time; a systematic grep-driven sweep of all 105 screens is still open.
- DB-integration test execution (`p0_scope_integration_test.php`, `p0_attendance_scope_test.php`) requires an approved isolated test database that doesn't exist in this environment — needs to be run in a real dev/CI environment before RB2/RB3 can be called fully verified end-to-end.
- On-device verification (camera failure states, secure-storage keystore behavior, `adb backup` extraction check) not performed — no physical device/emulator available here. The release APK itself now builds and is available at `build/app/outputs/apk/release/app-release.apk` for that manual pass.
- CI workflow not yet exercised on GitHub Actions — needs a push/PR to confirm it actually runs green.
- `ClubService`/`ReportService` god-class technical debt, global mutable `app_state.dart`, CORS wildcard consistency — all still open, unchanged from the original audit (not in scope for this remediation round).

## New Readiness Score

| Category | Before | After |
|---|---:|---:|
| Functional correctness | 60 | 65 *(RB2 fixed; RB1 still open)* |
| Data accuracy | 75 | 82 *(RB3 drift resolved)* |
| Sports calculations | 90 | 90 *(untouched, re-verified via tests)* |
| API/backend integration | 65 | 80 *(RB2+RB3 fixed and verified)* |
| UX/UI | 68 | 70 |
| Responsive design | 78 | 78 |
| Arabic/RTL | 80 | 84 *(2 files fully localized)* |
| Accessibility | 45 | 45 |
| Performance | 60 | 60 |
| Security | 62 | 76 *(secure storage, 401 handling, backup disabled, ProGuard)* |
| Authentication/RBAC | 78 | 85 *(new RBAC regression coverage)* |
| Error handling | 50 | 70 *(RB4 fixed; F5's 4 detail/form screens now have error+retry states)* |
| Testing | 20 | 40 *(new regression tests + CI file; still narrow, DB tests blocked)* |
| Production configuration | 45 | 85 *(RB5 fixed and verified via an actual successful `assembleRelease` build, not just configuration)* |
| **Overall (weighted)** | **64** | **75** |

## Status

🟡 **READY WITH REQUIRED FIXES** — conditional on scope:

- If the release is explicitly re-scoped to **Squat-only** for this cycle (matching the deferral of RB1), the remaining blockers (RB2–RB5) are fixed and verified to the extent this environment allows — the app is materially closer to a safe release than the 64/100 starting point.
- If all 3 MVP tests (per CLAUDE.md's original strict scope) are required for this release, status remains **🟠 NOT READY** until RB1 is addressed in the deferred next-update cycle.

## Final GO / NO-GO

**Conditional GO** for a Squat-only controlled release/demo, **NO-GO** for the full 3-test MVP scope until RB1 ships. Before either: (1) run the DB-integration tests in a real environment to close the BLOCKED gaps above, (2) execute one full `assembleRelease` build end-to-end, (3) push this branch to confirm CI is actually green, (4) do a short on-device pass for the camera error states and secure-storage behavior.

---

# تقرير الجاهزية التشغيلية مع النادي — 2026-09-19

**النطاق:** مراجعة ما يلزم لتشغيل التطبيق فعلياً مع نادي المريخ: التدريب (الحصص والحضور والحِمل)، واللاعب، والمدرب، والإدارة. تتحقق المراجعة أولاً من بنود تقرير أغسطس أعلاه، ثم تبحث عن مشاكل جديدة.
**المنهج:** قراءة الكود مباشرة، ثم تشغيل `flutter analyze` و `flutter test` واختبارات PHP وفحص `php -l`، ثم مقارنة `merr/api` بالنسخة المنشورة `academy/nextkickwebsite/api`.
**ما لم يُتحقق منه (لا يوجد وصول):** السيرفر الحي nextkick.me، وقاعدة البيانات الحقيقية، وجهاز فعلي. كل بند يعتمد على السيرفر مكتوب عنده «يجب التأكد على السيرفر».

## 1. الحكم العام

**التقييم: 70/100 — 🟠 غير جاهز للتشغيل الفعلي بعد، وجاهز للعرض (Demo) مع اختبار السكوات فقط.**
أغسطس بعد الإصلاحات: 75. نزل التقييم لأن الاستخدام الحقيقي بعدة موظفين كشف 4 عوائق تشغيلية لا تظهر في العرض بمستخدم واحد.

الحسابات الرياضية (sRPE, ACWR, Monotony/Strain, Hooper) صحيحة ومختبرة. عزل بيانات النادي في السيرفر سليم في معظم الـ endpoints. المشاكل كلها قابلة للإصلاح بتعديلات صغيرة ولا تحتاج إعادة بناء.

## 2. نتائج الفحوصات الآلية (نُفذت اليوم)

| الفحص | النتيجة |
|---|---|
| `flutter analyze` | تحذير واحد فقط: `_latestHooper` غير مستخدم في `player_dashboard.dart:551` (موجود من قبل) |
| `flutter test` | 29/29 نجاح |
| اختبارات PHP (pure) | 7/7 نجاح، ومنها 36/36 لحسابات الحِمل |
| `php -l` على كل ملفات الـ API | لا أخطاء syntax |
| `catch (_) {}` الصامتة في الشاشات | 6 فقط (انخفضت بعد إصلاحات أغسطس) |
| بيانات وهمية/عشوائية في الشاشات | لا يوجد (مطابق لقاعدة «لا درجات وهمية») |

## 3. عوائق الإطلاق (P0) — يجب حلها قبل التشغيل

| # | المشكلة | الدليل | الأثر على النادي |
|---|---|---|---|
| P0-1 | **اختبارا التوازن على رجل واحدة والهبوط بعد القفز ما زالا «قريباً»**، والسكوات هو الاختبار الوحيد الذي يعمل | `lib/screens/physical_assessment/player_selection_page.dart:222` (`_isComingSoon`) | 2 من 3 اختبارات MVP غير متاحة. البند لم يتغير منذ أغسطس (RB1) |
| P0-2 | **لا توجد طريقة لإنشاء حساب لموظف جديد** (مدرب، طبيب، معالج، أخصائي تغذية). الإدارة تولّد «رموز دعوة» من شاشة الطاقم، لكن شاشة التسجيل التي كانت تستخدم هذه الرموز حُذفت | `staff_screen.dart` يولّد الرموز؛ التبديل إلى التسجيل حُذف في commit `7d66633` فصار `isSignUp` كوداً ميتاً (`auth_page.dart:24`)؛ `club/staff.php` لا يوفّر إنشاء حساب بكلمة مرور | لا يستطيع أي موظف جديد الدخول للتطبيق. حسابات اللاعبين تعمل لأنها تُنشأ من شاشة إضافة لاعب |
| P0-3 | **لا توجد استعادة أو إعادة تعيين لكلمة المرور**، لا «نسيت كلمة المرور» للمستخدم ولا إعادة تعيين من الإدارة | بحث `forgot/reset_password` في `lib` و `api` بلا نتائج | أي لاعب ينسى كلمة المرور يُقفل عليه الحساب ولا يوجد حل من داخل النظام |
| P0-4 | **نسخة الـ API المنشورة متأخرة عن الكود.** `auth.php` المنشور (716 سطر) لا يحتوي على `delete_account`، وهي موجودة في `merr/api/auth.php:712` (896 سطر) ويستدعيها التطبيق في builds 17/18 | `diff -rq merr/api academy/nextkickwebsite/api` | إن لم تُرفع إلى nextkick.me فستفشل ميزة حذف الحساب، وهي نفس الميزة التي رفضت Apple التطبيق بسببها. **يجب التأكد على السيرفر قبل إعادة الإرسال** |

## 4. التدريب (الحصص، الحضور، الحِمل)

| الأولوية | المشكلة | الملف | الأثر |
|---|---|---|---|
| P1 | 7 ملفات API فيها إصلاحات 23 أغسطس غير مرفوعة للنسخة المنشورة: `sessions.php`, `matches.php`, `club/injuries.php`, `club/physio_sessions.php`, `club/rehab_phases.php`, `club/tasks.php`, `player/session/post-feedback.php`. في النسخة المنشورة، فشل إرسال الإشعار بعد الحفظ يُرجع خطأ مع أن البيانات حُفظت | مقارنة النسختين | المدرب يرى «فشل الحفظ» فيعيد المحاولة، فتتكرر الحصص/المباريات أو يعتقد أن البيانات ضاعت |
| P1 | تمارين الحصة مربوطة بمن أنشأ الحصة، وليس بالنادي | `api/sessions/exercises.php:49,81,137` (`cs.user_id = ?`)؛ التطبيق يستخدمها في `club_service.dart:982,1000` | المدرب الثاني أو الإدارة يحصلون على «Session not found» عند فتح أو إضافة تمارين لحصة لم ينشئوها. نفس نوع الخطأ RB2 |
| P1 | قائمة تقييمات الحصة تعرض فقط ما سجّله المستخدم الحالي | `api/club/session_assessments.php:56` (`WHERE user_id = ?`) | تقييمات المدرب الآخر في نفس الحصة لا تظهر |
| P1 | إنشاء/تعديل الحصة في السيرفر لا يتحقق من صلاحية `sessions.write`، فقط من أن المستخدم ليس لاعباً | `api/sessions.php:420-441` | الطبيب والمحلل وأخصائي التغذية والمعالج و staff (أدوار ليس لها `sessions.write`) يستطيعون إنشاء وتعديل الحصص عبر الـ API. الواجهة تخفي الزر فقط |
| P2 | حذف الحصة و `add_exercise` مربوطان بمن أنشأ الحصة (`sessions.php:378` و `:616`)، والحذف يُرجع `success` حتى لو لم يُحذف شيء | `api/sessions.php` | لا يُستخدم حالياً من التطبيق (لا يوجد زر حذف حصة)، لكنه خطأ كامن |
| P2 | عند تسجيل الحضور لا يتحقق السيرفر أن اللاعب مسجّل في الحصة أو تابع للنادي | `sessions.php` action `attendance` | سلامة بيانات فقط |
| P2 | اللاعب الذي يُنشأ له حساب بعد إنشاء الحصة لا يظهر في «حصة اليوم» إلا بعد إعادة حفظ الحصة | جسر `session_players` في `sessions.php:~540` | لاعب لا يرى الحصة ولا يرسل RPE، فيصبح الحِمل ناقصاً |
| P2 | توقيت قاعدة البيانات UTC (`db.php:47`) والسودان UTC+2. `CURDATE()` يُستخدم لمنع تكرار Hooper اليومي | `player/hooper/save.php:185,202` | إدخال بين 00:00 و02:00 بتوقيت السودان يُحسب لليوم السابق. أثر محدود |

**ما يعمل جيداً:** حساب sRPE = RPE × المدة، و ACWR (7/28 مع حماية البيانات الناقصة)، و Monotony/Strain، و Hooper، وكلها مختبرة. ساعة الحصة والوقت الفعلي لكل لاعب تعمل. الحضور مربوط بالنادي بعد إصلاح RB2.

## 5. اللاعب

| الأولوية | المشكلة | الملف | الأثر |
|---|---|---|---|
| **P1 (مهم جداً)** | **اللاعب لا يرى نتائج التقييم التي سجّلها له المدرب.** الاستعلام يبحث بـ `user_id` الخاص باللاعب، بينما التقييم محفوظ بـ `user_id` الخاص بالمدرب | `api/player/assessments.php:69` و `api/assessments.php:103` (فرع `$isPlayer`)؛ الحفظ في `assessments.php:335` | شاشة «تقييماتي» تظهر فارغة. الإصلاح: `WHERE player_id = ? AND club_id = ?` |
| P1 | حساب اللاعب يتطلب بريداً إلكترونياً، ولا توجد استعادة كلمة مرور (راجع P0-3) | `players.php:380` | لاعبون كثيرون بلا بريد، أو ينسون كلمة المرور |
| P2 | الإشعارات Push: ملف `config/fcm-service-account.json` غير موجود في النسخ المحلية، وبدونه `push.php` يُرجع null بصمت | `api/includes/push.php:18,34` | **يجب التأكد على السيرفر.** إن لم يكن موجوداً فلا تصل تنبيهات الحصص أو RPE للاعبين |
| P3 | تحذير `_latestHooper` غير مستخدم | `player_dashboard.dart:551` | تنظيف فقط |

## 6. المدرب (المعد البدني)

| الأولوية | المشكلة | الملف | الأثر |
|---|---|---|---|
| P1 | مشاكل الحصص في القسم 4 (التمارين وتقييمات الحصة مربوطة بمنشئها) تظهر فوراً عند وجود أكثر من مدرب | انظر القسم 4 | |
| P1 | اختبار واحد فقط من أصل 3 (P0-1) | | |
| **قرار مطلوب منك** | المدرب لديه صلاحية `medical.read`، و `players.php` يُرجع `medical_notes` و `injury_notes` كاملة (`SELECT *`) | `api/includes/club_auth.php:81`، `api/players.php:199,232` | CLAUDE.md ينص على أن المدرب لا يرى التفاصيل الطبية الحساسة. الصلاحية أُعطيت عمداً، فهذا قرار للإدارة وليس خطأ برمجياً |
| P3 | دالتا `ClubService.addAssessment` و `updatePlayerScores` كود ميت (لا يُستدعيان)، لكن `updatePlayerScores` ترسل `name: '—'` مع الدرجات فقط. لو رُبطت ستستبدل اسم اللاعب وتمسح المركز والفريق والملاحظات الطبية وحالة الإصابة | `lib/services/club_service.dart:563,899` | يُنصح بحذفها قبل أن يستخدمها أحد |

## 7. الإدارة

| الأولوية | المشكلة | الملف | الأثر |
|---|---|---|---|
| P0 | لا يمكن إنشاء حسابات موظفين ولا إعادة تعيين كلمات المرور (P0-2 و P0-3) | | |
| P2 | إيقاف موظف (`suspended`) لا يلغي جلسات دخوله (`user_tokens`). السيرفر يمنعه من بيانات النادي، لكنه يبقى داخل التطبيق ويرى أخطاء | `api/club/staff.php` (DELETE) | تجربة سيئة، وليست ثغرة |
| P2 | نشر الـ API يدوي بالنسخ بين مجلدين، وقد انحرفت النسختان مرتين (يوليو وأغسطس، والآن مرة ثالثة) | | يلزم إجراء ثابت: diff قبل كل رفع |
| P3 | ملف مؤقت متروك داخل `lib/`: `assessment_result_page.dart.tmp.8856.8cfbb5a3aea1` | | تنظيف |
| P3 | `codemagic.yaml` يستخدم `flutter: stable` بدون تثبيت إصدار (محلياً 3.32.8) | | بناء iOS قد ينكسر فجأة مع تحديث Flutter |

## 8. خطة العمل قبل الانطلاق (بالترتيب)

1. **رفع الـ API:** نسخ `auth.php` والملفات السبعة (القسم 4) إلى nextkick.me، ثم التأكد من `delete_account` ووجود ملف FCM على السيرفر.
2. **إنشاء حسابات الموظفين:** إما إرجاع شاشة «التسجيل برمز دعوة» (الرمز يربطه بالنادي)، أو إضافة «إنشاء حساب موظف بكلمة مرور» في شاشة الطاقم، بنفس طريقة حسابات اللاعبين.
3. **إعادة تعيين كلمة المرور من الإدارة** للاعب والموظف (أبسط وأسرع من البريد الإلكتروني).
4. **إصلاح رؤية اللاعب لتقييماته** (سطران في ملفين PHP).
5. **تحويل `sessions/exercises.php` و `session_assessments.php` إلى ربط بالنادي (`club_id`)**، وإضافة `requireClubPermission('sessions.write')` في إنشاء الحصة.
6. **قرار:** هل يُطلق التشغيل بالسكوات فقط، أم يُنتظر إكمال التوازن والهبوط (P0-1)؟
7. قرار صلاحية المدرب على الملاحظات الطبية.
8. تنظيف: حذف الكود الميت والملف المؤقت، وتثبيت إصدار Flutter في Codemagic.

## 9. اختبار قبول ميداني مع النادي (قبل التشغيل الفعلي)

نفّذه على جهازين على الأقل: حساب إدارة، وحسابا مدرب، و3 لاعبين.

- [ ] الإدارة تنشئ حساب مدرب جديد، والمدرب يدخل بنجاح
- [ ] الإدارة تنشئ لاعباً بحساب دخول، واللاعب يدخل ويرى «حصة اليوم»
- [ ] المدرب (أ) ينشئ حصة، والمدرب (ب) يفتحها ويضيف تمريناً ويسجل الحضور
- [ ] بدء الحصة وإيقافها، ثم التحقق أن دقائق كل لاعب صحيحة
- [ ] اللاعب يرسل Hooper قبل الحصة و RPE بعدها، ثم يظهر الحِمل عند المدرب
- [ ] تقييم سكوات للاعب، ثم اعتماده، ثم ظهوره عند اللاعب في «تقييماتي»
- [ ] وصول إشعار Push للاعب عند إنشاء الحصة
- [ ] إيقاف موظف، ثم التحقق أنه لا يرى بيانات النادي
- [ ] حذف حساب من داخل التطبيق (متطلب Apple)
- [ ] قطع الإنترنت أثناء الحفظ، ثم التحقق من ظهور رسالة خطأ واضحة
- [ ] تصدير تقرير PDF بالعربية

## 10. ما تم إصلاحه من تقرير أغسطس وما زال صحيحاً

| البند | الحالة اليوم |
|---|---|
| RB1 — اختبارا التوازن والهبوط | ❌ ما زال مفتوحاً |
| RB2 — الحضور مربوط بالمنشئ | ✅ مُصلح في `sessions.php`، لكن نفس الخطأ ما زال في `sessions/exercises.php` و `session_assessments.php` |
| RB3 — انحراف الـ API | ⚠️ انحراف جديد: 8 ملفات (auth + 7) |
| RB4 — شاشة الكاميرا السوداء | ✅ مُصلح (لم يُختبر على جهاز) |
| RB5 — إعدادات بناء Android | ✅ مُصلح |
| التخزين الآمن + معالجة 401 | ✅ موجود |
| CI | ✅ الملف موجود `.github/workflows/ci.yml` |

---

# Production Readiness Closure — 2026-09-19 (فرع `fix/production-readiness-closure`)

نقطة البداية: قسم «تقرير الجاهزية التشغيلية — 2026-09-19» أعلاه (70/100).
النطاق: إغلاق العوائق والمشاكل المهمة **بدون** إعادة بناء. لم يتم أي Deploy، ولم تُعدَّل أي قاعدة بيانات إنتاج أو تطوير. كل الاختبارات التكاملية نُفذت على قاعدة اختبار منفصلة.

## Executive Summary

**Production Readiness Score: 82/100**

كل المشاكل البرمجية المكتشفة في التقرير السابق أُصلحت داخل الـ API نفسه وليس في الواجهة فقط، ولكل منها اختبار انحدار (Regression) يعمل عبر HTTP حقيقي.
ما بقي هو التحقق على السيرفر، واختبار UAT متعدد المستخدمين، واختبار على جهاز حقيقي. هذه البنود لا يمكن إغلاقها من الكود.

**الحالة: `READY FOR STAGING UAT`**

## Report findings corrected after code verification

1. **§10 من طلب العمل — «الاختبار العامل هو Single Leg Balance»: غير دقيق.** الكود (`assessment_result_model.dart`) يصنّف `singleLegBalance` كـ `partial`، وهو مخفي خلف «قريباً» في `player_selection_page.dart:222`. الاختبارات المكتملة فعلاً هي Squat و CMJ و Drop Jump و Single Leg Drop Jump، أما Squat Jump فـ `partial` لكنه مفعّل. لم يُفعَّل SLB لأن تفعيله بدون تحقق على جهاز يخالف قاعدة «لا نتائج غير مُتحقق منها». لذلك يُستبدل Single Leg Balance في الخطوة 9 من سيناريو UAT بـ **Squat** إلى أن يُعتمد SLB.
2. **تقريري السابق قال «السكوات فقط يعمل»: غير دقيق.** الصحيح ما ورد في البند 1.
3. **«Session not found» عند المدرب الثاني:** السبب أن ثلاثة مسارات كانت تبحث بـ `user_id` المنشئ: `sessions/exercises.php:49,81,137` و `session_assessments.php:56` و `add_exercise`. الإصلاح لم يجعل الجلسات مشتركة بين المدربين. القراءة أصبحت على مستوى النادي (عرض فقط)، والكتابة تُرجع **403 `not_session_owner`**. الجلسة من نادٍ آخر تُرجع 404 حتى لا يُكشف وجودها.
4. **«ملف FCM غير موجود على السيرفر»: لا يمكن استنتاجه من النسخ المحلية.** الملف مستثنى عمداً في `.gitignore` (`api/config/fcm-service-account.json`)، فغيابه محلياً طبيعي. البند منقول إلى قائمة Server Verification.
5. **«7 ملفات فيها مشكلة الإشعار بعد الحفظ»:** وُجدت 4 استدعاءات إضافية غير محمية، وهي `alerts/send.php` و `daily_readiness.php` و `hooper/save.php` و `notifications.php`. لذلك نُقل الإصلاح إلى الدوال المركزية بدل كل ملف على حدة.
6. **اكتشاف جديد:** قواعد البيانات المحلية (dev/test) طُبّق عليها 4 فقط من 22 Migration. وأيضاً `0008` و `0009` تستخدمان صيغة `ADD COLUMN IF NOT EXISTS` الخاصة بـ **MariaDB** والتي **تفشل على MySQL**.

## Business rules applied (كما في الطلب)

- **الجلسة ملك المدرب الذي أنشأها**، والنادي حدود أمنية فقط. التعديل وتسجيل الحضور وساعة الجلسة والتمارين والتقييمات داخل الجلسة والحذف مسموحة للمالك فقط، أو لـ **owner/admin** كـ «admin override» (دور موجود أصلاً بصلاحية `*`). لم تُخترع صلاحيات جديدة.
- **التقييم ملك المدرب الذي سجّله** (`assessments.user_id`). اللاعب يرى تقييماته عن طريق `player_id`، ولا يُستخدم `user_id` للفلترة.
- **المعلومات الطبية على مستويين** باستخدام الصلاحية الموجودة `medical_detail.read` (الطبيب، المعالج، owner/admin). المدرب يتلقى الحالة، وسبب الغياب، وتاريخ العودة، والقيود (`player_daily_decisions`)، وعلامة `has_injury_notes`. **لا يتلقى النص الطبي من الـ API إطلاقاً.**

## Fixed (مُتحقق منه باختبارات فعلية)

| # | الإصلاح | الملفات | التحقق |
|---|---|---|---|
| F1 | **إنشاء حساب موظف** من الإدارة: `club/staff.php action=create_account`، بنفس منطق `register` للطاقم (users + club_staff + club_id). يمنع إنشاء owner، ويرفض تكرار البريد أو الهاتف (409)، ويُسجَّل في الـ Audit. لم يُرجَع التسجيل الذاتي الذي حُذف لأجل Apple | `api/club/staff.php`, `staff_screen.dart`, `api_service.dart` | HTTP D1–D6 |
| F2 | **Reset Password من الإدارة** (owner/admin) لموظف أو لاعب في نفس النادي. لا تُعرض كلمة المرور القديمة، وتُخزَّن بـ bcrypt cost 11. **تُلغى كل جلسات دخول المستخدم.** لا أحد يستطيع إعادة تعيين كلمة مرور الـ owner، والـ admin لا يُعاد تعيينه إلا من الـ owner. يُسجَّل في الـ Audit بدون كلمة المرور | `api/club/staff.php`, `staff_screen.dart`, `club_player_profile_page.dart` | HTTP D7–D15 |
| F3 | **إيقاف موظف يلغي جلسات دخوله** (سابقاً كان يبقى داخل التطبيق) | `api/club/staff.php` | HTTP D16 |
| F4 | **اللاعب يرى تقييماته التي سجّلها المدرب** في `player/assessments.php` و `assessments.php`، ومجموعات المحاولات، وآخر تقييم في `my-profile` وخطط الـ AI | 6 ملفات PHP | HTTP A2–A4 |
| F5 | **ملكية التقييم:** المدرب B لا يستطيع override أو approve أو الكتابة فوق تقييم المدرب A (403). اللاعب لا يسجّل تقييماً للاعب آخر. المدرب لا يسجّل في جلسة لا يملكها | `api/assessments.php` | HTTP A5–A13, B24 |
| F6 | **ملكية الجلسة** في كل مسارات الكتابة (upsert، clock، attendance، add_exercise، DELETE، exercises POST/DELETE) عبر `requireManageableSession()` مركزي | `api/sessions.php`, `api/sessions/exercises.php`, `club_auth.php` | HTTP B3–B14, B20–B21, B28–B29 |
| F7 | **فرض `sessions.write` في الـ API:** الطبيب والمحلل واللاعب لم يعودوا قادرين على إنشاء جلسات عبر طلب يدوي | `api/sessions.php` | HTTP B15–B17 |
| F8 | **عزل النادي في الجلسة:** رفض `player_ids` من نادٍ آخر (422)، ورفض حضور لاعب غير مسجّل في الجلسة (422)، ورفض الكتابة فوق id جلسة نادٍ آخر (403) | `api/sessions.php` | HTTP B8, B18–B20 |
| F9 | **تقييمات الجلسة تُعرض على مستوى النادي** (سابقاً للمسجّل الحالي فقط) | `api/club/session_assessments.php` | HTTP B23 |
| F10 | **فصل المعلومات الطبية:** `redactMedicalFields()` في `players.php` (3 مسارات)، و `club/player.php`، و `coach/players.php`، و `alerts/coach.php`، و `physical-coach-dashboard.php`. وأيضاً **عند تعديل المدرب للاعب تُحفظ ملاحظات الطبيب ولا تُمسح** (سابقاً كان نموذج المدرب يرسل null فيمسحها) | 6 ملفات PHP + `app_state.dart`, `add_edit_player_page.dart` | HTTP C1–C8 |
| F11 | **فشل الإشعار لا يُفشل حفظاً ناجحاً:** `createNotification()` تُرجع bool ولا ترمي Exception، و `notifyClubRole()` محمية. الجلسة تُرجع `success:true` مع `notifications_sent:false` كتحذير. `alerts/send.php` (حيث الإشعار هو العملية نفسها) يُرجع العدد الفعلي للمرسل والفاشل | `includes/notifications.php`, `includes/push.php`, `sessions.php`, `alerts/send.php` | Unit + HTTP B25–B27 |
| F12 | **خطأ جديد أُصلح: حذف device tokens صالحة.** أي فشل FCM (انقطاع شبكة، 500، 401) كان يحذف توكن الجهاز فتتوقف الإشعارات نهائياً لذلك الجهاز. الآن لا يُحذف التوكن إلا عند `UNREGISTERED` أو توكن غير صالح. وأُضيف Logging لكل حالة: sent، no_device_token، invalid token، rejected، credentials missing، network error | `includes/push.php` | Unit (9 حالات) |
| F13 | **الحماية من التكرار:** تكرار نفس id لجلسة أو تقييم من نفس المالك = تحديث (Idempotent) وليس صفاً جديداً. نموذج الجلسة يولّد id مرة واحدة لكل نموذج (سابقاً uuid جديد مع كل محاولة، فتتكرر الجلسة بعد timeout)، مع Guard ضد الضغط المزدوج. وأُضيف نفس الـ Guard لأزرار الاعتماد وإعادة الحفظ في شاشة النتيجة | `session_form_page.dart`, `assessment_result_page.dart`, `sessions.php`, `assessments.php` | HTTP A8, B2, B27 |
| F14 | **الواجهة:** `canManage` من السيرفر يخفي أزرار التعديل والساعة والحضور والتقييم في جلسة مدرب آخر، مع شريط «عرض فقط». وحقول الملاحظات الطبية مخفية لغير الطاقم الطبي | `club_models.dart`, `session_detail_page.dart` | analyze ✓ — DEVICE VERIFICATION REQUIRED |
| F15 | **Audit:** إنشاء وتعديل وحذف الجلسات، وإنشاء التقييم وتغيير درجته، وإنشاء حساب موظف، وإعادة تعيين كلمة المرور، وإيقاف موظف. التسجيل Best-effort عبر `logAuditSafe()` حتى لا يُفشل عملية محفوظة، ولا يُسجَّل فيه أي كلمة مرور | `includes/audit_log.php` + أعلاه | HTTP D15 |
| F16 | حذف كود ميت خطير: `ClubService.addAssessment` و `updatePlayerScores` (كانت سترسل `name:'—'` وتمسح بيانات اللاعب لو استُدعيت)، وحذف ملف `.tmp` المتروك في `lib/` | `club_service.dart` | analyze ✓ |
| F17 | أداة فحص Push على السيرفر: `php api/cli/test_push.php <email>` تطبع النتيجة (Outcome) | `api/cli/test_push.php` | php -l ✓ |

## Remaining Issues

| الأولوية | البند | ملاحظة |
|---|---|---|
| قرار منتج | Single Leg Balance و Jump Landing ما زالا «قريباً» | بطلبك: لا يؤخران الإطلاق. التفعيل يحتاج تحققاً على جهاز من `BalanceAnalysisService` |
| قرار منتج | owner/admin يتلقون النص الطبي من الـ API (صلاحية `*`) بينما التطبيق يخفيه عنهم | سلوك قائم قبل هذا العمل. إن كانت الإدارة لا ترى التفاصيل الطبية، تُستثنى `medical_detail.read` من `*` |
| قرار منتج | `performance_manager` و `tactical_coach` يملكون جلساتهم فقط، بلا override | تطبيق حرفي لقاعدة «لا تخترع صلاحيات» |
| قرار منتج | المدرب B يرى جلسات المدرب A (قراءة فقط) | القراءة على مستوى النادي ضرورية للوحات والتقارير. إن أردتم إخفاءها تماماً فهذا تغيير منفصل |
| قرار منتج | اللاعب يرى أيضاً التقييمات بحالة `pending_review` | هل يُعرض عليه المعتمد فقط؟ |
| قرار منتج | **مدير الأداء (performance_manager)** لم يعد يرى الملاحظات الطبية ولا يعدّلها. كان يملك `medical.write` لكنه لا يملك `medical_detail.read`، وتعديلاته على هذه الحقول تُتجاهل الآن. الطلب ذكر المدرب فقط | إما يبقى هكذا، أو تُعطى له `medical_detail.read/write` |
| قرار منتج | الـ admin يستطيع إنشاء حساب admin آخر (مطابق لقواعد رموز الدعوة الحالية)، بينما إعادة تعيين كلمة مرور admin مقصورة على الـ owner | هل يُقصر إنشاء admin على الـ owner أيضاً؟ |
| P2 | `coach/plans/generate-ai.php:154` ما زال يرسل نص `injury_notes` داخل الطلب إلى الـ AI عند توليد خطة من المدرب، وقد تعيده الخطة الناتجة | يُستبدل بالحالة والقيود فقط |
| مراقبة في UAT | جلسات قديمة في الإنتاج قائمة `player_ids` فيها فارغة لكن سُجّل لها حضور: أي تعديل حضور جديد عليها يُرجع 422 | متوقع مع التحقق الجديد، ويُراقب |
| مراقبة في UAT | حذف جلسة لا يحذف صف `training_sessions` ولا صفوف لاعب تقدّم فيها (`pre_checked`/`started`)، فلاعب أكمل الفحص المسبق قد يظل يراها في «حصة اليوم» | يحافظ على السجل، ويُراقب |
| مراقبة في UAT | جلسات مدرب تم إيقافه لا يعدّلها إلا owner/admin | نتيجة مباشرة لقاعدة الملكية |
| P2 | لا يوجد «إجبار تغيير كلمة المرور عند أول دخول» | يحتاج عمود `must_change_password` و Migration. المستخدم يستطيع التغيير من الإعدادات (`change_password`) |
| P2 | تبويب «رموز الدعوة» ما زال موجوداً، لكن لا توجد شاشة تسجيل تستخدم الرموز | يُقترح إخفاؤه أو شرح أنه للويب فقط |
| P2 | `auth.php?action=register` ما زال مفتوحاً على السيرفر: يمكن إنشاء حساب `coach` أو `team` نشط بدون رمز | لا يصل لبيانات أي نادٍ (لا يوجد club_staff)، لكن يُفضّل إغلاقه |
| P2 | حساب اللاعب يتطلب بريداً إلكترونياً | قاعدة قائمة |
| P2 | توقيت القاعدة UTC والسودان UTC+2 (`CURDATE()` في Hooper) | إدخال بين 00:00 و02:00 يُحسب لليوم السابق |
| P3 | `api/mobile/` كود غير مستخدم من التطبيق | للتنظيف لاحقاً |
| P3 | تحذير `_latestHooper` غير مستخدم | موجود من قبل |

## Production Blockers

1. **نشر الـ API لم يتم بعد:** السيرفر متأخر (راجع جدول Server Verification). **حذف الحساب (Apple) لن يعمل على الإنتاج قبل رفع `auth.php`.**
2. **حالة Migrations الإنتاج غير معروفة.** إن لم يُطبَّق `0012_device_tokens` فالإشعارات لا تعمل (الآن بدون أن تُفشل الحفظ). وإن كان الإنتاج MySQL وليس MariaDB فإن `0008` و `0009` تفشلان بصيغتهما الحالية.
3. **UAT متعدد المستخدمين على Staging لم يُنفَّذ.**

## Server Verification Required

| البند | ما يجب فعله |
|---|---|
| رفع الملفات | نسخ هذه الملفات من `merr/api` إلى `nextkickwebsite/api`، **ملفاً ملفاً وليس المجلد كاملاً** (المجلد المنشور يحتوي وحدات NextKick غير موجودة في merr): `auth.php`, `assessments.php`, `players.php`, `sessions.php`, `sessions/exercises.php`, `matches.php`, `ai/generate-plan.php`, `alerts/coach.php`, `alerts/send.php`, `club/physical-coach-dashboard.php`, `club/player.php`, `club/session_assessments.php`, `club/staff.php`, `club/injuries.php`, `club/physio_sessions.php`, `club/rehab_phases.php`, `club/tasks.php`, `coach/players.php`, `coach/plans/generate-ai.php`, `includes/audit_log.php`, `includes/club_auth.php`, `includes/notifications.php`, `includes/push.php`, `player/assessments.php`, `player/my-profile.php`, `player/ai-plan/generate.php`, `player/session/post-feedback.php`, `cli/test_push.php`. تم التحقق محلياً أن كل ملف منها يختلف عن النسخة المنشورة بسبب هذا العمل أو انحراف أغسطس فقط |
| Migrations | `php api/cli/migrations.php status` على الإنتاج (بحساب مخوّل)، وتسجيل أيها APPLIED. التأكد من نوع القاعدة (`SELECT VERSION()`). على MySQL تُطبَّق `0008` و `0009` بصيغة `ADD COLUMN` عادية (تم التحقق منها على نسخة اختبار) |
| device_tokens | `SHOW TABLES LIKE 'device_tokens'` |
| FCM | وجود `config/fcm-service-account.json` أو `FCM_SERVICE_ACCOUNT_PATH`، ثم `php api/cli/test_push.php <email>` بحساب له جهاز مسجّل، والتأكد أن Outcome = `sent` |
| حذف الحساب | بعد الرفع: `POST auth.php?action=delete_account` بحساب تجريبي على Staging |
| Staging | لا توجد بيئة Staging في المشروع. المطلوب نسخة من الإنتاج (قاعدة بيانات وملفات) تحت مسار منفصل، ثم تنفيذ كل ما سبق عليها أولاً |

## Device Verification Required

`Implemented — requires device verification`:
- شاشة إنشاء حساب موظف، وإعادة تعيين كلمة المرور (الطاقم وملف اللاعب).
- شريط «عرض فقط» وإخفاء أزرار جلسة مدرب آخر.
- إخفاء الحقول الطبية في نموذج اللاعب لغير الطاقم الطبي.
- وصول الإشعارات (Push) فعلياً.
- بقاء تسجيل الدخول بعد إعادة التشغيل، والخروج التلقائي بعد Reset أو إيقاف الحساب (401 → onboarding).
- شاشة حذف الحساب.
- سلوك إعادة المحاولة عند ضعف الشبكة (الجلسة لا تتكرر).
- «تقييماتي» عند اللاعب.

## Security Verification

| المجال | النتيجة | الدليل |
|---|---|---|
| Authorization في الـ API وليس الواجهة | ✅ | B15–B17 (طبيب/محلل/لاعب عبر طلب يدوي → 403)، D6/D14 |
| Club isolation | ✅ | A11–A13, B14, B18–B20, D12 (404/403/422) |
| Medical permissions | ✅ | C1–C8: النص الطبي لا يخرج من الـ API للمدرب، ولا يُمسح بتعديله |
| Session ownership | ✅ | B3–B14, B21, B24, B28 |
| Assessment ownership | ✅ | A5–A10 |
| Password handling | ✅ | bcrypt، إلغاء الجلسات، لا كلمة مرور في Audit (D15) |
| أخطاء 401/403/404/422 | ✅ | 401 توكن ملغى، 403 صلاحية/ملكية (`code`)، 404 خارج النادي، 422 بيانات غير صالحة، 409 تكرار |

## Test Results (أرقام فعلية من هذا التنفيذ)

| الاختبار | النتيجة |
|---|---|
| `flutter analyze` | تحذير واحد قائم من قبل (`_latestHooper`)، **0 مشاكل جديدة** |
| `flutter test` | **29/29** ناجح (1 skipped كما كان) |
| `php -l` على كل ملفات PHP المعدلة والجديدة | لا أخطاء |
| حسابات الحِمل `training_load_calculator_pure_test` | **36/36** |
| `body_composition_calculator_test` | **23/23** |
| اختبارات p0 pure (acwr, rpe_identity, rbac_matrix, sessions_write, body_comp_completeness, training_load_quality) | **6/6 OK** |
| `p1_notification_isolation_test` (جديد) | **OK** (3 سيناريوهات عزل + 9 حالات تصنيف FCM) |
| `p0_attendance_scope_test` (DB، حُدِّث للقاعدة الجديدة) | **OK** |
| `p0_scope_integration_test` (DB) | **OK** |
| **`p1_readiness_http_test` (جديد، HTTP حقيقي)** | **70/70** على قاعدة `smart_sport_p1_test_20260919` (مُهاجرة بالكامل) |
| نفس الاختبار على الكود القديم (HEAD) | **39 فشل من 70**: منها نحو 33 خطأ حقيقياً (Regression)، و 6 تفشل فقط لأنها تتحقق من حقول جديدة في الرد (`created`، `can_manage`، `notifications_sent`، `deleted`) لا يرجعها الكود القديم |
| Migrations على نسخة اختبار | كل الـ Pending طُبّقت بنجاح عدا 0005 و 0006 (تحتاجان موافقة يدوية حسب التصميم)، و 0008 و 0009 بصيغة MySQL |

التشغيل:
```
php api/tests/make_readiness_test_db.php smart_sport_test smart_sport_p1_test_20260919
APP_ENV=test TEST_DB_NAME=smart_sport_p1_test_20260919 php api/tests/p1_readiness_http_test.php
```

## Final Recommendation

**`READY FOR STAGING UAT`**

الكود جاهز للنشر على Staging وتنفيذ سيناريو UAT الكامل (24 خطوة، مع استبدال SLB بالـ Squat في الخطوة 9). لا يُنشر على الإنتاج قبل: رفع الملفات المذكورة، والتحقق من Migrations و `device_tokens` و FCM على السيرفر، ونجاح UAT بحسابات Admin و Coach A و Coach B وطبيب و 3 لاعبين، واختبار الجهاز للبنود أعلاه.

---

# Staging Readiness — Phase 2 (2026-09-19)

نص الطلب وصل مقطوعاً بعد البند 17 («لا يمكن تشغيله»)، فنُفّذت البنود 1–17 كاملة. أما Staging و UAT والنشر فتحتاج وصولاً للسيرفر ولأجهزة فعلية، وهو غير متاح من هذه البيئة، لذلك وُثّقت كمتطلبات مفتوحة ولم يُدَّعَ تنفيذها.

## Executive Summary

**Production Readiness Score: 85/100**, والحالة **`READY FOR STAGING UAT`**.
أُغلقت القرارات المفتوحة الأربعة، وأُخفيت اختبارات الـ AI بمفتاح مركزي واحد بدون حذف أي شيء. كل قاعدة جديدة مفروضة في الـ API ولها اختبار انحدار.

## Decisions closed (مُطبّقة ومُختبرة)

| القرار | التطبيق | التحقق |
|---|---|---|
| **اللاعب يرى التقييمات المعتمدة فقط** (`approved`). مسار الاعتماد حقيقي: زر «اعتماد» في شاشة النتيجة، ويحذف فيديو الجهاز بعده، والحالة الافتراضية `pending_review` | كل الاستعلامات الموجهة للاعب: `player/assessments.php`، `assessments.php` (القائمة + المحاولات)، `my-profile`، `reports/my-progress`، `ai-plan/generate`، `ai/generate-plan`. **استثناء:** ما سجّله اللاعب لنفسه (لاعب مستقل) يبقى ظاهراً له | HTTP A1b, A1c, A2–A4 |
| **owner/admin لا يرون النص الطبي تلقائياً.** `medical_detail.read/write` صارتا `EXPLICIT_ONLY_ACTIONS` لا تشملهما صلاحية `*`. تُمنحان صراحة للطبيب وأخصائي العلاج الطبيعي والتدليك فقط، وهذا يطابق التعليقات الموثقة أصلاً في `injuries.php` و `rehab_phases.php` | `includes/club_auth.php` | HTTP C9–C13، `p0_rbac_capability_matrix_test` (حُدِّث بسبب قرار العمل، ولم يُحذف منه شيء) |
| **مدير الأداء لا يرى النص الطبي**، ويرى الجاهزية والتوفر والقيود وحالة العودة | كان مطبّقاً في المرحلة السابقة، وأُضيف له اختبار | HTTP C11 |
| **owner فقط ينشئ admin:** سواء بإنشاء حساب مباشر، أو برمز دعوة من نوع admin، أو بإعادة تفعيل رمز admin معطّل. والـ admin لا يوقف admin آخر. لا يوجد في الـ API أي مسار لتغيير الدور (`staff_role`)، لذلك لا يمكن للمستخدم ترقية نفسه | `club/staff.php`، وخيار admin مخفي في الواجهة لغير الـ owner | HTTP D6a–D6g |

## AI Tests — `INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER`

المفتاح المركزي في `lib/feature_flags.dart`:
`kAiTestsEnabled = bool.fromEnvironment('AI_TESTS_ENABLED', defaultValue: false)`.
لإعادة التفعيل لاحقاً: `--dart-define=AI_TESTS_ENABLED=true`، بدون أي تعديل في الكود.

| الاختبار | الحالة |
|---|---|
| Squat Assessment | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| Countermovement Jump | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| Squat Jump | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| Drop Jump | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| Single Leg Drop Jump | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| Single Leg Balance | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| Jump Landing | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |
| اختبارات الجلسة الجماعية (Batch) بالكاميرا | INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER |

**كيف أُخفيت (بدون حذف):**
- **نقاط الدخول في الواجهة:** زر «تقييم بالكاميرا» في ملف اللاعب، وزر «اختبار AI» في لوحة المعد البدني (الإجراءات السريعة وقائمة التسجيل)، وزر الاختبار الجماعي وزر «ابدأ» لكل لاعب في شاشة الجلسة، وتبويب «تمارين AI» في نموذج الجلسة (التمارين اليدوية فقط تظهر)، وزر «بدء التقييمات» في تقرير الفريق، وتلميح «تقييم AI» في شاشة تنفيذ الجلسة للاعب.
- **حماية داخلية في الشاشات نفسها:** شاشة الكاميرا، وإعداد الوضعية (ويب)، واختيار الاختبار، ومركز التقييم، وطابور الجلسة تُرجع من `createState()` حالة «غير متاح» (`AiTestsDisabledState`). بذلك لا يبدأ `initState` إطلاقاً: لا كاميرا، ولا طلب إذن، ولا تحميل نموذج. وهذا يغطي Deep Links والمسارات القديمة المخزنة وأي `push` مباشر، بدون Crash.
- **المسارات:** `/physical-assessment` و `select` و `new-player` و `camera` تؤدي إلى صفحة «غير متاح» مع زر رجوع. الكود نفسه باقٍ.
- **ما بقي ظاهراً عمداً:** سجل التقييمات السابقة ونتائجها (`/physical-assessment/history` و `result` وتقييمات اللاعب)، وقائمة تمارين AI المحفوظة سابقاً على جلسة (عرض فقط)، والتقييم اليدوي، و FMS، وتكوين الجسم (غير معتمدة على AI).
- **Backend:** لم يُحذف ولم يُفتح أي Endpoint. الصلاحيات كما هي. لم تُكتب أي Migration، ولم تُعدَّل أو تُحذف أي نتيجة AI محفوظة.
- **كود ميت (غير قابل للوصول أصلاً):** `live_exercise_page.dart` (لا يستورده أي ملف) و `ClubPlayerDetailPage` (لا يُنشأ في أي مكان). تُركا كما هما.

## Database Migrations

| البند | النتيجة |
|---|---|
| تطبيق كل الـ migrations المعلّقة على نسخة من قاعدة الاختبار (MySQL 9.1) عبر `api/cli/migrations.php` | ✅ نجحت كلها: 0003, 0004, 0010–0020 |
| `0005` و `0006` | تُتخطى تلقائياً (`MANUAL APPROVAL REQUIRED`) حسب التصميم. تحتاج تقرير بيانات وموافقة قبل التشغيل |
| `0008` و `0009` | صيغة `ADD COLUMN IF NOT EXISTS` **تعمل على MariaDB فقط**. على MySQL تُطبَّق بصيغة `ADD COLUMN` (تم التحقق منها). **لم يُعدَّل الملفان** لأن تغييرهما يغيّر الـ checksum على أي قاعدة طُبّقا عليها |
| الإنتاج | **SERVER VERIFICATION REQUIRED:** `SELECT VERSION()` و `php api/cli/migrations.php status` |

## Production Blockers (المتبقية)

1. **Staging غير موجود بعد.** لم يُنشر الفرع على أي سيرفر.
2. **UAT متعدد المستخدمين لم يُنفَّذ.**
3. **حذف الحساب (Apple)** غير مُتحقق على السيرفر، لأن `auth.php` المنشور لا يحتوي `delete_account` حتى يُرفع.
4. **حالة Migrations الإنتاج** و `device_tokens` و FCM غير مُتحقق منها.

عدم تفعيل اختبارات الـ AI **ليس** Blocker، لأنها مخفية بالكامل ولا يمكن تشغيلها (مُختبر آلياً).

## Staging Plan (للتنفيذ على السيرفر)

1. مسار منفصل (مثال `staging.nextkick.me/api` أو `nextkick.me/staging/api`)، وقاعدة بيانات منفصلة **منسوخة من الإنتاج** (dump → restore). لا تُشارَك قاعدة الإنتاج.
2. `db_credentials.php` خاص بالـ Staging، ونسخة من `config/fcm-service-account.json` خارج الـ web root.
3. رفع ملفات الـ API المذكورة في قسم Closure (ملفاً ملفاً)، ثم تشغيل `migrations.php status` ثم `up` على Staging فقط.
4. بناء التطبيق للـ Staging: `--dart-define=API_BASE_URL=https://<staging>/api` (بدون `AI_TESTS_ENABLED`).
5. تشغيل مجموعة الاختبار الآلية على نسخة Staging:
   `APP_ENV=test TEST_DB_NAME=<staging_copy_test> php api/tests/p1_readiness_http_test.php`
   (تُنشئ بياناتها الخاصة وتحذفها).
6. `php api/cli/test_push.php <email>` بحساب له جهاز مسجّل.
7. UAT: سيناريو الـ 24 خطوة، مع استبدال الخطوة 9 (تقييم SLB) باختبار يدوي أو FMS لأن AI مخفي، وإضافة خطوة: «محاولة فتح اختبار AI من رابط قديم → صفحة غير متاح».

## Device Verification Required

كل بنود قسم Closure، مضافاً إليها: عدم ظهور أي زر اختبار AI في كل الشاشات، وصفحة «غير متاح» عند فتح رابط قديم، وعدم طلب إذن الكاميرا إطلاقاً.

## Test Results (هذه المرحلة، أرقام فعلية)

| الاختبار | النتيجة |
|---|---|
| `p1_readiness_http_test` (HTTP حقيقي) | **84/84** (كانت 70، أُضيفت 14 حالة: الاعتماد، الطبي لـ admin/owner/PM، ملف الإصابات، منع تصعيد الصلاحيات) |
| `flutter test` | **32/32** (1 skipped)، منها 3 جديدة لمفتاح الـ AI |
| `flutter analyze` | 0 مشاكل جديدة (التحذير القديم `_latestHooper` فقط) |
| `p0_rbac_capability_matrix_test` | OK |
| `p1_notification_isolation_test` | OK |
| `php -l` لكل الملفات المعدلة | لا أخطاء |

## Final Recommendation

**`READY FOR STAGING UAT`**. الخطوة التالية تنفيذ خطة الـ Staging أعلاه على السيرفر، ثم UAT، ثم Production Deployment Review.

---

# Staging & Server Verification — Phase 3 (2026-09-19)

## حدود هذه المرحلة (بصراحة)

من هذه البيئة **لا يوجد وصول للسيرفر**: لا SSH ولا cPanel ولا FTP لـ nextkick.me (مفاتيح SSH الموجودة تخص مشاريع أخرى، والنشر يتم برفع الملفات يدوياً عبر cPanel). ولا توجد بيئة Staging، ولا جهاز حقيقي متصل.

لذلك:
- **لم يُنفَّذ** `SELECT VERSION()` ولا `migrations.php status` على السيرفر.
- **لم يُنشر** شيء على Staging، و**لم يُنفَّذ** UAT متعدد المستخدمين، و**لم يُنفَّذ** اختبار الجهاز.
- ما نُفّذ فعلياً: فحص قراءة فقط لـ Endpoints عامة على الإنتاج (طلبات GET بدون توكن، بدون أي كتابة)، وتحقق من الـ Migrations على قواعد اختبار محلية مؤقتة، وتجهيز حزمة النشر كاملة.

## Environment

| البند | القيمة | المصدر |
|---|---|---|
| Production URL | `https://nextkick.me/api` | ثابت في `app_config.dart` |
| Web server | LiteSpeed خلف Cloudflare | Headers لطلب `health.php` |
| `health.php` | `{"status":"ok","checks":{"php":"ok","database":"ok"}}` | GET فعلي (قراءة فقط) |
| PHP version (prod) | **غير معروف**: لا يظهر في الـ Headers | SERVER VERIFICATION REQUIRED |
| DB engine/version (prod) | **غير معروف**. مؤشر قوي على **MariaDB**: الملف `migrations/live_v1.sql` مكتوب «Run once on nextkick.me» ويستخدم `ADD COLUMN IF NOT EXISTS` (صيغة MariaDB)، ومع ذلك طُبّق على الإنتاج | SERVER VERIFICATION REQUIRED: `SELECT VERSION();` |
| Staging URL | لا يوجد | BLOCKED |
| بيئة التحقق المحلية | PHP 8.3.14، MySQL 9.1.0، Flutter 3.32.8 | فعلي |
| Release commit (backend + app) | انظر «Exact Release Commit» أدناه | git |

## اكتشافات فحص الإنتاج (قراءة فقط)

| # | الاكتشاف | الدليل | الإجراء |
|---|---|---|---|
| S1 | **`auth.php` على الإنتاج يحتوي `delete_account` فعلاً.** «Unknown action» لأكشن وهمي، و«Method not allowed» لـ `delete_account` بـ GET. هذا يصحّح افتراض التقرير السابق المبني على النسخة المحلية المنسوخة | curl فعلي | Report finding corrected after code verification |
| S2 | **خطأ إنتاج: `players.php` يُرجع HTTP 200 بدل 401/403/404.** الملف يبدأ بـ 4 مسافات قبل `<?php`. LiteSpeed بلا output buffering يرسلها قبل الـ Headers فيضيع الـ status code. أثره: معالج 401 العام في التطبيق (تسجيل الخروج عند انتهاء الجلسة) لا يعمل لهذا الـ Endpoint | الإنتاج: `players.php → HTTP 200 "    {\"error\":\"Unauthorized\"}"`. محلياً بـ `output_buffering=0`: القديم 200 والمُصلح 401 | **أُصلح** (commit `17b3bd9`) مع اختبار CI يمنع تكراره في أي ملف |
| S3 | **`auth.php` على الإنتاج يُرجع HTTP 200 لأخطائه** (`action=me` بدون توكن → 200، مع مسافة قبل JSON). نسخ `auth.php` المحلية نظيفة، فالنسخة المرفوعة يدوياً على السيرفر مختلفة | curl فعلي | رفع `auth.php` من الريبو ضمن الـ Manifest، ثم التحقق بـ `curl -i` |
| S4 | `sessions.php` و `assessments.php` و `club/staff.php` تُرجع 401 صحيحاً | curl فعلي | — |

## Migration Status

| Migration | الحالة المحلية (قاعدة اختبار مُرقّاة) | الإنتاج | القرار |
|---|---|---|---|
| 0001–0004, 0007, 0010–0020 | APPLIED بنجاح عبر `migrations.php up` (MySQL 9.1) | **غير معروف** | تُطبّق على Staging أولاً بعد `status` |
| **0005** (أرشفة RPE المكررة + Unique keys) | PENDING. يتخطاها الـ runner تلقائياً (`SKIPPED_MANUAL`) | غير معروف | **Manual Approval** حسب التصميم: تعدّل البيانات (`is_active_record=0` للمكرر، **بدون حذف**، مع Audit)، وتضيف `UNIQUE (logical_key)` و `(club_id, idempotency_key)`. تتطلب تشغيل `preflight_data_audit.sql` واعتماد قائمة الأرشفة. **غير مطلوبة لهذا الإصدار**: لا يعتمد عليها أي كود في الفرع. للتشغيل الرسمي: `php api/cli/migrations.php up 0005_archive_rpe_duplicates_and_add_unique_key.sql` بعد الموافقة |
| **0006** (تصحيح `club_id` في تكوين الجسم) | PENDING (`SKIPPED_MANUAL`) | غير معروف | Manual Approval: تصحيح بيانات مع سجل (Ledger) وقابل للعكس. **غير مطلوبة لهذا الإصدار** |
| **0008 / 0009** | على MySQL تفشل بصيغتها (`ADD COLUMN IF NOT EXISTS`). طُبّقت بصيغة MySQL في بيئة الاختبار فقط، و**لم يُعدَّل الملفان** | غير معروف (مؤشر MariaDB) | إن أثبت `SELECT VERSION()` أنها MariaDB تُترك كما هي. إن كانت MySQL: تُطبّق يدوياً بـ `ADD COLUMN` عادي، ثم تُسجَّل في `p0_schema_migrations` بنفس الـ checksum، **بدون تعديل الملف**، حتى لا ينكسر السجل في أي بيئة طُبّقت عليها |
| **0021** (جديد: `assessments.status/approved_*`) | APPLIED. وتحقق منفصل: تضيف الأعمدة على جدول يفتقدها، وتشغيل ثانٍ لا يغيّر شيئاً (Idempotent)، والصفوف الموجودة تبقى (`pending_review`) | غير معروف | **مطلوبة لهذا الإصدار** لقاعدة «اللاعب يرى المعتمد فقط». آمنة على MySQL و MariaDB. وحتى لو لم تُطبَّق، لا يحدث 500 (راجع Fallback أدناه) |

**اكتشاف إضافي:** «Fresh installation» من الصفر **غير ممكن بالأدوات الحالية**. لا يوجد ملف schema أساسي، و `ensureSchema()` يعدّل جدول `assessments` (`db.php:122`) قبل إنشائه (`db.php:187`). لذلك **Staging يجب أن يُبنى من نسخة من قاعدة الإنتاج** (مسار الترقية)، ولا يُبنى من الصفر.

**Fallback:** عمود `assessments.status` كان يُنشأ فقط عبر الـ bootstrap المعطّل افتراضياً. أُضيف `playerAssessmentVisibilitySql()`: إذا غاب العمود فلا يوجد مسار اعتماد أصلاً، فيُعتبر الحفظ نهائياً (كما نص البند 6 من طلب المرحلة الثانية)، ولا يظهر 500 للاعب.

## Automated Tests (فعلية، محلياً)

| الاختبار | النتيجة |
|---|---|
| `p1_readiness_http_test` (HTTP حقيقي، **`output_buffering=0` مثل الإنتاج**) | **84/84** |
| PHP pure: training load 36/36، body composition 23/23، acwr، rpe_identity، rbac_matrix، sessions_write، bc_completeness، training_load_quality، notification_isolation، **no_stray_output (جديد)**، **assessment_visibility (جديد)** | كلها OK |
| DB tests: `p0_attendance_scope_test`، `p0_scope_integration_test` | OK |
| `php -l` لكل ملفات `api/` | لا أخطاء |
| `flutter test` | **32 passed، 0 failed، 1 skipped** |
| `flutter analyze` | تحذير واحد قديم (`_latestHooper`)، **0 جديد** |
| **على Staging** | **BLOCKED**: لا توجد بيئة Staging |

## UAT Results

| السيناريو | الحالة |
|---|---|
| 30 — إنشاء الأدوار (Owner/Admin/منع التصعيد) | **BLOCKED** على Staging. مُغطّى آلياً محلياً (D1–D6g) |
| 31 — Reset Password | **BLOCKED** على Staging. محلياً PASS (D7–D15) |
| 32 — ملكية الجلسات | **BLOCKED** على Staging. محلياً PASS (B1–B29) |
| 33 — ظهور التقييمات (معتمد فقط + استثناء التسجيل الذاتي) | **BLOCKED** على Staging. محلياً PASS (A1b–A4) |
| 34 — البيانات الطبية (Raw JSON) | **BLOCKED** على Staging. محلياً PASS (C1–C13) |
| 35 — AI مخفي | **DEVICE VERIFICATION REQUIRED**. آلياً PASS (Flutter tests 3) |
| 36 — الإشعارات | **BLOCKED / DEVICE VERIFICATION REQUIRED** |
| 37 — الحماية من التكرار | **BLOCKED** على Staging. محلياً PASS (A8, B2, B27) |
| 38 — حذف الحساب | **BLOCKED** على Staging. الإنتاج يحتوي الأكشن (S1). محلياً PASS (E1–E4) |
| 39 — الجهاز الحقيقي (كل البنود) | **DEVICE VERIFICATION REQUIRED** |
| 43 — مراجعة الـ Logs | **BLOCKED** |

## AI Tests

AI-based tests remain intentionally disabled through the centralized feature flag. Their source code, APIs, models, routes, historical data, and automated tests remain intact.

**`INTENTIONALLY DISABLED — NOT A PRODUCTION BLOCKER`**

## Security Verification

| المجال | محلياً (HTTP حقيقي) | Staging |
|---|---|---|
| Session coach ownership | PASS | BLOCKED |
| Admin escalation | PASS | BLOCKED |
| Assessment isolation | PASS | BLOCKED |
| Medical data exposure (Raw JSON) | PASS | BLOCKED |
| Club isolation | PASS | BLOCKED |

## FCM

| البند | الحالة |
|---|---|
| وجود الـ Credentials خارج Git | SERVER VERIFICATION REQUIRED (مستثناة من Git عمداً، وهذا صحيح) |
| جدول `device_tokens` | SERVER VERIFICATION REQUIRED |
| تسجيل التوكن | DEVICE VERIFICATION REQUIRED |
| وصول Push فعلي | DEVICE VERIFICATION REQUIRED |
| عدم حذف التوكن عند فشل مؤقت | PASS آلياً (9 حالات تصنيف)، وعلى السيرفر لم يُتحقق |

## Temporary file (البند 24)

`lib/screens/physical_assessment/assessment_result_page.dart.tmp.8856.8cfbb5a3aea1` كان نسخة احتياطية من المحرر (1123 سطراً، لا يستورده أي ملف، وامتداده ليس `.dart`). **حُذف في المرحلة الأولى** ضمن commit `f47047b` بدل commit مستقل. لا يمكن فصله الآن بدون إعادة كتابة التاريخ، ولم أفعل ذلك. الملف غير موجود في الشجرة الحالية.

## Remaining Production Blockers

1. **Staging لم يُنشأ، ولم يُنفَّذ عليه نشر ولا UAT** (لا وصول من هذه البيئة).
2. **نوع وإصدار قاعدة الإنتاج وحالة الـ Migrations غير مُتحقق منها** (`SELECT VERSION()`، `migrations.php status`).
3. **خطأ الـ status codes على الإنتاج** (S2 أُصلح في الكود ولم يُنشر، و S3 يحتاج رفع `auth.php`).
4. **FCM والإشعارات وحذف الحساب لم تُجرَّب على السيرفر ولا على جهاز.**

AI Tests المخفية **ليست** Blocker.

## Production Readiness Score: **85/100** (بدون تغيير)

لم يُرفع الرقم: كل التحقق الإضافي كان محلياً، وكشف فحص الإنتاج خطأً حقيقياً (S2/S3) لم يُنشر إصلاحه بعد. الكود جاهز، والتحقق على السيرفر هو الناقص.

---

## Production Deployment Review Package (للمراجعة فقط — لا يُنفَّذ الآن)

### Exact Release Commit

الـ SHA النهائي هو آخر commit على الفرع بعد commit هذا التقرير. الأمر `git log -1 --format=%H fix/production-readiness-closure` يطبعه. آخر commit كود قبل التقرير: `ec11250cb536b5e811195cdbfc9824b421b86c02`.

### Deployment Manifest — Backend (`merr/api` → `nextkickwebsite/api`، ملفاً ملفاً)

| path | الغرض | commits | Staging؟ | نوع | Migration؟ |
|---|---|---|---|---|---|
| `auth.php` | استبدال النسخة اليدوية على الإنتاج (status codes، S3). يحتوي `delete_account` | main | نعم | backend | لا |
| `players.php` | إزالة المخرجات قبل `<?php` (S2) + حجب الطبي + حفظ الملاحظات | `17b3bd9` `0f36d86` | نعم | backend | لا |
| `assessments.php` | ظهور اللاعب (معتمد فقط)، الملكية، Idempotency | `ec11250` `9eb4c65` `e42a9f6` | نعم | backend | **0021** |
| `player/assessments.php`، `player/my-profile.php`، `player/reports/my-progress.php`، `player/ai-plan/generate.php`، `ai/generate-plan.php` | ظهور اللاعب (معتمد فقط) | `ec11250` `9eb4c65` `e42a9f6` | نعم | backend | **0021** |
| `includes/assessment_visibility.php` | **جديد**: Fallback ظهور التقييمات | `ec11250` | نعم | backend | لا |
| `coach/plans/generate-ai.php`، `club/session_assessments.php` | استعلامات بـ `player_id`/النادي | `e42a9f6` | نعم | backend | لا |
| `sessions.php`، `sessions/exercises.php` | ملكية المدرب للجلسة، `sessions.write`، العزل، `can_manage` | `ad0d48b` | نعم | backend | لا |
| `includes/club_auth.php` | الملكية، الطبي على مستويين، `EXPLICIT_ONLY_ACTIONS` | `f47047b` `8a08553` | نعم | backend | لا |
| `includes/audit_log.php` | `logAuditSafe` | `f47047b` | نعم | backend | لا |
| `club/staff.php` | إنشاء حساب، Reset، Owner-only admin، إلغاء الجلسات | `1be264f` `44b16af` | نعم | backend | لا |
| `club/player.php`، `coach/players.php`، `alerts/coach.php`، `club/physical-coach-dashboard.php` | حجب النص الطبي | `0f36d86` | نعم | backend | لا |
| `includes/notifications.php`، `includes/push.php`، `alerts/send.php` | عزل فشل الإشعار، عدم حذف التوكن | `983de23` | نعم | backend (FCM) | لا (يستخدم `device_tokens` من 0012) |
| `cli/test_push.php` | أداة فحص Push | `983de23` | نعم | tooling | لا |
| `club/injuries.php`، `club/physio_sessions.php`، `club/rehab_phases.php`، `club/tasks.php`، `matches.php`، `player/session/post-feedback.php` | إصلاحات 23 أغسطس غير المنشورة (الإشعار بعد الحفظ) | main | نعم | backend | لا |
| `migrations/p0/0021_assessment_review_status.sql` (+ `.down.sql`) | **جديد** | `ec11250` | نعم | migration | — |

**لا يُرفع:** `api/tests/*` (أدوات اختبار فقط)، و `api/mobile/` (غير مستخدم)، و `db_credentials.php` و `config/fcm-service-account.json` (أسرار موجودة على السيرفر، لا تُستبدل).

### Frontend (App)

كل تغييرات `lib/` (المراحل 1–2) تتطلب Build جديداً للتطبيق. القيم: `AI_TESTS_ENABLED` غير معرّف (القيمة الافتراضية false)، وبدون أسرار في الكود (Sentry عبر `--dart-define`).
- **Staging build:** `flutter build apk --release --dart-define=API_BASE_URL=https://<staging-host>/api` (لم يُنفَّذ: لا يوجد Staging host).
- **Production build:** بدون `API_BASE_URL` (الافتراضي `https://nextkick.me/api`).

### Database Plan (بالترتيب)

1. Backup كامل (dump) لقاعدة الإنتاج قبل أي شيء.
2. `SELECT VERSION();` ثم `php api/cli/migrations.php status` (قراءة فقط) وحفظ الناتج.
3. إن ظهر 0008/0009 PENDING: MariaDB → تُطبّق بالـ runner. MySQL → تُطبّق يدوياً بصيغة `ADD COLUMN` وتُسجّل بالـ checksum نفسه.
4. تطبيق الـ PENDING المطلوبة فقط، **واحدة واحدة**: `php api/cli/migrations.php up <file>`، وأولها المطلوب لهذا الإصدار **0021**. أي pending آخر (مثل 0012 `device_tokens`) يُراجع قبل تطبيقه.
5. **لا** 0005 ولا 0006 في هذا الإصدار (غير مطلوبتين، وتحتاجان موافقة بيانات).
6. `migrations.php status` مرة أخرى.

### Pre-Deploy Checklist

- [ ] Staging UAT مكتمل بنجاح (غير منفّذ حتى الآن)
- [ ] DB backup + backup لمجلد `api/` الحالي على السيرفر
- [ ] `SELECT VERSION()` و `migrations.php status` محفوظان
- [ ] وجود `config/fcm-service-account.json` (أو `FCM_SERVICE_ACCOUNT_PATH`) و `db_credentials.php`
- [ ] الـ Manifest مطابق لـ `git diff main..<release-sha> -- api`

### Deployment Commands (للتنفيذ لاحقاً على السيرفر)

```bash
# قراءة فقط أولاً
mysql -e "SELECT VERSION();"
php api/cli/migrations.php status
# بعد رفع ملفات الـ Manifest
find api -name '*.php' -newer <backup-marker> -exec php -l {} \;
php api/cli/migrations.php up 0021_assessment_review_status.sql
php api/cli/migrations.php status
```

### Post-Deploy Verification

```bash
curl -i https://nextkick.me/api/health.php            # 200 + database ok
curl -i https://nextkick.me/api/players.php           # يجب 401 (كان 200)
curl -i "https://nextkick.me/api/auth.php?action=me"  # يجب 401 (كان 200)
php api/cli/test_push.php <test-account-email>        # Outcome: sent
```

ثم بحسابات اختبار: Login، وإنشاء جلسة وتعديلها ورفض المدرب B، وتقييم يدوي/FMS مع اعتماده ثم ظهوره للاعب، وقيد طبي يظهر للمدرب بدون النص، وحذف حساب اختبار.

### Rollback Plan

- **التطبيق (API):** إعادة رفع نسخة `api/` المحفوظة قبل النشر. كل التغييرات ملفات PHP مستقلة، ولا تغيّر شكل البيانات.
- **قاعدة البيانات:** 0021 **إضافية فقط** (أعمدة جديدة إن غابت). الـ down مقصود أن يكون no-op لحماية سجل الاعتمادات. الكود القديم يعمل مع الأعمدة الموجودة. **لا توجد Migration غير قابلة للعكس في هذا الإصدار**، و 0005/0006 مستبعدتان.
- **Build التطبيق:** إعادة نشر الـ Build السابق من المتجر/Codemagic.

---

## الحالة النهائية

**`NOT READY FOR PRODUCTION — BLOCKERS REMAIN`**

المتبقي: إنشاء Staging والنشر عليه، وتنفيذ UAT، والتحقق من DB/Migrations/FCM على السيرفر، واختبار الجهاز. كل ذلك يحتاج وصولاً للسيرفر وأجهزة غير متاحة في هذه البيئة. الكود وحزمة النشر جاهزان للمراجعة.

---

# Production Deployment Verification — 2026-09-19 (after upload)

النشر نُفّذ على nextkick.me من المجلد `academy/nextkickwebsite/api` (32 ملفاً من commit `3b1fc1c`). التحقق التالي فعلي على الإنتاج، بطلبات GET بدون توكن فقط، وبدون إنشاء أو تعديل أي بيانات.

| الجولة | النتيجة |
|---|---|
| بعد الرفع الأول | 9 ملفات مرفوعة وصلت بـ **UTF-8 BOM** (أُضيف أثناء الرفع، فالملفات المحلية نظيفة)، فرجعت HTTP 200 بدل 401. وثبت أن `jsonDecode` في Dart يرفض رداً يبدأ بـ BOM (`FormatException`)، أي أن التطبيق لم يكن يستطيع قراءة ردود هذه الملفات. **و `auth.php` المرفوع لم يكن النسخة الصحيحة: اختفى `delete_account`** (تراجع) |
| بعد إعادة الرفع | الملفات التسعة سليمة. اكتُشف أن `report_helpers.php` على السيرفر فيه BOM **قديم**، فكل التقارير كانت معطلة. و `delete_account` ما زال مفقوداً |
| بعد رفع `report_helpers.php` و `auth.php` | التقارير وحذف الحساب سليمة. فحص شامل لكل الـ Endpoints كشف **27 ملفاً آخر فيها BOM قديم على الإنتاج** (Hooper/RPE save، today-session، monitoring، teams، profile...)، أي أن هذه الأجزاء كانت معطلة في التطبيق قبل هذا العمل |
| **بعد رفع الـ 27 ملفاً (الحالة الحالية)** | **115/115 Endpoint بدون BOM أو مسافات قبل JSON.** الرموز: 84×401، 21×405، 5×200 (ملفات مساعدة ترجع رداً فارغاً)، 3×400 (Unknown action / معامل ناقص)، 1×403 (`config/` محجوب بـ .htaccess)، 1×500 |
| `auth.php?action=delete_account` | **405 لـ GET، أي أن الأكشن موجود** ✅ |
| `health.php` | 200، قاعدة البيانات ok |
| `ai/generate-plan.php` | 500 (التطبيق لا يستدعيه، ويعمل محلياً، فالمشكلة خاصة ببيئة السيرفر وليست Blocker) |

**درس النشر:** لا تُعدّل ولا تُلصق ملفات PHP عبر محرر cPanel أو Notepad، لأنهما قد يحفظان بـ BOM. الرفع يتم بزر Upload أو FTP binary فقط. بعد كل نشر: فحص الـ 115 Endpoint (يجب أن يرجع 0 BOM).

**ما زال غير مُتحقق (يحتاج حسابات اختبار أو جهازاً أو وصولاً للسيرفر):** حالة الـ Migrations وتشغيل `0021` (`migrations.php status`)، ونوع قاعدة البيانات، و FCM، والسيناريوهات بتسجيل دخول (ملكية الجلسة، ظهور التقييمات، الحجب الطبي، إنشاء حساب موظف و Reset، حذف حساب اختبار)، وكل بنود Device Verification.

**الحالة:** `NOT READY FOR PRODUCTION — BLOCKERS REMAIN`. الكود صار منشوراً وسليماً على مستوى HTTP، والمتبقي هو التحقق بعد تسجيل الدخول، والـ Migration، وFCM، والجهاز.
