import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FastingReportScreen extends StatelessWidget {
  const FastingReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in to view fasting reports.'),
        ),
      );
    }

    final historyRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('wellness')
        .doc('fasting')
        .collection('history');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F0),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Fasting Reports'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: historyRef.orderBy('finishedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final reports = _buildReports(docs);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _ReportHeroCard(reports: reports),
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
              _RecentFastList(docs: docs.take(12).toList()),
            ],
          );
        },
      ),
    );
  }
}

_ReportBundle _buildReports(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final now = DateTime.now();
  return _ReportBundle(
    weekly: _summarizePeriod(
      docs,
      now.subtract(const Duration(days: 7)),
      now,
    ),
    monthly: _summarizePeriod(
      docs,
      now.subtract(const Duration(days: 30)),
      now,
    ),
    yearly: _summarizePeriod(
      docs,
      now.subtract(const Duration(days: 365)),
      now,
    ),
  );
}

_PeriodReport _summarizePeriod(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DateTime start,
  DateTime end,
) {
  final filtered = docs.where((doc) {
    final finishedAt = (doc.data()['finishedAt'] as Timestamp?)?.toDate();
    if (finishedAt == null) return false;
    return !finishedAt.isBefore(start) && !finishedAt.isAfter(end);
  }).toList();

  final completedFasts = filtered.length;
  final totalHours = filtered.fold<double>(
    0,
    (sum, doc) => sum + ((doc.data()['completedHours'] as num?)?.toDouble() ?? 0),
  );
  final goalHits = filtered.where((doc) {
    return (doc.data()['completedTarget'] as bool?) ?? false;
  }).length;
  final longestHours = filtered.fold<double>(
    0,
    (maxValue, doc) {
      final hours = (doc.data()['completedHours'] as num?)?.toDouble() ?? 0;
      return hours > maxValue ? hours : maxValue;
    },
  );
  final double averageHours =
      completedFasts == 0 ? 0.0 : totalHours / completedFasts;
  final double hitRate =
      completedFasts == 0 ? 0.0 : goalHits / completedFasts;

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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF3F5),
            Color(0xFFFEEDE2),
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
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
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
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
            color: Colors.black.withOpacity(0.04),
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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
            style: const TextStyle(fontWeight: FontWeight.w700),
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
  const _RecentFastList({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          if (docs.isEmpty)
            const Text(
              'No completed fasting sessions yet.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ...docs.map((doc) {
              final data = doc.data();
              final completedTarget =
                  (data['completedTarget'] as bool?) ?? false;
              final completedHours =
                  (data['completedHours'] as num?)?.toDouble() ?? 0;
              final targetHours = (data['targetHours'] as num?)?.toInt() ?? 0;
              final finishedAt = (data['finishedAt'] as Timestamp?)?.toDate();

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
