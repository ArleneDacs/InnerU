# Goals Hub Mobile Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the Abundance 12 Goals Hub screen into a polished mobile-native dark-A12 layout with all user-visible content frozen, making the currently failing hub widget test pass.

**Architecture:** All changes live in one file, `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`. Shared palette constants and a gradient background widget go at file top; each private section widget (`_GoalsHeader`, `_ScorePanel`, `_MetricCard`, `_FilterChip`, `_GoalCard`, `_Badge`, `_EmptyGoalsState`) is restyled in place. The access check switches from the `CompanyMembershipService.loadForUser` singleton path to the same `users/{uid}` read via the injected `GoalsService.firestore`, which is what makes the screen testable with `FakeFirebaseFirestore`.

**Tech Stack:** Flutter 3.41.7, cloud_firestore, fake_cloud_firestore (tests). No new dependencies.

## Global Constraints

- **Content is frozen:** every user-visible string must remain byte-identical to the current file, with one exception — goal-card titles render `goal.title` as-authored instead of `goal.title.toUpperCase()`.
- **Only modify:** `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`. Do not touch the test file, services, domain, scoring, or any other screen.
- **No behavior changes:** same streams, same navigation, same filters, same responsive `Wrap` column logic (1/2/3 columns at 860/1280 breakpoints), same access rule (`_isAbundance12Company` untouched).
- After every task: `flutter test test/widget/abundance/goals_hub_screen_test.dart` prints `All tests passed!` and `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` reports `No issues found!`.
- Spec: `docs/superpowers/specs/2026-07-18-goals-hub-restyle-design.md`.

---

### Task 1: Make the hub widget test pass (injected access read + as-authored titles)

The test `test/widget/abundance/goals_hub_screen_test.dart` already exists and fails for two reasons: (a) `_resolveAccess` calls `CompanyMembershipService.loadForUser`, which is hardwired to `FirebaseFirestore.instance` and errors under widget tests, so the hub renders the "A12 only" denial screen; (b) the goal card renders `goal.title.toUpperCase()` but the test expects `Run 100 km`. This task is pure red→green; no visual redesign yet.

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart:38-42` (`_resolveAccess`) and `:833` (card title)
- Test (existing, unchanged): `test/widget/abundance/goals_hub_screen_test.dart`

**Interfaces:**
- Consumes: `GoalsService.firestore` getter (`lib/src/features/abundance/services/goals_service.dart:249`), static `CompanyMembershipService.fromUserData(Map<String, dynamic>?) → CompanyMembershipData` (`lib/src/services/company_membership_service.dart:126`).
- Produces: `_resolveAccess()` reading through the injected firestore — later tasks must NOT reintroduce `loadForUser` here.

- [ ] **Step 1: Run the existing test to confirm it fails**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: FAIL — `Found 0 widgets with text "Run 100 km"` (the access-denied screen renders instead of the hub).

- [ ] **Step 2: Route the access read through the injected firestore**

In `goals_hub_screen.dart`, replace the body of `_resolveAccess`:

```dart
// OLD
  Future<bool> _resolveAccess() async {
    if (_uid.isEmpty) return false;
    final membership = await CompanyMembershipService.loadForUser(_uid);
    return _isAbundance12Company(membership.activeMembership);
  }

// NEW
  Future<bool> _resolveAccess() async {
    if (_uid.isEmpty) return false;
    final userDoc =
        await _service.firestore.collection('users').doc(_uid).get();
    final membership =
        CompanyMembershipService.fromUserData(userDoc.data()).activeMembership;
    return _isAbundance12Company(membership);
  }
```

Keep the `company_membership_service.dart` import — `fromUserData` and the `CompanyMembership` type still use it. `_isAbundance12Company` stays exactly as it is.

- [ ] **Step 3: Render goal titles as-authored**

In `_GoalCard.build`, change the title `Text` (keep every style property as-is for now):

```dart
// OLD
                Text(
                  goal.title.toUpperCase(),

// NEW
                Text(
                  goal.title,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: `+1: All tests passed!`

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart
git commit -m "fix(abundance): hub access via injected firestore, titles as-authored"
```

---

### Task 2: Palette constants, gradient background, compact header

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` (file top, `_GoalsHubScreenState.build` scaffolds, `_GoalsHeader`)

**Interfaces:**
- Produces (file-level privates used by Tasks 3–5): `_bgTop`, `_bgBottom`, `_cardFill`, `_cardBorder`, `_wellFill`, `_gold`, `_pink`, `_mint`, `_cream`, `_slate`, `_dimSlate`, `_iceBlue` (all `const Color`), and `class _HubBackground extends StatelessWidget { const _HubBackground({required this.child}); final Widget child; }`.

- [ ] **Step 1: Add the palette constants and background widget**

Immediately after the imports (before `/// The Abundance 12 goals hub...`), insert:

```dart
// A12 dark palette shared by every section of the hub.
const _bgTop = Color(0xFF0A1130);
const _bgBottom = Color(0xFF050714);
const _cardFill = Color(0xFF111A45);
const _cardBorder = Color(0xBB27336C);
const _wellFill = Color(0xFF0A0F2B);
const _gold = Color(0xFFF0B93C);
const _pink = Color(0xFFFF6B86);
const _mint = Color(0xFF63E0B7);
const _cream = Color(0xFFF0E6CF);
const _slate = Color(0xFFB7C0E5);
const _dimSlate = Color(0xFF9EA8D6);
const _iceBlue = Color(0xFFCFD6FF);

class _HubBackground extends StatelessWidget {
  const _HubBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgBottom],
        ),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 2: Apply dark loading scaffolds and the gradient to the two built scaffolds**

In `_GoalsHubScreenState.build`, make these edits:

Both loading scaffolds (the access `ConnectionState.waiting` one and the goals `!snapshot.hasData` one):

```dart
// OLD (both occurrences)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );

// NEW (both occurrences)
          return const Scaffold(
            backgroundColor: _bgBottom,
            body: Center(child: CircularProgressIndicator(color: _gold)),
          );
```

Access-denied scaffold — wrap its body and switch the literal background:

```dart
// OLD
          return Scaffold(
            backgroundColor: const Color(0xFF050714),
            body: SafeArea(
              child: Center(

// NEW
          return Scaffold(
            backgroundColor: _bgBottom,
            body: _HubBackground(
              child: SafeArea(
                child: Center(
```

(Re-indent the rest of that subtree one level deeper and close the extra parenthesis at the end of the `SafeArea` — the card contents themselves are restyled later, in Task 5.)

Main hub scaffold — same wrap, plus mobile padding and tighter section gaps:

```dart
// OLD
            return Scaffold(
              backgroundColor: const Color(0xFF050714),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),

// NEW
            return Scaffold(
              backgroundColor: _bgBottom,
              body: _HubBackground(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
```

and change the three `const SizedBox(height: 28)` section gaps between header / summary / chips / list to `const SizedBox(height: 20)`. Re-indent the wrapped subtree and add the matching closing parenthesis.

- [ ] **Step 3: Scale down `_GoalsHeader`**

Replace the whole `_GoalsHeader` class body's `build` with:

```dart
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        const title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MY GOALS',
              style: TextStyle(
                color: _cream,
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontFamily: 'Georgia',
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Personal, professional and contribution - combined into your Goal Total Score.',
              style: TextStyle(
                color: _slate,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
          ],
        );

        final button = FilledButton.icon(
          onPressed: onNewGoal,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'New goal',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: title),
            const SizedBox(width: 24),
            button,
          ],
        );
      },
    );
  }
```

- [ ] **Step 4: Test and analyze**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: `+1: All tests passed!`
Run: `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart
git commit -m "style(abundance): hub gradient background and compact header"
```

---

### Task 3: Compact score hero and stat tiles

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` (`_GoalsSummaryGrid`, `_ScorePanel`, `_MetricCard`)

**Interfaces:**
- Consumes: Task 2 constants (`_cardFill`, `_cardBorder`, `_wellFill`, `_pink`, `_mint`, `_cream`, `_slate`, `_dimSlate`, `_iceBlue`).
- Produces: `_ScorePanel({required int score})`, `_MetricCard({required String label, required String value, required IconData icon, Color? valueColor})` — same constructors as today; `_GoalsSummaryGrid` keeps its existing constructor (including `categoryScores`, which stays a stored field).

- [ ] **Step 1: Replace `_GoalsSummaryGrid.build`**

Keep the class fields and constructor exactly as they are. Replace only `build`:

```dart
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = [
          _MetricCard(
            label: 'TOTAL GOALS',
            value: '$totalGoals',
            icon: Icons.adjust_rounded,
          ),
          _MetricCard(
            label: 'COMPLETED',
            value: '$completedGoals',
            icon: Icons.flag_outlined,
            valueColor: _mint,
          ),
          _MetricCard(
            label: 'IN PROGRESS',
            value: '$inProgressGoals',
            icon: Icons.calendar_month_outlined,
          ),
          _MetricCard(
            label: 'OVERDUE',
            value: '$overdueGoals',
            icon: Icons.warning_amber_rounded,
          ),
        ];

        final fourAcross = constraints.maxWidth >= 720;
        final Widget tileGrid;
        if (fourAcross) {
          tileGrid = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        } else {
          tileGrid = Column(
            children: [
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 12),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: tiles[2]),
                  const SizedBox(width: 12),
                  Expanded(child: tiles[3]),
                ],
              ),
            ],
          );
        }

        return Column(
          children: [
            _ScorePanel(score: goalScore),
            const SizedBox(height: 12),
            tileGrid,
          ],
        );
      },
    );
  }
```

- [ ] **Step 2: Replace `_ScorePanel.build`**

```dart
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x40FF6B86), blurRadius: 28),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: (score / 100).clamp(0.0, 1.0),
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    backgroundColor: _wellFill,
                    valueColor: const AlwaysStoppedAnimation<Color>(_pink),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        color: _pink,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'of 100',
                      style: TextStyle(color: _slate, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Goal Total Score',
                  style: TextStyle(
                    color: _cream,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Georgia',
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your Personal, Professional and Contribution scores, combined into one out of 100.',
                  style: TextStyle(color: _slate, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Replace `_MetricCard.build`**

Keep fields/constructor. New build:

```dart
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _wellFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _iceBlue, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _cream,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: _dimSlate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
```

Note the old fixed `height: 130` container is gone — tiles size to content.

- [ ] **Step 4: Test and analyze**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: `+1: All tests passed!`
Run: `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart
git commit -m "style(abundance): compact score hero and stat tiles"
```

---

### Task 4: Refined category chips, goal cards, badges

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` (`_CategoryChipsRow`, `_FilterChip`, `_GoalCard`, `_Badge`)

**Interfaces:**
- Consumes: Task 2 constants. `_GoalCard` keeps `_progressColor` and `_statusLabel` exactly as they are.
- Produces: same public shape as today — `_FilterChip({required String label, required int count, required bool selected, required VoidCallback onTap})`, `_Badge({required String text, required Color color, required Color background})`.

- [ ] **Step 1: Tighten chip spacing in `_CategoryChipsRow`**

Change the two `const SizedBox(width: 14)` gaps inside its `Row` to `const SizedBox(width: 10)`. Nothing else changes.

- [ ] **Step 2: Replace `_FilterChip.build`**

Keep fields/constructor. The label and count become two `Text` widgets (the test's `find.textContaining('Professional')` matches the label `Text`):

```dart
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2D2744) : const Color(0xFF101737),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _gold : const Color(0xFF27336C),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? _gold : _slate,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                color: selected ? _gold.withValues(alpha: 0.75) : _dimSlate,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: Replace `_GoalCard.build`**

Keep the class fields, `_progressColor`, and `_statusLabel` untouched. New build (all strings identical to today; title already as-authored from Task 1):

```dart
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActionPlanItem>>(
      stream: service.watchPlans(goal.id),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? const <ActionPlanItem>[];
        final completedPlans =
            plans.where((plan) => plan.status == ActionPlanStatus.done).length;
        final planLabel = plans.isEmpty
            ? 'No tasks yet'
            : '$completedPlans/${plans.length} tasks';
        final dueLabel = goal.isOverdue
            ? '${-goal.daysUntilDue}d overdue'
            : '${goal.daysUntilDue}d left';

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _cardFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: Color(goal.category.accent)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Badge(
                                text: goal.category.label,
                                color: Color(goal.category.accent),
                                background: const Color(0xFF241F37),
                              ),
                              _Badge(
                                text: _statusLabel(goal.status),
                                color: const Color(0xFF56C7F4),
                                background: const Color(0xFF142339),
                              ),
                              _Badge(
                                text: 'Score ${goal.progress}',
                                color: _pink,
                                background: const Color(0xFF2A2030),
                              ),
                              _Badge(
                                text: goal.rank.name,
                                color: _iceBlue,
                                background: const Color(0xFF232A47),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            goal.title,
                            style: const TextStyle(
                              color: _cream,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              fontFamily: 'Georgia',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((goal.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              goal.description!,
                              style: const TextStyle(
                                color: _slate,
                                fontSize: 13,
                                height: 1.45,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Text(
                                '${goal.progress}',
                                style: TextStyle(
                                  color: _progressColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 8,
                                    value:
                                        (goal.progress / 100).clamp(0.0, 1.0),
                                    backgroundColor: _wellFill,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _progressColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                color: _dimSlate,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${goal.targetDate.month}/${goal.targetDate.day}/${goal.targetDate.year}  -  $dueLabel',
                                  style: const TextStyle(
                                    color: _dimSlate,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                planLabel,
                                style: const TextStyle(
                                  color: _dimSlate,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
```

- [ ] **Step 4: Tighten `_Badge.build`**

```dart
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
```

- [ ] **Step 5: Test and analyze**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: `+1: All tests passed!`
Run: `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart
git commit -m "style(abundance): refined category chips and goal cards"
```

---

### Task 5: Empty state, access-denied card, final verification

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` (`_EmptyGoalsState`, access-denied card in `_GoalsHubScreenState.build`)

**Interfaces:**
- Consumes: Task 2 constants; the access-denied scaffold is already gradient-wrapped by Task 2.

- [ ] **Step 1: Restyle the access-denied card contents**

Inside the access-denied branch of `_GoalsHubScreenState.build`, replace the inner card `Container` (the one with `margin: EdgeInsets.all(24)`) with:

```dart
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _cardFill,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _cardBorder),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'A12 only',
                            style: TextStyle(
                              color: _gold,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'The My Goals experience is available for Abundance 12 company members only.',
                            style: TextStyle(
                              color: _slate,
                              height: 1.5,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            child: const Text('Go back'),
                          ),
                        ],
                      ),
                    ),
```

(Indentation shown assumes the Task 2 gradient wrap; match the actual surrounding depth.)

- [ ] **Step 2: Restyle `_EmptyGoalsState.build`**

```dart
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.adjust_rounded, size: 44, color: _dimSlate),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'No goals in this category yet' : 'No goals yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _cream,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap New goal to create your first A12 goal and start building your Goal Total Score.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _slate, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onNewGoal,
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
            ),
            child: const Text('New goal'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Full verification**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: `+1: All tests passed!`
Run: `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
Expected: `No issues found!`
Run: `flutter test test/widget/abundance/` (guard against regressions in sibling abundance widget tests)
Expected: `All tests passed!`

- [ ] **Step 4: Grep-check the content freeze**

Run: `grep -n "toUpperCase\|loadForUser" lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
Expected: exactly one match — the `companyCode.toUpperCase()` normalization line inside `_isAbundance12Company` (untouched by design). Any `goal.title.toUpperCase()` or `loadForUser` match is a task regression.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart
git commit -m "style(abundance): hub empty and access states match new scale"
```
