# Sleep Goal Duration Picker

**Date:** 2026-07-24
**File affected:** `lib/src/features/authentication/screen/sleep_tracker/sleep_settings.dart`

## Problem

In `SleepSettingsState`, the "Set your sleep goal" field is a `DropdownButton<int>` limited to whole hours 1–12. The user wants a time picker instead, so sleep goal can be set with hour + minute precision (e.g. "7h 30m"), consistent with the existing bedtime picker on the same row.

## Design

- Replace state:
  - `int? selectedSleepGoal = 9;` / `List<int> sleepGoalOptions = ...` →
  - `Duration selectedSleepGoal = const Duration(hours: 9);`
- Add a `_pickSleepGoal(BuildContext)` method that opens a `showModalBottomSheet` containing a `CupertinoTimerPicker` (`mode: CupertinoTimerPickerMode.hm`, `initialTimerDuration: selectedSleepGoal`), and on change updates `selectedSleepGoal` via `setState`.
  - `CupertinoTimerPicker` is used instead of `showTimePicker` because it is Flutter's built-in widget for duration entry (no AM/PM clock-time semantics, which would be misleading for a goal like "8h 30m").
- Replace the dropdown column for sleep goal (`_buildDropdownColumn("Set your \nsleep goal", ...)`) with a new `_buildSleepGoalColumn()` widget, visually matching `_buildTimePickerColumn()` (same `InkWell` + `Container` box styling, grey background, rounded corners, same size) so all three fields in the row look consistent.
- Format the displayed duration as `"{h}h {m}m"`, omitting minutes when zero (e.g. `"8h"` instead of `"8h 0m"`).
- Default value: `Duration(hours: 9)` (preserves current default of 9).
- No changes to persistence, the "Save details" button (still a no-op), the wake-up notification dropdown, or the bedtime picker.

## Out of scope

- Wiring "Save details" to actually persist settings.
- Changing the wake-up notification field.
- Any Firestore/backend changes.
