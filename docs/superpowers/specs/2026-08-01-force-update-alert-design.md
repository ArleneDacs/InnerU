# Force-update alert — design spec

Date: 2026-08-01
Status: Revised (automatic store-version sync added) — pending final user review

## Problem

InnerU has no mechanism to tell users their installed app is outdated. When a new
version is published to the App Store / Play Store, users on old builds keep
running them indefinitely with no prompt to update.

## Goal

When the app launches, check whether the installed version is behind the latest
published version. If it is, block the user with a non-dismissible dialog until
they update. The mobile app always asks *our own backend* for the latest version
(never the stores directly) — but the backend keeps itself up to date
automatically by polling Apple and Google on a schedule, so no developer action
is required after a release goes live.

## Decisions made during brainstorming

- **Block behavior: hard block only.** No "Later"/dismiss option, no configurable
  force flag. Any time the backend's recorded latest version is newer than the
  installed version, the dialog blocks the app until the user updates. There is no
  soft-nag mode in v1.
- **The mobile app's version source is our own backend**, not live queries
  against Apple/Google. This keeps the phone-side logic identical regardless of
  how the backend's record gets updated.
- **The backend's record updates itself automatically, on a schedule.** This
  reverses an earlier decision in this same brainstorming session (manual Artisan
  command over SSH) after the user decided the one-time setup cost of automation
  was worth it. A scheduled job checks both stores periodically (proposed:
  hourly) and updates the `app_versions` row without any human involvement:
  - **iOS**: calls Apple's free, public iTunes Lookup API
    (`https://itunes.apple.com/lookup?bundleId=com.valenin.inneru`) — no
    credentials needed. The response includes both the live `version` string and
    a ready-to-use `trackViewUrl` (the exact App Store page URL), so the backend
    never needs to know Apple's numeric app ID by hand.
  - **Android**: calls the Google Play Developer API (Android Publisher API)
    using a service-account credential the user sets up once in Google Play
    Console + Google Cloud Console (see "One-time external setup" below). Unlike
    Apple's API, Google's API does not expose a human-readable version *string*
    for the live production release — it exposes an integer **version code**
    (the same value as Flutter's build number, e.g. `34` from `1.0.4+34`). So the
    Android side of this feature compares build numbers, not `"1.1.0"`-style
    strings. The Play Store listing URL itself is static
    (`https://play.google.com/store/apps/details?id=com.valenin.inneru`) and does
    not need to come from the API — it's seeded once.
  - A manual Artisan override command is still kept (see Architecture) for local
    testing and as an emergency manual fallback, but it is no longer the primary
    mechanism.
- **Fail open on errors.** Network failure, timeout, or a malformed response from
  the backend must never block a user — they proceed into the app as normal. A
  backend outage (or a store-polling failure) must never lock out the whole user
  base.
- **Check runs once, at splash screen launch.** Not on every app resume. This is
  the MVP scope; a resume-time recheck is an easy addition later but out of scope
  now.
- No shared_preferences / "remind me later" persistence is needed, since there is
  no dismiss action to remember.

## One-time external setup required (user-performed, not automatable by us)

Before the Android side of automatic detection can work, the user needs to do
the following once, in their own Google accounts — this cannot be done by
writing code:

1. In Google Cloud Console, create (or reuse) a Cloud project, then create a
   **service account** in it (no special IAM roles needed) and download its
   **JSON key**.
2. In Play Console → **Users and permissions** → **Invite new user**, paste in
   the service account's `client_email` (from the downloaded JSON key) in place
   of a person's email, and grant it access to the InnerU app specifically —
   starting with "View app information," escalating to a release-management
   permission if that turns out to be insufficient for reading the production
   track (see the plan's deploy-verification checklist). Google has retired
   Play Console's old separate "API access" linking page in favor of this
   invite-as-a-user flow.
3. Confirm the **Google Play Android Developer API** is enabled for that Cloud
   project (Cloud Console → APIs & Services → Library).
4. Transfer the downloaded JSON key onto the backend server, outside the git
   repo, and record its path for the `.env` entry the implementation will add.

Separately: the backend already has Laravel's scheduler wired up in production
(`routes/console.php` runs `Schedule::command('meetings:sweep-reminders')`,
driven by a `php artisan schedule:run` cron entry per the comment there), so as
long as that existing cron entry is still active on the deploy server, **no new
cron setup is needed** — the new version-sync command can be registered right
alongside the existing scheduled command.

iOS requires no setup at all — Apple's lookup API is public.

## Architecture

### Backend (Laravel + Postgres, `backend/`)

**Data model:** a single-row `app_versions` table (singleton pattern). Note the
Android field stores an integer **build/version code**, not a semantic version
string — see rationale above:

- `id`
- `ios_latest_version` (string, e.g. `"1.1.0"`)
- `ios_store_url` (string)
- `android_latest_version_code` (integer, e.g. `35`)
- `android_store_url` (string)
- timestamps

A migration creates the table and seeds one default row. Defaults: `ios_latest_version`
set to the current pubspec version (`1.0.4`) and `android_latest_version_code` set to
the current pubspec build number (`34`), so the app is never considered outdated
immediately after this feature ships. `android_store_url` is seeded from the known
package id (`https://play.google.com/store/apps/details?id=com.valenin.inneru`);
`ios_store_url` starts blank and is filled in automatically the first time the
sync job runs (Apple's lookup response supplies it directly).

**Endpoint:** `GET /api/app-version`, public, unauthenticated, registered next to
the existing `/health` route (outside any auth middleware group, since it must be
callable before login). Returns:

```json
{
  "ios": { "latest_version": "1.1.0", "store_url": "https://apps.apple.com/app/id123..." },
  "android": { "latest_version_code": 35, "store_url": "https://play.google.com/store/apps/details?id=com.valenin.inneru" }
}
```

Controller reads the singleton row (creating the default if somehow absent) and
maps it to this shape. Follows the existing `App\Http\Controllers\Api\*`
convention.

**Scheduled sync command (primary mechanism):** a new Artisan command, e.g.
`app:sync-store-versions`, registered in `routes/console.php` via
`Schedule::command('app:sync-store-versions')->hourly()`, alongside the existing
`meetings:sweep-reminders` entry. On each run:
- Calls Apple's iTunes Lookup API via the `Http` facade, extracts `version` and
  `trackViewUrl` from `results[0]`, and updates `ios_latest_version` /
  `ios_store_url`.
- Authenticates to the Google Play Developer API using the service-account JSON
  key (path read from a new `.env` entry, e.g. `PLAY_SERVICE_ACCOUNT_PATH`) via
  the `google/apiclient` composer package, reads the current production track's
  live release for `com.valenin.inneru`, and updates
  `android_latest_version_code`.
- Each platform's call is wrapped independently in its own try/catch: a failure
  fetching one platform's data (network error, malformed response, expired
  credential) is logged and skipped without preventing the other platform's
  update, and without throwing — a failed sync run must never crash the
  scheduler or leave stale-but-not-corrupted data in place.

**Manual override command (fallback, not primary):**
`php artisan app:set-version {platform} {version} {storeUrl?}` remains available
for local testing or emergency manual correction, updating the same row directly.

### Flutter (`lib/`)

- Add `package_info_plus` to `pubspec.yaml` (new dependency). `http` and
  `url_launcher` are already present and sufficient otherwise.
- New `AppUpdateService` (`lib/src/services/app_update_service.dart`):
  - Reads installed version info via `PackageInfo.fromPlatform()` (`.version`
    string and `.buildNumber` string).
  - Calls `GET /api/app-version` via `http` with a 5-second timeout.
  - **iOS**: compares installed `PackageInfo.version` against the response's
    `ios.latest_version` using a small dot-separated integer version comparator
    (handles mismatched segment counts, e.g. `1.0` vs `1.0.4`).
  - **Android**: compares `int.parse(PackageInfo.buildNumber)` against the
    response's `android.latest_version_code` as a plain integer comparison —
    matching what the Google Play Developer API actually exposes (see
    Architecture). This is a different comparison than iOS's, by necessity.
  - Returns a simple result: outdated (with the store URL to open) or not
    outdated. Any exception (network error, timeout, malformed JSON, or a
    non-numeric `buildNumber`) is treated as "not outdated" (fail open) and
    logged to Crashlytics (already wired into `main.dart`).
- New `ForceUpdateDialog` widget, colocated in
  `lib/src/features/authentication/screen/splash_screen/` (matching the existing
  colocation pattern of feature-local dialogs like `edit_group_dialog.dart`).
  Non-dismissible (`barrierDismissible: false`, back navigation disabled via
  `PopScope(canPop: false)`), single "Update Now" button that opens the store URL
  via `url_launcher` (`launchUrl` with `LaunchMode.externalApplication`).
- `splash_screen.dart` changes: `initState` starts the existing 3-second branding
  timer and the version check concurrently, but navigation is gated on **both**
  completing — not on the timer alone. Concretely: `navigateToLogin` is only
  invoked after `Future.wait([timerFuture, checkFuture])` resolves, so a check
  that takes longer than 3 seconds (up to its 5-second timeout) still gets a
  chance to block before any navigation happens. This closes the gap where a
  slow network response could otherwise arrive after a fixed 3s timer already
  navigated an outdated user past the splash screen.
  - If outdated: show `ForceUpdateDialog` instead of navigating to login.
  - If not outdated (including on error/timeout): navigate to login as today —
    the user still sees at least the 3s branding period, plus however much
    longer the check took (capped at 5s).

## Data flow

```
App launch
  → splash screen initState, started concurrently:
      → AppUpdateService.checkForUpdate() [fires immediately, 5s timeout]
      → 3s branding timer [unchanged visual duration]
  → navigateToLogin only runs after BOTH finish (Future.wait):
      outdated  → show ForceUpdateDialog instead (blocking, no back button)
                    → tap "Update Now" → open store_url in App Store / Play Store
      not outdated / error → navigate to login
```

## Testing

- **Backend:**
  - Feature test for `GET /api/app-version` — reachable without auth, returns
    the documented JSON shape, works against the seeded default row.
  - Feature/unit tests for `app:sync-store-versions` with the Apple/Google HTTP
    calls faked (`Http::fake()` for Apple; the Google client mocked/faked for
    Android) covering: successful sync updates both fields; an Apple failure
    doesn't block the Android update and vice versa; a malformed response from
    either is logged and skipped without throwing.
  - Run via `vendor/bin/phpunit --configuration=phpunit.pgsql.xml` (per existing
    Postgres CI setup; `php artisan test --configuration=X` is known broken).
- **Flutter:**
  - Unit tests for the iOS version-string comparator: equal versions, older by
    major/minor/patch, mismatched segment counts (`1.0` vs `1.0.1`).
  - Unit tests for the Android build-number integer comparison, including a
    non-numeric `buildNumber` falling back to "not outdated."
  - Widget test on the splash screen: dialog appears when the service reports
    outdated; dialog does not appear when up to date; dialog does not appear
    when the service call errors/times out (fail-open path).

## Out of scope (explicitly deferred, not part of this build)

- Soft-nag / dismissible mode, or a per-release configurable force flag.
- An admin webpage/UI for editing the version record — the automatic sync is
  the primary path; the manual Artisan command is a fallback, not a UI.
- Rechecking on app resume (only checked once, at cold-start splash screen).
- Any recovery/alerting if the Google service-account credential expires or is
  revoked (the sync simply logs and skips Android updates until it's fixed
  manually — no paging/alerting is built for this in v1).
