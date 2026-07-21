import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:shimmer/shimmer.dart'; // <-- Added shimmer package

// Custom Colors
const customColor1 = Color(0xFF6D849A); // Primary color
const customColor2 = Color(0xFFCE8F5A); // Secondary color
const customColor3 = Color(0xFF90A17D); // Accent color

class UserProgressPage extends StatefulWidget {
  const UserProgressPage({super.key});

  @override
  State<UserProgressPage> createState() => _UserProgressPageState();
}

class _UserProgressPageState extends State<UserProgressPage> {
  List<Map<String, dynamic>> users = [];
  Map<String, Map<String, Map<String, bool>>> userProgressData = {};
  String currentUserId = '';
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        currentUserId = '';
        users = [];
        userProgressData = {};
        isLoading = false;
      });
      return;
    }

    try {
      if (!mounted) return;
      setState(() {
        currentUserId = session.id.toString();
      });
      await _loadFriendsProgress();
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadFriendsProgress() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });

    final monthKey =
        '${selectedYear.toString()}-${selectedMonth.toString().padLeft(2, '0')}';

    try {
      final friends =
          await DailyTrackerApiService.instance.fetchFriends(month: monthKey);
      final tempUsers = <Map<String, dynamic>>[];
      final progressData = <String, Map<String, Map<String, bool>>>{};

      for (final friend in friends) {
        final userId = (friend['userId'] as String?)?.trim() ?? '';
        if (userId.isEmpty || userId == currentUserId) continue;

        final username = (friend['username'] as String?)?.trim();
        final progress = friend['progress'];
        final monthProgress = <String, Map<String, bool>>{};

        if (progress is Map) {
          for (final entry in progress.entries) {
            final dateKey = entry.key.toString();
            if (entry.value is Map) {
              final taskMap = Map<String, dynamic>.from(entry.value as Map);
              monthProgress[dateKey] = {
                'Call': taskMap['Call'] == true,
                'Steps': taskMap['Steps'] == true,
                'Exercise': taskMap['Exercise'] == true,
                'Meditation': taskMap['Meditation'] == true,
                'Learning': taskMap['Learning'] == true,
                'Add Value': taskMap['Add Value'] == true,
              };
            }
          }
        }

        progressData[userId] = monthProgress;
        tempUsers.add({
          'userId': userId,
          'username': username?.isNotEmpty == true ? username : 'Unknown',
        });
      }

      if (!mounted) return;
      setState(() {
        users = tempUsers
          ..sort((a, b) => (a['username'] as String)
              .toLowerCase()
              .compareTo((b['username'] as String).toLowerCase()));
        userProgressData = progressData;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        users = [];
        userProgressData = {};
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        final accentColor = companyTheme.iconColor;
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              title: const Text('Friends Tracker'),
            ),
            body: isLoading
                ? _buildShimmerLoader(companyTheme)
                : users.isEmpty
                    ? Center(
                        child: Text(
                          'No group progress yet',
                          style: TextStyle(color: companyTheme.mutedInkColor),
                        ),
                      )
                    : ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          String userId = users[index]['userId'];
                          String username = users[index]['username'];

                          return Card(
                            color: companyTheme.surfaceColor,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: companyTheme.primaryColor.withValues(
                                  alpha: companyTheme.isDark ? 0.24 : 0.14,
                                ),
                              ),
                            ),
                            child: ExpansionTile(
                              iconColor: accentColor,
                              collapsedIconColor: accentColor,
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              title: Text(
                                username,
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              children: [
                                _buildDailyTracker(
                                  userId,
                                  DateTime.now(),
                                  companyTheme,
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'Previous Progress',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: companyTheme.primaryColor,
                                    ),
                                  ),
                                ),
                                _buildCalendar(userId, companyTheme),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerLoader(CompanyThemeData companyTheme) {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: companyTheme.mutedInkColor.withValues(alpha: 0.16),
          highlightColor: companyTheme.surfaceColor,
          child: Card(
            color: companyTheme.surfaceColor,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Container(
              height: 100,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 20, width: 150, color: Colors.white),
                  const SizedBox(height: 10),
                  Container(
                      height: 14, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 10),
                  Container(
                      height: 14, width: double.infinity, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyTracker(
    String userId,
    DateTime date,
    CompanyThemeData companyTheme,
  ) {
    String dateKey = DateFormat('yyyy-MM-dd').format(date);
    Map<String, bool> tasks = userProgressData[userId]?[dateKey] ??
        {
          'Call': false,
          'Steps': false,
          'Exercise': false,
          'Meditation': false,
          'Learning': false,
          'Add Value': false,
        };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: tasks.keys.map((task) {
          return CheckboxListTile(
            title: Text(task, style: TextStyle(color: companyTheme.inkColor)),
            value: tasks[task],
            onChanged: null,
            activeColor: companyTheme.primaryColor,
            checkColor: companyTheme.primaryColor.computeLuminance() > 0.48
                ? Colors.black
                : Colors.white,
            side: BorderSide(
              color: companyTheme.mutedInkColor.withValues(alpha: 0.7),
              width: 1.6,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendar(String userId, CompanyThemeData companyTheme) {
    int daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
    int firstDayOfWeek = DateTime(selectedYear, selectedMonth, 1).weekday % 7;
    List<String> weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Container(
      margin: EdgeInsets.all(8),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: companyTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: companyTheme.primaryColor.withValues(
            alpha: companyTheme.isDark ? 0.24 : 0.14,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: companyTheme.isDark
                ? Colors.black.withValues(alpha: 0.22)
                : companyTheme.primaryColor.withValues(alpha: 0.10),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMonthYearSelector(companyTheme),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: companyTheme.primaryColor,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 8),
          GridView.builder(
            physics: NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: daysInMonth + firstDayOfWeek,
            itemBuilder: (context, index) {
              if (index < firstDayOfWeek) return Container();
              int day = index - firstDayOfWeek + 1;
              String dateKey =
                  '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

              return InkWell(
                onTap: () => _showDailyTrackerDialog(userId, dateKey),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color:
                        userProgressData[userId]?.containsKey(dateKey) ?? false
                            ? companyTheme.primaryColor.withValues(alpha: 0.32)
                            : companyTheme.surfaceColor,
                    border: Border.all(
                      color: companyTheme.iconColor.withValues(alpha: 0.46),
                    ),
                  ),
                  child: Text('$day',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: companyTheme.inkColor,
                      )),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthYearSelector(CompanyThemeData companyTheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_left, color: companyTheme.iconColor),
          onPressed: () async {
            setState(() {
              if (selectedMonth == 1) {
                selectedMonth = 12;
                selectedYear--;
              } else {
                selectedMonth--;
              }
            });
            await _loadFriendsProgress();
          },
        ),
        Text(
            DateFormat('MMMM yyyy')
                .format(DateTime(selectedYear, selectedMonth)),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: companyTheme.inkColor)),
        IconButton(
          icon: Icon(Icons.arrow_right, color: companyTheme.iconColor),
          onPressed: () async {
            setState(() {
              if (selectedMonth == 12) {
                selectedMonth = 1;
                selectedYear++;
              } else {
                selectedMonth++;
              }
            });
            await _loadFriendsProgress();
          },
        ),
      ],
    );
  }

  void _showDailyTrackerDialog(String userId, String dateKey) {
    final companyTheme =
        CompanyThemeService.cachedThemeForUser(currentUserId) ??
            CompanyThemeData.standard;
    Map<String, bool> tasks = userProgressData[userId]?[dateKey] ??
        {
          'Call': false,
          'Steps': false,
          'Exercise': false,
          'Meditation': false,
          'Learning': false,
          'Add Value': false,
        };

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: AlertDialog(
            title: Text(
              "Daily Tracker",
              style: TextStyle(color: companyTheme.inkColor),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: tasks.keys.map((task) {
                return CheckboxListTile(
                  title: Text(
                    task,
                    style: TextStyle(color: companyTheme.inkColor),
                  ),
                  value: tasks[task],
                  onChanged: null,
                  activeColor: companyTheme.primaryColor,
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              )
            ],
          ),
        );
      },
    );
  }
}
