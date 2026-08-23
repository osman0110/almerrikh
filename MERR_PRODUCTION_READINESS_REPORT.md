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
