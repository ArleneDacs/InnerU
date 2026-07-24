# Background Sleep Alarm

**Date:** 2026-07-24

## Problem

When a sleep goal is reached, InnerU is supposed to alert the user like an alarm clock. Today it only actually makes sound if the app happens to be open and mounted on the Sleep Tracker screen: `_playCompletionAlarm()` in `sleep_tracker.dart` plays a looping `AudioPlayer` that's driven entirely by an in-app `Timer` (`_armGoalReachedAlarm`). That timer, and the audio player, are Flutter/Dart-side state — both get suspended the moment the app is backgrounded, and don't exist at all if the app was killed.

There is a separate, already-correct mechanism: `FastingNotificationService.scheduleSleepWakeNotification()` schedules a real OS-level local notification for the wake time, using `AndroidNotificationCategory.alarm`, `fullScreenIntent: true`, `ongoing: true`, and `InterruptionLevel.timeSensitive` on iOS. This notification reliably fires even when the app is backgrounded or killed — that's why the user sees the notification. But it uses `playSound: true` with no custom sound, so it plays the OS's default short chime once, not a loud continuous alarm tone. The notification and the in-app alarm sound are two independent mechanisms that only appear connected when the app happens to already be in the foreground.

## Goal

When the sleep goal is hit, the device should make alarm-like noise even if InnerU is backgrounded or fully closed, continuing until the user responds — approximating a real alarm clock within what each platform's OS actually permits.

## Platform constraint (decided)

True indefinite background audio looping requires different things per platform:
- **iOS**: requires Apple's "critical alerts" entitlement, a special permission granted only to specific app categories (health/safety), applied for directly with Apple, not guaranteed, and not something obtainable from code. Without it, the OS caps any single notification's sound to one playthrough (~30s max).
- **Android**: permits a real continuous alarm without any special entitlement, via a foreground service running a looping `MediaPlayer`, triggered by an exact `AlarmManager` alarm.

**Decision:** Do not pursue the iOS critical-alerts entitlement. Ship the best achievable version per platform now:
- **iOS**: approximate a continuous alarm with a burst of repeated time-sensitive notifications, each carrying a loud alarm-style sound, spaced closely together.
- **Android**: build the real thing — native foreground-service alarm with a continuously looping sound, same as a phone's built-in alarm clock.

## Behavior (decided)

- **Duration**: if the user never responds, the alarm keeps trying for **5 minutes**, then gives up.
  - iOS: repeat notifications roughly every 28 seconds for 5 minutes (~10-11 notifications).
  - Android: the foreground service's looping sound plays continuously for 5 minutes, then stops itself.
  - On timeout (no response), the sleep session is **not** auto-ended — the user must open the app and tap "End Sleep" themselves. We don't want to silently close out a session nobody actually woke up for.
- **Stopping the alarm**: on either platform, there are three ways to stop it, and all three do the same thing — **stop the sound AND end the sleep session immediately** (matches a phone alarm's "stop" button):
  1. Tapping the notification (iOS) or the alarm's full-screen notification (Android).
  2. Tapping "End Sleep" inside the app while the alarm is still ringing.
  3. The 5-minute timeout (sound stops only; session is left running, not auto-ended — see above).
- Whichever of the first two happens first cancels the other: e.g. if the user taps "End Sleep" in-app, any remaining scheduled iOS burst notifications are cancelled / the Android foreground service is stopped.

## Architecture

A new `SleepAlarmService` (singleton, alongside the existing `FastingNotificationService`) is the only thing `sleep_tracker.dart` talks to:

```dart
class SleepAlarmService {
  static final SleepAlarmService instance = SleepAlarmService._();

  /// Arms the platform-appropriate alarm for [wakesAt]. Replaces any
  /// previously armed alarm for this user.
  Future<void> arm({required DateTime wakesAt, required int goalHours});

  /// Cancels the armed alarm (pending iOS burst notifications, or the
  /// Android foreground service if currently running).
  Future<void> disarm();
}
```

Internally, `arm()` branches on `Platform.isIOS` / `Platform.isAndroid` and delegates to iOS-burst-scheduling logic (pure Dart, using `flutter_local_notifications`) or a `MethodChannel` call into new native Android code. `sleep_tracker.dart` calls `SleepAlarmService.instance.arm(...)` wherever it currently calls `_armGoalReachedAlarm()` / `scheduleSleepWakeNotification`, and `disarm()` from `_endSleepSession()`.

The existing foreground-only mechanism (`_playCompletionAlarm`, `_sleepAlarmPlayer`, `_armGoalReachedAlarm`, `_goalReachedTimer`) is removed — `SleepAlarmService` supersedes it on all platforms, including when the app happens to be in the foreground (no need for two parallel systems).

## iOS implementation

- `SleepAlarmService._armIOS()` schedules ~11 individual `zonedSchedule` calls via the existing `FlutterLocalNotificationsPlugin`, IDs `sleepAlarmBurstBaseId + i` for `i in 0..10`, each 28 seconds apart starting at `wakesAt`.
- Each notification: `DarwinNotificationDetails(sound: 'sleep_alarm.caf', interruptionLevel: .timeSensitive, categoryIdentifier: 'SLEEP_ALARM')`.
- A `DarwinNotificationCategory('SLEEP_ALARM', actions: [DarwinNotificationAction.plain('STOP_ALARM', 'Stop')])` is registered at plugin initialization so the notification itself can offer a "Stop" action in addition to a plain tap.
- `disarm()` cancels all 11 notification IDs (safe to call even if some have already fired/expired).

## Android implementation

New native code under `android/app/src/main/kotlin/.../sleepalarm/`:
- `SleepAlarmReceiver` (BroadcastReceiver): started by an exact `AlarmManager` alarm scheduled from `SleepAlarmService._armAndroid()` via `MethodChannel`. On fire, starts `SleepAlarmForegroundService`.
- `SleepAlarmForegroundService` (foreground service, media-playback type): plays `res/raw/sleep_alarm.mp3` on a looping `MediaPlayer`, posts the ongoing full-screen alarm notification (reusing the existing alarm-category/full-screen-intent notification style already used for `scheduleSleepWakeNotification`), and self-stops after 5 minutes via a `Handler.postDelayed`.
- Tapping the notification launches `MainActivity` with an intent extra (`stop_sleep_alarm=true`); `MainActivity` forwards this to Flutter via the same `MethodChannel` on launch/resume, which routes to ending the session (see below).
- New manifest permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (Android 14+ requires this be declared for a media-type foreground service), `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`. `USE_FULL_SCREEN_INTENT` is already present.

## Notification-tap routing (new infrastructure)

No notification tap is currently wired to any in-app action — this doesn't exist yet and is a prerequisite. Add to `FastingNotificationService.initialize()`:
- `onDidReceiveNotificationResponse` / `onDidReceiveBackgroundNotificationResponse` callbacks that inspect `response.payload` and, for `sleep_alarm` / `STOP_ALARM`, expose a `Stream`/callback that `sleep_tracker.dart` listens to and reacts to by calling its existing end-sleep logic.
- Cold-start handling: check `getNotificationAppLaunchDetails()` in `main.dart` at startup; if the launch payload is `sleep_alarm`, route the same way once the app reaches a state where `SleepTracker`'s logic can run (session exists, etc.).
- Android's native tap path (service notification, not a `flutter_local_notifications` payload) reaches Flutter via the separate `MethodChannel` mentioned above, but resolves to calling the *same* Dart-side "end sleep from alarm" entrypoint, so the app has one code path regardless of which platform triggered it.

## Assets

The app's existing audio assets (`Night_Firepit.mp3`, `Ocean_Waves.mp3`, `Rain_Sounds.mp3`, `Forest_Birds.mp3`) are all calm ambient/meditation sounds — none are appropriate for an urgent wake-up alarm, and none should be reused here. This needs a real alarm tone: an urgent, escalating beeping/buzzer pattern, not ambient noise.

Since there's no licensed alarm sound file available to source, the tone will be **procedurally synthesized** rather than reused or downloaded: a script (e.g. Python writing raw PCM samples, or `ffmpeg`'s tone-generation filters if available on the build machine) generates a classic alarm-clock buzzer cadence — a sharp tone (e.g. ~800-1000Hz) in a fast on/off beep pattern, optionally with a second, higher-pitched tone alternating in for urgency — rendered once as a short loopable clip (~2-4 seconds of a *repeating* beep pattern, not 2-4 seconds of a single tone) so that looping it (Android) or bundling it as-is (iOS) sounds like a continuous, deliberate alarm rather than a cut-off ambient track.

- **Source of truth**: one generated file, `assets/audio/sleep_alarm.wav` (uncompressed, so it can be freely re-encoded per platform without quality loss), checked into the repo alongside the other audio assets.
- iOS: re-encoded to `sleep_alarm.caf`, ≤30s (the synthesized clip is a few seconds, well under the limit — no need to loop it *within* the file itself since each burst notification only plays it once), bundled in `ios/Runner/`.
- Android: re-encoded to `android/app/src/main/res/raw/sleep_alarm.mp3` (or `.ogg`), used both as the notification sound and looped (`isLooping = true`) by the foreground service's `MediaPlayer` — this is where the "repeating beep cadence baked into a short loopable clip" choice matters, since Android genuinely loops the file seamlessly.

## Out of scope

- Applying for Apple's critical-alerts entitlement.
- A true continuous (non-bursted) alarm on iOS.
- Snooze functionality.
- Changing the *daily bedtime reminder* or *ongoing sleep* notifications — this only touches the goal-reached wake alarm.

## Testing

- Dart-side burst-scheduling math (11 notifications, 28s apart, correct IDs) and the `SleepAlarmService.arm/disarm` API surface: unit-testable in isolation.
- The end-to-end native behavior (Android foreground service actually looping audio, iOS notifications actually firing while backgrounded/killed, tap routing from a cold start) is **not** verifiable by the Flutter test suite — this class of behavior requires manual device testing (backgrounding/killing the app, waiting for the alarm, tapping it), the same testability boundary already noted for other native-plugin-backed code in this codebase (video/audio players, Firebase). This should be manually verified on a real device before considering the feature done, especially the Android foreground-service and iOS cold-start-tap paths.
