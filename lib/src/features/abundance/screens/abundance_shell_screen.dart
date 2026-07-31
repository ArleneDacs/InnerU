import 'package:flutter/material.dart';

import 'package:selfcare_projects/src/features/abundance/screens/coach/coach_quests_roster_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/abundance_mentee_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_settings.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

/// The custom app shell (header + 5-tab bottom nav) A12-Tracker wraps every
/// screen in, built only for Abundance members. Only the Quests tab has a
/// finished redesign so far (mentee: [GoalsHubScreen]; coach:
/// [CoachQuestsRosterScreen]) — Home/Guild/Profile/More render InnerU's
/// existing equivalent screens verbatim as placeholders until their own
/// specs land (see the design spec's "App shell" section).
///
/// The "ABUNDANCE 12" / "THE GAME OF MY LIFE" header copy is static ported
/// brand text, not derived from [companyTheme]'s company name — A12 is
/// single-tenant, so its own wordmark is fixed, not tenant-derived.
class AbundanceShellScreen extends StatefulWidget {
  const AbundanceShellScreen({
    super.key,
    required this.isCoach,
    required this.service,
    required this.uid,
    required this.companyTheme,
    this.initialIndex = 0,
    this.questsAccessResolverOverride,
  });

  final bool isCoach;
  final GoalsService service;
  final String uid;
  final CompanyThemeData companyTheme;

  /// Which tab the shell lands on. Defaults to Home (0), matching every A12
  /// reference screenshot — real callers should not need to override this.
  /// Exposed (mirroring the established `Setuppage`/`CoachSetuppage` pattern
  /// in `lib/setup_navbar.dart`) so tests/callers can start on a different
  /// tab without changing the real default — e.g. this shell's own coach
  /// test starts on Quests to avoid building `CoachDashboardScreen`, which
  /// touches `FirebaseFirestore.instance` synchronously and crashes without
  /// a live Firebase app.
  final int initialIndex;

  /// Forwarded verbatim to `GoalsHubScreen.accessResolver` on the mentee
  /// Quests tab. Left `null` in production so `GoalsHubScreen` falls through
  /// to its own real access resolution
  /// (`GoalsService.fetchActiveCompanyIdentity` ->
  /// `CompanyMembershipService.loadForUser`) — exactly the same
  /// production-real-default-with-test-override shape as [initialIndex].
  /// This shell's own widget test supplies a value here because it
  /// constructs `GoalsService(FakeFirebaseFirestore())` with no seeded
  /// `users/{uid}` doc, which would otherwise make the real check correctly
  /// (but inconveniently, for that test) deny access.
  final Future<bool> Function(String uid)? questsAccessResolverOverride;

  @override
  State<AbundanceShellScreen> createState() => _AbundanceShellScreenState();
}

class _AbundanceShellScreenState extends State<AbundanceShellScreen> {
  // Tab order is Home(0)/Quests(1)/Guild(2)/Profile(3)/More(4). Seeded from
  // widget.initialIndex (defaults to Home) in initState below.
  late int _index;

  // Each tab body is constructed at most once, the first time it's
  // selected, then cached here and reused for the rest of the shell's
  // lifetime (so switching tabs preserves scroll position / in-progress
  // state instead of re-fetching). Slots that have never been visited stay
  // a cheap SizedBox.shrink() placeholder rather than eagerly building the
  // real screen — several of the embedded screens (e.g. CoachDashboardScreen)
  // touch Firebase/network state directly in their State's field
  // initializers, which is unsafe to do for tabs the user hasn't opened yet
  // (and, in widget tests without a live Firebase app, throws outright).
  final List<Widget> _builtTabs = List<Widget>.filled(5, const SizedBox.shrink());
  final Set<int> _visited = {};

  static const _tabLabels = ['Home', 'Quests', 'Guild', 'Profile', 'More'];
  static const _tabIcons = [
    Icons.home_outlined,
    Icons.military_tech_outlined,
    Icons.groups_outlined,
    Icons.person_outline,
    Icons.more_horiz,
  ];

  Widget get _questsTabBody => widget.isCoach
      ? CoachQuestsRosterScreen(service: widget.service, coachUid: widget.uid)
      : GoalsHubScreen(
          service: widget.service,
          uid: widget.uid,
          // No hardcoded bypass here: in production this is null, so
          // GoalsHubScreen runs its own real access check
          // (GoalsService.fetchActiveCompanyIdentity ->
          // CompanyMembershipService.loadForUser), the same check every
          // other GoalsHubScreen caller relies on. Only this shell's own
          // widget test supplies a non-null override, via
          // widget.questsAccessResolverOverride, to bypass the check in its
          // specific test setup (see that field's doc comment).
          accessResolver: widget.questsAccessResolverOverride,
        );

  Widget get _homeTabBody => widget.isCoach
      ? const CoachDashboardScreen()
      : AbundanceMenteeDashboardScreen(
          initialCompanyTheme: widget.companyTheme,
          service: widget.service,
        );

  Widget _tabBodyFor(int index) {
    switch (index) {
      case 0:
        return _homeTabBody;
      case 1:
        return _questsTabBody;
      case 2:
        return const Leaderboard();
      case 3:
        return const ProfileSettings();
      default:
        return const SizedBox.shrink(); // "More" never actually renders.
    }
  }

  void _ensureBuilt(int index) {
    if (_visited.add(index)) {
      _builtTabs[index] = _tabBodyFor(index);
    }
  }

  @override
  void initState() {
    super.initState();
    // Clamped to 0-3, not 0-4: index 4 ("More") is a bottom-sheet trigger,
    // not a tab body, so landing on it would show an empty SizedBox.shrink().
    _index = widget.initialIndex.clamp(0, 3);
    _ensureBuilt(_index);
  }

  void _onTabTapped(int newIndex) {
    if (newIndex == 4) {
      BottomSheetWidget.show(context);
      return; // stay on the current tab; More is a trigger, not a screen.
    }
    setState(() {
      _index = newIndex;
      _ensureBuilt(newIndex);
    });
  }

  static const int _questsTabIndex = 1;

  PreferredSizeWidget _buildShellHeader() {
    return AppBar(
      backgroundColor: AbundanceColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ABUNDANCE 12',
              style: TextStyle(
                  color: AbundanceColors.foreground,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          Text('THE GAME OF MY LIFE',
              style: TextStyle(
                  color: AbundanceColors.primaryGold, fontSize: 10)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none,
              color: AbundanceColors.foreground),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbundanceColors.background,
      // Only the Quests tab gets the shell's own header. The other four tabs
      // embed InnerU screens that each bring their own root Scaffold+AppBar
      // (AbundanceMenteeDashboardScreen, CoachDashboardScreen, Leaderboard,
      // ProfileSettings), so rendering the shell's header there stacked two
      // headers on top of each other. This mirrors how Setuppage/
      // CoachSetuppage in lib/setup_navbar.dart already solve the same
      // problem (`appBar: index == 2 ? null : AppBar(...)`).
      //
      // Neither Quests-tab body has an AppBar of its own — GoalsHubScreen has
      // no Scaffold at all and CoachQuestsRosterScreen's Scaffold passes no
      // appBar — so this is the one tab that needs the shell to supply one.
      appBar: _index == _questsTabIndex ? _buildShellHeader() : null,
      body: IndexedStack(index: _index, children: _builtTabs),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AbundanceColors.surfaceRaised,
        selectedItemColor: AbundanceColors.primaryGold,
        unselectedItemColor: AbundanceColors.muted,
        currentIndex: _index,
        onTap: _onTabTapped,
        items: [
          for (var i = 0; i < _tabLabels.length; i++)
            BottomNavigationBarItem(
              icon: Icon(_tabIcons[i]),
              label: _tabLabels[i],
            ),
        ],
      ),
    );
  }
}
