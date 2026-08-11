import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/abundance/screens/abundance_shell_screen.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/default_landing_screen.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';

/// Task 13's integration point — the single highest-risk untested seam on this
/// branch per the whole-branch review, and the file that decides whether
/// [AbundanceShellScreen] is ever built at all.
///
/// Both widgets branch in `build()`: an Abundance company theme swaps the
/// whole screen for the Abundance shell; every other company keeps the
/// pre-existing `Scaffold` + `CurvedNavigationBar`, untouched.
///
/// `initialIndex: 3` (TodoList) is used throughout rather than the production
/// default of 2, because index 2 is `DashboardScreen` / `CoachDashboardScreen`,
/// which touch `FirebaseFirestore.instance` synchronously in State field
/// initializers and throw with no live Firebase app, and index 0
/// (`Meditation`) needs a `Provider` this harness does not install. The index
/// does not participate in the gating branch under test — the branch runs
/// before `_screens[index]` is ever read.
CompanyThemeData _abundanceTheme({
  String code = 'ABU15DN',
  String name = 'ABUNDANCE',
}) {
  return CompanyThemeData.standard.copyWith(
    companyCode: code,
    companyName: name,
    isCompanyTheme: true,
  );
}

void main() {
  group('Setuppage', () {
    testWidgets('uses the saved Meditation default on the standard shell',
        (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<TimeProvider>(
          create: (_) => TimeProvider(),
          child: const MaterialApp(
            home: Setuppage(
              defaultScreen: DefaultLandingScreen.meditation,
              initialCompanyTheme: CompanyThemeData.standard,
            ),
          ),
        ),
      );

      expect(
        tester
            .widget<CurvedNavigationBar>(find.byType(CurvedNavigationBar))
            .index,
        0,
      );
    });

    testWidgets('uses the saved Community default on the standard shell',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Setuppage(
          defaultScreen: DefaultLandingScreen.community,
          initialCompanyTheme: CompanyThemeData.standard,
        ),
      ));

      expect(
        tester
            .widget<CurvedNavigationBar>(find.byType(CurvedNavigationBar))
            .index,
        4,
      );
    });

    testWidgets('renders AbundanceShellScreen for an Abundance company theme',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Setuppage(
          initialIndex: 3,
          initialCompanyTheme: _abundanceTheme(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AbundanceShellScreen), findsOneWidget);
      expect(
        tester
            .widget<AbundanceShellScreen>(find.byType(AbundanceShellScreen))
            .initialIndex,
        1,
      );
      // The standard chrome must be gone entirely, not merely hidden behind
      // the shell.
      expect(find.byType(CurvedNavigationBar), findsNothing);
    });

    testWidgets('matches on the company name alone, not just the code',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Setuppage(
          initialIndex: 3,
          initialCompanyTheme: _abundanceTheme(code: 'SOMETHINGELSE'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AbundanceShellScreen), findsOneWidget);
    });

    testWidgets(
        'keeps the pre-existing Scaffold + CurvedNavigationBar for the '
        'standard (non-Abundance) theme', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Setuppage(
          initialIndex: 3,
          initialCompanyTheme: CompanyThemeData.standard,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AbundanceShellScreen), findsNothing);
      expect(find.byType(CurvedNavigationBar), findsOneWidget);
      expect(find.byType(SetupBottomNavigationScope), findsOneWidget);
    });

    testWidgets('a near-miss company code does not trigger the shell',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Setuppage(
          initialIndex: 3,
          initialCompanyTheme: CompanyThemeData.standard.copyWith(
            companyCode: 'ABU15DNX',
            companyName: 'Not Abundance',
            isCompanyTheme: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AbundanceShellScreen), findsNothing);
      expect(find.byType(CurvedNavigationBar), findsOneWidget);
    });

    testWidgets('maps an unavailable saved default to Abundance Home',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Setuppage(
          defaultScreen: DefaultLandingScreen.community,
          initialCompanyTheme: _abundanceTheme(),
        ),
      ));

      final shell = tester.widget<AbundanceShellScreen>(
        find.byType(AbundanceShellScreen),
      );
      expect(shell.initialIndex, 0);
    });
  });

  group('CoachSetuppage', () {
    testWidgets('renders AbundanceShellScreen for an Abundance company theme',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CoachSetuppage(
          initialIndex: 3,
          initialCompanyTheme: _abundanceTheme(),
        ),
      ));
      await tester.pump();

      final shell = tester.widget<AbundanceShellScreen>(
        find.byType(AbundanceShellScreen),
      );

      // The coach shell's Home tab is CoachDashboardScreen, which touches
      // FirebaseFirestore.instance in a State field initializer and throws
      // with no live Firebase app. That is a pre-existing limitation already
      // documented in abundance_shell_screen_test.dart, and it is downstream
      // of the branch under test here — drain the errors it raises so this
      // test reports on the gating decision only.
      while (tester.takeException() != null) {}
      // The coach flavour of the shell, not the mentee one — this is the bit
      // that decides whether the Quests tab shows the coach roster or the
      // mentee hub.
      expect(shell.isCoach, isTrue);
      expect(find.byType(CurvedNavigationBar), findsNothing);
    });

    testWidgets(
        'keeps the pre-existing Scaffold + CurvedNavigationBar for the '
        'standard (non-Abundance) theme', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: CoachSetuppage(
          initialIndex: 3,
          initialCompanyTheme: CompanyThemeData.standard,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AbundanceShellScreen), findsNothing);
      expect(find.byType(CurvedNavigationBar), findsOneWidget);
      expect(find.byType(SetupBottomNavigationScope), findsOneWidget);
    });
  });
}
