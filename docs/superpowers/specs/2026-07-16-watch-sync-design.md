# InnerU Phone → Watch Sync — Design

**Date:** 2026-07-16
**Status:** Approved by user (app screen + watch-face widget)

## Problem

The watchOS companion app (`ios/InnerUWatch`) is a static mockup. Its four cards
(Steps, Fasting, Meditate, Mood) show hardcoded text. Nothing done in the phone
app (e.g. completing a meditation) reflects on the watch, because no
communication channel exists: no WatchConnectivity code on either side, no watch
package in `pubspec.yaml`.

## Goal

What the user does in the InnerU phone app reflects on the watch, in two places:

1. **Watch app screen** — the four cards show live data.
2. **Watch face** — a Smart Stack (rectangular) widget shows steps, meditation
   streak, and fasting status without opening the app.

## Approach (chosen)

**WatchConnectivity via the `watch_connectivity` Flutter package.** The phone
pushes a small state snapshot with `updateApplicationContext` whenever a tracked
value changes. iOS stores the newest snapshot and delivers it to the watch even
if the watch app is closed. No servers, works offline, no login on the watch.

Rejected alternatives:
- *Watch reads Firebase directly* — Firebase on watchOS is poorly supported and
  requires solving auth on the watch. Too heavy.
- *Hand-rolled WCSession bridge* — same result as the package with more native
  code to maintain.

## Data snapshot (application context payload)

```json
{
  "steps": 4231,
  "stepGoal": 8000,
  "fastingActive": true,
  "fastingStartMs": 1752641400000,
  "fastingGoalHours": 16,
  "meditatedToday": true,
  "meditationStreak": 5,
  "mood": "Happy",
  "moodAtMs": 1752652200000,
  "updatedAtMs": 1752655800000
}
```

All keys optional; the watch renders placeholders ("—", "No active fast",
"Not yet today", "No check-in yet") for missing values.

## Components

### 1. Flutter: `WatchSyncService` (`lib/src/services/watch_sync_service.dart`)

Singleton holding the current snapshot. Feature code calls typed setters:

- `syncSteps(int steps, {int? goal})`
- `syncFasting({required bool active, DateTime? start, int? goalHours})`
- `syncMeditation({required bool doneToday, required int streak})`
- `syncMood(String mood, DateTime at)`

Each setter merges into the snapshot and pushes via
`WatchConnectivity.updateApplicationContext`. Guards: iOS only
(`Platform.isIOS`), no-op when unsupported/unpaired, errors swallowed with
`debugPrint` (sync must never break a feature flow).

Snapshot merge logic lives in a plain `WatchSnapshot` class with **no Firebase
or plugin imports** so it is unit-testable (Firebase singletons block mocking;
see test suite constraints).

### 2. Hook points (one call each, where data is already saved)

| Feature | File | Where |
|---|---|---|
| Meditation | `lib/src/features/authentication/screen/meditation/meditation_screen.dart` | after the streak/dailytracker update |
| Fasting | `lib/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart` | in `_startFast` and `_endFast` |
| Steps | `lib/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart` | pedometer listener, throttled (sync on ≥100-step delta or ≥5 min) |
| Mood | `lib/src/services/emotion_service.dart` | after the `emotions` Firestore write |

### 3. Watch app: `PhoneConnector` (Swift, `ios/InnerUWatch/PhoneConnector.swift`)

`NSObject, WCSessionDelegate, ObservableObject`. Activates `WCSession`, applies
`receivedApplicationContext` on launch and updates on
`didReceiveApplicationContext`. Publishes a `WatchState` struct. Also writes the
snapshot to the App Group `UserDefaults` and calls
`WidgetCenter.shared.reloadAllTimelines()`.

`ContentView` reads `PhoneConnector` via `@StateObject`; the four cards render
live values. Fasting elapsed time ticks locally (computed from `fastingStartMs`
via `TimelineView`), so it needs no continuous updates from the phone.

### 4. Watch-face widget: `InnerUWatchWidget` (new WidgetKit extension target)

- Rectangular Smart Stack family (`accessoryRectangular`): steps today,
  meditation streak, fasting status/elapsed.
- Reads the snapshot from App Group `UserDefaults`
  (group id: `group.com.valenin.inneru.watch`; watch app bundle id is
  `com.valenin.inneru.watchkitapp`, widget will be
  `com.valenin.inneru.watchkitapp.widget`).
- Fasting elapsed ticks via timeline entries computed from the start timestamp.
- Refresh: whenever the watch app receives data; background delivery is rationed
  by watchOS, so the widget may lag the phone by a few minutes. Accepted for v1.

### 5. Xcode project changes

- Add `InnerUWatchWidget` extension target embedded in the watch app.
- App Groups capability on the watch app + widget extension (may require a
  provisioning profile refresh on the user's Apple account).
- `watch_connectivity` package added to `pubspec.yaml`.

## Error handling

- Phone side: all sync calls are fire-and-forget; failures logged, never thrown.
- Watch side: missing/partial snapshots render placeholders; malformed values
  ignored key-by-key.
- Android: `WatchSyncService` setters return immediately.

## Testing

- Unit tests (`test/unit`) for `WatchSnapshot` merge/serialization and the
  steps-throttle rule — pure Dart, no Firebase.
- Manual end-to-end: iPhone simulator + paired watch simulator; do a meditation
  / start a fast on the phone, confirm the watch app cards and widget update.
