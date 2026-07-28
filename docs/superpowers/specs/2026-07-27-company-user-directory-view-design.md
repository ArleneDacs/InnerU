# Company User Directory View — Design

## Problem

Users belong to a company (`users.company_id`, denormalized copies in `users.company_name`/`users.company_code`), and companies are managed separately (`companies` table — currently includes at least Gencys and Abundance). There is no way to browse the database and see, per company, which users belong to it and their current point standing without hand-writing a join every time. This is purely a backend/database concern — no UI or API changes are in scope.

## Goal

Add a read-only Postgres **view** that joins `users` to `companies` (and each user's latest per-company point total), so any database client (psql, a GUI tool, an Artisan tinker session, etc.) can query it directly, e.g.:

```sql
SELECT * FROM company_user_directory WHERE company_code = 'GENCYS';
SELECT * FROM company_user_directory WHERE company_code = 'ABUNDANCE';
```

## Non-goals

- No Flutter/UI changes.
- No new API endpoint.
- No change to how `users.company_id` / `company_memberships` is populated or resolved — this view only reads existing data.
- No per-company physical tables — a single company-parameterized view covers every company, present and future, without a migration each time a company is added.

## Design

### Object

A single Postgres view: `company_user_directory`.

### Columns

| Column | Source | Notes |
|---|---|---|
| `user_id` | `users.id` | |
| `name` | `users.name` | |
| `email` | `users.email` | |
| `role` | `users.role` | |
| `is_coach` | `users.is_coach` | |
| `is_admin` | `users.is_admin` | |
| `number` | `users.number` | |
| `user_created_at` | `users.created_at` | |
| `company_id` | `companies.id` | NULL if user has no company |
| `company_name` | `companies.name` | canonical name, not the denormalized copy on `users` |
| `company_code` | `companies.code` | canonical code |
| `company_is_active` | `companies.is_active` | |
| `current_points` | latest `user_points.user_total_score` for that user **within that company** | NULL if the user has no `user_points` row for that company |
| `current_points_as_of` | the `date` of that latest `user_points` row | NULL under the same condition |

### Joins

```
users u
  LEFT JOIN companies c ON c.id = u.company_id
  LEFT JOIN LATERAL (
    SELECT up.user_total_score, up.date
    FROM user_points up
    WHERE up.user_id = u.id
      AND up.company_id IS NOT DISTINCT FROM u.company_id
    ORDER BY up.date DESC, up.updated_at DESC
    LIMIT 1
  ) up ON true
```

- `LEFT JOIN companies`: users with `company_id IS NULL` (or pointing at a since-deleted company) still appear, with company columns NULL, instead of being silently dropped. This matches the existing `AdminUserController` behavior of surfacing "no company assigned" users rather than hiding them.
- `LATERAL` join for points: `user_points` is a per-day, per-company log (unique on `user_id, date, company_id`), not a single running total, so the view needs "most recent row for this user in this company" rather than a plain join. `IS NOT DISTINCT FROM` (rather than `=`) correctly matches rows where both `u.company_id` and `up.company_id` are NULL.

### Ordering

`ORDER BY c.name NULLS LAST, u.name` — so a plain `SELECT * FROM company_user_directory` naturally clusters rows by company (alphabetical), with unassigned users trailing at the end.

### Migration

One new migration, e.g. `database/migrations/2026_07_27_000000_create_company_user_directory_view.php`:

- `up()`: `DB::statement('CREATE VIEW company_user_directory AS ...')` with the query above.
- `down()`: `DB::statement('DROP VIEW IF EXISTS company_user_directory')`.

Ships through the existing deploy pipeline (push to `master` → CI → auto-deploy → `migrate --force` on production) — no manual server step required, consistent with how the rest of the Firestore→Postgres migration work landed.

### Testing

A Feature test (e.g. `tests/Feature/CompanyUserDirectoryViewTest.php`) that:

1. Seeds two companies (e.g. codes `GENCYS`, `ABUNDANCE`) and one user in each, plus one user with `company_id = null`.
2. Seeds one `user_points` row per company-assigned user (and none for the unassigned user).
3. Queries the view directly (`DB::table('company_user_directory')->get()` or raw SQL) and asserts:
   - Each company-assigned user's row has the correct `company_name`/`company_code`/`current_points`.
   - The unassigned user's row exists with `company_id`/`company_name`/`company_code`/`current_points` all NULL (not omitted).
   - A user with no `user_points` row at all still appears, with `current_points` NULL.

## Rollout

Standard migration deploy — no data backfill needed (a view has no storage to backfill), no downtime, reversible via the migration's `down()`.
