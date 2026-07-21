import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/fasting_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class FastingReportScreen extends StatefulWidget {
  const FastingReportScreen({super.key});

  @override
  State<FastingReportScreen> createState() => _FastingReportScreenState();
}

class _FastingReportScreenState extends State<FastingReportScreen> {
  final FastingApiService _fastingApi = FastingApiService.instance;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _fastingApi.fetchHistory(limit: 365);
  }

  Future<void> _refresh() async {
    setState(() {
      _historyFuture = _fastingApi.fetchHistory(limit: 365);
    });
    await _historyFuture;
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in to view fasting reports.'),
        ),
      );
    }

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);

              return Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                appBar: AppBar(
                  backgroundColor: companyTheme.surfaceColor,
                  foregroundColor: companyTheme.inkColor,
                  iconTheme: IconThemeData(color: companyTheme.inkColor),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    'Fasting Reports',
                    style: TextStyle(
                      color: companyTheme.inkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                body: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _historyFuture,
                  builder: (context, snapshot) {
                    final history = snapshot.data ?? <Map<String, dynamic>>[];
                    final reports = _buildReports(history);
                    final dailyHours = _buildDailyHours(history);

                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        children: [
                          _ReportHeroCard(reports: reports),
                          const SizedBox(height: 18),
                          _CalendarBarCard(dailyHours: dailyHours),
                          const SizedBox(height: 18),
                          _PeriodReportCard(
                            title: 'Weekly',
                            subtitle: 'Your last 7 days of fasting',
                            report: reports.weekly,
                            accentColor: const Color(0xFFFF4663),
                          ),
                          const SizedBox(height: 16),
                          _PeriodReportCard(
                            title: 'Monthly',
                            subtitle: 'Your last 30 days of fasting',
                            report: reports.monthly,
                            accentColor: const Color(0xFFFF9A31),
                          ),
                          const SizedBox(height: 16),
                          _PeriodReportCard(
                            title: 'Yearly',
                            subtitle: 'Your last 365 days of fasting',
                            report: reports.yearly,
                            accentColor: const Color(0xFF6B8BFF),
                          ),
                          const SizedBox(height: 18),
                          _RecentFastList(history: history.take(12).toList()),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

_ReportBundle _buildReports(
    List<Map<String, dynamic>> history) {
  final now = DateTime.now();
  return _ReportBundle(
    weekly: _summarizePeriod(
      history,
      now.subtract(const Duration(days: 7)),
      now,
    ),
    monthly: _summarizePeriod(
      history,
      now.subtract(const Duration(days: 30)),
      now,
    ),
    yearly: _summarizePeriod(
      history,
      now.subtract(const Duration(days: 365)),
      now,
    ),
  );
}

Map<String, double> _buildDailyHours(
  List<Map<String, dynamic>> history,
) {
  final totals = <String, double>{};

  for (final data in history) {
    final finishedAt = DateTime.tryParse(data['finishedAt'].toString());
    if (finishedAt == null) continue;

    final key = DateFormat('yyyy-MM-dd').format(finishedAt);
    final hours = (data['completedHours'] as num?)?.toDouble() ?? 0;
    totals.update(key, (value) => value + hours, ifAbsent: () => hours);
  }

  return totals;
}

_PeriodReport _summarizePeriod(
  List<Map<String, dynamic>> history,
  DateTime start,
  DateTime end,
) {
  final filtered = history.where((data) {
    final finishedAt = DateTime.tryParse(data['finishedAt'].toString());
    if (finishedAt == null) return false;
    return !finishedAt.isBefore(start) && !finishedAt.isAfter(end);
  }).toList();

  final completedFasts = filtered.length;
  final totalHours = filtered.fold<double>(
    0,
    (sum, data) => sum + ((data['completedHours'] as num?)?.toDouble() ?? 0),
  );
  final goalHits = filtered.where((data) {
    return data['completedTarget'] == true;
  }).length;
  final longestHours = filtered.fold<double>(
    0,
    (maxValue, data) {
      final hours = (data['completedHours'] as num?)?.toDouble() ?? 0;
      return hours > maxValue ? hours : maxValue;
    },
  );
  final double averageHours =
      completedFasts == 0 ? 0.0 : totalHours / completedFasts;
  final double hitRate = completedFasts == 0 ? 0.0 : goalHits / completedFasts;

  return _PeriodReport(
    completedFasts: completedFasts,
    totalHours: totalHours,
    averageHours: averageHours,
    longestHours: longestHours,
    goalHits: goalHits,
    hitRate: hitRate,
  );
}

class _ReportBundle {
  const _ReportBundle({
    required this.weekly,
    required this.monthly,
    required this.yearly,
  });

  final _PeriodReport weekly;
  final _PeriodReport monthly;
  final _PeriodReport yearly;
}

class _PeriodReport {
  const _PeriodReport({
    required this.completedFasts,
    required this.totalHours,
    required this.averageHours,
    required this.longestHours,
    required this.goalHits,
    required this.hitRate,
  });

  final int completedFasts;
  final double totalHours;
  final double averageHours;
  final double longestHours;
  final int goalHits;
  final double hitRate;
}

class _ReportHeroCard extends StatelessWidget {
  const _ReportHeroCard({required this.reports});

  final _ReportBundle reports;

  @override
  Widget build(BuildContext context) {
    final totalFasts = reports.yearly.completedFasts;
    final totalHours = reports.yearly.totalHours;
    final yearlyHitRate = (reports.yearly.hitRate * 100).round();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.16),
            theme.colorScheme.secondary.withValues(alpha: 0.14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Fasting Overview',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'A quick snapshot of how consistent your fasting routine has been.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 150,
                child: _overviewTile(
                  'Yearly fasts',
                  '$totalFasts',
                  const Color(0xFFFF4663),
                ),
              ),
              SizedBox(
                width: 150,
                child: _overviewTile(
                  'Hours fasted',
                  _hoursLabel(totalHours),
                  const Color(0xFFFF9A31),
                ),
              ),
              SizedBox(
                width: 150,
                child: _overviewTile(
                  'Goal hit rate',
                  '$yearlyHitRate%',
                  const Color(0xFF6B8BFF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewTile(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _CalendarBarCard extends StatelessWidget {
  const _CalendarBarCard({required this.dailyHours});

  final Map<String, double> dailyHours;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final leadingDays = monthStart.weekday % 7;
    final totalCells = leadingDays + monthEnd.day;
    final trailingDays = (7 - (totalCells % 7)) % 7;
    final cells = totalCells + trailingDays;
    final last7Days = List.generate(7, (index) {
      final date = DateTime(now.year, now.month, now.day - (6 - index));
      final key = DateFormat('yyyy-MM-dd').format(date);
      return _BarPoint(
        label: DateFormat('E').format(date).substring(0, 1),
        value: dailyHours[key] ?? 0,
      );
    });
    final maxBarValue = last7Days.fold<double>(
      0,
      (maxValue, point) => point.value > maxValue ? point.value : maxValue,
    );
    const weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final isSmallScreen = MediaQuery.of(context).size.height < 760;

    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calendar Report',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat('MMMM yyyy').format(now),
            style: const TextStyle(color: Colors.black54),
          ),
          SizedBox(height: isSmallScreen ? 14 : 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth - (6 * 8)) / 7;
              final compact = cellWidth < 42 || isSmallScreen;
              final childAspectRatio = compact ? 0.64 : 0.84;

              return Column(
                children: [
                  Row(
                    children: weekdayLabels.map((label) {
                      return Expanded(
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: Colors.black45,
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 11 : 12,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  GridView.builder(
                    itemCount: cells,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: childAspectRatio,
                    ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leadingDays + 1;
                      if (dayNumber <= 0 || dayNumber > monthEnd.day) {
                        return const SizedBox.shrink();
                      }

                      final date = DateTime(now.year, now.month, dayNumber);
                      final key = DateFormat('yyyy-MM-dd').format(date);
                      final hours = dailyHours[key] ?? 0;
                      final intensity =
                          hours <= 0 ? 0.0 : (hours / 20).clamp(0.15, 1.0);
                      final isToday = date.year == now.year &&
                          date.month == now.month &&
                          date.day == now.day;

                      return Container(
                        decoration: BoxDecoration(
                          color: hours <= 0
                              ? const Color(0xFFF7F3EF)
                              : Color.lerp(
                                  const Color(0xFFFFEEF2),
                                  const Color(0xFFFF4663),
                                  intensity,
                                ),
                          borderRadius:
                              BorderRadius.circular(compact ? 12 : 16),
                          border: isToday
                              ? Border.all(
                                  color: const Color(0xFF2F2B29),
                                  width: 1.2,
                                )
                              : null,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 4 : 8,
                          vertical: compact ? 3 : 7,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: compact ? 11 : 14,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: hours > 0.5
                                    ? Colors.white
                                    : const Color(0xFF383230),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hours > 0
                                    ? '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)}h'
                                    : '-',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: compact ? 8 : 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  color: hours > 0.5
                                      ? Colors.white
                                      : Colors.black45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          SizedBox(height: isSmallScreen ? 16 : 20),
          const Text(
            'Last 7 Days',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          SizedBox(height: isSmallScreen ? 8 : 12),
          SizedBox(
            height: isSmallScreen ? 142 : 158,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: last7Days.map((point) {
                final barHeight = maxBarValue <= 0
                    ? 8.0
                    : (point.value / maxBarValue) * (isSmallScreen ? 82 : 96);
                return Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: isSmallScreen ? 2 : 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          point.value <= 0 ? '0h' : _hoursLabel(point.value),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 9 : 10,
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 4 : 6),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width: isSmallScreen ? 22 : 24,
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Color(0xFFFF4663),
                                Color(0xFFFF9A87),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 4 : 6),
                        Text(
                          point.label,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarPoint {
  const _BarPoint({
    required this.label,
    required this.value,
  });

  final String label;
  final double value;
}

class _PeriodReportCard extends StatelessWidget {
  const _PeriodReportCard({
    required this.title,
    required this.subtitle,
    required this.report,
    required this.accentColor,
  });

  final String title;
  final String subtitle;
  final _PeriodReport report;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final hitRatePercent = (report.hitRate * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2E2A28),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _metricBox('Completed', '${report.completedFasts}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricBox('Goal hits', '${report.goalHits}'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metricBox('Avg fast', _hoursLabel(report.averageHours)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricBox('Longest', _hoursLabel(report.longestHours)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Goal completion $hitRatePercent%',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: report.hitRate.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: const Color(0xFFF2ECE7),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5F0),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _RecentFastList extends StatelessWidget {
  const _RecentFastList({required this.history});

  final List<Map<String, dynamic>> history;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Sessions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 14),
          if (history.isEmpty)
            const Text(
              'No completed fasting sessions yet.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ...history.map((data) {
              final completedTarget = data['completedTarget'] == true;
              final completedHours =
                  (data['completedHours'] as num?)?.toDouble() ?? 0;
              final targetHours = (data['targetHours'] as num?)?.toInt() ?? 0;
              final finishedAt = DateTime.tryParse(
                data['finishedAt']?.toString() ?? '',
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F5F0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      completedTarget
                          ? Icons.check_circle_rounded
                          : Icons.timelapse_rounded,
                      color: completedTarget
                          ? const Color(0xFFFF4663)
                          : const Color(0xFFFF9A31),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_hoursLabel(completedHours)} completed',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E2A28),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${finishedAt == null ? 'Unknown date' : DateFormat('MMM d, yyyy • hh:mm a').format(finishedAt)} • Goal ${targetHours}h',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

String _hoursLabel(double value) {
  final formatted = value.toStringAsFixed(1);
  return formatted.endsWith('.0') ? '${value.toInt()}h' : '${formatted}h';
}
