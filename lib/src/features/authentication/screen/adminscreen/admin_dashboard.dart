import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/addcoach.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/admin_daily_tracker_overview.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/admin_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/manage_companies.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/viewalluser.dart';
import 'package:selfcare_projects/src/services/admin_access.dart';
import 'package:selfcare_projects/src/services/admin_user_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

const Color _primary = Color(0xFF6F7B5C);
const Color _surface = Color(0xFFFFFFFF);
const Color _ink = Color(0xFF24311F);
const Color _mutedInk = Color(0xFF6B7165);
const Color _softTeal = Color(0xFFE8F6F3);
const Color _border = Color(0xFFE0E5D9);
const Color primary = _primary;
const Color surface = _surface;
const Color ink = _ink;
const Color mutedInk = _mutedInk;
const Color softTeal = _softTeal;
const Color border = _border;

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(builder: (context) => _buildContent(context)),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<bool>(
      future: AdminAccess.isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data != true) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      CupertinoIcons.lock_shield_fill,
                      color: Color(0xFFD95555),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Access Denied',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This area is only available to admins.',
                    style: TextStyle(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return const _AdminDashboardContent();
      },
    );
  }
}

class _AdminDashboardContent extends StatefulWidget {
  const _AdminDashboardContent();

  @override
  State<_AdminDashboardContent> createState() => _AdminDashboardContentState();
}

class _AdminDashboardContentState extends State<_AdminDashboardContent> {
  late Future<_AdminDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboardData();
  }

  Future<_AdminDashboardData> _loadDashboardData() async {
    final users = await AdminUserApiService.instance.fetchUsers();

    var adminCount = 0;
    var coachUserCount = 0;
    final companyUserCounts = <String, _CompanyUserCount>{};

    for (final user in users) {
      final role = user.role.trim().toLowerCase();
      final isAdmin = user.isAdmin || role == 'admin';
      final isCoach = user.isCoach || role == 'coach';
      if (isAdmin) adminCount++;
      if (isCoach) coachUserCount++;

      final companyName = user.companyName?.trim() ?? '';
      final companyCode = user.companyCode?.trim().toUpperCase() ?? '';
      final key = _companyKey(companyCode, companyName);
      final existing = companyUserCounts[key];
      companyUserCounts[key] = _CompanyUserCount(
        id: key,
        name: companyName.isNotEmpty
            ? companyName
            : companyCode.isNotEmpty
                ? companyCode
                : 'No company assigned',
        code: companyCode,
        count: (existing?.count ?? 0) + 1,
      );
    }

    final companyUsers = companyUserCounts.values.toList()
      ..sort((a, b) {
        final countSort = b.count.compareTo(a.count);
        if (countSort != 0) return countSort;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final recentUsers = [...users]
      ..sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));

    final recentCompanies = companyUsers
        .where((company) => company.id != 'No company assigned')
        .take(5)
        .map((company) {
          return _RecentCompany(
            name: company.name,
            code: company.code,
          );
        })
        .toList();

    return _AdminDashboardData(
      userCount: users.length,
      coachCount: coachUserCount,
      adminCount: adminCount,
      companyCount: companyUsers
          .where((company) => company.id != 'No company assigned')
          .length,
      recentUsers: recentUsers
          .take(5)
          .map((user) => _RecentUser.fromApiUser(user))
          .toList(),
      recentCompanies: recentCompanies,
      companyUsers: companyUsers,
    );
  }

  void _refresh() {
    setState(() {
      _dashboardFuture = _loadDashboardData();
    });
  }

  String _companyKey(String companyCode, String companyName) {
    if (companyCode.isNotEmpty) return companyCode;
    if (companyName.isNotEmpty) return companyName;
    return 'No company assigned';
  }

  DateTime _sortDate(AdminUserApiUser user) {
    return user.updatedAt ?? user.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _copyCompanyCode(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Copied company code: $code')),
    );
  }

  void _openCoachCompanyManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddCoachScreen()),
    ).then((_) => _refresh());
  }

  void _openCompanyManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ManageCompaniesScreen()),
    ).then((_) => _refresh());
  }

  void _openRoleManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ManageCoachesScreen()),
    ).then((_) => _refresh());
  }

  void _openAdminProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminProfileScreen()),
    ).then((_) => _refresh());
  }

  void _openDailyTrackerOverview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminDailyTrackerOverviewScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surface,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'Admin Dashboard',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: _openAdminProfile,
            icon: Icon(
              CupertinoIcons.person_crop_circle,
              color: theme.colorScheme.onSurface,
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: Icon(
              CupertinoIcons.arrow_clockwise,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_AdminDashboardData>(
          future: _dashboardFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _DashboardMessage(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'Dashboard could not load',
                body: snapshot.error.toString(),
                action: TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(CupertinoIcons.arrow_clockwise),
                  label: const Text('Try again'),
                ),
              );
            }

            final data = snapshot.data ?? _AdminDashboardData.empty();

            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildStatsGrid(data),
                  const SizedBox(height: 16),
                  _buildCompanyUsers(data.companyUsers),
                  const SizedBox(height: 16),
                  _buildQuickActions(),
                  const SizedBox(height: 16),
                  _buildCompanyCodes(data.recentCompanies),
                  const SizedBox(height: 16),
                  _buildRecentUsers(data.recentUsers),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              CupertinoIcons.chart_bar_alt_fill,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'InnerU administration',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accounts, roles, and company access codes.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.3,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(_AdminDashboardData data) {
    final theme = Theme.of(context);
    final stats = [
      _DashboardStat(
        label: 'Users',
        value: data.userCount,
        icon: CupertinoIcons.person_3_fill,
        color: theme.colorScheme.onSurface,
      ),
      _DashboardStat(
        label: 'Coaches',
        value: data.coachCount,
        icon: CupertinoIcons.person_2_fill,
        color: const Color(0xFF90A17D),
      ),
      _DashboardStat(
        label: 'Admins',
        value: data.adminCount,
        icon: CupertinoIcons.shield_fill,
        color: const Color(0xFF6D849A),
      ),
      _DashboardStat(
        label: 'Companies',
        value: data.companyCount,
        icon: CupertinoIcons.building_2_fill,
        color: const Color(0xFFCE8F5A),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 620;
        final columns = isWide ? 4 : 2;
        final spacing = isWide ? 8.0 : 10.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 10,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: itemWidth,
                  child: _StatTile(stat: stat),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return _DashboardSection(
      title: 'Quick Actions',
      child: Column(
        children: [
          _ActionTile(
            icon: CupertinoIcons.person_crop_circle_badge_plus,
            title: 'Manage users and roles',
            subtitle: 'Promote users into coaches or admins.',
            onTap: _openRoleManager,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: CupertinoIcons.building_2_fill,
            title: 'Manage companies',
            subtitle: 'Edit names, themes, logos, codes, and loading media.',
            onTap: _openCompanyManager,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: CupertinoIcons.person_2_fill,
            title: 'Manage coaches',
            subtitle: 'View coach profiles and create your coach profile.',
            onTap: _openCoachCompanyManager,
          ),
          const Divider(height: 1),
          _ActionTile(
            icon: CupertinoIcons.checkmark_seal_fill,
            title: 'Daily tracker overview',
            subtitle: "Monitor every user's daily checklist progress.",
            onTap: _openDailyTrackerOverview,
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyUsers(List<_CompanyUserCount> companies) {
    return _DashboardSection(
      title: 'Users by Company',
      child: companies.isEmpty
          ? const _EmptyListText('No company users found.')
          : Column(
              children: companies.map((company) {
                final isLast = company == companies.last;
                return Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _softTeal,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          CupertinoIcons.building_2_fill,
                          color: _ink,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        company.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        company.code.isEmpty ? 'No code' : company.code,
                        style: const TextStyle(color: _mutedInk),
                      ),
                      trailing: Text(
                        company.count.toString(),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!isLast) const Divider(height: 1),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildCompanyCodes(List<_RecentCompany> companies) {
    return _DashboardSection(
      title: 'Company Codes',
      trailing: TextButton(
        onPressed: _openCompanyManager,
        child: const Text(
          'Manage',
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: companies.isEmpty
          ? const _EmptyListText('No company codes yet.')
          : Column(
              children: companies.map((company) {
                final isLast = company == companies.last;
                return Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        company.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        company.code,
                        style: const TextStyle(
                          color: mutedInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Copy code',
                        onPressed: () => _copyCompanyCode(company.code),
                        icon: const Icon(CupertinoIcons.doc_on_doc),
                      ),
                    ),
                    if (!isLast) const Divider(height: 1),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRecentUsers(List<_RecentUser> users) {
    return _DashboardSection(
      title: 'Recent Accounts',
      trailing: TextButton(
        onPressed: _openRoleManager,
        child: const Text(
          'View all',
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: users.isEmpty
          ? const _EmptyListText('No recent users found.')
          : Column(
              children: users.map((user) {
                final isLast = user == users.last;
                return Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: softTeal,
                        child: Text(
                          user.initials,
                          style: const TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        '${user.email} • ${user.companyLabel}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: mutedInk,
                        ),
                      ),
                      trailing: _RoleBadge(role: user.role),
                    ),
                    if (!isLast) const Divider(height: 1),
                  ],
                );
              }).toList(),
            ),
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _DashboardStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: softTeal,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(stat.icon, color: stat.color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: mutedInk,
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: softTeal,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: ink),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: mutedInk,
          height: 1.25,
        ),
      ),
      trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
      onTap: onTap,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4F2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        role,
        style: const TextStyle(
          color: ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: mutedInk,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyListText extends StatelessWidget {
  const _EmptyListText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(color: mutedInk),
      ),
    );
  }
}

class _AdminDashboardData {
  const _AdminDashboardData({
    required this.userCount,
    required this.coachCount,
    required this.adminCount,
    required this.companyCount,
    required this.recentUsers,
    required this.recentCompanies,
    required this.companyUsers,
  });

  factory _AdminDashboardData.empty() {
    return const _AdminDashboardData(
      userCount: 0,
      coachCount: 0,
      adminCount: 0,
      companyCount: 0,
      recentUsers: [],
      recentCompanies: [],
      companyUsers: [],
    );
  }

  final int userCount;
  final int coachCount;
  final int adminCount;
  final int companyCount;
  final List<_RecentUser> recentUsers;
  final List<_RecentCompany> recentCompanies;
  final List<_CompanyUserCount> companyUsers;
}

class _DashboardStat {
  const _DashboardStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _RecentUser {
  const _RecentUser({
    required this.name,
    required this.email,
    required this.role,
    required this.companyName,
    required this.companyCode,
  });

  factory _RecentUser.fromApiUser(AdminUserApiUser user) {
    return _RecentUser(
      name: user.name.isNotEmpty ? user.name : 'Unknown User',
      email: user.email.isNotEmpty ? user.email : 'No email',
      role: user.role.isNotEmpty ? user.role : 'user',
      companyName: user.companyName?.isNotEmpty == true ? user.companyName! : '',
      companyCode: user.companyCode?.isNotEmpty == true ? user.companyCode! : '',
    );
  }

  final String name;
  final String email;
  final String role;
  final String companyName;
  final String companyCode;

  String get companyLabel {
    if (companyName.isNotEmpty && companyCode.isNotEmpty) {
      return '$companyName ($companyCode)';
    }
    if (companyName.isNotEmpty) return companyName;
    if (companyCode.isNotEmpty) return companyCode;
    return 'No company';
  }

  String get initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _CompanyUserCount {
  const _CompanyUserCount({
    required this.id,
    required this.name,
    required this.code,
    required this.count,
  });

  final String id;
  final String name;
  final String code;
  final int count;
}

class _RecentCompany {
  const _RecentCompany({
    required this.name,
    required this.code,
  });

  final String name;
  final String code;
}
