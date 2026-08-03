import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/auth/auth_role_home.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/models/community_bottom_sheet.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/daily_score_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/profile_picture_bus.dart';
import 'package:selfcare_projects/src/services/user_point_api_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_day_score.dart';
import 'package:shared_preferences/shared_preferences.dart';

const customColor1 = Color(0xFF6D849A); // Example primary color
const customColor2 = Color(0xFFCE8F5A); // Example secondary color
const customColor3 = Color(0xFF90A17D); // Example accent color

String _dailyTaskFieldKey(String task) {
  switch (task) {
    case 'Call':
      return 'call';
    case 'Steps':
      return 'steps';
    case 'Meditation':
      return 'meditation';
    case 'Exercise':
      return 'exercise';
    case 'Learning':
      return 'learning';
    case 'Add Value':
      return 'addValue';
    case 'Goals':
    case 'Todo List':
      return 'todoList';
    default:
      return task.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }
}

class _DailyTaskItem {
  const _DailyTaskItem({
    required this.id,
    required this.title,
    required this.isDefault,
  });

  final String id;
  final String title;
  final bool isDefault;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isDefault': isDefault,
      };

  static _DailyTaskItem? fromMap(dynamic value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    if (id is! String || title is! String) return null;
    final trimmedTitle = title.trim();
    if (id.trim().isEmpty || trimmedTitle.isEmpty) return null;

    return _DailyTaskItem(
      id: id.trim(),
      title: trimmedTitle,
      isDefault: value['isDefault'] == true,
    );
  }
}

final List<_DailyTaskItem> _defaultDailyTaskItems = [
  for (final title in [
    'Call',
    'Steps',
    'Exercise',
    'Meditation',
    'Learning',
    'Add Value',
  ])
    _DailyTaskItem(
      id: _dailyTaskFieldKey(title),
      title: title,
      isDefault: true,
    ),
];

Map<String, bool> _emptyTaskState(List<_DailyTaskItem> items) => {
      for (final item in items) item.id: false,
    };

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text("Edit Profile")));
}

class ChangeMeditationScreen extends StatelessWidget {
  const ChangeMeditationScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text("Change Meditation Song")));
}

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text("Manage Subscription")));
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.title});
  final String title;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String selectedCategory = '';
  bool isLoading = true;
  String username = "Loading...";
  String email = "Loading...";
  String? _profilePicUrl;

  // Daily Tracker related variables
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  List<_DailyTaskItem> dailyTrackerItems = List.of(_defaultDailyTaskItems);
  Map<String, bool> todayTasks = _emptyTaskState(_defaultDailyTaskItems);
  bool _isEditingDailyTracker = false;
  // The actual meditation duration already recorded for today, in minutes.
  // Reconciliation writes (_syncDailyTrackerScore, _syncTodayTask) must reuse
  // this instead of guessing, or they will clobber a real completed-session
  // duration (e.g. 30 minutes) with a nominal "done" placeholder of 1 minute.
  int _todayMeditationMinutes = 0;
  int _todayTodoListScore = 0;
  int _todayTodoListScoreContribution = 0;
  bool _todayTodoListIncludedInTotal = false;
  Future<void> _pendingTaskSync = Future<void>.value();

  @override
  void initState() {
    super.initState();
    UserService.getUserData().then((data) {
      setState(() {
        username = data["username"]!;
        email = data["email"]!;
      });
    });
    _fetchProfilePic();
    ProfilePictureBus.latestUrl.addListener(_onProfilePictureBusUpdate);
    _loadDailyTrackerItems().then((_) {
      if (!mounted) return;
      _restoreCachedDailyTrackerState().then((_) {
        if (!mounted) return;
        fetchDailyTrackerData();
      });
    });
  }

  @override
  void dispose() {
    ProfilePictureBus.latestUrl.removeListener(_onProfilePictureBusUpdate);
    super.dispose();
  }

  void _onProfilePictureBusUpdate() {
    if (!mounted) return;
    setState(() {
      _profilePicUrl = ProfilePictureBus.latestUrl.value;
    });
  }

  Future<void> _loadDailyTrackerItems() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    try {
      final userData = await UserService.getUserData();
      final rawItems = userData['dailyTrackerItems'];
      final parsedItems = rawItems is List
          ? rawItems
              .map(_DailyTaskItem.fromMap)
              .whereType<_DailyTaskItem>()
              .toList()
          : <_DailyTaskItem>[];
      final trackerOnlyItems =
          parsedItems.where((item) => item.id != 'todoList').toList();
      final resolvedItems = trackerOnlyItems.isEmpty
          ? List.of(_defaultDailyTaskItems)
          : trackerOnlyItems;

      if (!mounted) return;
      final preservedTasks = {
        for (final item in resolvedItems)
          item.id: todayTasks[item.id] ?? false,
      };
      setState(() {
        dailyTrackerItems = resolvedItems;
        todayTasks = preservedTasks;
      });

      if (parsedItems.any((item) => item.id == 'todoList')) {
        await _saveDailyTrackerItems();
      }
    } catch (e) {
      print("Error loading daily tracker items: $e");
    }
  }

  Future<void> _saveDailyTrackerItems() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    await UserService.updateUserFields({
      'daily_tracker_items': dailyTrackerItems.map((item) => item.toMap()).toList(),
    });
  }

  bool _readTaskCompletion(Map<String, dynamic> data, _DailyTaskItem item) {
    if (item.isDefault) {
      return data[item.id] == true;
    }

    final customTasks = data['customDailyTasks'];
    if (customTasks is Map) {
      final customTask = customTasks[item.id];
      if (customTask is Map) {
        return customTask['completed'] == true;
      }
      if (customTask is bool) return customTask;
    }

    return false;
  }

  Map<String, dynamic> _dailyTrackerSnapshotTasks() {
    return {
      '__snapshotTaskIds': dailyTrackerItems.map((item) => item.id).toList(),
      for (final item in dailyTrackerItems)
        item.id: {
          'title': item.title,
          'completed': todayTasks[item.id] == true,
          'isDefault': item.isDefault,
        },
    };
  }

  bool _trackerHasSnapshot(Map<String, dynamic> tracker) {
    final raw = tracker['customDailyTasks'];
    if (raw is! Map) return false;
    final snapshotTaskIds = raw['__snapshotTaskIds'];
    return snapshotTaskIds is List && snapshotTaskIds.isNotEmpty;
  }

  int get _dailyTrackerTaskCount => dailyTrackerItems.length;

  double _dailyTrackerTaskProgress(_DailyTaskItem item) {
    return todayTasks[item.id] == true ? 1 : 0;
  }

  int get _dailyTrackerCompletedCount => dailyTrackerItems
      .where((item) => _dailyTrackerTaskProgress(item) >= 1)
      .length;

  double get _dailyTrackerCompletedWeight => dailyTrackerItems.fold<double>(
        0,
        (total, item) => total + _dailyTrackerTaskProgress(item),
      );

  double get _dailyTrackerTaskValue {
    if (_dailyTrackerTaskCount == 0) return 0;
    return 100 / _dailyTrackerTaskCount;
  }

  double get _dailyTrackerScore {
    if (_dailyTrackerTaskCount == 0) return 0;
    return ((_dailyTrackerCompletedWeight / _dailyTrackerTaskCount) * 100)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  String _formatPercent(num value) {
    final formatted = value.toStringAsFixed(1);
    return formatted.endsWith('.0')
        ? formatted.substring(0, formatted.length - 2)
        : formatted;
  }

  String _dailyTrackerCacheKey(String date) {
    final session = AuthService.instance.currentSession;
    final userId = session?.id.toString() ?? 'guest';
    return 'profile_daily_tracker_${userId}_$date';
  }

  Future<void> _restoreCachedDailyTrackerState() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    final prefs = await SharedPreferences.getInstance();
    final cache = prefs.getString(
      _dailyTrackerCacheKey(DateFormat('yyyy-MM-dd').format(DateTime.now())),
    );
    if (cache == null || cache.isEmpty) return;

    final decoded = jsonDecode(cache);
    if (decoded is! Map) return;

    final cachedTasksRaw = decoded['todayTasks'];
    final cachedTasks = <String, bool>{};
    if (cachedTasksRaw is Map) {
      for (final entry in cachedTasksRaw.entries) {
        final key = entry.key?.toString();
        if (key == null || key.isEmpty) continue;
        cachedTasks[key] = entry.value == true;
      }
    }

    if (!mounted) return;
    setState(() {
      if (cachedTasks.isNotEmpty) {
        todayTasks = {
          for (final item in dailyTrackerItems)
            item.id: cachedTasks[item.id] ?? false,
        };
      }

      _todayTodoListScore = (decoded['todoListScore'] is num)
          ? (decoded['todoListScore'] as num).round().clamp(0, 100)
          : _todayTodoListScore;
      _todayTodoListScoreContribution = (decoded['todoListScoreContribution'] is num)
          ? (decoded['todoListScoreContribution'] as num).round().clamp(0, 100)
          : _todayTodoListScoreContribution;
      _todayTodoListIncludedInTotal =
          decoded['todoListIncludedInTotal'] == true ||
              _todayTodoListScore > 0 ||
              _todayTodoListIncludedInTotal;
    });
  }

  Future<void> _cacheDailyTrackerState() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _dailyTrackerCacheKey(DateFormat('yyyy-MM-dd').format(DateTime.now())),
      jsonEncode({
        'todayTasks': todayTasks,
        'todoListScore': _todayTodoListScore,
        'todoListScoreContribution': _todayTodoListScoreContribution,
        'todoListIncludedInTotal': _todayTodoListIncludedInTotal,
      }),
    );
  }

  num get _combinedDailyAndTodoScore {
    if (!_todayTodoListIncludedInTotal) return _dailyTrackerScore;
    final effectiveTodoListScore =
        _todayTodoListScore > 0 ? _todayTodoListScore : _todayTodoListScoreContribution;
    return ((_dailyTrackerScore + effectiveTodoListScore) / 2)
        .clamp(0, 100);
  }

  Future<void> _syncDailyTrackerScore() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;
    final membershipData =
        await CompanyMembershipService.loadForUser(session.id.toString());

    await DailyTrackerApiService.instance.upsert(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      username: username,
      meditation: todayTasks['meditation'],
      steps: todayTasks['steps'],
      call: todayTasks['call'],
      exercise: todayTasks['exercise'],
      learning: todayTasks['learning'],
      addValue: todayTasks['addValue'],
      todoList: todayTasks['todoList'],
      callCount: todayTasks['call'] == true ? 1 : 0,
      exerciseCount: todayTasks['exercise'] == true ? 1 : 0,
      exerciseMinutes: todayTasks['exercise'] == true ? 10 : 0,
      learningCount: todayTasks['learning'] == true ? 1 : 0,
      valueCount: todayTasks['addValue'] == true ? 1 : 0,
      todoListCount: _todayTodoListScore,
      dailyTrackerScore: _dailyTrackerScore.round(),
      todoListScore: _todayTodoListScore,
      todoListScoreDailyContribution: _todayTodoListScoreContribution,
      todoListIncludedInTotal: _todayTodoListIncludedInTotal,
      userTotalScore: _combinedDailyAndTodoScore.round(),
      customDailyTasks: _dailyTrackerSnapshotTasks(),
      // Reconciliation must never invent a duration. This runs whenever the
      // tracker snapshot needs repairing (e.g. right after fetch), which can
      // happen after a real meditation session already recorded its actual
      // minutes -- sending a hardcoded "1" here would silently overwrite
      // that correct value the next time the app opens.
      meditationMinutes: todayTasks['meditation'] == true
          ? (_todayMeditationMinutes > 0 ? _todayMeditationMinutes : 1)
          : 0,
      companyId: membershipData.activeMembership?.id,
      companyCode: membershipData.activeMembership?.code,
      companyName: membershipData.activeMembership?.name,
    );
  }

  void listenToDailyTrackerUpdates() {
    // Realtime Firestore listeners are no longer needed for profile tracker data.
  }

  Future<void> fetchDailyTrackerData() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;
    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final response = await DailyTrackerApiService.instance.fetch(
        date: todayDate,
      );
      final tracker = response['tracker'];
      if (tracker is! Map<String, dynamic>) {
        await resetDailyTracker(todayDate, session.id.toString());
        await checkAndAssignPoints();
        return;
      }

      setState(() {
        final rawTodoListScore = tracker['todoListScore'];
        _todayTodoListScore = rawTodoListScore is num
            ? rawTodoListScore.round().clamp(0, 100)
            : 0;
        final rawTodoListContribution =
            tracker['todoListScoreDailyContribution'];
        _todayTodoListScoreContribution = rawTodoListContribution is num
            ? rawTodoListContribution.round().clamp(0, 100)
            : 0;
        _todayTodoListIncludedInTotal =
            tracker['todoListIncludedInTotal'] == true ||
                _todayTodoListScore > 0 ||
                _todayTodoListScoreContribution > 0;
        final rawMeditationMinutes = tracker['meditationMinutes'];
        _todayMeditationMinutes =
            rawMeditationMinutes is num ? rawMeditationMinutes.round() : 0;
        todayTasks = {
          for (final item in dailyTrackerItems)
            item.id: _readTaskCompletion(tracker, item),
        };
        isLoading = false;
      });
      await _cacheDailyTrackerState();
      if (!_trackerHasSnapshot(tracker)) {
        await _syncDailyTrackerScore();
      }
      await checkAndAssignPoints();
    } catch (e) {
      print("Error fetching tracker data: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> resetDailyTracker(String todayDate, String userId) async {
    final membershipData = await CompanyMembershipService.loadForUser(userId);
    final trackerUsername = await _resolveTrackerUsername(userId);

    // Reset task values
    setState(() {
      todayTasks = _emptyTaskState(dailyTrackerItems);
      _todayMeditationMinutes = 0;
      _todayTodoListScore = 0;
      _todayTodoListScoreContribution = 0;
      _todayTodoListIncludedInTotal = false;
      isLoading = false;
    });
    await _cacheDailyTrackerState();

    await DailyTrackerApiService.instance.upsert(
      date: todayDate,
      username: trackerUsername ?? username,
      stepCount: 0,
      stepGoal: 5000,
      meditation: false,
      steps: false,
      call: false,
      exercise: false,
      learning: false,
      addValue: false,
      todoList: false,
      callCount: 0,
      exerciseCount: 0,
      exerciseMinutes: 0,
      learningCount: 0,
      valueCount: 0,
      todoListCount: 0,
      dailyTrackerScore: 0,
      todoListScore: 0,
      todoListScoreDailyContribution: 0,
      todoListIncludedInTotal: false,
      userTotalScore: 0,
      customDailyTasks: _dailyTrackerSnapshotTasks(),
      meditationMinutes: 0,
      companyId: membershipData.activeMembership?.id,
      companyCode: membershipData.activeMembership?.code,
      companyName: membershipData.activeMembership?.name,
    );
  }

  Future<String?> _resolveTrackerUsername(String userId) async {
    final cachedUsername = username.trim();
    if (cachedUsername.isNotEmpty && cachedUsername != 'Loading...') {
      return cachedUsername;
    }

    try {
      final userData = await UserService.getUserData();
      final resolvedUsername =
          userData['username']?.toString().trim() ?? userData['name']?.toString().trim() ?? '';

      if (resolvedUsername.isEmpty) {
        return null;
      }

      return resolvedUsername;
    } catch (e) {
      print("Error resolving tracker username: $e");
      return null;
    }
  }

  Future<void> _toggleTodayTask(_DailyTaskItem item, bool? value) async {
    if (value == null) return;

    final session = AuthService.instance.currentSession;
    if (session == null) return;

    setState(() {
      todayTasks[item.id] = value;
      if (item.id == 'meditation' && value == false) {
        _todayMeditationMinutes = 0;
      }
    });

    // Keep rapid manual changes ordered. Each request patches only the task
    // that was tapped, so it cannot overwrite an automatic completion for a
    // different task while the user is editing the checklist.
    final previous = _pendingTaskSync;
    final completer = Completer<void>();
    _pendingTaskSync = completer.future;
    await previous;

    try {
      await _syncTodayTask(session.id.toString(), item, value);
    } catch (e) {
      if (mounted) {
        setState(() {
          todayTasks[item.id] = !(value);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to update ${item.title}. Please try again.'),
          ),
        );
      }
    } finally {
      completer.complete();
    }
  }

  Future<void> _syncTodayTask(
    String userId,
    _DailyTaskItem item,
    bool value,
  ) async {
    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final membershipData = await CompanyMembershipService.loadForUser(userId);
    final manualCount = value ? 1 : 0;

    await DailyTrackerApiService.instance.upsert(
      date: todayDate,
      username: username,
      meditation: item.id == 'meditation' ? value : null,
      steps: item.id == 'steps' ? value : null,
      call: item.id == 'call' ? value : null,
      exercise: item.id == 'exercise' ? value : null,
      learning: item.id == 'learning' ? value : null,
      addValue: item.id == 'addValue' ? value : null,
      todoList: item.id == 'todoList' ? value : null,
      callCount: item.id == 'call' ? manualCount : null,
      exerciseCount: item.id == 'exercise' ? manualCount : null,
      exerciseMinutes: item.id == 'exercise' ? (value ? 10 : 0) : null,
      learningCount: item.id == 'learning' ? manualCount : null,
      valueCount: item.id == 'addValue' ? manualCount : null,
      customDailyTasks: _dailyTrackerSnapshotTasks(),
      // Checking the box on doesn't mean "1 minute" -- if a real session
      // already recorded a duration today, keep it instead of stomping it
      // with the manual-toggle placeholder.
      meditationMinutes: item.id == 'meditation'
          ? (value
              ? (_todayMeditationMinutes > 0
                  ? _todayMeditationMinutes
                  : manualCount)
              : 0)
          : null,
      companyId: membershipData.activeMembership?.id,
      companyCode: membershipData.activeMembership?.code,
      companyName: membershipData.activeMembership?.name,
    );
    await _cacheDailyTrackerState();
    await checkAndAssignPoints();
  }

  Future<void> _showAddDailyTaskDialog() async {
    final availableItems = _defaultDailyTaskItems
        .where(
          (module) =>
              module.id != 'todoList' &&
              !dailyTrackerItems.any((item) => item.id == module.id),
        )
        .toList();

    if (availableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All available modules are already in Daily Tracker.'),
        ),
      );
      return;
    }

    _DailyTaskItem selectedItem = availableItems.first;

    final item = await showDialog<_DailyTaskItem>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Daily Module'),
              content: DropdownButtonFormField<_DailyTaskItem>(
                initialValue: selectedItem,
                decoration: const InputDecoration(
                  labelText: 'Module',
                  border: OutlineInputBorder(),
                ),
                items: availableItems.map((module) {
                  return DropdownMenuItem<_DailyTaskItem>(
                    value: module,
                    child: Text(module.title),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    selectedItem = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, selectedItem),
                  child: const Text('ADD'),
                ),
              ],
            );
          },
        );
      },
    );

    if (item == null) return;

    setState(() {
      dailyTrackerItems = [...dailyTrackerItems, item];
      todayTasks[item.id] = false;
    });

    try {
      await _saveDailyTrackerItems();
      await _syncDailyTrackerScore();
      await checkAndAssignPoints();
      await fetchDailyTrackerData();
    } catch (e) {
      print('Error saving daily task item: $e');
    }
  }

  Future<void> _removeDailyTask(_DailyTaskItem item) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Daily Task'),
        content: Text('Remove ${item.title} from your Daily Tracker?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );

    if (shouldRemove != true) return;

    final previousItems = List<_DailyTaskItem>.of(dailyTrackerItems);
    final previousTasks = Map<String, bool>.of(todayTasks);

    setState(() {
      dailyTrackerItems =
          dailyTrackerItems.where((task) => task.id != item.id).toList();
      todayTasks.remove(item.id);
    });

    try {
      await _saveDailyTrackerItems();
      await _syncDailyTrackerScore();
      await checkAndAssignPoints();
      await fetchDailyTrackerData();
    } catch (e) {
      print('Error removing daily task item: $e');
      if (!mounted) return;
      setState(() {
        dailyTrackerItems = previousItems;
        todayTasks = previousTasks;
      });
    }
  }

  Future<void> _restoreDefaultDailyTasks() async {
    setState(() {
      dailyTrackerItems = List.of(_defaultDailyTaskItems);
      todayTasks = _emptyTaskState(dailyTrackerItems);
    });

    try {
      await _saveDailyTrackerItems();
      await _syncDailyTrackerScore();
      await checkAndAssignPoints();
      await fetchDailyTrackerData();
    } catch (e) {
      print('Error restoring daily tracker defaults: $e');
    }
  }

  Future<Set<int>> _fetchTrackedDays() async {
    final month = DateFormat('yyyy-MM')
        .format(DateTime(selectedYear, selectedMonth, 1));

    try {
      final trackers = await DailyTrackerApiService.instance.fetchHistory(
        month: month,
      );
      final trackedDays = trackers
          .map((tracker) => tracker['date']?.toString())
          .whereType<String>()
          .map((date) => DateTime.tryParse(date))
          .whereType<DateTime>()
          .where((date) =>
              date.year == selectedYear && date.month == selectedMonth)
          .map((date) => date.day)
          .toSet();

      return trackedDays;
    } catch (e) {
      print("Error fetching tracked days: $e");
      return {};
    }
  }

  Future<void> _fetchProfilePic() async {
    try {
      final userData = await UserService.getUserData();
      final dynamic rawProfilePic =
          userData["profilePic"] ?? userData["profile_pic"];
      final String cleanedUrl = rawProfilePic is String ? rawProfilePic.trim() : "";
      if (!mounted) return;
      setState(() {
        _profilePicUrl = cleanedUrl.isEmpty ? null : cleanedUrl;
      });
    } catch (e) {
      print("Error fetching profile picture: $e");
    }
  }

  Future<void> checkAndAssignPoints() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;
    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final userData = await UserService.getUserData();
      final usernameValue = userData['username']?.toString() ?? username;
      final membershipData = CompanyMembershipService.fromUserData(userData);

      final trackerResponse = await DailyTrackerApiService.instance.fetch(
        date: todayDate,
      );
      final tracker = trackerResponse['tracker'];
      if (tracker is! Map<String, dynamic>) return;
      final dailyTrackerIds = dailyTrackerItems
          .map((item) => item.id)
          .where((id) => id.trim().isNotEmpty && id != 'todoList')
          .toList();
      final scoreSummary = DailyScoreService.summarizeTracker(
        tracker,
        dailyTrackerIds: dailyTrackerIds,
      );
      final meditationMinutes =
          (tracker['meditationMinutes'] as num?)?.toInt() ?? 0;
      final stepsTaken = (tracker['stepCount'] as num?)?.toInt() ?? 0;
      final exerciseCount = (tracker['exerciseCount'] as num?)?.toInt() ?? 0;
      final callsMade = (tracker['callCount'] as num?)?.toInt() ?? 0;
      final learningEntries = (tracker['learningCount'] as num?)?.toInt() ?? 0;
      final valueEntries = (tracker['valueCount'] as num?)?.toInt() ?? 0;
      final todoListCount = (tracker['todoListCount'] as num?)?.toInt() ?? 0;
      final taskCompletion = <String, bool>{
        'Meditation': tracker['meditation'] == true,
        'Steps': tracker['steps'] == true,
        'Exercise': tracker['exercise'] == true,
        'Call': tracker['call'] == true,
        'Learning': tracker['learning'] == true,
        'Add Value': tracker['addValue'] == true,
        'Goals': tracker['todoList'] == true,
      };

      await UserPointApiService.instance.upsert(
        date: todayDate,
        username: usernameValue,
        totalPoints: scoreSummary.totalPoints,
        dailyTrackerScore: scoreSummary.dailyTrackerScore,
        todoListScore: scoreSummary.todoListScore,
        todoListScoreDailyContribution: scoreSummary.todoListScoreContribution,
        todoListIncludedInTotal: scoreSummary.todoListIncludedInTotal,
        userTotalScore: scoreSummary.totalPoints.round(),
        tasks: taskCompletion.map((key, value) => MapEntry(key, value)),
        server: userData['team']?.toString() ?? 'Default',
        companyId: membershipData.activeMembership?.id,
        companyCode: membershipData.activeMembership?.code,
        companyName: membershipData.activeMembership?.name,
        activityCounts: {
          'meditationMinutes': meditationMinutes,
          'stepsTaken': stepsTaken,
          'exerciseCount': exerciseCount,
          'callsMade': callsMade,
          'learningEntries': learningEntries,
          'valueEntries': valueEntries,
          'todoListCount': todoListCount,
          'todoListScore': scoreSummary.todoListScore,
          'todoListScoreDailyContribution':
              scoreSummary.todoListScoreContribution,
          'todoListIncludedInTotal': scoreSummary.todoListIncludedInTotal,
          'dailyTrackerScore': scoreSummary.dailyTrackerScore,
          'userTotalScore': scoreSummary.totalPoints,
        },
      );

      print("Total points assigned: ${scoreSummary.totalPoints}");
    } catch (e) {
      print("Error in assigning points: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    final avatarSize = (screenWidth * 0.35).clamp(96.0, 180.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AuthRoleHome()),
          (route) => false, // Removes all previous routes from the stack
        );
      },
      child: CompanyThemeBuilder(
        builder: (context, companyTheme) {
          return Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor:
                  companyTheme.isDark ? companyTheme.surfaceColor : null,
              foregroundColor:
                  companyTheme.isDark ? companyTheme.inkColor : null,
              iconTheme: IconThemeData(
                color: companyTheme.isDark
                    ? Colors.white.withValues(alpha: 0.92)
                    : companyTheme.iconColor,
              ),
              actionsIconTheme: IconThemeData(
                color: companyTheme.isDark
                    ? Colors.white.withValues(alpha: 0.92)
                    : companyTheme.iconColor,
              ),
              surfaceTintColor: Colors.transparent,
              title: Text(widget.title),
              actions: [
                IconButton(
                  onPressed: () =>
                      CommunityBottomSheet.show(context, companyTheme: companyTheme),
                  icon: Icon(Icons.edit),
                )
              ],
            ),
            body: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    child: Column(
                      children: [
                        (_profilePicUrl == null ||
                                _profilePicUrl!.trim().isEmpty)
                            ? Image.asset(
                                'assets/images/avatar.png',
                                width: avatarSize,
                                height: avatarSize,
                              )
                            : ClipOval(
                                child: Image.network(
                                  _profilePicUrl!,
                                  width: avatarSize,
                                  height: avatarSize,
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return SizedBox(
                                      width: avatarSize,
                                      height: avatarSize,
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset(
                                      'assets/images/avatar.png',
                                      width: avatarSize,
                                      height: avatarSize,
                                    );
                                  },
                                ),
                              ),

                        SizedBox(height: 10),
                        Column(
                          children: [
                            Text(
                              username,
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                color: companyTheme.inkColor,
                              ),
                            ),
                            Text(
                              email,
                              style: TextStyle(
                                fontSize: 18,
                                color: companyTheme.mutedInkColor,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),

                        // Start of Daily Tracker Section
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Daily Tracker',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: companyTheme.inkColor,
                                ),
                              ),
                            ),
                            if (_isEditingDailyTracker) ...[
                              IconButton(
                                tooltip: 'Restore defaults',
                                onPressed: _restoreDefaultDailyTasks,
                                icon: Icon(
                                  Icons.restart_alt_rounded,
                                  color: companyTheme.mutedInkColor,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Add daily task',
                                onPressed: _showAddDailyTaskDialog,
                                icon: Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: companyTheme.iconColor,
                                ),
                              ),
                            ],
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isEditingDailyTracker =
                                      !_isEditingDailyTracker;
                                });
                              },
                              icon: Icon(
                                _isEditingDailyTracker
                                    ? Icons.check_rounded
                                    : Icons.edit_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _isEditingDailyTracker ? 'Done' : 'Edit',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: companyTheme.iconColor,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: companyTheme.surfaceColor,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: companyTheme.isDark
                                  ? companyTheme.primaryColor
                                      .withValues(alpha: 0.18)
                                  : const Color(0xFFE3EAE8),
                            ),
                          ),
                          child: Column(
                            children: dailyTrackerItems.isEmpty
                                ? [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        _isEditingDailyTracker
                                            ? 'No daily tasks yet. Tap + to add one.'
                                            : 'No daily tasks yet. Tap Edit to add one.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: companyTheme.mutedInkColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ]
                                : [
                                    _buildDailyTrackerScore(companyTheme),
                                    Divider(
                                      color: companyTheme.mutedInkColor
                                          .withValues(alpha: 0.18),
                                      height: 20,
                                    ),
                                    for (final item in dailyTrackerItems)
                                      _buildTaskRow(
                                        item,
                                        todayTasks,
                                        companyTheme,
                                      ),
                                  ],
                          ),
                        ),

                        SizedBox(height: 16),

                        ExpansionTile(
                          title: Text(
                            'View Previous Progress',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: companyTheme.inkColor,
                            ),
                          ),
                          children: [_buildCalendar(companyTheme)],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDailyTrackerScore(CompanyThemeData companyTheme) {
    final taskValue = _dailyTrackerTaskValue;
    final score = _dailyTrackerScore;
    final scoreLabel =
        '$_dailyTrackerCompletedCount of $_dailyTrackerTaskCount complete • each task ${_formatPercent(taskValue)}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Daily score',
                  style: TextStyle(
                    color: companyTheme.inkColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${_formatPercent(score)}%',
                style: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (score / 100).clamp(0.0, 1.0).toDouble(),
              backgroundColor: companyTheme.mutedInkColor.withValues(
                alpha: 0.16,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                companyTheme.iconColor,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            scoreLabel,
            style: TextStyle(
              color: companyTheme.mutedInkColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Builds each task row for Today's tracker
  Widget _buildTaskRow(
    _DailyTaskItem item,
    Map<String, bool> taskMap,
    CompanyThemeData companyTheme,
  ) {
    bool isCompleted = taskMap[item.id] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Checkbox(
            value: isCompleted,
            activeColor: companyTheme.isDark
                ? companyTheme.iconColor
                : companyTheme.primaryColor,
            checkColor: companyTheme.isDark ? Colors.black : Colors.white,
            side: BorderSide(
              color: companyTheme.isDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : companyTheme.mutedInkColor,
              width: 1.8,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            onChanged: (value) => _toggleTodayTask(item, value),
          ),
          Expanded(
            child: InkWell(
              onTap: () {
                _toggleTodayTask(item, !isCompleted);
              },
              child: Text(
                item.title,
                style: TextStyle(
                  color: isCompleted
                      ? companyTheme.primaryColor
                      : companyTheme.inkColor,
                  fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          if (_isEditingDailyTracker)
            IconButton(
              tooltip: 'Remove ${item.title}',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: companyTheme.mutedInkColor,
              ),
              onPressed: () => _removeDailyTask(item),
            ),
        ],
      ),
    );
  }

  // Builds the Calendar for Previous Days
  Widget _buildCalendar(CompanyThemeData companyTheme) {
    int daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
    int firstDayOfWeek = DateTime(selectedYear, selectedMonth, 1).weekday % 7;
    List<String> weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return FutureBuilder<Set<int>>(
      future: _fetchTrackedDays(),
      builder: (context, snapshot) {
        Set<int> trackedDays = snapshot.data ?? {};

        return Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(16),
          constraints: BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: companyTheme.surfaceColor,
            border: Border.all(
              color: companyTheme.primaryColor.withValues(alpha: 0.35),
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: selectedMonth,
                    onChanged: (newMonth) {
                      setState(() {
                        selectedMonth = newMonth!;
                      });
                    },
                    items: List.generate(
                      12,
                      (index) => DropdownMenuItem<int>(
                        value: index + 1,
                        child: Text(
                          DateFormat('MMMM')
                              .format(DateTime(selectedYear, index + 1, 1)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  DropdownButton<int>(
                    value: selectedYear,
                    onChanged: (newYear) {
                      setState(() {
                        selectedYear = newYear!;
                      });
                    },
                    items: List.generate(
                      10,
                      (index) => DropdownMenuItem<int>(
                        value: DateTime.now().year - 5 + index,
                        child: Text('${DateTime.now().year - 5 + index}'),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: weekdays
                    .map((day) => Expanded(
                          child: Center(
                            child: Text(day,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        customColor1)), // Applied customColor1 for weekday labels
                          ),
                        ))
                    .toList(),
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
                  if (index < firstDayOfWeek) {
                    return Container();
                  }
                  int day = index - firstDayOfWeek + 1;

                  DateTime currentDate = DateTime.now();
                  bool isPastDay = DateTime(selectedYear, selectedMonth, day)
                      .isBefore(DateTime(currentDate.year, currentDate.month,
                          currentDate.day));

                  bool hasData = trackedDays.contains(day);

                  return InkWell(
                    onTap: () => _showDailyTrackerDialog(day),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: (day == currentDate.day &&
                                selectedMonth == currentDate.month &&
                                selectedYear == currentDate.year)
                            ? customColor2 // Applied customColor2 to highlight today's date
                            : (isPastDay && hasData
                                ? customColor3 // Applied customColor3 to highlight past days with data
                                : Colors.white), // Default for other days
                        border: Border.all(
                            color:
                                customColor1), // Applied customColor1 for calendar day borders
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 0, 0,
                              0), // Applied customColor1 for day numbers
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

// Popup for Previous Days
  Future<void> _showDailyTrackerDialog(int day) async {
    final selectedDate = DateFormat('yyyy-MM-dd')
        .format(DateTime(selectedYear, selectedMonth, day));

    List<DailyTrackerHistoryTask> selectedDateTasks = const [];
    int? dayScorePercent;

    try {
      final response = await DailyTrackerApiService.instance.fetch(
        date: selectedDate,
      );
      final data = response['tracker'];
      if (data is Map<String, dynamic>) {
        selectedDateTasks = resolveDayTrackerTasks(data);
        dayScorePercent = resolveDayScorePercent(data);
      } else {
        print("No data found for $selectedDate.");
      }
    } catch (e) {
      print("Error fetching tracker data for $selectedDate: $e");
    }

    // Captured as a `final` local so it promotes to non-null inside the
    // dialog builder closure below.
    final resolvedScorePercent = dayScorePercent;

    // Show the dialog with fetched data
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Tracker for $selectedMonth/$day/$selectedYear"),
          content: StatefulBuilder(
            builder: (context, setState) {
              final colors = Theme.of(context).colorScheme;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (resolvedScorePercent != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Score',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '$resolvedScorePercent%',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: (resolvedScorePercent / 100)
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        backgroundColor: colors.onSurface.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'No tracker data recorded for this day.',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ...selectedDateTasks.map((task) {
                    return CheckboxListTile(
                      title: Text(task.title),
                      value: task.completed,
                      onChanged:
                          null, // Checkboxes are not interactive in this dialog
                    );
                  }),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }
}
