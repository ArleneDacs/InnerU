import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/daily_check_in_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';

class EmotionTrackerPage extends StatefulWidget {
  const EmotionTrackerPage({super.key});

  @override
  State<EmotionTrackerPage> createState() => _EmotionTrackerPageState();
}

class _EmotionTrackerPageState extends State<EmotionTrackerPage> {
  final EmotionService _emotionService = EmotionService();
  final DailyCheckInApiService _dailyCheckInService =
      DailyCheckInApiService.instance;
  final TextEditingController _winsController = TextEditingController();
  final TextEditingController _challengesController = TextEditingController();
  final TextEditingController _lessonsController = TextEditingController();
  final TextEditingController _gratitudeController = TextEditingController();
  final TextEditingController _tomorrowFocusController =
      TextEditingController();
  Map<DateTime, String> _emotionsByDay = {};
  Map<DateTime, List<_TimedEmotionEntry>> _emotionLogsByDay = {};
  List<_DailyCheckInEntry> _pastCheckIns = [];
  String? _todayEmotion;
  String? _loadErrorMessage;
  String? _checkInHistoryError;
  int _todayMoodScore = 3;
  bool _hasTodayCheckIn = false;

  List<String> _weeks = [];
  String? _selectedWeek;
  DateTime _focusedMonth = DateTime.now();
  bool _isLoading = false;
  bool _isLoadingCheckInHistory = false;
  bool _isSavingEmotion = false;
  bool _isSavingCheckIn = false;

  @override
  void initState() {
    super.initState();
    _weeks = _weeksForMonth(_focusedMonth.month);
    _fetchEmotions(showLoading: true);
  }

  @override
  void dispose() {
    _winsController.dispose();
    _challengesController.dispose();
    _lessonsController.dispose();
    _gratitudeController.dispose();
    _tomorrowFocusController.dispose();
    super.dispose();
  }

  Future<void> _fetchEmotions({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final querySnapshot = await _emotionService.fetchHistory(
        month: DateFormat('yyyy-MM').format(_focusedMonth),
      );

      final logsByDay = <DateTime, List<_TimedEmotionEntry>>{};

      for (final data in querySnapshot) {
        final firestoreDate = data['date']?.toString();
        if (firestoreDate == null || firestoreDate.isEmpty) {
          continue;
        }

        final emotionType = _normalizeEmotion(data['emotion'] as String?);
        final normalizedDate = _parseFirestoreDate(firestoreDate);
        final dayLogs = logsByDay.putIfAbsent(
          normalizedDate,
          () => <_TimedEmotionEntry>[],
        );
        final history = data['history'];

        if (history is List && history.isNotEmpty) {
          for (final rawEntry in history) {
            if (rawEntry is! Map) continue;
            final entryEmotion = _normalizeEmotion(
              rawEntry['emotion'] as String?,
            );
            final loggedAt = _readDateTime(rawEntry['loggedAt']) ??
                _readDateTime(rawEntry['createdAt']) ??
                _readDateTime(data['lastLoggedAt']) ??
                _readDateTime(data['updatedAt']) ??
                _readDateTime(data['createdAt']) ??
                normalizedDate;
            dayLogs.add(
              _TimedEmotionEntry(
                emotion: entryEmotion,
                loggedAt: loggedAt,
              ),
            );
          }
        }

        if (dayLogs.isEmpty) {
          final loggedAt = _readDateTime(data['lastLoggedAt']) ??
              _readDateTime(data['updatedAt']) ??
              _readDateTime(data['createdAt']) ??
              normalizedDate;
          dayLogs.add(
            _TimedEmotionEntry(
              emotion: emotionType,
              loggedAt: loggedAt,
            ),
          );
        }
      }

      final emotionsData = <DateTime, String>{};
      logsByDay.forEach((day, entries) {
        entries.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
        if (entries.isNotEmpty) {
          emotionsData[day] = entries.last.emotion;
        }
      });

      DateTime today = _normalizeDate(DateTime.now());

      if (!mounted) return;
      setState(() {
        _emotionsByDay = emotionsData;
        _emotionLogsByDay = logsByDay;
        _todayEmotion = emotionsData[today];
        _isLoading = false;
        _loadErrorMessage = null;
      });

      await _loadTodayCheckIn(session.id.toString());
      await _loadPastCheckIns(session.id.toString());
    } catch (e) {
      debugPrint("Error fetching emotions: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage =
            "Mood history could not load. You can still check in now.";
      });
    }
  }

  Future<void> _loadTodayCheckIn(String userId) async {
    try {
      final today = EmotionService.dateKeyFor(DateTime.now());
      final response = await _dailyCheckInService.fetch(date: today);

      if (!mounted) return;

      final data = response['checkIn'];
      if (data is! Map<String, dynamic>) {
        setState(() {
          _todayMoodScore = 3;
          _hasTodayCheckIn = false;
          _winsController.text = '';
          _challengesController.text = '';
          _lessonsController.text = '';
          _gratitudeController.text = '';
          _tomorrowFocusController.text = '';
        });
        return;
      }

      setState(() {
        _todayMoodScore = _readInt(data['rating']).clamp(1, 5);
        _hasTodayCheckIn = true;
        _winsController.text = _stringValue(data['winsToday']);
        _challengesController.text = _stringValue(data['challenges']);
        _lessonsController.text = _stringValue(data['lessonsLearned']);
        _gratitudeController.text = _stringValue(data['gratitude']);
        _tomorrowFocusController.text = _stringValue(data['tomorrowFocus']);
      });
    } catch (e) {
      debugPrint('Error loading daily check-in: $e');
    }
  }

  Future<void> _loadPastCheckIns(String userId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingCheckInHistory = true;
    });

    try {
      final snapshot = await _dailyCheckInService.fetchHistory(
        month: DateFormat('yyyy-MM').format(_focusedMonth),
      );

      final entries = snapshot
          .map(_DailyCheckInEntry.fromMap)
          .toList()
        ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

      if (!mounted) return;
      setState(() {
        _pastCheckIns = entries.take(5).toList();
        _checkInHistoryError = null;
        _isLoadingCheckInHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading past check-ins: $e');
      if (!mounted) return;
      setState(() {
        _checkInHistoryError = 'Past check-ins could not load right now.';
        _isLoadingCheckInHistory = false;
      });
    }
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? 3;
    return 3;
  }

  String _stringValue(dynamic value) {
    if (value is String) return value;
    return '';
  }

  DateTime? _readDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _normalizeEmotion(String? value) {
    final normalized = (value ?? 'unknown').trim().toLowerCase();
    return normalized.isEmpty ? 'unknown' : normalized;
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _parseFirestoreDate(String dateString) {
    try {
      return _normalizeDate(DateTime.parse(dateString));
    } catch (e) {
      return DateTime.now();
    }
  }

  List<String> _weeksForMonth(int month) {
    DateTime now = DateTime.now();
    int year = now.year;

    int lastDay = DateTime(year, month + 1, 1).subtract(Duration(days: 1)).day;

    return [
      'Week 1: ${_formatDate(DateTime(year, month, 1))} to ${_formatDate(DateTime(year, month, 9))}',
      'Week 2: ${_formatDate(DateTime(year, month, 10))} to ${_formatDate(DateTime(year, month, 16))}',
      'Week 3: ${_formatDate(DateTime(year, month, 17))} to ${_formatDate(DateTime(year, month, 23))}',
      'Week 4: ${_formatDate(DateTime(year, month, 24))} to ${_formatDate(DateTime(year, month, lastDay))}',
    ];
  }

  String _formatDate(DateTime date) {
    return "${_getMonthName(date.month)} ${date.day}";
  }

  String _getMonthName(int month) {
    List<String> months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ];
    return months[month - 1];
  }

  Color _getColorForEmotion(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Colors.yellow;
      case 'sad':
        return Colors.blue;
      case 'angry':
        return Colors.red;
      case 'neutral':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getIconForEmotion(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Icons.sentiment_satisfied_alt_rounded;
      case 'sad':
        return Icons.sentiment_dissatisfied_rounded;
      case 'angry':
        return Icons.local_fire_department_rounded;
      case 'neutral':
        return Icons.remove_circle_rounded;
      default:
        return Icons.help_rounded;
    }
  }

  Widget _buildEmotionIcon(
    String emotion, {
    required Color color,
    double size = 24,
  }) {
    return Icon(
      _getIconForEmotion(emotion),
      color: color,
      size: size,
    );
  }

  String _labelForEmotion(String emotion) {
    final normalized = emotion.toLowerCase();
    if (normalized.isEmpty) return 'Unknown';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }

  String _formatClockTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Future<void> _saveEmotion(String emotion) async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSavingEmotion) return;

    setState(() {
      _isSavingEmotion = true;
    });

    try {
      final username =
          session.name.trim().isNotEmpty ? session.name.trim() : 'Unknown';
      final result = await _emotionService.saveTodayEmotion(
        userId: session.id.toString(),
        emotion: emotion,
        username: username,
      );
      await _fetchEmotions();
      if (!mounted) return;
      final label = _labelForEmotion(result.emotion ?? emotion);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mood updated to $label.')),
      );
    } catch (e) {
      debugPrint('Error saving emotion from tracker: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update mood. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingEmotion = false;
        });
      }
    }
  }

  Future<void> _saveTodayCheckIn() async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSavingCheckIn) return;

    setState(() {
      _isSavingCheckIn = true;
    });

    try {
      final username =
          session.name.trim().isNotEmpty ? session.name.trim() : 'Unknown';
      final today = EmotionService.dateKeyFor(DateTime.now());
      final result = await _dailyCheckInService.upsert(
        date: today,
        rating: _todayMoodScore,
        winsToday: _winsController.text.trim(),
        challenges: _challengesController.text.trim(),
        lessonsLearned: _lessonsController.text.trim(),
        gratitude: _gratitudeController.text.trim(),
        tomorrowFocus: _tomorrowFocusController.text.trim(),
        username: username,
        lastFiledAt: DateTime.now().toIso8601String(),
      );

      if (!mounted) return;
      setState(() {
        _hasTodayCheckIn = true;
      });
      await _loadTodayCheckIn(session.id.toString());
      await _loadPastCheckIns(session.id.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['checkIn'] is Map<String, dynamic>
                ? "Today's check-in updated successfully."
                : "Today's check-in filed successfully.",
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error saving daily check-in: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't file today's check-in.")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCheckIn = false;
        });
      }
    }
  }

  void _showDayEmotionMessage(BuildContext context, DateTime day) {
    final normalizedDay = _normalizeDate(day);
    final entries = _emotionLogsByDay[normalizedDay] ?? const [];
    final dayLabel = _formatDate(normalizedDay);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Mood on $dayLabel"),
        content: entries.isEmpty
            ? const Text(
                "No mood recorded for this day.",
                style: TextStyle(fontSize: 16),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: entries.reversed.map((entry) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: _getColorForEmotion(entry.emotion)
                          .withValues(alpha: 0.18),
                      child: _buildEmotionIcon(
                        entry.emotion,
                        color: _getColorForEmotion(entry.emotion),
                        size: 22,
                      ),
                    ),
                    title: Text(_labelForEmotion(entry.emotion)),
                    subtitle: Text(_formatClockTime(entry.loggedAt)),
                  );
                }).toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  void _analyzeStressForWeek(String selectedWeek) {
    RegExp weekRegExp = RegExp(r'(\w+) (\d+) to (\w+) (\d+)');
    Match? match = weekRegExp.firstMatch(selectedWeek);

    if (match != null) {
      String startMonthName = match.group(1)!;
      int startDay = int.parse(match.group(2)!);
      String endMonthName = match.group(3)!;
      int endDay = int.parse(match.group(4)!);

      int startMonth = _getMonthIndex(startMonthName);
      int endMonth = _getMonthIndex(endMonthName);

      DateTime startDate = DateTime(DateTime.now().year, startMonth, startDay);
      DateTime endDate = DateTime(DateTime.now().year, endMonth, endDay);

      int stressCount = 0;
      int totalDays = 0;
      _emotionsByDay.forEach((date, emotion) {
        if (date.isAfter(startDate.subtract(Duration(days: 1))) &&
            date.isBefore(endDate.add(Duration(days: 1)))) {
          if (emotion == 'sad' || emotion == 'angry' || emotion == 'neutral') {
            stressCount++;
          }
          totalDays++;
        }
      });

      String analysisMessage;
      if (totalDays == 0) {
        analysisMessage = 'No emotions were logged for this week.';
      } else {
        double stressPercentage = (stressCount / totalDays) * 100;
        if (stressPercentage > 50) {
          analysisMessage =
              'Your stress level for this week is very high. Consider meditation or sharing your thoughts with a community.';
        } else if (stressPercentage > 25) {
          analysisMessage =
              'You had a moderate level of stress this week. Keep an eye on your emotions and practice mindfulness.';
        } else {
          analysisMessage =
              'Your stress level for this week was low. Keep up the good work maintaining emotional balance!';
        }
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Stress Analysis for $selectedWeek"),
          content: Text(analysisMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  int _getMonthIndex(String monthName) {
    List<String> months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ];
    return months.indexOf(monthName) + 1;
  }

  String _checkInPreview(_DailyCheckInEntry entry) {
    final notes = [
      entry.winsToday,
      entry.gratitude,
      entry.challenges,
      entry.lessonsLearned,
      entry.tomorrowFocus,
    ];
    for (final note in notes) {
      final trimmed = note.trim();
      if (trimmed.isNotEmpty) {
        if (trimmed.length <= 84) return trimmed;
        return '${trimmed.substring(0, 81)}...';
      }
    }
    return 'No notes added.';
  }

  Widget _buildHistoryTag(
    CompanyThemeData companyTheme,
    String label, {
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? companyTheme.primaryColor).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (color ?? companyTheme.primaryColor).withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color ?? companyTheme.inkColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildPastCheckInsCard(CompanyThemeData companyTheme) {
    final hasEntries = _pastCheckIns.isNotEmpty;

    return Card(
      elevation: 0,
      color: companyTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE0E5D9),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: false,
          iconColor: companyTheme.inkColor,
          collapsedIconColor: companyTheme.mutedInkColor,
          title: Text(
            'Past check-ins',
            style: TextStyle(
              color: companyTheme.inkColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            _isLoadingCheckInHistory
                ? 'Loading history...'
                : _checkInHistoryError ??
                    (hasEntries
                        ? '${_pastCheckIns.length} recent entries'
                        : 'No past check-ins yet'),
            style: TextStyle(
              color: companyTheme.mutedInkColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            if (_isLoadingCheckInHistory)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_checkInHistoryError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _checkInHistoryError!,
                  style: TextStyle(
                    color: companyTheme.mutedInkColor,
                    height: 1.4,
                  ),
                ),
              )
            else if (!hasEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Your filed check-ins will appear here after you save them.',
                  style: TextStyle(
                    color: companyTheme.mutedInkColor,
                    height: 1.4,
                  ),
                ),
              )
            else
              ..._pastCheckIns.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: companyTheme.backgroundColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: companyTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatDate(entry.date),
                                style: TextStyle(
                                  color: companyTheme.inkColor,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _buildHistoryTag(
                              companyTheme,
                              '${entry.rating}/5',
                              color: companyTheme.primaryColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _checkInPreview(entry),
                          style: TextStyle(
                            color: companyTheme.mutedInkColor,
                            height: 1.35,
                          ),
                        ),
                        if (entry.tomorrowFocus.trim().isNotEmpty ||
                            entry.gratitude.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (entry.gratitude.trim().isNotEmpty)
                                _buildHistoryTag(
                                  companyTheme,
                                  'Gratitude',
                                  color: Colors.tealAccent,
                                ),
                              if (entry.tomorrowFocus.trim().isNotEmpty)
                                _buildHistoryTag(
                                  companyTheme,
                                  'Tomorrow focus',
                                  color: Colors.amber,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayCheckInCard(CompanyThemeData companyTheme) {
    final options = const <int, String>{
      1: 'Struggling',
      2: 'Low',
      3: 'Steady',
      4: 'Good',
      5: 'Energised',
    };

    InputDecoration fieldDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: companyTheme.mutedInkColor.withValues(alpha: 0.78),
        ),
        filled: true,
        fillColor: companyTheme.isDark
            ? companyTheme.backgroundColor.withValues(alpha: 0.6)
            : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: companyTheme.primaryColor.withValues(alpha: 0.14),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: companyTheme.primaryColor.withValues(alpha: 0.14),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: companyTheme.primaryColor,
            width: 1.2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      );
    }

    Widget ratingTile(int rating, String label) {
      final selected = _todayMoodScore == rating;
      return InkWell(
        onTap: () {
          setState(() {
            _todayMoodScore = rating;
          });
        },
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? companyTheme.primaryColor.withValues(alpha: 0.16)
                : companyTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? companyTheme.primaryColor
                  : companyTheme.primaryColor.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            children: [
              Text(
                '$rating',
                style: TextStyle(
                  color: companyTheme.inkColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: companyTheme.mutedInkColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: companyTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE0E5D9),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's check-in",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: companyTheme.inkColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Honest beats impressive. Nobody scores you on the prose.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: companyTheme.mutedInkColor,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 14),
            Text(
              'How did today feel?',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: companyTheme.inkColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth >= 700 ? 5 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: options.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: count == 5 ? 1.8 : 1.45,
                  ),
                  itemBuilder: (context, index) {
                    final rating = index + 1;
                    return ratingTile(rating, options[rating]!);
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _winsController,
              maxLines: 3,
              style: TextStyle(
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w500,
              ),
              decoration: fieldDecoration(
                'What went right, however small.',
              ).copyWith(
                labelText: 'Wins today',
                labelStyle: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _challengesController,
              maxLines: 2,
              style: TextStyle(
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w500,
              ),
              decoration: fieldDecoration('What got in the way?').copyWith(
                labelText: 'Challenges',
                labelStyle: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lessonsController,
              maxLines: 2,
              style: TextStyle(
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w500,
              ),
              decoration:
                  fieldDecoration('What would you do differently tomorrow?')
                      .copyWith(
                labelText: 'Lessons learned',
                labelStyle: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gratitudeController,
              maxLines: 2,
              style: TextStyle(
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w500,
              ),
              decoration: fieldDecoration('Who or what are you grateful for today?')
                  .copyWith(
                labelText: 'Gratitude',
                labelStyle: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tomorrowFocusController,
              maxLines: 2,
              style: TextStyle(
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w500,
              ),
              decoration: fieldDecoration('The one thing that would make tomorrow a win.')
                  .copyWith(
                labelText: "Tomorrow's focus",
                labelStyle: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 420;
                final clearButton = TextButton(
                  onPressed: _isSavingCheckIn
                      ? null
                      : () {
                          setState(() {
                            _todayMoodScore = 3;
                            _winsController.clear();
                            _challengesController.clear();
                            _lessonsController.clear();
                            _gratitudeController.clear();
                            _tomorrowFocusController.clear();
                          });
                        },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    foregroundColor: companyTheme.mutedInkColor,
                  ),
                  child: const Text('Clear'),
                );

                final saveButton = FilledButton(
                  onPressed: _isSavingCheckIn ? null : _saveTodayCheckIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: companyTheme.primaryColor,
                    foregroundColor: companyTheme.backgroundColor,
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _isSavingCheckIn
                        ? 'Saving...'
                        : (_hasTodayCheckIn
                            ? "Update today's check-in"
                            : "File today's check-in"),
                    textAlign: TextAlign.center,
                  ),
                );

                if (isWide) {
                  return Row(
                    children: [
                      clearButton,
                      const SizedBox(width: 12),
                      Expanded(child: saveButton),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    saveButton,
                    const SizedBox(height: 8),
                    Center(child: clearButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayMoodCard(CompanyThemeData companyTheme) {
    final hasEmotion = _todayEmotion != null;
    return Card(
      elevation: 0,
      color: companyTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.25)
              : const Color(0xFFE0E5D9),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: hasEmotion
                    ? _getColorForEmotion(_todayEmotion!).withValues(alpha: .25)
                    : companyTheme.primaryColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: hasEmotion
                    ? _buildEmotionIcon(
                        _todayEmotion!,
                        color: _getColorForEmotion(_todayEmotion!),
                        size: 24,
                      )
                    : Icon(
                        CupertinoIcons.plus,
                        color: companyTheme.inkColor,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasEmotion ? 'Current mood' : 'No mood selected yet',
                    style: TextStyle(
                      color: companyTheme.mutedInkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasEmotion
                        ? _labelForEmotion(_todayEmotion!)
                        : 'Choose how you feel right now.',
                    style: TextStyle(
                      color: companyTheme.inkColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionButton({
    required CompanyThemeData companyTheme,
    required String emotion,
  }) {
    final isSelected = _todayEmotion == emotion;
    return InkWell(
      onTap: _isSavingEmotion ? null : () => _saveEmotion(emotion),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? _getColorForEmotion(emotion).withValues(alpha: .32)
              : companyTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _getColorForEmotion(emotion)
                : (companyTheme.isDark
                    ? companyTheme.primaryColor.withValues(alpha: 0.18)
                    : const Color(0xFFE0E5D9)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildEmotionIcon(
              emotion,
              color: isSelected
                  ? _getColorForEmotion(emotion)
                  : companyTheme.inkColor,
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _labelForEmotion(emotion),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionChooser(CompanyThemeData companyTheme) {
    final emotions = ['happy', 'neutral', 'sad', 'angry'];
    return AbsorbPointer(
      absorbing: _isSavingEmotion,
      child: Opacity(
        opacity: _isSavingEmotion ? .62 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _todayEmotion == null ? 'Select your mood' : 'Change your mood',
              style: TextStyle(
                color: companyTheme.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 560;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: emotions.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isWide ? 4 : 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: isWide ? 2.2 : 2.75,
                  ),
                  itemBuilder: (context, index) {
                    return _buildEmotionButton(
                      companyTheme: companyTheme,
                      emotion: emotions[index],
                    );
                  },
                );
              },
            ),
            if (_isSavingEmotion) ...[
              const SizedBox(height: 10),
              Text(
                'Saving mood...',
                style: TextStyle(
                  color: companyTheme.mutedInkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTimeline(CompanyThemeData companyTheme) {
    final today = _normalizeDate(DateTime.now());
    final entries = _emotionLogsByDay[today] ?? const <_TimedEmotionEntry>[];

    return Card(
      elevation: 0,
      color: companyTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE0E5D9),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: entries.isNotEmpty,
          iconColor: companyTheme.inkColor,
          collapsedIconColor: companyTheme.mutedInkColor,
          title: Text(
            "Today's mood timeline",
            style: TextStyle(
              color: companyTheme.inkColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            entries.isEmpty
                ? 'No logs yet'
                : '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'} today',
            style: TextStyle(
              color: companyTheme.mutedInkColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            if (entries.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No mood logged yet. Pick one above to start your timeline.',
                  style: TextStyle(
                    color: companyTheme.mutedInkColor,
                    height: 1.4,
                  ),
                ),
              )
            else
              ...entries.reversed.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _getColorForEmotion(entry.emotion)
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _buildEmotionIcon(
                          entry.emotion,
                          color: _getColorForEmotion(entry.emotion),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _labelForEmotion(entry.emotion),
                          style: TextStyle(
                            color: companyTheme.inkColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _formatClockTime(entry.loggedAt),
                        style: TextStyle(
                          color: companyTheme.mutedInkColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingHistoryCard(CompanyThemeData companyTheme) {
    return Card(
      elevation: 0,
      color: companyTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE0E5D9),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: companyTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Loading mood history...',
                style: TextStyle(
                  color: companyTheme.mutedInkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadErrorCard(CompanyThemeData companyTheme) {
    final message = _loadErrorMessage;
    if (message == null) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      color: companyTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: companyTheme.primaryColor.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle_fill,
              color: companyTheme.primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: companyTheme.inkColor,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(
              onPressed:
                  _isLoading ? null : () => _fetchEmotions(showLoading: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        final session = AuthService.instance.currentSession;
        if (session == null) {
          return Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Emotion Tracker',
                style: TextStyle(color: companyTheme.inkColor),
              ),
            ),
            body: Center(
              child: Text(
                'User not logged in.',
                style: TextStyle(color: companyTheme.inkColor),
              ),
            ),
          );
        }

        return Theme(
          data: Theme.of(context).copyWith(
            scaffoldBackgroundColor: companyTheme.backgroundColor,
            cardColor: companyTheme.surfaceColor,
            textTheme: Theme.of(context).textTheme.apply(
                  bodyColor: companyTheme.inkColor,
                  displayColor: companyTheme.inkColor,
                ),
          ),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Emotion Tracker',
                style: TextStyle(color: companyTheme.inkColor),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    if (_isLoading) ...[
                      _buildLoadingHistoryCard(companyTheme),
                      const SizedBox(height: 16),
                    ],
                    _buildLoadErrorCard(companyTheme),
                    if (_loadErrorMessage != null) const SizedBox(height: 16),
                    _buildTodayCheckInCard(companyTheme),
                    const SizedBox(height: 16),
                    _buildPastCheckInsCard(companyTheme),
                    const SizedBox(height: 16),
                    _buildTodayMoodCard(companyTheme),
                    const SizedBox(height: 16),
                    _buildEmotionChooser(companyTheme),
                    const SizedBox(height: 16),
                    _buildTodayTimeline(companyTheme),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: companyTheme.surfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: companyTheme.isDark
                              ? companyTheme.primaryColor
                                  .withValues(alpha: 0.18)
                              : const Color(0xFFE0E5D9),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: DropdownButton<String>(
                          value: _selectedWeek,
                          hint: Text(
                            "Select a week",
                            style: TextStyle(
                              color: companyTheme.mutedInkColor,
                            ),
                          ),
                          dropdownColor: companyTheme.surfaceColor,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedWeek = newValue;
                              });
                              _analyzeStressForWeek(newValue);
                            }
                          },
                          items: _weeks.map((String week) {
                            return DropdownMenuItem<String>(
                              value: week,
                              child: Text(
                                week,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: companyTheme.inkColor,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: companyTheme.surfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: companyTheme.isDark
                              ? companyTheme.primaryColor
                                  .withValues(alpha: 0.18)
                              : const Color(0xFFE0E5D9),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: TableCalendar(
                          focusedDay: _focusedMonth,
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2030, 12, 31),
                          calendarStyle: CalendarStyle(
                            markersMaxCount: 0,
                            defaultTextStyle: TextStyle(
                              color: companyTheme.inkColor,
                            ),
                            weekendTextStyle: TextStyle(
                              color: companyTheme.inkColor,
                            ),
                            outsideTextStyle: TextStyle(
                              color: companyTheme.mutedInkColor
                                  .withValues(alpha: 0.55),
                            ),
                            todayDecoration: BoxDecoration(
                              color: companyTheme.primaryColor
                                  .withValues(alpha: 0.78),
                              shape: BoxShape.circle,
                            ),
                          ),
                          headerStyle: HeaderStyle(
                            titleTextStyle: TextStyle(
                              color: companyTheme.inkColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                            formatButtonVisible: false,
                          ),
                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              color: companyTheme.mutedInkColor,
                              fontWeight: FontWeight.w700,
                            ),
                            weekendStyle: TextStyle(
                              color: companyTheme.mutedInkColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          calendarBuilders: CalendarBuilders(
                            defaultBuilder: (context, date, _) {
                              DateTime normalizedDate = _normalizeDate(date);
                              if (_emotionsByDay.containsKey(normalizedDate)) {
                                String emotion =
                                    _emotionsByDay[normalizedDate]!;
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: _getColorForEmotion(emotion),
                                        shape: BoxShape.circle,
                                      ),
                                      width: 35,
                                      height: 35,
                                    ),
                                    _buildEmotionIcon(
                                      emotion,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ],
                                );
                              }
                              return null;
                            },
                          ),
                          onDaySelected: (selectedDay, focusedDay) {
                            _showDayEmotionMessage(context, selectedDay);
                          },
                          onPageChanged: (focusedDay) {
                            setState(() {
                              _focusedMonth = focusedDay;
                              _weeks = _weeksForMonth(_focusedMonth.month);
                              _selectedWeek = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimedEmotionEntry {
  const _TimedEmotionEntry({
    required this.emotion,
    required this.loggedAt,
  });

  final String emotion;
  final DateTime loggedAt;
}

class _DailyCheckInEntry {
  const _DailyCheckInEntry({
    required this.date,
    required this.rating,
    required this.winsToday,
    required this.challenges,
    required this.lessonsLearned,
    required this.gratitude,
    required this.tomorrowFocus,
    required this.sortKey,
  });

  factory _DailyCheckInEntry.fromMap(Map<String, dynamic> data) {
    final dateKey = data['date'] as String? ?? '';
    final parsedDate = DateTime.tryParse(dateKey) ?? DateTime.now();
    int readInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value.trim()) ?? 3;
      return 3;
    }

    String readText(dynamic value) {
      if (value is String) return value;
      return '';
    }

    final fallbackSortKey = () {
      for (final key in ['updatedAt', 'createdAt', 'lastFiledAt']) {
        final value = data[key];
        if (value is DateTime) return value.millisecondsSinceEpoch;
        if (value is String) {
          final parsed = DateTime.tryParse(value);
          if (parsed != null) return parsed.millisecondsSinceEpoch;
        }
      }
      return parsedDate.millisecondsSinceEpoch;
    }();

    return _DailyCheckInEntry(
      date: parsedDate,
      rating: readInt(data['rating']).clamp(1, 5),
      winsToday: readText(data['winsToday']),
      challenges: readText(data['challenges']),
      lessonsLearned: readText(data['lessonsLearned']),
      gratitude: readText(data['gratitude']),
      tomorrowFocus: readText(data['tomorrowFocus']),
      sortKey: fallbackSortKey,
    );
  }

  final DateTime date;
  final int rating;
  final String winsToday;
  final String challenges;
  final String lessonsLearned;
  final String gratitude;
  final String tomorrowFocus;
  final int sortKey;
}
