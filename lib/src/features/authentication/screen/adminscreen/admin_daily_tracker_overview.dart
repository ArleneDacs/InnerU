import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/admin_access.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

const List<String> _dailyTrackerTaskLabels = [
  'Call',
  'Steps',
  'Exercise',
  'Meditation',
  'Learning',
  'Add Value',
];

class AdminDailyTrackerOverviewScreen extends StatelessWidget {
  const AdminDailyTrackerOverviewScreen({super.key});

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
            appBar: AppBar(title: const Text('Daily Tracker Overview')),
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

        return const _AdminDailyTrackerOverviewContent();
      },
    );
  }
}

class _AdminDailyTrackerOverviewContent extends StatefulWidget {
  const _AdminDailyTrackerOverviewContent();

  @override
  State<_AdminDailyTrackerOverviewContent> createState() =>
      _AdminDailyTrackerOverviewContentState();
}

class _AdminDailyTrackerOverviewContentState
    extends State<_AdminDailyTrackerOverviewContent> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  List<Map<String, dynamic>> _users = const [];
  String _todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final Set<String> _expandedUserIds = {};

  int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is bool) return value ? 1 : 0;
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _monthKey =>
      '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await DailyTrackerApiService.instance
          .fetchAdminOverview(month: _monthKey);
      final users = (result['users'] as List).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['username']?.toString() ?? '')
            .toLowerCase()
            .compareTo((b['username']?.toString() ?? '').toLowerCase()));

      if (!mounted) return;
      setState(() {
        _users = users;
        final date = result['date']?.toString() ?? '';
        if (date.isNotEmpty) _todayKey = date;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load daily tracker data. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    var month = _selectedMonth + delta;
    var year = _selectedYear;
    if (month < 1) {
      month = 12;
      year--;
    } else if (month > 12) {
      month = 1;
      year++;
    }
    setState(() {
      _selectedMonth = month;
      _selectedYear = year;
    });
    _load();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((user) {
      final username = (user['username']?.toString() ?? '').toLowerCase();
      final email = (user['email']?.toString() ?? '').toLowerCase();
      final company =
          (user['companyName']?.toString() ?? '').toLowerCase();
      return username.contains(query) ||
          email.contains(query) ||
          company.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredUsers;
    final usersWithActivityToday = _users
        .where((user) => _readInt(user['todayCompletedCount']) > 0)
        .length;
    final usersFullyDoneToday = _users.where((user) {
      final completed = _readInt(user['todayCompletedCount']);
      final total = _readInt(user['todayTaskCount']);
      return total > 0 && completed >= total;
    }).length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          'Daily Tracker Overview',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _load,
            icon: Icon(CupertinoIcons.refresh, color: theme.colorScheme.onSurface),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSummaryRow(
                        theme,
                        totalUsers: _users.length,
                        activeToday: usersWithActivityToday,
                        fullyDoneToday: usersFullyDoneToday,
                      ),
                      const SizedBox(height: 16),
                      _buildMonthSelector(theme),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, or company',
                          prefixIcon: const Icon(CupertinoIcons.search),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              _users.isEmpty
                                  ? 'No users found.'
                                  : 'No users match "$_searchQuery".',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        )
                      else
                        ...filtered.map((user) => _buildUserCard(theme, user)),
                    ],
                  ),
      ),
    );
  }

  Widget _buildSummaryRow(
    ThemeData theme, {
    required int totalUsers,
    required int activeToday,
    required int fullyDoneToday,
  }) {
    final stats = [
      ('Total users', totalUsers.toString(), CupertinoIcons.person_2_fill,
          const Color(0xFF6D849A)),
      ('Active today', activeToday.toString(),
          CupertinoIcons.checkmark_alt_circle_fill, const Color(0xFF90A17D)),
      ('Fully done today', fullyDoneToday.toString(),
          CupertinoIcons.star_fill, const Color(0xFFCE8F5A)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 1;
        final spacing = 10.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: stats.map((stat) {
            final (label, value, icon, color) = stat;
            return SizedBox(
              width: itemWidth,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMonthSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(CupertinoIcons.left_chevron,
                color: theme.colorScheme.onSurface),
            onPressed: () => _changeMonth(-1),
          ),
          Text(
            DateFormat('MMMM yyyy')
                .format(DateTime(_selectedYear, _selectedMonth)),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          IconButton(
            icon: Icon(CupertinoIcons.right_chevron,
                color: theme.colorScheme.onSurface),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(ThemeData theme, Map<String, dynamic> user) {
    final userId = user['userId']?.toString() ?? '';
    final username = (user['username']?.toString().trim().isNotEmpty ?? false)
        ? user['username'].toString()
        : 'Unknown';
    final email = user['email']?.toString() ?? '';
    final companyName = user['companyName']?.toString() ?? '';
    final completed = _readInt(user['todayCompletedCount']);
    final total = _readInt(
      user['todayTaskCount'],
      fallback: _dailyTrackerTaskLabels.length,
    );
    final isFullyDone = total > 0 && completed >= total;
    final hasActivity = completed > 0;
    final badgeColor = isFullyDone
        ? const Color(0xFF90A17D)
        : hasActivity
            ? const Color(0xFFCE8F5A)
            : theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final isExpanded = _expandedUserIds.contains(userId);

    return Card(
      color: theme.colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: ExpansionTile(
        key: PageStorageKey(userId),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedUserIds.add(userId);
            } else {
              _expandedUserIds.remove(userId);
            }
          });
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(
          username,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          [
            if (email.isNotEmpty) email,
            if (companyName.isNotEmpty) companyName,
          ].join(' · '),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$completed/$total today',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: badgeColor,
            ),
          ),
        ),
        children: [
          _buildTodayChecklist(theme, user),
          _buildMonthCalendar(theme, user),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Map<String, bool> _tasksForDate(Map<String, dynamic> user, String dateKey) {
    final progress = user['progress'];
    if (progress is Map && progress[dateKey] is Map) {
      final raw = Map<String, dynamic>.from(progress[dateKey] as Map);
      return {
        for (final label in _dailyTrackerTaskLabels)
          label: _readBool(raw[label] ?? raw[label.toLowerCase()]),
      };
    }
    return {for (final label in _dailyTrackerTaskLabels) label: false};
  }

  Widget _buildTodayChecklist(ThemeData theme, Map<String, dynamic> user) {
    final tasks = _tasksForDate(user, _todayKey);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: tasks.entries.map((entry) {
          return CheckboxListTile(
            dense: true,
            title: Text(
              entry.key,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
            value: entry.value,
            onChanged: null,
            activeColor: theme.colorScheme.primary,
            controlAffinity: ListTileControlAffinity.leading,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMonthCalendar(ThemeData theme, Map<String, dynamic> user) {
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final firstDayOfWeek =
        DateTime(_selectedYear, _selectedMonth, 1).weekday % 7;
    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final progress = user['progress'];
    final trackedDates = progress is Map
        ? progress.keys.map((key) => key.toString()).toSet()
        : <String>{};
    final cells = <Widget>[];
    final totalCells = daysInMonth + firstDayOfWeek;
    const cellCount = 7;

    for (var i = 0; i < totalCells; i++) {
      if (i < firstDayOfWeek) {
        cells.add(const SizedBox.shrink());
        continue;
      }

      final day = i - firstDayOfWeek + 1;
      final dateKey =
          '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final tracked = trackedDates.contains(dateKey);
      final tasks = tracked ? _tasksForDate(user, dateKey) : null;
      final completedCount =
          tasks?.values.where((done) => done).length ?? 0;
      final isFull = tasks != null &&
          completedCount >= _dailyTrackerTaskLabels.length;

      cells.add(
        Padding(
          padding: const EdgeInsets.all(1.5),
          child: InkWell(
            onTap: tracked ? () => _showDayDetails(context, dateKey, user) : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: !tracked
                    ? Colors.transparent
                    : isFull
                        ? const Color(0xFF90A17D).withValues(alpha: 0.55)
                        : const Color(0xFFCE8F5A).withValues(alpha: 0.4),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.16),
                ),
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    while (cells.length % cellCount != 0) {
      cells.add(const SizedBox.shrink());
    }

    final rows = <TableRow>[];
    for (var i = 0; i < cells.length; i += cellCount) {
      rows.add(TableRow(children: cells.sublist(i, i + cellCount)));
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: weekdays
                .map((day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                ))
                .toList(),
          ),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
              3: FlexColumnWidth(),
              4: FlexColumnWidth(),
              5: FlexColumnWidth(),
              6: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows,
          ),
        ],
      ),
    );
  }

  void _showDayDetails(
    BuildContext context,
    String dateKey,
    Map<String, dynamic> user,
  ) {
    final tasks = _tasksForDate(user, dateKey);
    final completedCount = tasks.values.where((done) => done).length;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dateKey),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$completedCount/${_dailyTrackerTaskLabels.length} tasks completed',
              ),
              const SizedBox(height: 12),
              ...tasks.entries.map(
                (entry) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key),
                  value: entry.value,
                  onChanged: null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
