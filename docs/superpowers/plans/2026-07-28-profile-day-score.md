# Profile Day-Score Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user taps a past day in the Profile screen's "View Previous Progress" calendar, the day-detail dialog shows that day's already-computed score percentage (or a clear "no data" message), instead of only a read-only checklist with no percentage anywhere.

**Architecture:** `_showDailyTrackerDialog` in `profile.dart` already fetches the full tracker record for the tapped day via `DailyTrackerApiService.instance.fetch(date: ...)` — that payload already includes `userTotalScore` (`backend/app/Http/Controllers/Api/DailyTrackerController.php::mapTracker`), the same 0–100 score value shown for *today* elsewhere on this page. A tiny pure function extracts/clamps that value from the raw tracker map (testable in isolation); the dialog method calls it and renders one extra row before the existing checklist.

**Tech Stack:** Flutter/Dart, existing `DailyTrackerApiService`, `flutter_test`.

## Global Constraints

- No backend changes — `userTotalScore` is already returned by the exact API call this dialog already makes (per spec `docs/superpowers/specs/2026-07-28-profile-day-score-design.md`).
- No changes to the calendar grid cells themselves, and no month-level average — score is shown only in the per-day dialog (per user's explicit answer during brainstorming).
- A day with no tracker record must show a "no data" message, never a misleading "0%".
- This repo's convention (per user instruction) is: never `git commit` unless explicitly asked in the moment. Do NOT run `git commit` as part of executing this plan — stage changes if useful, but leave the actual commit to the user unless they ask for it in that session.

---

### Task 1: Pure day-score resolver + unit test

**Files:**
- Create: `lib/src/features/authentication/screen/profile/profile_day_score.dart`
- Test: `test/unit/profile_day_score_test.dart`

**Interfaces:**
- Produces: `int resolveDayScorePercent(Map<String, dynamic> trackerData)` — reads `trackerData['userTotalScore']`, rounds it if it's numeric, clamps to `0..100`, and defaults to `0` if the key is missing or non-numeric. Task 2 calls this only when a tracker record exists for the tapped day (the "does a record exist at all" distinction stays in `profile.dart`, this function only ever runs against a real record).

- [ ] **Step 1: Write the failing tests**

Create `test/unit/profile_day_score_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_day_score.dart';

void main() {
  group('resolveDayScorePercent', () {
    test('returns the stored integer score as-is', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 20}),
        20,
      );
    });

    test('rounds a fractional score', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 82.6}),
        83,
      );
    });

    test('clamps a score above 100', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 140}),
        100,
      );
    });

    test('clamps a negative score to 0', () {
      expect(
        resolveDayScorePercent({'userTotalScore': -5}),
        0,
      );
    });

    test('defaults to 0 when the key is missing', () {
      expect(
        resolveDayScorePercent(<String, dynamic>{}),
        0,
      );
    });

    test('defaults to 0 when the value is not numeric', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 'not-a-number'}),
        0,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/profile_day_score_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:selfcare_projects/src/features/authentication/screen/profile/profile_day_score.dart'` (the file doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/src/features/authentication/screen/profile/profile_day_score.dart`:

```dart
/// The score percentage (0-100) for a single day's daily-tracker record.
///
/// [trackerData] must be an already-fetched tracker record for a specific
/// day (e.g. the `tracker` map from `DailyTrackerApiService.fetch`) — this
/// does not distinguish "no record for this day" from "record with a 0
/// score"; callers must check for a missing record themselves and only
/// call this once a record is known to exist.
int resolveDayScorePercent(Map<String, dynamic> trackerData) {
  final raw = trackerData['userTotalScore'];
  if (raw is num) {
    return raw.round().clamp(0, 100);
  }
  return 0;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/profile_day_score_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/src/features/authentication/screen/profile/profile_day_score.dart test/unit/profile_day_score_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Stage the change (do not commit — see Global Constraints)**

```bash
git add lib/src/features/authentication/screen/profile/profile_day_score.dart test/unit/profile_day_score_test.dart
```

---

### Task 2: Show the score in the day-detail dialog

**Files:**
- Modify: `lib/src/features/authentication/screen/profile/profile.dart:1343-1414` (`_showDailyTrackerDialog`)

**Interfaces:**
- Consumes: `int resolveDayScorePercent(Map<String, dynamic> trackerData)` from Task 1.

This task has no automated test — `profile.dart` has no existing widget test (consistent with other Firebase/network-backed screens in this codebase; see `test/unit/inneru-test-suite` conventions), so it's verified via `flutter analyze` plus a manual run-through described in the final step.

- [ ] **Step 1: Add the import**

In `lib/src/features/authentication/screen/profile/profile.dart`, add this import alongside the other same-directory imports near the top of the file (after the existing `import 'package:selfcare_projects/src/services/user_point_api_service.dart';` line):

```dart
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_day_score.dart';
```

- [ ] **Step 2: Track the day's score alongside the existing task map**

Find this exact block (currently around line 1344):

```dart
// Popup for Previous Days
  Future<void> _showDailyTrackerDialog(int day) async {
    final selectedDate = DateFormat('yyyy-MM-dd')
        .format(DateTime(selectedYear, selectedMonth, day));

    Map<String, bool> selectedDateTasks = {
      for (final item in dailyTrackerItems) item.title: false,
    };

    try {
      final response = await DailyTrackerApiService.instance.fetch(
        date: selectedDate,
      );
      final data = response['tracker'];
      if (data is Map<String, dynamic>) {
        selectedDateTasks = {
          for (final item in dailyTrackerItems)
            item.title: _readTaskCompletion(data, item),
        };

        final customTasks = data['customDailyTasks'];
        if (customTasks is Map) {
          for (final entry in customTasks.entries) {
            final value = entry.value;
            if (value is Map) {
              final title = value['title'];
              if (title is String && title.trim().isNotEmpty) {
                selectedDateTasks[title.trim()] = value['completed'] == true;
              }
            }
          }
        }
      } else {
        print("No data found for $selectedDate.");
      }
    } catch (e) {
      print("Error fetching tracker data for $selectedDate: $e");
    }
```

Replace it with:

```dart
// Popup for Previous Days
  Future<void> _showDailyTrackerDialog(int day) async {
    final selectedDate = DateFormat('yyyy-MM-dd')
        .format(DateTime(selectedYear, selectedMonth, day));

    Map<String, bool> selectedDateTasks = {
      for (final item in dailyTrackerItems) item.title: false,
    };
    int? dayScorePercent;

    try {
      final response = await DailyTrackerApiService.instance.fetch(
        date: selectedDate,
      );
      final data = response['tracker'];
      if (data is Map<String, dynamic>) {
        selectedDateTasks = {
          for (final item in dailyTrackerItems)
            item.title: _readTaskCompletion(data, item),
        };
        dayScorePercent = resolveDayScorePercent(data);

        final customTasks = data['customDailyTasks'];
        if (customTasks is Map) {
          for (final entry in customTasks.entries) {
            final value = entry.value;
            if (value is Map) {
              final title = value['title'];
              if (title is String && title.trim().isNotEmpty) {
                selectedDateTasks[title.trim()] = value['completed'] == true;
              }
            }
          }
        }
      } else {
        print("No data found for $selectedDate.");
      }
    } catch (e) {
      print("Error fetching tracker data for $selectedDate: $e");
    }

    // Captured as a `final` local so it promotes to non-null inside the
    // dialog builder closure below.
    final resolvedScorePercent = dayScorePercent;
```

- [ ] **Step 3: Render the score row above the checklist**

Find this exact block (immediately after the code from Step 2, currently around line 1382):

```dart
    // Show the dialog with fetched data
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Tracker for $selectedMonth/$day/$selectedYear"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: selectedDateTasks.keys.map((task) {
                  return CheckboxListTile(
                    title: Text(task),
                    value: selectedDateTasks[task],
                    onChanged:
                        null, // Checkboxes are not interactive in this dialog
                  );
                }).toList(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }
```

Replace it with:

```dart
    // Show the dialog with fetched data
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Tracker for $selectedMonth/$day/$selectedYear"),
          content: StatefulBuilder(
            builder: (context, setState) {
              final colors = Theme.of(context).colorScheme;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (resolvedScorePercent != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Score',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '$resolvedScorePercent%',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: (resolvedScorePercent / 100)
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        backgroundColor: colors.onSurface.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No tracker data recorded for this day.',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ...selectedDateTasks.keys.map((task) {
                    return CheckboxListTile(
                      title: Text(task),
                      value: selectedDateTasks[task],
                      onChanged:
                          null, // Checkboxes are not interactive in this dialog
                    );
                  }),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/src/features/authentication/screen/profile/profile.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run the full test suite to confirm nothing else broke**

Run: `flutter test test/unit test/widget`
Expected: all tests pass (same count as before this change, plus the 6 new tests from Task 1).

- [ ] **Step 6: Manual verification**

This screen has no automated widget test, so confirm by hand:

1. Run the app and open Profile → "View Previous Progress".
2. Tap a day that has a saved daily-tracker record. Confirm the dialog shows a "Score" row with a percentage and a progress bar matching that day's actual completion, above the checklist.
3. Tap a day known to have no tracker record (e.g. before the user started using the app, or a day with no activity at all). Confirm the dialog shows "No tracker data recorded for this day." instead of "Score 0%".
4. Tap today. Confirm its score in this dialog matches the "Daily score" percentage shown elsewhere on the same Profile page (`_buildDailyTrackerScore`).

- [ ] **Step 7: Stage the change (do not commit — see Global Constraints)**

```bash
git add lib/src/features/authentication/screen/profile/profile.dart
```
