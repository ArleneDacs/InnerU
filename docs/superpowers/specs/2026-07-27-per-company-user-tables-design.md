# Per-Company User Tables — Design

## Problem

The `company_user_directory` view (already shipped, commit `4b0c88f`) lets you see any company's users by filtering `WHERE company_code = '...'`. The user wants something more direct: each company should have its **own** named database table/view — e.g. a `gencys_users` table and an `abundance_users` table — that can be opened directly, without the `users` table itself ever being touched, renamed, or eliminated. This should work automatically for companies that exist today and any created later through the app's "Manage companies" screen.

## Goal

For every company, maintain a dedicated, always-current view named `{sanitized company code}_users` (e.g. `gencys_users`) containing exactly that company's rows from `company_user_directory`. Created automatically when a company is created, dropped automatically when a company is deleted, and backfilled for companies that already exist.

## Non-goals

- No change to the `users` table, its schema, or its data — this is a hard requirement, enforced by a runtime safety guard (below), not just a convention.
- No UI/API changes (same as the original view — this is a database-level convenience).
- No rename handling: `companies.code` is set once at creation and never changes afterward (confirmed by reading `CompanyController::update()` — it can edit `name` and theme/media fields, never `code`), so there is no "company renamed, view needs renaming" case to build.

## Design

### Foundation: reuse, don't duplicate

Each per-company view is a thin wrapper: `SELECT * FROM company_user_directory WHERE company_id = '<uuid>'`. All the join/aggregation logic (users × companies × latest points) stays in the one already-shipped view — these new views just narrow it to one company.

### Naming and sanitization

Table name = `sanitize(company.code) + '_users'`. Sanitization: lowercase, collapse any run of non-`[a-z0-9]` characters to a single `_`, trim leading/trailing `_`, fall back to `'company'` if that leaves nothing, and prefix `c_` if the result starts with a digit (SQL identifiers shouldn't lead with a digit). This makes the exact same code produce the exact same table name every time, and tolerates company codes that don't fit the app's current auto-generated format (3 letters + 4 alphanumerics), in case that ever changes or a row was created some other way.

Because the suffix `_users` is always appended, the generated name can never literally equal `users` — so the real table can never be accidentally targeted by name collision with a *company's own* view. The actual protection needed is against a per-company view colliding with some *other* pre-existing database object (another company's view, or any other real table): before creating a view, the code checks whether an object with that exact name already exists anywhere in the database (via `information_schema.tables` on Postgres, `sqlite_master` on SQLite — the test suite runs SQLite, production runs Postgres, so this check must work on both) and refuses to proceed if so, raising a clear error instead of silently overwriting or corrupting anything.

### Lifecycle

- **Company created** → a Laravel model observer (`CompanyObserver::created()`) calls `CompanyUserTableService::createFor($company)`, which creates the view and records its exact name on `companies.user_table_name` (a new nullable, unique column — unique so the database itself guarantees no two companies can ever claim the same view name).
- **Company deleted** → `CompanyObserver::deleted()` calls `CompanyUserTableService::dropFor($company)`, which reads the recorded `user_table_name` and drops that view.
- **Companies that already exist** (e.g. today's Gencys, Abundance) → the migration that adds the `user_table_name` column also runs a one-time backfill pass (`CompanyUserTableService::backfillAll()`) creating views for every company that doesn't have one yet, so existing companies get their table immediately on deploy — no separate manual step.
- **Company creation failure safety**: `CompanyController::store()` wraps its `Company::create()` call in a database transaction. If the observer's view-creation step throws (e.g. the rare name-collision case), the whole company row is rolled back too — no orphaned company left behind with a half-finished setup.

### Where the observer gets registered

`AppServiceProvider::boot()` currently returns early when running in console (`if ($this->app->runningInConsole()) { return; }`) — that early return exists to skip an unrelated block (an ad hoc `pending_registrations` table auto-creation check). The `Company::observe(...)` registration must be added **before** that early return, otherwise it would silently never activate during `php artisan migrate`, `php artisan test`, or any other console context — which is exactly where this needs to work (tests, and the Artisan-driven deploy pipeline).

## Testing

Two layers, matching the two-task split in the implementation plan:

1. **Service-level** (`CompanyUserTableService` in isolation): sanitization edge cases (messy input, digit-leading, empty-after-sanitizing), `createFor`/`dropFor` against companies inserted via a raw `DB::table('companies')->insert(...)` (bypassing Eloquent events, so the observer doesn't interfere), the collision guard proven against a real pre-existing colliding object, and `backfillAll()` proven against companies that existed before it runs.
2. **Integration** (through the real app surfaces): creating a company via `CompanyController::store()` (or `Company::create()` directly, which is equivalent) results in a working `{code}_users` view; deleting via `CompanyController::destroy()` (or `Company::delete()`) drops it; the `users` table itself is provably untouched throughout (row count and columns unchanged).

## Rollout

One migration (adds the `user_table_name` column, then backfills). No data loss risk — views have no storage, and the migration's `down()` drops every view it's responsible for before removing the column, fully reversible.
