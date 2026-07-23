import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/admin_dashboard.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/daily_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_dashboard_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/admin_access.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

enum AbundanceHubAudience {
  mentee,
  coach,
}

class AbundanceHubScreen extends StatefulWidget {
  const AbundanceHubScreen({
    super.key,
    this.initialCompanyTheme,
    this.audience = AbundanceHubAudience.mentee,
  });

  final CompanyThemeData? initialCompanyTheme;
  final AbundanceHubAudience audience;

  @override
  State<AbundanceHubScreen> createState() => _AbundanceHubScreenState();
}

class _AbundanceHubScreenState extends State<AbundanceHubScreen> {
  late final Future<_HubAccess> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _loadAccess();
  }

  Future<_HubAccess> _loadAccess() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return const _HubAccess(allowed: false, theme: CompanyThemeData.standard);
    }

    final uid = session.id.toString();
    final membershipData = await CompanyMembershipService.loadForUser(uid);
    final activeMembership = membershipData.activeMembership;
    final allowed = _isAbundance12Membership(activeMembership);
    final isAdmin = await AdminAccess.isAdmin();

    final theme = widget.initialCompanyTheme ??
        await CompanyThemeService.resolveForUser(uid);

    return _HubAccess(
      allowed: allowed,
      theme: theme,
      companyName: activeMembership?.name ?? theme.companyName,
      companyCode: activeMembership?.code ?? theme.companyCode,
      isAdmin: isAdmin,
    );
  }

  bool _isAbundance12Membership(CompanyMembership? membership) {
    if (membership == null) return false;
    return _isAbundance12Company(name: membership.name, code: membership.code);
  }

  bool _isAbundance12Company({
    String name = '',
    String code = '',
  }) {
    final normalizedName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedCode = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalizedName.contains('abundance12') ||
        (normalizedName.contains('abundance') && normalizedName.contains('12')) ||
        normalizedCode.contains('ABUNDANCE12') ||
        normalizedCode.contains('ABUND12') ||
        normalizedCode == 'A12' ||
        normalizedCode.startsWith('AB12');
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  List<_HubModule> _modules(BuildContext context, _HubAccess access) {
    final isCoach = widget.audience == AbundanceHubAudience.coach;
    final modules = <_HubModule>[
      _HubModule(
        title: 'My Goals',
        subtitle: 'Personal, professional and contribution goals.',
        icon: Icons.flag_outlined,
        onTap: () => Navigator.of(context).pushNamed('/goalsHub'),
      ),
      _HubModule(
        title: 'Core Tasks',
        subtitle: 'Daily discipline and streak tracking.',
        icon: Icons.checklist_rounded,
        onTap: () => _open(context, const UserProgressPage()),
      ),
      _HubModule(
        title: 'Daily Check-In',
        subtitle: 'Mood, reflection and the day’s pulse.',
        icon: Icons.edit_note_rounded,
        onTap: () => _open(context, const EmotionTrackerPage()),
      ),
      _HubModule(
        title: 'My Analytics',
        subtitle: 'A daily dashboard for momentum and habits.',
        icon: Icons.insights_rounded,
        onTap: () => _open(context, const DashboardScreen()),
      ),
      _HubModule(
        title: 'Leaderboards',
        subtitle: 'See how the company is moving.',
        icon: Icons.emoji_events_outlined,
        onTap: () => Navigator.of(context).pushNamed('/leaderboard'),
      ),
      _HubModule(
        title: 'Notes',
        subtitle: 'Private reflections and written follow-ups.',
        icon: Icons.sticky_note_2_outlined,
        onTap: () => Navigator.of(context).pushNamed('/notes'),
      ),
    ];

    if (isCoach) {
      modules.addAll([
        _HubModule(
          title: 'Coach Dashboard',
          subtitle: 'Coach view, councils and mentee support.',
          icon: Icons.groups_rounded,
          onTap: () => _open(context, const CoachDashboardScreen()),
        ),
        _HubModule(
          title: 'Coaches',
          subtitle: 'Open the coach directory and chat flow.',
          icon: Icons.forum_outlined,
          onTap: () => Navigator.of(context).pushNamed('/coachesScreen'),
        ),
      ]);
    }

    if (access.isAdmin) {
      modules.add(
        _HubModule(
          title: 'Admin Overview',
          subtitle: 'Manage the company from one place.',
          icon: Icons.admin_panel_settings_outlined,
          onTap: () => _open(context, const AdminDashboardScreen()),
        ),
      );
    }

    return modules;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HubAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final access = snapshot.data!;
        if (!access.allowed) {
          return Scaffold(
            backgroundColor: access.theme.backgroundColor,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      color: access.theme.surfaceColor,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 44,
                              color: access.theme.iconColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'A12 access only',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: access.theme.inkColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'This workspace is reserved for Abundance 12 company members.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: access.theme.mutedInkColor,
                                  ),
                            ),
                            if (Navigator.of(context).canPop()) ...[
                              const SizedBox(height: 20),
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Go back'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Theme(
          data: AppTheme.company(access.theme),
          child: Scaffold(
            backgroundColor: access.theme.backgroundColor,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1080
                      ? 3
                      : constraints.maxWidth >= 700
                          ? 2
                          : 1;

                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              access.theme.primaryColor,
                              access.theme.accentColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Pill(
                                  label: 'Abundance 12',
                                  background: Colors.white.withValues(alpha: 0.18),
                                  foreground: Colors.white,
                                ),
                                _Pill(
                                  label: widget.audience == AbundanceHubAudience.coach
                                      ? 'Coach mode'
                                      : 'Mentee mode',
                                  background: Colors.white.withValues(alpha: 0.18),
                                  foreground: Colors.white,
                                ),
                                _Pill(
                                  label: access.companyCode.isNotEmpty
                                      ? access.companyCode
                                      : access.companyName,
                                  background: Colors.white.withValues(alpha: 0.18),
                                  foreground: Colors.white,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Abundance Hub',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'The tracker workspace for ${access.companyName.isNotEmpty ? access.companyName : 'your company'}.\nGoals, check-ins, analytics and leadership tools live here.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    height: 1.45,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.audience == AbundanceHubAudience.coach
                            ? 'Coach tools'
                            : 'Member tools',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: access.theme.inkColor,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _modules(context, access).length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: columns == 1 ? 2.6 : 1.65,
                        ),
                        itemBuilder: (context, index) {
                          final module = _modules(context, access)[index];
                          return _ModuleCard(
                            theme: access.theme,
                            module: module,
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'This hub is locked to Abundance 12 company accounts.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: access.theme.mutedInkColor,
                            ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HubAccess {
  const _HubAccess({
    required this.allowed,
    required this.theme,
    this.companyName = '',
    this.companyCode = '',
    this.isAdmin = false,
  });

  final bool allowed;
  final CompanyThemeData theme;
  final String companyName;
  final String companyCode;
  final bool isAdmin;
}

class _HubModule {
  const _HubModule({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.theme,
    required this.module,
  });

  final CompanyThemeData theme;
  final _HubModule module;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surfaceColor,
      borderRadius: BorderRadius.circular(22),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: module.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.iconColor.withValues(alpha: 0.14),
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  module.icon,
                  color: theme.iconColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: theme.inkColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      module.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: theme.mutedInkColor,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Open',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: theme.iconColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
