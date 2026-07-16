# InnerU Phone → Watch Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phone-app activity (steps, fasting, meditation, mood) shows live in the watch app's four cards and in a watch-face Smart Stack widget.

**Architecture:** The phone pushes a flat key/value snapshot via WatchConnectivity `updateApplicationContext` whenever a tracked value changes. The watch app receives it (`PhoneConnector`), renders it in `ContentView`, saves it to App Group `UserDefaults`, and reloads the WidgetKit timeline. The widget reads the same snapshot from the App Group.

**Tech Stack:** Flutter + `watch_connectivity` package (phone side); Swift/SwiftUI + WatchConnectivity + WidgetKit (watch side); `xcodeproj` Ruby gem for project surgery.

**Spec:** `docs/superpowers/specs/2026-07-16-watch-sync-design.md`

## Global Constraints

- Phone-side sync is iOS-only: every public `WatchSyncService` method no-ops unless `!kIsWeb && Platform.isIOS`.
- Sync must never break a feature flow: all failures are caught and `debugPrint`-ed, never rethrown.
- App Group id: `group.com.valenin.inneru.watch` (exact).
- Bundle ids: watch app `com.valenin.inneru.watchkitapp` (existing), widget `com.valenin.inneru.watchkitapp.widget`.
- Watch targets: `WATCHOS_DEPLOYMENT_TARGET = 10.0`, `SWIFT_VERSION = 5.0`, `DEVELOPMENT_TEAM = 965T647JG7`, `TARGETED_DEVICE_FAMILY = 4`.
- Snapshot keys (exact): `steps`, `stepGoal`, `stepsDate`, `fastingActive`, `fastingStartMs`, `fastingGoalHours`, `meditatedOn`, `meditationStreak`, `mood`, `moodAtMs`, `updatedAtMs`. Dates are `yyyy-MM-dd` strings in local time; `*Ms` are epoch milliseconds.
- Run `pod install` with `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` (CocoaPods crashes on this machine otherwise).
- Ruby scripts run with `/opt/homebrew/opt/ruby/bin/ruby`; they bootstrap the `xcodeproj` gem from CocoaPods' bundled gems (see script header in Task 3).
- Disk is tight on this Mac — do not create extra simulators or DerivedData copies beyond what the verification steps require.

---

### Task 1: Pure Dart snapshot model + step throttle gate (TDD)

**Files:**
- Create: `lib/src/services/watch_snapshot.dart`
- Create: `lib/src/services/watch_sync_service.dart`
- Test: `test/unit/watch_snapshot_test.dart`
- Modify: `pubspec.yaml` (via `flutter pub add`)

**Interfaces:**
- Produces: `WatchSnapshot` with `void merge(Map<String, Object?> updates)` (drops null values) and `Map<String, Object> get data` (unmodifiable copy); `String dayKey(DateTime date)` returning `yyyy-MM-dd`; `StepSyncGate` with `bool shouldSync(int steps, DateTime now)`; singleton `WatchSyncService.instance` with `void syncSteps(int steps, {int? goal})`, `void syncFasting({required bool active, DateTime? start, int? goalHours})`, `void syncMeditation({required int streak, DateTime? completedAt})`, `void syncMood(String mood, DateTime at)`.
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

Create `test/unit/watch_snapshot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/watch_snapshot.dart';

void main() {
  group('WatchSnapshot', () {
    test('merge stores values and data returns them', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 100, 'mood': 'happy'});
      expect(snapshot.data['steps'], 100);
      expect(snapshot.data['mood'], 'happy');
    });

    test('merge drops null values but keeps existing keys', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 100});
      snapshot.merge({'steps': null, 'stepGoal': 5000});
      expect(snapshot.data['steps'], 100);
      expect(snapshot.data['stepGoal'], 5000);
    });

    test('merge overwrites existing values', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 100});
      snapshot.merge({'steps': 250});
      expect(snapshot.data['steps'], 250);
    });

    test('data is unmodifiable', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 1});
      expect(() => snapshot.data['steps'] = 2, throwsUnsupportedError);
    });
  });

  group('dayKey', () {
    test('formats with zero padding', () {
      expect(dayKey(DateTime(2026, 7, 6)), '2026-07-06');
      expect(dayKey(DateTime(2026, 11, 23)), '2026-11-23');
    });
  });

  group('StepSyncGate', () {
    final t0 = DateTime(2026, 7, 16, 12, 0, 0);

    test('first call always syncs', () {
      final gate = StepSyncGate();
      expect(gate.shouldSync(10, t0), isTrue);
    });

    test('small delta within interval does not sync', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      expect(gate.shouldSync(50, t0.add(const Duration(minutes: 1))), isFalse);
    });

    test('delta of 100 or more syncs', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      expect(gate.shouldSync(110, t0.add(const Duration(seconds: 5))), isTrue);
    });

    test('small delta after 5 minutes syncs', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      expect(gate.shouldSync(11, t0.add(const Duration(minutes: 5))), isTrue);
    });

    test('gate rebases after a granted sync', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      gate.shouldSync(110, t0.add(const Duration(minutes: 1)));
      expect(
        gate.shouldSync(150, t0.add(const Duration(minutes: 2))),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/InnerU && flutter test test/unit/watch_snapshot_test.dart`
Expected: FAIL — cannot resolve `package:selfcare_projects/src/services/watch_snapshot.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/services/watch_snapshot.dart`:

```dart
/// Pure model for the phone→watch state snapshot.
/// Keep this file free of Firebase and plugin imports so it stays
/// unit-testable (Firebase singletons block mocking in this repo).
class WatchSnapshot {
  final Map<String, Object> _data = {};

  Map<String, Object> get data => Map.unmodifiable(_data);

  void merge(Map<String, Object?> updates) {
    updates.forEach((key, value) {
      if (value != null) {
        _data[key] = value;
      }
    });
  }
}

String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// Throttles step syncs so the watch is not spammed on every step.
class StepSyncGate {
  StepSyncGate({
    this.minStepDelta = 100,
    this.minInterval = const Duration(minutes: 5),
  });

  final int minStepDelta;
  final Duration minInterval;

  int? _lastSteps;
  DateTime? _lastAt;

  bool shouldSync(int steps, DateTime now) {
    final lastSteps = _lastSteps;
    final lastAt = _lastAt;
    final due = lastSteps == null ||
        lastAt == null ||
        (steps - lastSteps).abs() >= minStepDelta ||
        now.difference(lastAt) >= minInterval;
    if (due) {
      _lastSteps = steps;
      _lastAt = now;
    }
    return due;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/InnerU && flutter test test/unit/watch_snapshot_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Add the watch_connectivity dependency**

Run: `cd ~/InnerU && flutter pub add watch_connectivity`
Expected: `+ watch_connectivity 2.x.x` and "Got dependencies".
Then: `cd ~/InnerU/ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install`
Expected: ends with "Pod installation complete!" and mentions `watch_connectivity`.

- [ ] **Step 6: Write the service (plugin wiring — no unit test, verified by analyzer)**

Create `lib/src/services/watch_sync_service.dart`:

```dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'package:selfcare_projects/src/services/watch_snapshot.dart';

/// Pushes activity state to the Apple Watch companion app.
/// Fire-and-forget: failures are logged and never thrown.
class WatchSyncService {
  WatchSyncService._();

  static final WatchSyncService instance = WatchSyncService._();

  final WatchConnectivity _watch = WatchConnectivity();
  final WatchSnapshot _snapshot = WatchSnapshot();
  final StepSyncGate _stepGate = StepSyncGate();

  bool get _enabled => !kIsWeb && Platform.isIOS;

  void syncSteps(int steps, {int? goal}) {
    if (!_enabled) return;
    final now = DateTime.now();
    if (!_stepGate.shouldSync(steps, now)) return;
    _push({
      'steps': steps,
      if (goal != null) 'stepGoal': goal,
      'stepsDate': dayKey(now),
    });
  }

  void syncFasting({required bool active, DateTime? start, int? goalHours}) {
    if (!_enabled) return;
    _push({
      'fastingActive': active,
      if (active && start != null)
        'fastingStartMs': start.millisecondsSinceEpoch,
      if (active && goalHours != null) 'fastingGoalHours': goalHours,
    });
  }

  void syncMeditation({required int streak, DateTime? completedAt}) {
    if (!_enabled) return;
    _push({
      'meditatedOn': dayKey(completedAt ?? DateTime.now()),
      'meditationStreak': streak,
    });
  }

  void syncMood(String mood, DateTime at) {
    if (!_enabled) return;
    _push({'mood': mood, 'moodAtMs': at.millisecondsSinceEpoch});
  }

  void _push(Map<String, Object?> updates) {
    _snapshot.merge(updates);
    _snapshot.merge({'updatedAtMs': DateTime.now().millisecondsSinceEpoch});
    unawaited(_send());
  }

  Future<void> _send() async {
    try {
      if (!await _watch.isSupported) return;
      if (!await _watch.isPaired) return;
      await _watch.updateApplicationContext(
        Map<String, dynamic>.from(_snapshot.data),
      );
    } catch (error) {
      debugPrint('Watch sync failed: $error');
    }
  }
}
```

- [ ] **Step 7: Analyze**

Run: `cd ~/InnerU && flutter analyze lib/src/services/watch_snapshot.dart lib/src/services/watch_sync_service.dart`
Expected: "No issues found!"

- [ ] **Step 8: Commit**

```bash
cd ~/InnerU
git add lib/src/services/watch_snapshot.dart lib/src/services/watch_sync_service.dart test/unit/watch_snapshot_test.dart pubspec.yaml pubspec.lock ios/Podfile.lock
git commit -m "feat: add WatchSyncService for phone-to-watch state sync

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Hook the four features into WatchSyncService

**Files:**
- Modify: `lib/src/features/authentication/screen/meditation/meditation_screen.dart` (`_onMeditationComplete`, ~line 141)
- Modify: `lib/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart` (`_loadFastingState` ~line 51, `_startFast` ~line 81, `_endFast` ~line 110)
- Modify: `lib/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart` (`_updateStepCount`, ~line 401)
- Modify: `lib/src/services/emotion_service.dart` (`saveTodayEmotion`, both branches)

**Interfaces:**
- Consumes: `WatchSyncService.instance` methods from Task 1 (exact signatures listed there).
- Produces: nothing new — one-line calls at existing save points.

- [ ] **Step 1: Confirm the streak enum value name**

Run: `grep -n "ActivityStreakType.meditation" ~/InnerU/lib/src/services/meditation_streak_service.dart`
Expected: at least one hit (used by `MeditationStreakService`). If the enum value differs, use the name found here in Step 2.

- [ ] **Step 2: Meditation hook**

In `meditation_screen.dart`, add imports (keep existing ones; `meditation_streak_service.dart` is already imported at line 20):

```dart
import 'dart:async';

import 'package:selfcare_projects/src/services/watch_sync_service.dart';
```

(Skip `dart:async` if already imported.) In `_onMeditationComplete`, change the try block:

```dart
    try {
      final milestones = await _meditationStreakService.recordCompletedSession(
        userId: userId,
      );
      unawaited(_syncMeditationToWatch(userId));
      return milestones;
    } catch (error) {
      debugPrint('Meditation streak update failed: $error');
      return <MeditationStreakMilestone>[];
    }
```

Add this private method to the same State class:

```dart
  Future<void> _syncMeditationToWatch(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = snapshot.data() ?? <String, dynamic>{};
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: data[ActivityStreakService.lastDateFieldFor(
          ActivityStreakType.meditation,
        )],
        currentStreak: ActivityStreakService.readInt(
          data[ActivityStreakService.currentFieldFor(
            ActivityStreakType.meditation,
          )],
        ),
      );
      WatchSyncService.instance.syncMeditation(streak: streak);
    } catch (error) {
      debugPrint('Watch meditation sync failed: $error');
    }
  }
```

- [ ] **Step 3: Fasting hooks**

In `fasting_timer_screen.dart`, add import:

```dart
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
```

In `_startFast`, directly after `_startTicker();` (~line 97):

```dart
      WatchSyncService.instance
          .syncFasting(active: true, start: now, goalHours: _selectedHours);
```

In `_endFast`, inside the `try` block, after the history/state handling completes (immediately before the method's success snackbar / end of try):

```dart
      WatchSyncService.instance.syncFasting(active: false);
```

In `_loadFastingState`, inside `if (_startTime != null && _endTime != null) {` after `_startTicker();`:

```dart
          WatchSyncService.instance.syncFasting(
            active: true,
            start: _startTime,
            goalHours: _selectedHours,
          );
```

and in the `else` branch after `await _clearFastingNotifications();`:

```dart
          WatchSyncService.instance.syncFasting(active: false);
```

- [ ] **Step 4: Steps hook**

In `steptracker_screen.dart`, add import:

```dart
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
```

In `_updateStepCount`, directly after the `_stepStreamController.add(_steps);` block (~line 403):

```dart
    WatchSyncService.instance.syncSteps(_steps, goal: _dailyGoal);
```

(The `StepSyncGate` inside the service handles throttling — no throttle code here.)

- [ ] **Step 5: Mood hook**

In `emotion_service.dart`, add import:

```dart
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
```

In `saveTodayEmotion`, add the same line in BOTH branches, immediately before each `return EmotionSaveResult(...)`:

```dart
    WatchSyncService.instance.syncMood(normalizedEmotion, savedAt);
```

- [ ] **Step 6: Analyze and run the unit suite**

Run: `cd ~/InnerU && flutter analyze lib/src/features/authentication/screen/meditation/meditation_screen.dart lib/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart "lib/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart" lib/src/services/emotion_service.dart`
Expected: "No issues found!"
Run: `cd ~/InnerU && flutter test test/unit`
Expected: all tests pass (WatchSyncService no-ops on the host because `Platform.isIOS` is false).

- [ ] **Step 7: Commit**

```bash
cd ~/InnerU
git add lib/src/features/authentication/screen/meditation/meditation_screen.dart lib/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart "lib/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart" lib/src/services/emotion_service.dart
git commit -m "feat: sync meditation, fasting, steps, and mood to watch

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Watch app receives and displays live data

**Files:**
- Create: `ios/InnerUWatch/WatchState.swift` (shared with widget in Task 4)
- Create: `ios/InnerUWatch/PhoneConnector.swift`
- Create: `ios/InnerUWatch/InnerUWatch.entitlements`
- Rewrite: `ios/InnerUWatch/ContentView.swift`
- Create: `ios/scripts/add_watch_files.rb`
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (via the script only)

**Interfaces:**
- Consumes: snapshot keys from Global Constraints.
- Produces: `WatchState` struct (`steps: Int?`, `stepGoal: Int?`, `stepsToday: Int?`, `fastingActive: Bool`, `fastingStart: Date?`, `fastingGoalHours: Int?`, `meditatedToday: Bool`, `meditationStreak: Int`, `mood: String?`, `moodAt: Date?`, `init(dict: [String: Any])`); `enum SharedStore { appGroupId, snapshotKey }` — Task 4's widget uses both.

- [ ] **Step 1: Create WatchState.swift**

```swift
import Foundation

enum SharedStore {
    static let appGroupId = "group.com.valenin.inneru.watch"
    static let snapshotKey = "watchSnapshot"
}

/// Parsed snapshot received from the iPhone. All fields optional —
/// the UI shows placeholders for anything missing.
struct WatchState {
    var steps: Int?
    var stepGoal: Int?
    var stepsDate: String?
    var fastingActive: Bool = false
    var fastingStart: Date?
    var fastingGoalHours: Int?
    var meditatedOn: String?
    var meditationStreak: Int = 0
    var mood: String?
    var moodAt: Date?

    init() {}

    init(dict: [String: Any]) {
        steps = dict["steps"] as? Int
        stepGoal = dict["stepGoal"] as? Int
        stepsDate = dict["stepsDate"] as? String
        fastingActive = dict["fastingActive"] as? Bool ?? false
        if let ms = dict["fastingStartMs"] as? Double {
            fastingStart = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = dict["fastingStartMs"] as? Int {
            fastingStart = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        fastingGoalHours = dict["fastingGoalHours"] as? Int
        meditatedOn = dict["meditatedOn"] as? String
        meditationStreak = dict["meditationStreak"] as? Int ?? 0
        mood = dict["mood"] as? String
        if let ms = dict["moodAtMs"] as? Double {
            moodAt = Date(timeIntervalSince1970: ms / 1000)
        } else if let ms = dict["moodAtMs"] as? Int {
            moodAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        }
    }

    static func todayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Steps only count if they were recorded today.
    var stepsToday: Int? {
        stepsDate == Self.todayKey() ? steps : nil
    }

    var meditatedToday: Bool {
        meditatedOn == Self.todayKey()
    }

    static func loadFromSharedStore() -> WatchState {
        let dict = UserDefaults(suiteName: SharedStore.appGroupId)?
            .dictionary(forKey: SharedStore.snapshotKey) ?? [:]
        return WatchState(dict: dict)
    }
}
```

- [ ] **Step 2: Create PhoneConnector.swift**

```swift
import Foundation
import WatchConnectivity
import WidgetKit

/// Receives application-context snapshots from the iPhone, publishes them
/// to the UI, and persists them for the watch-face widget.
final class PhoneConnector: NSObject, ObservableObject, WCSessionDelegate {
    @Published var state = WatchState.loadFromSharedStore()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        if !context.isEmpty {
            apply(context)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        apply(applicationContext)
    }

    private func apply(_ dict: [String: Any]) {
        DispatchQueue.main.async {
            self.state = WatchState(dict: dict)
            UserDefaults(suiteName: SharedStore.appGroupId)?
                .set(dict, forKey: SharedStore.snapshotKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
```

- [ ] **Step 3: Rewrite ContentView.swift**

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var connector = PhoneConnector()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("InnerU")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("Quick check-in")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                card(title: "Steps", detail: stepsDetail)
                fastingCard
                card(title: "Meditate", detail: meditationDetail)
                card(title: "Mood", detail: moodDetail)
            }
            .padding(.horizontal, 4)
        }
    }

    private var stepsDetail: String {
        guard let steps = connector.state.stepsToday else {
            return "No steps yet today"
        }
        let formatted = steps.formatted()
        if let goal = connector.state.stepGoal {
            return "\(formatted) of \(goal.formatted()) steps"
        }
        return "\(formatted) steps today"
    }

    private var fastingCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(title: "Fasting", detail: fastingDetail(at: context.date))
        }
    }

    private func fastingDetail(at now: Date) -> String {
        guard connector.state.fastingActive,
              let start = connector.state.fastingStart else {
            return "No active fast"
        }
        let minutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        let elapsed = "\(minutes / 60)h \(minutes % 60)m"
        if let goal = connector.state.fastingGoalHours {
            return "\(elapsed) of \(goal)h"
        }
        return "\(elapsed) elapsed"
    }

    private var meditationDetail: String {
        guard connector.state.meditatedToday else {
            return "Not yet today"
        }
        let streak = connector.state.meditationStreak
        return streak > 1 ? "Done today · \(streak)-day streak" : "Done today"
    }

    private var moodDetail: String {
        guard let mood = connector.state.mood else {
            return "No check-in yet"
        }
        var detail = mood.capitalized
        if let at = connector.state.moodAt {
            detail += " · \(at.formatted(date: .omitted, time: .shortened))"
        }
        return detail
    }

    private func card(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.green.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
```

- [ ] **Step 4: Create InnerUWatch.entitlements**

`ios/InnerUWatch/InnerUWatch.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.valenin.inneru.watch</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 5: Script the Xcode project changes**

Create `ios/scripts/add_watch_files.rb`:

```ruby
# Adds WatchState.swift + PhoneConnector.swift to the InnerUWatch target
# and wires up its entitlements. Run with /opt/homebrew/opt/ruby/bin/ruby.
Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec/gems/*/lib').each do |path|
  $LOAD_PATH.unshift(path)
end
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

watch_target = project.targets.find { |t| t.name == 'InnerUWatch' }
raise 'InnerUWatch target not found' unless watch_target

watch_group = project.main_group.find_subpath('InnerUWatch', false)
raise 'InnerUWatch group not found' unless watch_group

%w[WatchState.swift PhoneConnector.swift].each do |file_name|
  next if watch_group.files.any? { |f| f.path == file_name }
  file_ref = watch_group.new_reference(file_name)
  watch_target.add_file_references([file_ref])
end

watch_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] =
    'InnerUWatch/InnerUWatch.entitlements'
end

project.save
puts 'InnerUWatch target updated.'
```

Run: `/opt/homebrew/opt/ruby/bin/ruby ~/InnerU/ios/scripts/add_watch_files.rb`
Expected: `InnerUWatch target updated.`

- [ ] **Step 6: Build to verify**

Run: `cd ~/InnerU && flutter build ios --simulator 2>&1 | tail -5`
Expected: "✓ Built build/ios/iphonesimulator/Runner.app" (building Runner also builds the embedded watch app; watch Swift errors would fail this build).

- [ ] **Step 7: Commit**

```bash
cd ~/InnerU
git add ios/InnerUWatch ios/scripts/add_watch_files.rb ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat: watch app shows live activity data from phone

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Watch-face Smart Stack widget

**Files:**
- Create: `ios/InnerUWatchWidget/InnerUWatchWidget.swift`
- Create: `ios/InnerUWatchWidget/Info.plist`
- Create: `ios/InnerUWatchWidget/InnerUWatchWidget.entitlements`
- Create: `ios/scripts/add_watch_widget_target.rb`
- Modify: `ios/Runner.xcodeproj/project.pbxproj` (via the script only)

**Interfaces:**
- Consumes: `WatchState` and `SharedStore` from Task 3 (`WatchState.swift` gets compiled into this target too).
- Produces: widget bundle id `com.valenin.inneru.watchkitapp.widget`, family `.accessoryRectangular`.

- [ ] **Step 1: Create InnerUWatchWidget.swift**

```swift
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let state: WatchState
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, state: WatchState())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SnapshotEntry) -> Void
    ) {
        completion(SnapshotEntry(date: .now, state: .loadFromSharedStore()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SnapshotEntry>) -> Void
    ) {
        let state = WatchState.loadFromSharedStore()
        var entries = [SnapshotEntry(date: .now, state: state)]
        if state.fastingActive {
            // Tick the elapsed time once a minute for the next 30 minutes.
            for minute in 1...30 {
                entries.append(SnapshotEntry(
                    date: .now.addingTimeInterval(Double(minute) * 60),
                    state: state
                ))
            }
        }
        let refresh = Date.now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct InnerUWidgetView: View {
    var entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("InnerU")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
            Text(stepsLine)
                .font(.system(size: 13, weight: .medium))
            Text(bottomLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    private var stepsLine: String {
        guard let steps = entry.state.stepsToday else { return "No steps yet" }
        return "\(steps.formatted()) steps"
    }

    private var bottomLine: String {
        if entry.state.fastingActive, let start = entry.state.fastingStart {
            let minutes = max(0, Int(entry.date.timeIntervalSince(start)) / 60)
            return "Fasting \(minutes / 60)h \(minutes % 60)m"
        }
        if entry.state.meditatedToday {
            let streak = entry.state.meditationStreak
            return streak > 1 ? "Meditated · \(streak)-day streak" : "Meditated today"
        }
        return "No meditation yet"
    }
}

@main
struct InnerUWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "InnerUWatchWidget",
            provider: SnapshotProvider()
        ) { entry in
            InnerUWidgetView(entry: entry)
        }
        .configurationDisplayName("InnerU")
        .description("Steps, fasting, and meditation at a glance.")
        .supportedFamilies([.accessoryRectangular])
    }
}
```

- [ ] **Step 2: Create the widget Info.plist**

`ios/InnerUWatchWidget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>InnerU</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 3: Create the widget entitlements**

`ios/InnerUWatchWidget/InnerUWatchWidget.entitlements` — identical content to `InnerUWatch.entitlements` (same single app group `group.com.valenin.inneru.watch`).

- [ ] **Step 4: Script the widget target creation**

Create `ios/scripts/add_watch_widget_target.rb`:

```ruby
# Creates the InnerUWatchWidget WidgetKit extension target, embeds it in
# the InnerUWatch app, and shares WatchState.swift with it.
# Run with /opt/homebrew/opt/ruby/bin/ruby. Safe to re-run (idempotent).
Dir.glob('/opt/homebrew/Cellar/cocoapods/*/libexec/gems/*/lib').each do |path|
  $LOAD_PATH.unshift(path)
end
require 'xcodeproj'

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |t| t.name == 'InnerUWatchWidget' }
  puts 'InnerUWatchWidget target already exists — nothing to do.'
  exit 0
end

watch_target = project.targets.find { |t| t.name == 'InnerUWatch' }
raise 'InnerUWatch target not found' unless watch_target

widget = project.new_target(
  :app_extension, 'InnerUWatchWidget', :watchos, '10.0'
)

widget.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.valenin.inneru.watchkitapp.widget'
  bs['INFOPLIST_FILE'] = 'InnerUWatchWidget/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['SDKROOT'] = 'watchos'
  bs['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
  bs['TARGETED_DEVICE_FAMILY'] = '4'
  bs['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  bs['SWIFT_VERSION'] = '5.0'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['DEVELOPMENT_TEAM'] = '965T647JG7'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'InnerUWatchWidget/InnerUWatchWidget.entitlements'
  bs['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  bs['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  bs['SKIP_INSTALL'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ]
end

widget_group = project.main_group.find_subpath('InnerUWatchWidget', false) ||
               project.main_group.new_group('InnerUWatchWidget', 'InnerUWatchWidget')
widget_source = widget_group.new_reference('InnerUWatchWidget.swift')
widget.add_file_references([widget_source])

watch_state = project.files.find do |f|
  f.real_path.to_s.end_with?('InnerUWatch/WatchState.swift')
end
raise 'WatchState.swift not found — run add_watch_files.rb first' unless watch_state
widget.add_file_references([watch_state])

embed = watch_target.copy_files_build_phases.find do |phase|
  phase.symbol_dst_subfolder_spec == :plug_ins
end
unless embed
  embed = watch_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
watch_target.add_dependency(widget)

project.save
puts 'InnerUWatchWidget target created.'
```

Run: `/opt/homebrew/opt/ruby/bin/ruby ~/InnerU/ios/scripts/add_watch_widget_target.rb`
Expected: `InnerUWatchWidget target created.`

- [ ] **Step 5: Build to verify**

Run: `cd ~/InnerU && flutter build ios --simulator 2>&1 | tail -5`
Expected: "✓ Built build/ios/iphonesimulator/Runner.app". If the widget fails to compile or embed, the build fails here.

- [ ] **Step 6: Commit**

```bash
cd ~/InnerU
git add ios/InnerUWatchWidget ios/scripts/add_watch_widget_target.rb ios/Runner.xcodeproj/project.pbxproj
git commit -m "feat: add InnerU Smart Stack widget for the watch face

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: End-to-end verification on paired simulators

**Files:** none (verification only).

- [ ] **Step 1: Find or create a paired iPhone+Watch simulator pair**

Run: `xcrun simctl list pairs`
Expected: at least one pair. If none, create one:

```bash
xcrun simctl pair <watch-udid> <phone-udid>
```

(pick UDIDs from `xcrun simctl list devices available`).

- [ ] **Step 2: Boot both simulators and install the apps**

```bash
open -a Simulator
xcrun simctl boot <phone-udid>
xcrun simctl boot <watch-udid>
xcrun simctl install <phone-udid> ~/InnerU/build/ios/iphonesimulator/Runner.app
xcrun simctl install <watch-udid> ~/InnerU/build/ios/iphonesimulator/Runner.app/Watch/InnerUWatch.app
```

Expected: no errors. (If the watch app path differs, check `ls ~/InnerU/build/ios/iphonesimulator/Runner.app/Watch/`.)

- [ ] **Step 3: Exercise the flow**

On the phone simulator: log in, record a mood, start a fast. On the watch simulator: open InnerU.
Expected: Mood card shows the recorded mood; Fasting card shows elapsed time ticking.
Then long-press the watch face → add the InnerU widget to the Smart Stack.
Expected: widget shows the fasting line.

- [ ] **Step 4: Report results to the user**

Simulator pedometer/steps can't be exercised (no step events on simulator) — note that steps were verified by code review + unit tests only, and real-device testing is the user's final check.

---

## Post-plan notes (user-facing, not tasks)

- **App Store archive:** the widget uses Automatic signing; the existing Release config for the watch app uses a manual profile ("InnerU Watch App Store"). Before the next App Store upload, the user must register the app group `group.com.valenin.inneru.watch` and the new bundle id `com.valenin.inneru.watchkitapp.widget` in the Apple Developer portal and create/download its provisioning profile (or switch the whole watch pair to automatic signing in Xcode).
- Widget freshness on real hardware depends on watchOS background-delivery budgets; the fasting timer ticks locally regardless.
