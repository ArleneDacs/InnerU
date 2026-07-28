# Firestore → PostgreSQL Data Migration Design

## Context

InnerU's Flutter app currently talks directly to Firestore (30 files reference
`cloud_firestore`) across these collections: `coach_groups`, `coach_requests`,
`coaches`, `comments`, `goals`, `history`, `merits`, `notes`, `tasks`,
`updates`, `userpoints`, `users`, `wellness`.

A new version of the app is being built against a Laravel API backend
(`backend/`) backed by PostgreSQL. The Laravel side already has a largely
complete schema mirroring the Firestore data model (users, goals + child
tables, coach_groups, coach_requests, user_points, daily_trackers,
fasting_history, exercise_logs, calorie_days/entries, chat, walks, etc.) and
its own independent auth system (`AuthController`: email/password register +
login via Sanctum, Google sign-in via live token verification, Apple sign-in
matched by a stored `apple_user_id`). It is not currently wired to Firebase
Auth in any way — there is no `firebase_uid` column anywhere.

**Goal:** migrate existing users and their data out of Firestore/Firebase
Auth into the Laravel/Postgres backend as a one-time cutover, so existing
users can keep using their account (same email + password) and see their
existing profile/app data (goals, points, history, etc.) in the new app —
without needing to sign up again.

## Decisions made

- **Postgres becomes the primary database** going forward; this is a full
  replacement, not an analytics mirror.
- **Both login credentials and profile/app data** must carry over for
  existing users.
- **Firebase password hashes are migrated directly** (not a forced
  password-reset flow) — users should be able to log in with their existing
  password on the new app.
- **Hard cutover, not coexistence.** This is a one-time transfer. There is no
  requirement to keep Firestore and Postgres in sync over time or to support
  old and new app versions writing to two different backends concurrently.
- **Pipeline shape: Node extract → Laravel load**, chosen over an all-PHP
  Artisan importer or a managed ETL tool (see rejected alternatives below).

## Architecture: two-phase, one-time pipeline

### Phase 1 — Extract (Node.js)

A one-off script, using the `firebase-admin` SDK plus the Firebase CLI, run
against production Firebase:

- Dumps every Firestore collection listed above to local JSON files
  (`snapshot/<collection>.json`), preserving each document's Firestore
  document ID.
- Runs `firebase auth:export snapshot/auth-users.json --format=JSON` to pull
  every Firebase Auth user: uid, email, password hash, salt, provider data
  (`password` / `google.com` / `apple.com`), email-verified status.
- Captures the project's password hash config (the scrypt parameters:
  signer key, salt separator, rounds, memory cost) needed later to verify
  those hashes, saved to `snapshot/hash-config.json`.

The snapshot directory is git-ignored — it contains password hashes and must
never be committed. It is a frozen point-in-time copy, which makes the load
phase safely re-runnable without hitting live Firestore again or worrying
about data changing mid-migration.

### Phase 2 — Load (Laravel Artisan command: `firestore:import`)

Reads the snapshot and upserts into Postgres, respecting FK dependency
order:

1. `users` (merged from the Firestore `users` doc + the matching Auth export
   record, joined by uid)
2. `coach_groups`, `coach_requests`
3. `goals` and its child tables (`goal_tasks`, `goal_updates`,
   `goal_comments`, `goal_merits`)
4. `user_points`
5. `wellness`/`history`/`notes`/etc. → their corresponding existing tables
   (`daily_trackers`, `fasting_history`, `exercise_logs`, `calorie_days`,
   `calorie_entries`, `note_comments`, `todo_tasks`, as applicable)

Every migrated table gets a nullable, unique `firebase_uid` (users) or
`firestore_id` (everything else) column. This is both the join key across
collections and what makes the importer idempotent — re-running after fixing
a mapping bug upserts by that key instead of creating duplicate rows.

The exact field-by-field mapping from each Firestore collection's document
shape to its target Postgres columns is not enumerated in this design — it's
mechanical but sizable work (checking the relevant Flutter model classes
against each Laravel migration for all ~14 collections) and is deferred to
the implementation-plan step.

## Password / identity continuity

### Password-based accounts

- The Firebase password hash + salt for each user land in temporary holding
  columns (`legacy_password_hash`, `legacy_password_salt`) on `users` —
  *not* the live `password` column.
- A new custom Laravel hash driver, `firebase_scrypt` (implementing
  `Illuminate\Contracts\Hashing\Hasher`), verifies a plaintext password
  against Firebase's modified-scrypt algorithm using those two columns plus
  the exported `hash-config.json` parameters.
- `AuthController::login()` gains one added branch: if `password` is empty
  but `legacy_password_hash` is set, verify via the `firebase_scrypt` driver
  instead of the default bcrypt check. On success, the plaintext password is
  rehashed with bcrypt into `password`, and the legacy columns are cleared —
  a "lazy migration" where each user converts to native Laravel hashing
  transparently on their first successful login after cutover.
- On verification failure, behavior is unchanged from today: "The provided
  credentials are incorrect." No new lockout behavior is introduced.
- Every imported user must have `email_verified_at` set (from the Auth
  export's verified status), since `login()` currently blocks unverified
  users regardless of password correctness.
- **This is the highest-risk piece of the whole migration.** A subtly wrong
  scrypt reimplementation could silently fail to verify correct passwords
  (or, worse, misbehave in an unsafe way). Before trusting it broadly, it
  must be validated against a handful of real accounts with known passwords
  and confirmed to verify correctly — not approved by code review alone.

### Google sign-in accounts

No password involved. `AuthController::google()` verifies the Google ID
token live and matches the user by email on every login — so as long as
`email` is imported correctly, existing Google-sign-in users work
immediately post-migration with no additional migration step.

### Apple sign-in accounts

`AuthController::apple()` matches by a stored `apple_user_id` column, which
already exists on `users`. Copying `apple_user_id` from the Auth export's
provider data during import means existing Apple-sign-in users match
correctly post-migration.

## Media / Storage

Firebase Storage stays live and continues serving existing files (profile
pictures, etc.) unchanged. Only structured data (Firestore) and credentials
(Firebase Auth) move to Postgres/Laravel; fields like `profile_pic` keep
their existing Firebase Storage URLs. Moving off Firebase Storage entirely
is out of scope for this migration.

## Safety net

- `firestore:import` supports a `--dry-run` flag that reports planned
  inserts/updates without committing anything.
- A summary report at the end of each run: counts per collection
  (imported / skipped / already-existing), and any records that failed
  mapping — logged with their Firestore document ID for manual follow-up —
  rather than aborting the entire run on a single bad record.
- Re-running the command after fixing a mapping or transform bug is safe and
  won't duplicate rows, due to upserting by `firebase_uid`/`firestore_id`.

## Rollout sequence

1. Build and test the pipeline against a Firestore snapshot (ideally a
   staging/dev Firebase project, not production) first.
2. Dry-run the load phase against a real production Firestore export;
   review the summary report.
3. Real load into production Postgres — before the new app version ships,
   so there is time to verify without user-facing impact.
4. Manually verify a sample of migrated accounts: confirm login works
   (including at least one real password-based account, to validate the
   `firebase_scrypt` driver against a known-correct password), and spot-check
   a few users' goals/points/history data against the original Firestore
   records.
5. Release the new Laravel-backed app version. Firestore is retired
   (read-only or fully decommissioned) once the old app version is no
   longer in use.

## Rejected alternatives

- **All-in-PHP Artisan importer** reading Firestore live via a PHP Firestore
  client: rejected because Firebase Auth's password-hash export is only
  available through Firebase's Node-based CLI tooling regardless, so a
  Node step is unavoidable anyway. Reading live Firestore repeatedly during
  development also risks inconsistent data between debug runs, vs. a frozen
  snapshot.
- **Managed ETL tool** (e.g. Airbyte/Fivetran Firestore→Postgres connector):
  rejected as overkill for a one-time cutover — adds infrastructure and
  cost for what is not an ongoing sync need, and still would not solve the
  Firebase Auth password-hash export problem.
- **Keep Firebase Auth as the identity provider** (Laravel verifies Firebase
  ID tokens instead of owning passwords): rejected because the Laravel
  `AuthController` already independently owns registration/login/password
  hashing/Google/Apple sign-in — reverting to Firebase-token verification
  would mean re-architecting already-built auth code, and the user
  explicitly wants existing passwords to work natively against the new
  backend.
- **Forced password-reset on first login** instead of hash migration:
  considered as the lower-risk option, but explicitly declined by the user
  in favor of migrating real password hashes for a frictionless login
  experience.
