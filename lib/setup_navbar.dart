import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/community/community_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class Setuppage extends StatefulWidget {
  const Setuppage({
    super.key,
    this.initialIndex = 2,
    this.initialCompanyTheme,
  });

  final int initialIndex;
  final CompanyThemeData? initialCompanyTheme;
  @override
  State<Setuppage> createState() => _SetuppageState();
}

class _SetuppageState extends State<Setuppage> {
  late int index;
  late CompanyThemeData _companyTheme;

  List<Widget> get _screens => [
        Meditation(),
        StepTracker(),
        DashboardScreen(initialCompanyTheme: _companyTheme),
        TodoList(),
        CommunityScreen(),
      ];

  final _titles = ["Meditation", "Step Tracker", "", "To Do List", "Community"];

  // Default (unselected) icons
  final List<Widget> _defaultIcons = [
    Icon(CupertinoIcons.suit_heart, size: 30),
    Icon(Icons.directions_walk_outlined, size: 30),
    Icon(Icons.dashboard_outlined, size: 30),
    Icon(CupertinoIcons.lightbulb, size: 30),
    Icon(Icons.edit_outlined, size: 30),
  ];

  // Selected (active) icons
  final List<Widget> _selectedIcons = [
    Icon(CupertinoIcons.suit_heart_fill, size: 30),
    Icon(Icons.directions_walk, size: 30),
    Icon(Icons.dashboard, size: 30),
    Icon(CupertinoIcons.lightbulb_fill, size: 30),
    Icon(Icons.edit, size: 30),
  ];

  @override
  void initState() {
    super.initState();
    _companyTheme = widget.initialCompanyTheme ??
        CompanyThemeService.cachedThemeForUser(
          AuthService.instance.currentUserId ?? '',
        ) ??
        CompanyThemeData.standard;
    index = widget.initialIndex.clamp(0, 4);
    _loadCompanyTheme();
  }

  @override
  void didUpdateWidget(covariant Setuppage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final updatedTheme = widget.initialCompanyTheme;
    if (updatedTheme != null && updatedTheme != oldWidget.initialCompanyTheme) {
      setState(() {
        _companyTheme = updatedTheme;
      });
    }
  }

  Future<void> _loadCompanyTheme() async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;
    try {
      final theme = await CompanyThemeService.resolveForUser(userId);
      if (!mounted) return;
      setState(() => _companyTheme = theme);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = _companyTheme;
    return Theme(
      data: AppTheme.company(theme),
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: index == 2
            ? null
            : AppBar(
                backgroundColor: theme.surfaceColor,
                surfaceTintColor: Colors.transparent,
                title: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _titles[index],
                    style: TextStyle(color: theme.inkColor),
                  ),
                ),
                actions: [
                  IconButton(
                    color: theme.iconColor,
                    icon: Icon(CupertinoIcons.line_horizontal_3, size: 28),
                    onPressed: () {
                      BottomSheetWidget.show(context);
                    },
                  ),
                ],
              ),
        body: SetupBottomNavigationScope(
          child: _screens[index],
        ),
        bottomNavigationBar: _ThemedBottomNavigationBar(
          theme: theme,
          index: index,
          defaultIcons: _defaultIcons,
          selectedIcons: _selectedIcons,
          onTap: (newIndex) {
            setState(() => index = newIndex);
          },
        ),
      ),
    );
  }
}

class CoachSetuppage extends StatefulWidget {
  const CoachSetuppage({
    super.key,
    this.initialIndex = 2,
    this.initialCompanyTheme,
  });

  final int initialIndex;
  final CompanyThemeData? initialCompanyTheme;

  @override
  State<CoachSetuppage> createState() => _CoachSetuppageState();
}

class _CoachSetuppageState extends State<CoachSetuppage> {
  late int index;
  late CompanyThemeData _companyTheme;

  List<Widget> get _screens => [
        Meditation(),
        StepTracker(),
        CoachDashboardScreen(),
        TodoList(),
        CommunityScreen(),
      ];

  final _titles = ["Meditation", "Step Tracker", "", "To Do List", "Community"];

  final List<Widget> _defaultIcons = [
    Icon(CupertinoIcons.suit_heart, size: 30),
    Icon(Icons.directions_walk_outlined, size: 30),
    Icon(Icons.dashboard_outlined, size: 30),
    Icon(CupertinoIcons.lightbulb, size: 30),
    Icon(Icons.edit_outlined, size: 30),
  ];

  final List<Widget> _selectedIcons = [
    Icon(CupertinoIcons.suit_heart_fill, size: 30),
    Icon(Icons.directions_walk, size: 30),
    Icon(Icons.dashboard, size: 30),
    Icon(CupertinoIcons.lightbulb_fill, size: 30),
    Icon(Icons.edit, size: 30),
  ];

  @override
  void initState() {
    super.initState();
    _companyTheme = widget.initialCompanyTheme ??
        CompanyThemeService.cachedThemeForUser(
          AuthService.instance.currentUserId ?? '',
        ) ??
        CompanyThemeData.standard;
    index = widget.initialIndex.clamp(0, 4);
    _loadCompanyTheme();
  }

  @override
  void didUpdateWidget(covariant CoachSetuppage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final updatedTheme = widget.initialCompanyTheme;
    if (updatedTheme != null && updatedTheme != oldWidget.initialCompanyTheme) {
      setState(() {
        _companyTheme = updatedTheme;
      });
    }
  }

  Future<void> _loadCompanyTheme() async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;
    try {
      final theme = await CompanyThemeService.resolveForUser(userId);
      if (!mounted) return;
      setState(() => _companyTheme = theme);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = _companyTheme;
    return Theme(
      data: AppTheme.company(theme),
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
        appBar: index == 2
            ? null
            : AppBar(
                backgroundColor: theme.surfaceColor,
                surfaceTintColor: Colors.transparent,
                title: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _titles[index],
                    style: TextStyle(color: theme.inkColor),
                  ),
                ),
                actions: [
                  IconButton(
                    color: theme.iconColor,
                    icon: Icon(CupertinoIcons.line_horizontal_3, size: 28),
                    onPressed: () {
                      BottomSheetWidget.show(context);
                    },
                  ),
                ],
              ),
        body: SetupBottomNavigationScope(
          child: _screens[index],
        ),
        bottomNavigationBar: _ThemedBottomNavigationBar(
          theme: theme,
          index: index,
          defaultIcons: _defaultIcons,
          selectedIcons: _selectedIcons,
          onTap: (newIndex) {
            setState(() => index = newIndex);
          },
        ),
      ),
    );
  }
}

class SetupBottomNavigationScope extends InheritedWidget {
  const SetupBottomNavigationScope({
    super.key,
    required super.child,
  });

  static bool hasBottomNavigation(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<SetupBottomNavigationScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(SetupBottomNavigationScope oldWidget) => false;
}

class _ThemedBottomNavigationBar extends StatelessWidget {
  const _ThemedBottomNavigationBar({
    required this.theme,
    required this.index,
    required this.defaultIcons,
    required this.selectedIcons,
    required this.onTap,
  });

  final CompanyThemeData theme;
  final int index;
  final List<Widget> defaultIcons;
  final List<Widget> selectedIcons;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return CurvedNavigationBar(
      height: 60,
      animationDuration: const Duration(milliseconds: 300),
      backgroundColor: theme.backgroundColor,
      buttonBackgroundColor:
          theme.isDark ? theme.primaryColor : const Color(0xFFEFD199),
      color: theme.isDark ? theme.surfaceColor : const Color(0xFF90A17D),
      index: index,
      items: List.generate(
        defaultIcons.length,
        (i) => IconTheme(
          data: IconThemeData(
            color: theme.isDark
                ? (i == index ? theme.backgroundColor : theme.primaryColor)
                : null,
          ),
          child: i == index ? selectedIcons[i] : defaultIcons[i],
        ),
      ),
      onTap: onTap,
    );
  }
}
