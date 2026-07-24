# Sleep Goal Duration Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the whole-hours dropdown for "Set your sleep goal" in the sleep settings screen with a tap-to-open duration picker (hours + minutes), styled to match the existing bedtime time-picker box.

**Architecture:** Single-file change to `SleepSettingsState`. State type for the sleep goal changes from `int?` (hours) to `Duration`. A new `_pickSleepGoal` handler opens a `showModalBottomSheet` hosting a `CupertinoTimerPicker` (`mode: hm`), and a new `_buildSleepGoalColumn` widget replaces the old dropdown column, visually matching `_buildTimePickerColumn`.

**Tech Stack:** Flutter/Dart, `flutter/cupertino.dart` (`CupertinoTimerPicker` — built into the Flutter SDK, no new pubspec dependency needed), `flutter_test` for the widget test.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-24-sleep-goal-time-picker-design.md`
- Only `lib/src/features/authentication/screen/sleep_tracker/sleep_settings.dart` and its test are in scope. Do not touch the wake-up dropdown, the bedtime picker, or the "Save details" button behavior.
- Default sleep goal stays `Duration(hours: 9)` (preserves current default of 9).
- Display format: `"{h}h {m}m"`, omitting minutes when zero (e.g. `"9h"` not `"9h 0m"`; `"7h 30m"` when minutes present).
- Package name for imports/tests: `selfcare_projects`.

---

### Task 1: Replace sleep goal dropdown with duration picker

**Files:**
- Modify: `lib/src/features/authentication/screen/sleep_tracker/sleep_settings.dart`
- Test: `test/widget/sleep_settings_test.dart` (create)

**Interfaces:**
- Produces: `SleepSettingsState.selectedSleepGoal` — type `Duration`, default `Duration(hours: 9)`.
- Produces: `SleepSettingsState._pickSleepGoal(BuildContext)` — opens the duration picker bottom sheet, updates `selectedSleepGoal` via `setState` on confirm.
- Produces: `SleepSettingsState._buildSleepGoalColumn()` — returns the tappable box + label `Column`, replacing the old `_buildDropdownColumn("Set your \nsleep goal", ...)` call in `build()`.
- Produces: `SleepSettingsState._formatSleepGoal(Duration)` — returns the `"{h}h {m}m"` / `"{h}h"` display string.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/sleep_settings_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_settings.dart';

void main() {
  testWidgets('sleep goal box shows default duration and opens a duration picker on tap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SleepSettings()),
      ),
    );

    // Default sleep goal is 9 hours, shown as "9h" (no dropdown arrow, no minutes suffix).
    expect(find.text('9h'), findsOneWidget);

    await tester.tap(find.text('9h'));
    await tester.pumpAndSettle();

    // Tapping opens a bottom sheet containing the duration picker.
    expect(find.byType(CupertinoTimerPicker), findsOneWidget);
  });

  testWidgets('sleep goal box formats non-zero minutes as "Xh Ym"',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SleepSettings()),
      ),
    );

    final state =
        tester.state<SleepSettingsState>(find.byType(SleepSettings));
    state.setState(() {
      state.selectedSleepGoal = const Duration(hours: 7, minutes: 30);
    });
    await tester.pump();

    expect(find.text('7h 30m'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/sleep_settings_test.dart`
Expected: FAIL — `selectedSleepGoal` is currently `int?` so `Duration(hours: 7, minutes: 30)` won't assign, `find.text('9h')` won't be found (current UI shows a dropdown with `"9"` plus arrow, not a plain `"9h"` box), and `CupertinoTimerPicker` won't be found (nothing opens it yet).

- [ ] **Step 3: Implement the duration state, picker handler, and formatter**

In `lib/src/features/authentication/screen/sleep_tracker/sleep_settings.dart`, add the cupertino import and replace the sleep goal state fields:

```dart
import 'package:flutter/cupertino.dart';
```

Replace:

```dart
  int? selectedSleepGoal = 9;
  List<int> sleepGoalOptions = List.generate(12, (index) => index + 1);
```

with:

```dart
  Duration selectedSleepGoal = const Duration(hours: 9);
```

Add the formatter and the picker handler (near `_pickTime`):

```dart
  String _formatSleepGoal(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  Future<void> _pickSleepGoal(BuildContext context) async {
    Duration tempGoal = selectedSleepGoal;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SizedBox(
          height: 250,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.hm,
            initialTimerDuration: selectedSleepGoal,
            onTimerDurationChanged: (Duration newDuration) {
              tempGoal = newDuration;
            },
          ),
        );
      },
    );

    setState(() {
      selectedSleepGoal = tempGoal;
    });
  }
```

- [ ] **Step 4: Replace the dropdown column with the duration picker column in `build()`**

Replace:

```dart
              Expanded(
                child: _buildDropdownColumn("Set your \nsleep goal",
                    selectedSleepGoal, sleepGoalOptions, (newValue) {
                  setState(() {
                    selectedSleepGoal = newValue;
                  });
                }),
              ),
```

with:

```dart
              Expanded(
                child: _buildSleepGoalColumn(),
              ),
```

- [ ] **Step 5: Add `_buildSleepGoalColumn`, styled like `_buildTimePickerColumn`**

Add this method next to `_buildTimePickerColumn`:

```dart
  Widget _buildSleepGoalColumn() {
    return Column(
      children: [
        InkWell(
          onTap: () => _pickSleepGoal(context),
          child: SizedBox(
            child: Container(
              width: 110,
              height: 45,
              padding: EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _formatSleepGoal(selectedSleepGoal),
                style: GoogleFonts.roboto(),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Text("Set your \nsleep goal", style: TextStyle(fontSize: 14)),
      ],
    );
  }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/widget/sleep_settings_test.dart`
Expected: PASS (both tests)

- [ ] **Step 7: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS (no other test references `selectedSleepGoal`, `sleepGoalOptions`, or the removed dropdown, since this was the only usage site)

- [ ] **Step 8: Commit**

```bash
git add lib/src/features/authentication/screen/sleep_tracker/sleep_settings.dart test/widget/sleep_settings_test.dart
git commit -m "feat: replace sleep goal dropdown with duration picker"
```
