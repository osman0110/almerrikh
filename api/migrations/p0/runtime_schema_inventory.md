# Runtime schema inventory

`api/db.php::ensureSchema()` historically performs DDL and backfills during API
requests. P0 adds no new DDL to that function and disables invocation during
normal requests.

## Existing runtime mutation groups

| Area | Runtime operations found | P0 disposition |
|---|---|---|
| Authentication | Creates `users`, `user_tokens`, lifecycle and linkage columns | Existing schema retained; not duplicated in P0 |
| FMS and assessments | Creates assessment/FMS tables, scores and indexes | Out of P0 scope |
| Player monitoring | Creates legacy body metrics, Hooper and RPE tables; later alters their types and linkage columns | RPE P0 additions are in migrations 0004–0005; legacy DDL remains transitional |
| Body composition | Creates assessments, goals, formulas and indexes | P0 additions are in migration 0002 |
| Club roster/sessions | Creates players, sessions and attendance; adds club/team/source fields | Team staff scope is in migration 0001 |
| Club entity/staff | Calls `_schema.php` and `_staff_schema.php`, both of which create/backfill at runtime | Normal runtime calls are disabled; full extraction remains a separate deployment project |
| Audit | Creates basic `audit_logs` | P0 enrichment is in migration 0003 |
| Medical/rehab/tasks | Creates injury, rehab, physiotherapy, nutrition and task tables | Out of P0 scope |
| Reports/settings | Creates settings and several supporting/report tables | Out of P0 scope |
| Backfills | Updates roles, `club_id`, source fields and owner/staff mappings | No P0 automatic replay; inspect on a database copy |
| Database creation | Previously ran `CREATE DATABASE IF NOT EXISTS` per request | Runs only with explicit `ALLOW_RUNTIME_SCHEMA_BOOTSTRAP=1` |

## Risk and transition

- Fresh databases still require the reviewed legacy installation path until
  the remaining groups are extracted into versioned migrations.
- Existing databases must run `php api/cli/migrations.php status` and the
  read-only preflight before disabling the compatibility bootstrap.
- Do not remove `ensureSchema()` yet: it remains an explicit legacy escape
  hatch, not a normal request path.
- No P0 migration drops a legacy table or deletes a historical row.
