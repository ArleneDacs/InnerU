// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/calorie_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/chat_room.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coach_carousel.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coaches_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_mentee_goals_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_step_submissions_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notifications/notifications_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart'
    show Task, taskProgress;
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/chat_api_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/daily_score_service.dart';
import 'package:selfcare_projects/src/services/dashboard_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';
import 'package:selfcare_projects/src/services/notification_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key});

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatApiService _chatApi = ChatApiService.instance;
  final DashboardApiService _dashboardApi = DashboardApiService.instance;

  bool _isSavingProfile = false;
  String? selectedEmotion;
  String? _currentUserEmotion;
  String _quote = 'Your daily inspiration...';
  String _author = 'Unknown';
  final Map<String, DateTime> _localChatReadOverrides = <String, DateTime>{};
  final Set<String> _pressedTiles = <String>{};
  final EmotionService _emotionService = EmotionService();
  final GlobalKey _dashboardStackKey = GlobalKey();
  late CompanyThemeData _companyTheme;
  late final AnimationController _tileTransitionController;
  Timer? _refreshTimer;
  StreamSubscription<String?>? _todayEmotionSubscription;
  _CoachDashboardTileTransition? _activeTileTransition;
  bool _isEmotionLoading = true;
  bool _isSavingEmotion = false;
  int? _realMenteeCount;
  String? _primaryGroupName;

  String get _userId =>
      AuthService.instance.currentSession?.id.toString() ?? '';
  String get _todayDate => EmotionService.todayKey();

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _userStream =>
      _firestore.collection('users').doc(_userId).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _coachStream =>
      _firestore.collection('coaches').doc(_userId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _menteesStream => _firestore
      .collection('users')
      .where('coachIds', arrayContains: _userId)
      .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _pendingRequestsStream =>
      _firestore
          .collection('coach_requests')
          .where('coachId', isEqualTo: _userId)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _coachGroupsStream =>
      _firestore
          .collection('coach_groups')
          .where('coachId', isEqualTo: _userId)
          .snapshots();

  @override
  void initState() {
    super.initState();
    _companyTheme = CompanyThemeService.cachedThemeForUser(
          AuthService.instance.currentSession?.id.toString() ?? '',
        ) ??
        CompanyThemeData.standard;
    _tileTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _loadCompanyTheme();
    _restoreTodayEmotionFromCache();
    _listenToTodayEmotion();
    _fetchQuote();
    _loadLocalChatReadOverrides();
    _loadCoachTeamStats();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {});
      _loadCoachTeamStats();
    });
  }

  // The hero card's Team/Mentees stats need the real coach-mentee
  // relationships and groups from the API — the legacy _menteesStream
  // Firestore query above is no longer written to since the move to
  // Postgres, so it reads as empty regardless of actual mentee count.
  Future<void> _loadCoachTeamStats() async {
    try {
      final results = await Future.wait([
        CoachApiService.instance.fetchMentees(),
        CoachApiService.instance.fetchGroups(),
      ]);
      if (!mounted) return;
      final mentees = results[0];
      final groups = results[1];
      setState(() {
        _realMenteeCount = mentees.length;
        _primaryGroupName = groups.isNotEmpty
            ? (groups.first['name'] as String?)?.trim()
            : null;
      });
    } catch (error) {
      debugPrint('Failed to load coach team stats: $error');
    }
  }

  @override
  void dispose() {
    _todayEmotionSubscription?.cancel();
    _refreshTimer?.cancel();
    _tileTransitionController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalChatReadOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final overrides = <String, DateTime>{};
    final prefix = 'chat_read_override_${_userId}_';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final rawValue = prefs.getInt(key);
      if (rawValue == null) continue;
      final chatRoomId = key.substring(prefix.length);
      overrides[chatRoomId] = DateTime.fromMillisecondsSinceEpoch(rawValue);
    }
    if (!mounted) return;
    setState(() {
      _localChatReadOverrides
        ..clear()
        ..addAll(overrides);
    });
  }

  Future<void> _loadCompanyTheme() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    try {
      final companyTheme = await CompanyThemeService.resolveForUser(
        session.id.toString(),
      );
      if (!mounted) return;
      setState(() {
        _companyTheme = companyTheme;
      });
    } catch (e) {
      debugPrint('Error fetching coach company theme: $e');
    }
  }

  Future<void> _fetchQuote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedQuote = prefs.getString('coach_quote');
      final savedAuthor = prefs.getString('coach_author');
      final savedDate = prefs.getString('coach_quote_date');
      final today = DateTime.now().toString().split(' ')[0];

      if (savedQuote != null && savedAuthor != null && savedDate == today) {
        if (!mounted) return;
        setState(() {
          _quote = savedQuote;
          _author = savedAuthor;
        });
        return;
      }

      final response =
          await http.get(Uri.parse('https://zenquotes.io/api/random'));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final newQuote = data[0]['q'] ?? 'No quote available.';
        final newAuthor = data[0]['a'] ?? 'Unknown';

        if (!mounted) return;
        setState(() {
          _quote = newQuote;
          _author = newAuthor;
        });

        await prefs.setString('coach_quote', newQuote);
        await prefs.setString('coach_author', newAuthor);
        await prefs.setString('coach_quote_date', today);
      }
    } catch (_) {}
  }

  Future<void> _restoreTodayEmotionFromCache() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isEmotionLoading = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = session.id.toString();
    final savedEmotion = prefs.getString('selected_emotion_$userId');
    final savedDate = prefs.getString('emotion_date_$userId');

    if (!mounted) return;
    if (savedDate == _todayDate &&
        savedEmotion != null &&
        savedEmotion.isNotEmpty) {
      setState(() {
        _currentUserEmotion = savedEmotion;
        _isEmotionLoading = false;
      });
    }
  }

  Future<String> _getUsername() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return 'Coach';

    try {
      final userData = await UserService.getUserData();
      final username = (userData['username'] as String?)?.trim();
      if (username != null && username.isNotEmpty) {
        return username;
      }
    } catch (_) {}

    if (session.email.split('@').first.isNotEmpty) {
      return session.email.split('@').first;
    }
    return 'Coach';
  }

  Future<void> _openAssignedCoachChat({
    required BuildContext context,
    required Coach coach,
  }) async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    final username = await _getUsername();
    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          coach: coach,
          userId: session.id.toString(),
          userName: username,
        ),
      ),
    );
  }

  Future<void> _listenToTodayEmotion() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isEmotionLoading = false;
      });
      return;
    }

    await _todayEmotionSubscription?.cancel();
    _todayEmotionSubscription = _emotionService
        .watchTodayEmotion(
      session.id.toString(),
    )
        .listen(
      (emotion) async {
        if (!mounted) return;
        setState(() {
          _currentUserEmotion = emotion;
          _isEmotionLoading = false;
        });
        await _cacheTodayEmotion(emotion);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Error listening to emotion updates: $error');
        if (!mounted) return;
        setState(() {
          _isEmotionLoading = false;
        });
      },
    );
  }

  Future<void> _selectEmotion(String emotion) async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isEmotionLoading || _isSavingEmotion) return;

    final username = await _getUsername();
    if (!mounted) return;

    setState(() {
      _isSavingEmotion = true;
    });

    try {
      final result = await _emotionService.saveTodayEmotion(
        userId: session.id.toString(),
        emotion: emotion,
        username: username,
      );

      if (!mounted) return;

      setState(() {
        selectedEmotion = emotion;
        _currentUserEmotion = result.emotion ?? emotion;
      });
      await _cacheTodayEmotion(result.emotion ?? emotion);
    } catch (e) {
      debugPrint('Error saving emotion: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save emotion. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingEmotion = false;
        });
      }
    }
  }

  Future<void> _cacheTodayEmotion(String? emotion) async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = session.id.toString();
    final emotionKey = 'selected_emotion_$userId';
    final dateKey = 'emotion_date_$userId';

    if (emotion == null || emotion.isEmpty) {
      await prefs.remove(emotionKey);
      await prefs.remove(dateKey);
      return;
    }

    await prefs.setString(emotionKey, emotion);
    await prefs.setString(dateKey, _todayDate);
  }

  Future<void> _showCoachProfileDialog({
    Map<String, dynamic>? userData,
    Map<String, dynamic>? coachData,
  }) async {
    final fullNameController = TextEditingController(
      text: (coachData?['fullName'] as String?) ??
          (userData?['username'] as String?) ??
          '',
    );
    final bioController = TextEditingController(
      text: (coachData?['bio'] as String?) ?? '',
    );
    final phoneController = TextEditingController(
      text: (coachData?['phonenumber'] as String?) ??
          (userData?['number'] as String?) ??
          '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                (coachData == null || coachData.isEmpty)
                    ? 'Create Coach Profile'
                    : 'Edit Coach Profile',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bioController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Bio'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneController,
                      decoration:
                          const InputDecoration(labelText: 'Phone Number'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isSavingProfile
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isSavingProfile
                      ? null
                      : () async {
                          if (fullNameController.text.trim().isEmpty ||
                              bioController.text.trim().isEmpty ||
                              phoneController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All fields are required'),
                              ),
                            );
                            return;
                          }

                          setState(() => _isSavingProfile = true);
                          setDialogState(() {});

                          final teamName = fullNameController.text.trim();
                          await UserService.updateUserData(
                            name: teamName,
                            number: phoneController.text.trim(),
                          );

                          if (!mounted) return;
                          setState(() => _isSavingProfile = false);
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Coach profile saved successfully'),
                            ),
                          );
                        },
                  child: Text(
                    (coachData == null || coachData.isEmpty)
                        ? 'Create'
                        : 'Save',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _assignMentee({
    required String menteeId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) async {
    await CoachApiService.instance.assignMentee(
      menteeId: menteeId,
      teamName: teamName,
      groupId: groupId,
      groupName: groupName,
    );
  }

  Future<void> _removeMentee(String menteeId) async {
    await CoachApiService.instance.removeMentee(menteeId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mentee removed from your team')),
    );
  }

  Future<void> _acceptCoachRequest({
    required String requestId,
    required String menteeId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) async {
    await CoachApiService.instance.acceptRequest(
      requestId: requestId,
      teamName: teamName,
      groupId: groupId,
      groupName: groupName,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _createCoachGroup(String name) async {
    final groupName = name.trim();
    if (groupName.isEmpty) {
      throw ArgumentError('Group name is required');
    }
    await CoachApiService.instance.createGroup(name: groupName);
  }

  Future<void> _deleteCoachGroup({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
  }) async {
    await CoachApiService.instance.deleteGroup(groupId);
  }

  Future<void> _declineCoachRequest(String requestId) async {
    await CoachApiService.instance.declineRequest(requestId);
    if (mounted) {
      setState(() {});
    }
  }

  Future<Map<String, dynamic>?> _latestTrackerForUser(String userId) async {
    return CoachApiService.instance.fetchLatestTracker(userId);
  }

  String _formatTrackerDate(Map<String, dynamic>? tracker) {
    final rawDate = tracker?['date'] as String?;
    if (rawDate == null || rawDate.isEmpty) return 'No activity yet';
    try {
      return DateFormat.yMMMd().format(DateTime.parse(rawDate));
    } catch (_) {
      return rawDate;
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.68),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGlassSectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface.withValues(
            alpha: colors.brightness == Brightness.dark ? 0.96 : 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: colors.primary.withValues(
            alpha: colors.brightness == Brightness.dark ? 0.20 : 0.10,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: colors.brightness == Brightness.dark ? 0.18 : 0.05,
            ),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  // A coach can also be a mentee of another coach, so this mirrors the
  // "My Coach" section on the regular dashboard. Assignment lives in the
  // coach_mentees relationship table, not on the user's own profile — see
  // CoachApiService.fetchMyCoaches().
  Future<List<Coach>> _loadMyCoaches() async {
    final coaches = await CoachApiService.instance.fetchMyCoaches();
    return coaches
        .where((data) => (data['id'] as String?) != _userId)
        .map((data) {
          final id = (data['id'] as String?)?.trim() ?? '';
          if (id.isEmpty) return null;

          final name = (data['name'] as String?)?.trim() ?? '';
          return Coach(
            id: id,
            name: name.isNotEmpty ? name : 'My Coach',
            email: (data['email'] as String?) ?? '',
            phone: (data['number'] as String?) ?? '',
            bio: 'Your support coach',
            profilePic: (data['profilePic'] as String?) ?? '',
            backgroundColor: const Color(0xFFDCE5D4),
          );
        })
        .whereType<Coach>()
        .toList();
  }

  Widget _buildMyCoachSection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<List<Coach>>(
      future: _loadMyCoaches(),
      builder: (context, coachSnapshot) {
        final coaches = coachSnapshot.data ?? const <Coach>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'My Coach',
              subtitle: 'You can coach others and still receive support.',
            ),
            const SizedBox(height: 14),
            if (coachSnapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (coaches.isEmpty)
              _buildNoAssignedCoachCard(context)
            else if (coaches.length == 1)
              _buildAssignedCoachCard(context, coach: coaches.first)
            else
              CoachCarousel(
                cards: [
                  for (final coach in coaches)
                    _buildAssignedCoachCard(context, coach: coach),
                ],
                activeDotColor: colors.primary,
                inactiveDotColor: colors.primary.withValues(alpha: 0.25),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNoAssignedCoachCard(
    BuildContext context, {
    String title = 'No coach yet',
    String message =
        'Apply to another coach when you want support as a mentee.',
  }) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pushNamed(context, '/coachesScreen'),
      child: _buildGlassSectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                CupertinoIcons.person_crop_circle_badge_plus,
                color: colors.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.70),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              CupertinoIcons.chevron_right,
              color: colors.onSurface.withValues(alpha: 0.60),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedCoachCard(
    BuildContext context, {
    required Coach coach,
  }) {
    final colors = Theme.of(context).colorScheme;
    return _buildGlassSectionCard(
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: colors.primary.withValues(alpha: 0.10),
                backgroundImage: coach.profilePic.isNotEmpty
                    ? NetworkImage(coach.profilePic)
                    : null,
                child: coach.profilePic.isEmpty
                    ? Icon(Icons.person, color: colors.primary, size: 30)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coach.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coach.bio.isEmpty ? 'Your support coach' : coach.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: colors.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => CoachProfileDialog(coach: coach),
                    );
                  },
                  child: const Text('View profile'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openAssignedCoachChat(
                    context: context,
                    coach: coach,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInboxAction() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatApi.watchRooms(_userId),
      builder: (context, snapshot) {
        var unreadCount = 0;
        for (final chatData in snapshot.data ?? <Map<String, dynamic>>[]) {
          final roomId = (chatData['chatRoomId'] as String?)?.trim() ?? '';
          final localReadTime = _localChatReadOverrides[roomId];
          final lastMessageTimeRaw = chatData['lastMessageTime'];
          final lastMessageTime = lastMessageTimeRaw is String
              ? DateTime.tryParse(lastMessageTimeRaw) ??
                  DateTime.fromMillisecondsSinceEpoch(0)
              : lastMessageTimeRaw is DateTime
                  ? lastMessageTimeRaw
                  : DateTime.fromMillisecondsSinceEpoch(0);
          final lastReadAt = Map<String, dynamic>.from(
            chatData['lastReadAt'] as Map? ?? <String, dynamic>{},
          );
          final lastReadAtRaw = lastReadAt[_userId];
          final readTime = lastReadAtRaw is String
              ? DateTime.tryParse(lastReadAtRaw)
              : lastReadAtRaw is DateTime
                  ? lastReadAtRaw
                  : null;
          final effectiveReadTime = [
            if (readTime != null) readTime,
            if (localReadTime != null) localReadTime,
          ].fold<DateTime?>(
            null,
            (latest, candidate) => latest == null || candidate.isAfter(latest)
                ? candidate
                : latest,
          );
          if (effectiveReadTime != null &&
              !lastMessageTime.isAfter(effectiveReadTime)) {
            continue;
          }

          final unreadCounts = Map<String, dynamic>.from(
            chatData['unreadCounts'] as Map? ?? <String, dynamic>{},
          );
          if (unreadCounts.containsKey(_userId)) {
            final rawValue = unreadCounts[_userId];
            if (rawValue is int) {
              unreadCount += rawValue;
            } else if (rawValue is num) {
              unreadCount += rawValue.toInt();
            }
          } else {
            final lastSenderId =
                (chatData['lastSenderId'] as String?)?.trim() ?? '';
            if (lastSenderId.isNotEmpty &&
                lastSenderId != _userId &&
                (effectiveReadTime == null ||
                    lastMessageTime.isAfter(effectiveReadTime))) {
              unreadCount += 1;
            }
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              color: _companyTheme.iconColor,
              icon: const Icon(CupertinoIcons.chat_bubble_2, size: 24),
              onPressed: () async {
                final dashboard = await _dashboardApi.fetchDashboard();
                final userData = dashboard['user'] is Map
                    ? Map<String, dynamic>.from(dashboard['user'] as Map)
                    : <String, dynamic>{};
                final userName =
                    (userData['name'] as String?)?.trim().isNotEmpty == true
                        ? (userData['name'] as String).trim()
                        : await _getUsername();
                if (!context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatListScreen(
                      userId: _userId,
                      userName: userName,
                      allowGroupChat: true,
                      groupName: (userData['name'] as String?)?.trim(),
                    ),
                  ),
                );
                if (!mounted) return;
                await _loadLocalChatReadOverrides();
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE56B6F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleCoachNotificationTap(
    BuildContext context,
    Map<String, dynamic> notification, {
    required String teamName,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> coachData,
  }) {
    final type = (notification['type'] as String?) ?? '';
    switch (type) {
      case 'mentee_request_received':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CoachManageMenteesPage(
              firestore: _firestore,
              currentUserId: _userId,
              currentUserName: (userData['username'] as String?) ??
                  (coachData['fullName'] as String?) ??
                  'Coach',
              teamName: teamName,
              menteesStream: _menteesStream,
              pendingRequestsStream: _pendingRequestsStream,
              groupsStream: _coachGroupsStream,
              onAssignMentee: _assignMentee,
              onRemoveMentee: _removeMentee,
              onAcceptRequest: _acceptCoachRequest,
              onDeclineRequest: _declineCoachRequest,
              onCreateGroup: _createCoachGroup,
              onDeleteGroup: _deleteCoachGroup,
              latestTrackerForUser: _latestTrackerForUser,
              formatTrackerDate: _formatTrackerDate,
            ),
          ),
        );
        break;
      case 'mentee_progress_logged':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CoachMenteeActivityCalendarPage(
              firestore: _firestore,
              menteesStream: _menteesStream,
            ),
          ),
        );
        break;
      case 'step_submission_received':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CoachStepSubmissionsScreen(),
          ),
        );
        break;
    }
  }

  Widget _buildNotificationAction({
    required String teamName,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> coachData,
  }) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: NotificationApiService.instance.watchNotifications(),
      builder: (context, snapshot) {
        final unreadCountRaw = snapshot.data?['unreadCount'];
        final unreadCount = unreadCountRaw is int ? unreadCountRaw : 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              color: _companyTheme.iconColor,
              icon: const Icon(CupertinoIcons.bell, size: 24),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NotificationsScreen(
                      userId: _userId,
                      onNotificationTap: (tapContext, notification) =>
                          _handleCoachNotificationTap(
                        tapContext,
                        notification,
                        teamName: teamName,
                        userData: userData,
                        coachData: coachData,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE56B6F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  num _scoreFromUserPointData(Map<String, dynamic>? data) {
    return DailyScoreService.resolveDisplayTotalPoints(data);
  }

  String _scoreLabel(num score) {
    return score == score.roundToDouble()
        ? score.toStringAsFixed(0)
        : score.toStringAsFixed(1);
  }

  Widget _buildCoachProfileAndPoints(
    BuildContext context, {
    required String? profilePic,
  }) {
    final theme = _companyTheme;

    return FutureBuilder<Map<String, dynamic>>(
      future: _dashboardApi.fetchDashboard(),
      builder: (context, snapshot) {
        final summary = snapshot.data?['summary'] is Map
            ? Map<String, dynamic>.from(snapshot.data!['summary'] as Map)
            : <String, dynamic>{};
        final totalPoints = _scoreFromUserPointData(summary);
        final totalPointsLabel = _scoreLabel(totalPoints);
        final imageUrl = profilePic?.trim() ?? '';

        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => Navigator.pushNamed(context, '/profile'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: theme.surfaceColor.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.isDark
                    ? theme.primaryColor.withValues(alpha: 0.2)
                    : theme.primaryColor.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (imageUrl.isEmpty)
                  Image.asset(
                    'assets/images/avatar.png',
                    width: 22,
                    height: 22,
                  )
                else
                  ClipOval(
                    child: Image.network(
                      imageUrl,
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/avatar.png',
                          width: 22,
                          height: 22,
                        );
                      },
                    ),
                  ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.isDark
                        ? theme.primaryColor.withValues(alpha: 0.12)
                        : theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.star_fill,
                        size: 10,
                        color: theme.isDark
                            ? theme.primaryColor
                            : const Color(0xFFCE8F5A),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        totalPointsLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: theme.inkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth > 600 ? 28.0 : 20.0;
    final companyTheme = _companyTheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() ?? <String, dynamic>{};

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _coachStream,
          builder: (context, coachSnapshot) {
            final coachData = coachSnapshot.data?.data() ?? <String, dynamic>{};
            // coachData/userData come from Firestore docs that are only
            // populated once a coach profile exists there; new accounts
            // created since the move to Postgres never get one, so both
            // were coming back empty and displayName fell through to the
            // literal 'Coach' placeholder — rendering as "Hello, Coach
            // Coach" next to the hardcoded prefix below. The account's real
            // name always lives in the Postgres-backed session, so use that
            // before falling back to the legacy Firestore fields.
            final sessionName = AuthService.instance.currentSession?.name;
            final teamName = (coachData['fullName'] as String?) ??
                (userData['team'] as String?) ??
                (userData['username'] as String?) ??
                'My Team';
            final displayName = (coachData['fullName'] as String?) ??
                sessionName ??
                (userData['username'] as String?) ??
                'Coach';
            final profilePic = (userData['profilePic'] as String?)?.trim();

            return Scaffold(
              backgroundColor: companyTheme.backgroundColor,
              appBar: AppBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                foregroundColor: companyTheme.iconColor,
                automaticallyImplyLeading: false,
                leadingWidth: 104,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCoachProfileAndPoints(
                      context,
                      profilePic: profilePic,
                    ),
                  ),
                ),
                actions: [
                  _buildInboxAction(),
                  _buildNotificationAction(
                    teamName: teamName,
                    userData: userData,
                    coachData: coachData,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: IconButton(
                      icon: const Icon(
                        CupertinoIcons.line_horizontal_3,
                        size: 28,
                      ),
                      color: companyTheme.iconColor,
                      onPressed: () => BottomSheetWidget.show(context),
                    ),
                  ),
                ],
              ),
              body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _menteesStream,
                builder: (context, menteeSnapshot) {
                  final mentees = menteeSnapshot.data?.docs ?? [];

                  return Stack(
                    key: _dashboardStackKey,
                    children: [
                      SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          8,
                          horizontalPadding,
                          24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHero(
                              displayName: displayName,
                              teamName: teamName,
                              coachData: coachData,
                              menteeCount: mentees.length,
                              userData: userData,
                              quote: _quote,
                              author: _author,
                            ),
                            const SizedBox(height: 22),
                            _buildScrollableFeatureRail(context),
                            const SizedBox(height: 28),
                            _buildMyCoachSection(context),
                            const SizedBox(height: 28),
                            _buildSectionTitle('Coach tools'),
                            const SizedBox(height: 12),
                            _buildNavigationCards(
                              context,
                              teamName: teamName,
                              userData: userData,
                              coachData: coachData,
                              mentees: mentees,
                            ),
                            const SizedBox(height: 24),
                            _buildUnifiedMoodSection(context),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: _buildTileTransitionOverlay(),
                      ),
                      if (selectedEmotion != null)
                        Positioned.fill(
                          child: _buildMoodEffectsOverlay(selectedEmotion!),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHero({
    required String displayName,
    required String teamName,
    required Map<String, dynamic> coachData,
    required int menteeCount,
    required Map<String, dynamic> userData,
    required String quote,
    required String author,
  }) {
    final materialTheme = Theme.of(context);
    final companyTheme = _companyTheme;
    final bio = (coachData['bio'] as String?)?.trim();
    final phone = AuthService.instance.currentSession?.number?.trim();
    final companyLabel = companyTheme.isCompanyTheme
        ? '${companyTheme.companyName} Safespace Coach'
        : 'Safespace Coach';
    final heroColors = companyTheme.isDark
        ? [
            const Color(0xFF031019),
            Color.alphaBlend(
              companyTheme.primaryColor.withValues(alpha: 0.26),
              const Color(0xFF071A24),
            ),
            Color.alphaBlend(
              companyTheme.accentColor.withValues(alpha: 0.22),
              const Color(0xFF031019),
            ),
          ]
        : [
            companyTheme.primaryColor,
            companyTheme.accentColor,
            const Color(0xFFF2E4D0),
          ];
    final badgeContentColor = companyTheme.isDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF355033);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.38),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroColors,
        ),
        boxShadow: [
          BoxShadow(
            color: companyTheme.primaryColor.withValues(
              alpha: companyTheme.isDark ? 0.22 : 0.28,
            ),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: companyTheme.isDark ? 0.1 : 0.28,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: companyTheme.isDark
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'Coach hub',
              style: TextStyle(
                color: badgeContentColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Hello, Coach $displayName',
            style: materialTheme.textTheme.headlineSmall?.copyWith(
              color: companyTheme.inkColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            companyLabel,
            style: TextStyle(
              color: companyTheme.isDark
                  ? companyTheme.primaryColor
                  : const Color(0xFF42563E),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            bio?.isNotEmpty == true
                ? bio!
                : 'Keep your team aligned, support your mentees, and track the day with intention.',
            style: materialTheme.textTheme.bodyLarge?.copyWith(
              color: companyTheme.isDark
                  ? companyTheme.mutedInkColor
                  : const Color(0xFF42563E),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildHeroChip(
                'Team',
                _primaryGroupName?.isNotEmpty == true
                    ? _primaryGroupName!
                    : 'No team yet',
              ),
              _buildHeroChip('Mentees', '${_realMenteeCount ?? 0}'),
              _buildHeroChip(
                'Phone',
                phone?.isNotEmpty == true ? phone! : 'Not set',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: companyTheme.isDark ? 0.08 : 0.34,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: companyTheme.isDark
                    ? companyTheme.primaryColor.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.42),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.quote_bubble_fill,
                      size: 18,
                      color: companyTheme.isDark
                          ? companyTheme.primaryColor
                          : const Color(0xFF4F6047),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Today\'s note',
                      style: TextStyle(
                        color: companyTheme.isDark
                            ? companyTheme.primaryColor
                            : const Color(0xFF4F6047),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  quote,
                  style: TextStyle(
                    color: companyTheme.inkColor,
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  author,
                  style: TextStyle(
                    color: companyTheme.isDark
                        ? companyTheme.mutedInkColor
                        : const Color(0xFF61715B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _showCoachProfileDialog(
              userData: userData,
              coachData: coachData,
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: companyTheme.surfaceColor.withValues(
                alpha: companyTheme.isDark ? 0.12 : 0.92,
              ),
              foregroundColor: companyTheme.isDark
                  ? companyTheme.primaryColor
                  : companyTheme.inkColor,
              side: BorderSide(
                color: companyTheme.isDark
                    ? companyTheme.primaryColor.withValues(alpha: 0.34)
                    : companyTheme.primaryColor.withValues(alpha: 0.24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              coachData.isEmpty ? 'Create Coach Profile' : 'Edit Coach Profile',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip(String label, String value) {
    final companyTheme = _companyTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: companyTheme.isDark ? 0.08 : 0.26,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: companyTheme.isDark
                  ? companyTheme.mutedInkColor
                  : const Color(0xFF5E6E57),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: companyTheme.inkColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClickableInfoCard(
    BuildContext context,
    String tileKey,
    String title,
    String description,
    IconData icon,
    Color color,
    Widget destinationPage, {
    int? setupIndex,
    String? backgroundImage,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.72).clamp(220.0, 310.0);
    final isPressed = _pressedTiles.contains(tileKey);
    final isTransitioning = _activeTileTransition?.tileKey == tileKey;

    return SizedBox(
      width: cardWidth,
      child: Opacity(
        opacity: isTransitioning ? 0 : 1,
        child: AnimatedScale(
          scale: isPressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: isPressed ? const Offset(0, 0.012) : Offset.zero,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: Builder(
              builder: (tileContext) => GestureDetector(
                onTapDown: (_) {
                  setState(() {
                    _pressedTiles.add(tileKey);
                  });
                },
                onTapCancel: () {
                  setState(() {
                    _pressedTiles.remove(tileKey);
                  });
                },
                onTapUp: (_) {
                  setState(() {
                    _pressedTiles.remove(tileKey);
                  });
                },
                onTap: () {
                  _runTileTransition(
                    tileContext: tileContext,
                    tileKey: tileKey,
                    title: title,
                    description: description,
                    icon: icon,
                    color: color,
                    destinationPage: destinationPage,
                    setupIndex: setupIndex,
                  );
                },
                child: _buildTileFace(
                  title: title,
                  description: description,
                  icon: icon,
                  color: color,
                  isPressed: isPressed,
                  backgroundImage: backgroundImage,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableFeatureRail(BuildContext context) {
    final companyTheme = _companyTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Today's focus"),
        const SizedBox(height: 6),
        Text(
          'Lead by example and keep your habits visible.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: companyTheme.mutedInkColor,
              ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 184,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildClickableInfoCard(
                context,
                'steps_tile',
                'Steps',
                'Track your movement and keep your coaching energy active.',
                CupertinoIcons.flame_fill,
                const Color(0xFFDDE7D5),
                StepTracker(),
                setupIndex: 1,
                backgroundImage: 'assets/images/steps.gif',
              ),
              const SizedBox(width: 14),
              _buildClickableInfoCard(
                context,
                'exercise_tile',
                'Exercise',
                'Log pilates, gym, yoga, sports, or any custom workout.',
                Icons.fitness_center,
                const Color(0xFFE9E4F2),
                const ExerciseTrackerScreen(),
                backgroundImage: 'assets/images/exercise.gif',
              ),
              const SizedBox(width: 14),
              _buildClickableInfoCard(
                context,
                'meditate_tile',
                'Meditate',
                'Reset your attention before guiding someone else.',
                CupertinoIcons.sparkles,
                const Color(0xFFE8E3D8),
                Meditation(),
                setupIndex: 0,
                backgroundImage: 'assets/images/meditate.gif',
              ),
              const SizedBox(width: 14),
              _buildClickableInfoCard(
                context,
                'fasting_tile',
                'Fasting',
                'Stay on your plan and model consistency for your mentees.',
                CupertinoIcons.timer_fill,
                const Color(0xFFF2E5D2),
                const FastingTimerScreen(),
                backgroundImage: 'assets/images/fasting.gif',
              ),
              const SizedBox(width: 14),
              _buildClickableInfoCard(
                context,
                'calories_tile',
                'Calories',
                'Log meals and keep nutrition choices visible.',
                CupertinoIcons.leaf_arrow_circlepath,
                const Color(0xFFE1EDDF),
                const CalorieTrackerScreen(),
                backgroundImage: 'assets/images/calorie.gif',
              ),
              const SizedBox(width: 14),
              _buildClickableInfoCard(
                context,
                'sleep_tile',
                'Sleep',
                'Protect your recovery so your coaching stays steady.',
                CupertinoIcons.moon_zzz_fill,
                const Color(0xFFDDE4F0),
                const SleepTracker(),
                backgroundImage: 'assets/images/sleep.gif',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTileFace({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    bool isPressed = false,
    String? backgroundImage,
  }) {
    final companyTheme = _companyTheme;
    final tileBase = companyTheme.isDark
        ? Color.alphaBlend(
            color.withValues(alpha: 0.12),
            companyTheme.surfaceColor,
          )
        : Color.alphaBlend(
            color.withValues(alpha: 0.42),
            companyTheme.surfaceColor,
          );
    final borderColor = companyTheme.primaryColor.withValues(
      alpha: companyTheme.isDark ? 0.28 : 0.18,
    );
    final softOverlay = companyTheme.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.58);
    final iconPanelColor = companyTheme.isDark
        ? companyTheme.primaryColor.withValues(alpha: 0.16)
        : companyTheme.surfaceColor.withValues(alpha: 0.68);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 184,
      // Without this, none of the Stack's decorative circles/icon badge
      // (several positioned right at or past the card edges, like the big
      // accent circle at top:-28/right:-18) get clipped to the card's
      // rounded corners -- they render with their own sharp bounds, poking
      // past the rounded shape instead of sitting inline with it.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            companyTheme.surfaceColor.withValues(
              alpha: companyTheme.isDark ? 0.96 : 0.84,
            ),
            tileBase,
            Color.alphaBlend(
              companyTheme.primaryColor.withValues(
                alpha: companyTheme.isDark ? 0.10 : 0.16,
              ),
              tileBase,
            ),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: companyTheme.primaryColor.withValues(
              alpha: isPressed ? 0.10 : 0.18,
            ),
            blurRadius: isPressed ? 16 : 26,
            offset: Offset(0, isPressed ? 8 : 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (backgroundImage != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Opacity(
                  opacity: 0.3,
                  child: Image.asset(
                    backgroundImage,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          Positioned(
            top: -28,
            right: -18,
            child: Container(
              width: 126,
              height: 126,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    softOverlay,
                    softOverlay.withValues(alpha: 0.02),
                  ],
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -18,
            left: -14,
            child: Transform.rotate(
              angle: -0.45,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      softOverlay.withValues(alpha: 0.34),
                      softOverlay.withValues(alpha: 0.08),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white
                        .withValues(alpha: companyTheme.isDark ? 0.04 : 0.1),
                    Colors.transparent,
                    Colors.black
                        .withValues(alpha: companyTheme.isDark ? 0.18 : 0.06),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: iconPanelColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                icon,
                color: companyTheme.iconColor,
                size: 27,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: companyTheme.primaryColor.withValues(
                      alpha: companyTheme.isDark ? 0.16 : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Coach practice',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: companyTheme.iconColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: companyTheme.inkColor,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: companyTheme.mutedInkColor,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'Open',
                      style: TextStyle(
                        color: companyTheme.iconColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: companyTheme.primaryColor.withValues(
                          alpha: companyTheme.isDark ? 0.18 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: companyTheme.iconColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runTileTransition({
    required BuildContext tileContext,
    required String tileKey,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required Widget destinationPage,
    int? setupIndex,
  }) async {
    if (_activeTileTransition != null) return;

    final stackContext = _dashboardStackKey.currentContext;
    if (stackContext == null) return;

    final tileBox = tileContext.findRenderObject() as RenderBox?;
    final stackBox = stackContext.findRenderObject() as RenderBox?;
    if (tileBox == null || stackBox == null) return;

    final topLeft = stackBox.globalToLocal(tileBox.localToGlobal(Offset.zero));
    final rect = topLeft & tileBox.size;

    setState(() {
      _pressedTiles.remove(tileKey);
      _activeTileTransition = _CoachDashboardTileTransition(
        tileKey: tileKey,
        rect: rect,
        title: title,
        description: description,
        icon: icon,
        color: color,
      );
    });

    await _tileTransitionController.forward(from: 0);
    if (!mounted) return;

    // The regular user dashboard reaches these same feature pages through
    // named routes wrapped in `_companyThemed` (see main.dart), so they pick
    // up the company theme. This tile grid instead pushes the destination
    // page directly through a bare PageRouteBuilder, so without this Theme
    // wrapper the page would fall back to the app's default light theme
    // instead of matching the rest of the coach dashboard.
    final targetPage = setupIndex != null
        ? CoachSetuppage(initialIndex: setupIndex)
        : Theme(
            data: AppTheme.company(_companyTheme),
            child: destinationPage,
          );

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) => targetPage,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.02, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    _tileTransitionController.reset();
    setState(() {
      _activeTileTransition = null;
    });
  }

  Widget _buildTileTransitionOverlay() {
    final transition = _activeTileTransition;
    if (transition == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _tileTransitionController,
        builder: (context, child) {
          final t =
              Curves.easeInOutCubic.transform(_tileTransitionController.value);
          final size = MediaQuery.of(context).size;
          final targetWidth = size.width.clamp(280.0, 420.0) * 0.82;
          final targetHeight = 260.0;
          final targetRect = Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: targetWidth,
            height: targetHeight,
          );
          final moveT =
              Curves.easeOutCubic.transform((t / 0.42).clamp(0.0, 1.0));
          final scatterT = ((t - 0.58) / 0.42).clamp(0.0, 1.0);
          final currentRect = Rect.lerp(transition.rect, targetRect, moveT)!;
          final overlayOpacity =
              Tween<double>(begin: 0, end: 0.22).transform(t);
          final tileOpacity = scatterT > 0
              ? (1 - Curves.easeInCubic.transform(scatterT))
                  .clamp(0.0, 1.0)
                  .toDouble()
              : 1.0;
          final turns = scatterT > 0
              ? Tween<double>(begin: 0, end: 1.12).transform(
                  Curves.easeInOutCubic.transform(scatterT),
                )
              : 0.0;
          final scaleBoost = scatterT > 0
              ? Tween<double>(begin: 1.0, end: 1.12).transform(
                  Curves.easeInOut.transform(scatterT),
                )
              : 1.0;

          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: overlayOpacity,
                  child: Container(color: const Color(0xFF24311F)),
                ),
              ),
              Positioned(
                left: currentRect.left,
                top: currentRect.top,
                width: currentRect.width,
                height: currentRect.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(
                      opacity: tileOpacity,
                      child: Transform.scale(
                        scale: scaleBoost,
                        child: Transform.rotate(
                          angle: turns * 3.141592653589793 * 2,
                          child: child,
                        ),
                      ),
                    ),
                    if (scatterT > 0)
                      ..._buildTileScatterFragments(
                        size: currentRect.size,
                        color: transition.color,
                        progress: scatterT,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
        child: _buildTileFace(
          title: transition.title,
          description: transition.description,
          icon: transition.icon,
          color: transition.color,
        ),
      ),
    );
  }

  List<Widget> _buildTileScatterFragments({
    required Size size,
    required Color color,
    required double progress,
  }) {
    const fragments = [
      (
        ax: -0.34,
        ay: -0.22,
        size: 26.0,
        radius: 10.0,
        dx: -120.0,
        dy: -88.0,
        rot: -0.9
      ),
      (
        ax: 0.28,
        ay: -0.18,
        size: 20.0,
        radius: 8.0,
        dx: 128.0,
        dy: -96.0,
        rot: 1.1
      ),
      (
        ax: -0.18,
        ay: 0.08,
        size: 22.0,
        radius: 9.0,
        dx: -96.0,
        dy: 24.0,
        rot: 0.8
      ),
      (
        ax: 0.16,
        ay: 0.16,
        size: 18.0,
        radius: 8.0,
        dx: 90.0,
        dy: 46.0,
        rot: -1.2
      ),
      (
        ax: -0.04,
        ay: 0.26,
        size: 24.0,
        radius: 10.0,
        dx: -18.0,
        dy: 136.0,
        rot: 1.0
      ),
      (
        ax: 0.34,
        ay: 0.02,
        size: 16.0,
        radius: 7.0,
        dx: 144.0,
        dy: 8.0,
        rot: 1.4
      ),
    ];

    final eased = Curves.easeOutCubic.transform(progress);
    final fade =
        (1 - Curves.easeInQuad.transform(progress)).clamp(0.0, 1.0).toDouble();
    final center = Offset(size.width / 2, size.height / 2);

    return fragments.map((fragment) {
      final start = Offset(
        center.dx + size.width * fragment.ax,
        center.dy + size.height * fragment.ay,
      );
      final end = Offset(
        start.dx + fragment.dx,
        start.dy + fragment.dy,
      );
      final current = Offset.lerp(start, end, eased)!;

      return Positioned(
        left: current.dx - (fragment.size / 2),
        top: current.dy - (fragment.size / 2),
        child: Opacity(
          opacity: fade,
          child: Transform.rotate(
            angle: fragment.rot *
                Curves.easeInOut.transform(progress) *
                3.141592653589793,
            child: Container(
              width: fragment.size,
              height: fragment.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fragment.radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.84),
                    Color.alphaBlend(const Color(0x33FFFFFF), color),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildNavigationCards(
    BuildContext context, {
    required String teamName,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> coachData,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
  }) {
    return Column(
      children: [
        _buildNavigationCard(
          title: 'Manage mentees',
          subtitle: 'Add or remove mentees from a cleaner dedicated page.',
          icon: CupertinoIcons.person_2_fill,
          color: const Color(0xFFDDE7D5),
          actionLabel: 'Manage',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CoachManageMenteesPage(
                  firestore: _firestore,
                  currentUserId: _userId,
                  currentUserName: (userData['username'] as String?) ??
                      (coachData['fullName'] as String?) ??
                      'Coach',
                  teamName: teamName,
                  menteesStream: _menteesStream,
                  pendingRequestsStream: _pendingRequestsStream,
                  groupsStream: _coachGroupsStream,
                  onAssignMentee: _assignMentee,
                  onRemoveMentee: _removeMentee,
                  onAcceptRequest: _acceptCoachRequest,
                  onDeclineRequest: _declineCoachRequest,
                  onCreateGroup: _createCoachGroup,
                  onDeleteGroup: _deleteCoachGroup,
                  latestTrackerForUser: _latestTrackerForUser,
                  formatTrackerDate: _formatTrackerDate,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildNavigationCard(
          title: 'Manage groups',
          subtitle: 'Create groups, assign mentees, and compare group scores.',
          icon: CupertinoIcons.rectangle_grid_2x2_fill,
          color: const Color(0xFFF4E6C8),
          actionLabel: 'Organize',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CoachGroupCustomizationPage(
                  firestore: _firestore,
                  currentUserId: _userId,
                  teamName: teamName,
                  menteesStream: _menteesStream,
                  groupsStream: _coachGroupsStream,
                  onCreateGroup: _createCoachGroup,
                  onDeleteGroup: _deleteCoachGroup,
                  onAssignMentee: _assignMentee,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildNavigationCard(
          title: 'Recent activity',
          subtitle:
              'See all mentee progress in a calendar view like user progress.',
          icon: CupertinoIcons.calendar,
          color: const Color(0xFFE7EDF4),
          actionLabel: 'View',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CoachMenteeActivityCalendarPage(
                  firestore: _firestore,
                  menteesStream: _menteesStream,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildNavigationCard(
          title: 'Step submissions',
          subtitle: 'Review manually logged steps and their proof photos.',
          icon: CupertinoIcons.check_mark_circled,
          color: const Color(0xFFF4E0DC),
          actionLabel: 'Review',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CoachStepSubmissionsScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNavigationCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final companyTheme = _companyTheme;
    final cardColor = companyTheme.isDark
        ? Color.alphaBlend(
            color.withValues(alpha: 0.10),
            companyTheme.surfaceColor,
          )
        : Color.alphaBlend(
            color.withValues(alpha: 0.42),
            companyTheme.surfaceColor,
          );
    final onPrimary = companyTheme.primaryColor.computeLuminance() > 0.48
        ? Colors.black
        : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: companyTheme.primaryColor.withValues(
            alpha: companyTheme.isDark ? 0.24 : 0.14,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: companyTheme.primaryColor.withValues(
                alpha: companyTheme.isDark ? 0.18 : 0.12,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: companyTheme.iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: companyTheme.inkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: companyTheme.mutedInkColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: companyTheme.primaryColor,
              foregroundColor: onPrimary,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodSection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('How do you feel today?'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.10),
            ),
          ),
          child: _currentUserEmotion == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildEmojiMood('😀', () => _selectEmotion('happy')),
                    _buildEmojiMood('😐', () => _selectEmotion('neutral')),
                    _buildEmojiMood('😔', () => _selectEmotion('sad')),
                    _buildEmojiMood('😡', () => _selectEmotion('angry')),
                  ],
                )
              : Column(
                  children: [
                    Text(
                      'Today I\'m feeling $_currentUserEmotion',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmotionTrackerPage(),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Track Your Emotions',
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.primary,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: colors.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildEmojiMood(String emoji, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 36)),
        ),
      ),
    );
  }

  Widget _buildUnifiedMoodSection(BuildContext context) {
    final companyTheme = _companyTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Mood check-in",
          subtitle: "Keep track of how today feels, not just what you finish.",
        ),
        const SizedBox(height: 14),
        _buildGlassSectionCard(
          child: _isEmotionLoading
              ? const SizedBox(
                  height: 132,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : _currentUserEmotion == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Choose the mood that feels closest right now.",
                          style: TextStyle(
                            color: companyTheme.mutedInkColor,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        AbsorbPointer(
                          absorbing: _isSavingEmotion,
                          child: Opacity(
                            opacity: _isSavingEmotion ? 0.62 : 1,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: _buildUnifiedMoodChoice(
                                      icon: CupertinoIcons.smiley_fill,
                                      label: "Happy",
                                      color: const Color(0xFFF5DEB0),
                                      onTap: () => _selectEmotion("happy"),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0),
                                    child: _buildUnifiedMoodChoice(
                                      icon: CupertinoIcons.minus_circle_fill,
                                      label: "Neutral",
                                      color: const Color(0xFFE6E4DE),
                                      onTap: () => _selectEmotion("neutral"),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0),
                                    child: _buildUnifiedMoodChoice(
                                      icon: CupertinoIcons.cloud_rain_fill,
                                      label: "Sad",
                                      color: const Color(0xFFDCE6F3),
                                      onTap: () => _selectEmotion("sad"),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: _buildUnifiedMoodChoice(
                                      icon: CupertinoIcons.flame_fill,
                                      label: "Angry",
                                      color: const Color(0xFFF2D2C6),
                                      onTap: () => _selectEmotion("angry"),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isSavingEmotion) ...[
                          const SizedBox(height: 14),
                          Text(
                            "Saving your mood...",
                            style: TextStyle(
                              color: companyTheme.mutedInkColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: companyTheme.isDark
                                    ? companyTheme.primaryColor
                                        .withValues(alpha: 0.14)
                                    : const Color(0xFFDDE7D5),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                CupertinoIcons.heart_fill,
                                color: companyTheme.isDark
                                    ? companyTheme.primaryColor
                                    : const Color(0xFF5E7652),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                "Today you're feeling $_currentUserEmotion",
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: companyTheme.inkColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Nice check-in. You can keep a longer emotion history in the tracker whenever you want.",
                          style: TextStyle(
                            color: companyTheme.mutedInkColor,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EmotionTrackerPage(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: companyTheme.isDark
                                ? companyTheme.primaryColor
                                : const Color(0xFF6E8464),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Track Your Emotions",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildUnifiedMoodChoice({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: const Color(0xFF4A5E45), size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodOverlay(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/happy.gif'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'sad':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/rain.gif'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'angry':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/angry.gif'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'neutral':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/neutral.gif'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMoodEffectsOverlay(String emotion) {
    final message = _getMoodPopupMessage(emotion);
    final title = emotion[0].toUpperCase() + emotion.substring(1);

    return Stack(
      children: [
        _buildMoodOverlay(emotion),
        Container(
          color: Colors.black.withValues(alpha: 0.24),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22.0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F0E5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _getMoodPopupIcon(emotion),
                                color: const Color(0xFF4A5E45),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "$title mood selected",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedEmotion = null;
                          });
                        },
                        child: const Icon(
                          Icons.close,
                          size: 22,
                          color: Color(0xFF4A5E45),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF4A5E45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getMoodPopupMessage(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return 'Keep the joy going. Continue being happy every day and spread positivity to others.';
      case 'sad':
        return 'It is okay to feel sad. Take a deep breath, be kind to yourself, and let this moment pass.';
      case 'angry':
        return 'Your feelings matter. Release the tension, stay calm, and choose a peaceful next step.';
      case 'neutral':
        return 'A calm mood is balanced energy. Keep the steady pace and enjoy the little wins today.';
      default:
        return 'Your emotion is noted. Keep moving forward with care and positivity.';
    }
  }

  IconData _getMoodPopupIcon(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return CupertinoIcons.smiley_fill;
      case 'sad':
        return CupertinoIcons.cloud_rain_fill;
      case 'angry':
        return CupertinoIcons.flame_fill;
      case 'neutral':
        return CupertinoIcons.moon_fill;
      default:
        return CupertinoIcons.heart_fill;
    }
  }

  Widget _buildEmptyStateCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }
}

class CoachTeamOverviewPage extends StatelessWidget {
  const CoachTeamOverviewPage({
    super.key,
    required this.teamName,
    required this.userData,
    required this.coachData,
    required this.menteeCount,
    required this.onEditProfile,
    required this.onOpenInbox,
  });

  final String teamName;
  final Map<String, dynamic> userData;
  final Map<String, dynamic> coachData;
  final int menteeCount;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenInbox;

  @override
  Widget build(BuildContext context) {
    final hasProfile = coachData.isNotEmpty;
    final username = (userData['username'] as String?) ?? 'Coach';

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'Team overview',
              style: TextStyle(color: companyTheme.inkColor),
            ),
            backgroundColor: Colors.transparent,
            foregroundColor: companyTheme.iconColor,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: companyTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: companyTheme.isDark
                        ? companyTheme.primaryColor.withValues(alpha: 0.18)
                        : companyTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: companyTheme.primaryColor.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasProfile
                          ? (coachData['fullName'] as String? ?? teamName)
                          : username,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: companyTheme.inkColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasProfile
                          ? (coachData['bio'] as String? ??
                              'Coach profile ready')
                          : 'Create your coach profile so users can connect with you and your team stays organized.',
                      style: TextStyle(
                        height: 1.45,
                        color: companyTheme.mutedInkColor,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FutureBuilder<List<dynamic>>(
                      future: Future.wait([
                        CoachApiService.instance.fetchMentees(),
                        CoachApiService.instance.fetchGroups(),
                      ]),
                      builder: (context, snapshot) {
                        final mentees =
                            (snapshot.data?[0] as List?) ?? const [];
                        final groups = (snapshot.data?[1] as List?) ?? const [];
                        final primaryGroupName = groups.isNotEmpty
                            ? (groups.first as Map)['name'] as String?
                            : null;
                        final phone =
                            AuthService.instance.currentSession?.number?.trim();

                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _OverviewChip(
                              'Team name',
                              primaryGroupName?.isNotEmpty == true
                                  ? primaryGroupName!
                                  : 'No team yet',
                            ),
                            _OverviewChip(
                              'Assigned mentees',
                              '${mentees.length}',
                            ),
                            _OverviewChip(
                              'Phone',
                              phone?.isNotEmpty == true ? phone! : 'Not set',
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: onEditProfile,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                              hasProfile ? 'Edit profile' : 'Create profile'),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: companyTheme.primaryColor,
                            foregroundColor: companyTheme.isDark
                                ? companyTheme.backgroundColor
                                : Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: onOpenInbox,
                          icon: const Icon(CupertinoIcons.chat_bubble_2_fill),
                          label: const Text('Open inbox'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: companyTheme.isDark
                                ? companyTheme.primaryColor
                                : companyTheme.inkColor,
                            side: BorderSide(
                              color: companyTheme.primaryColor.withValues(
                                alpha: companyTheme.isDark ? 0.34 : 0.26,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CoachGroupCustomizationPage extends StatelessWidget {
  const CoachGroupCustomizationPage({
    super.key,
    required this.firestore,
    required this.currentUserId,
    required this.teamName,
    required this.menteesStream,
    required this.groupsStream,
    required this.onCreateGroup,
    required this.onDeleteGroup,
    required this.onAssignMentee,
  });

  final FirebaseFirestore firestore;
  final String currentUserId;
  final String teamName;
  final Stream<QuerySnapshot<Map<String, dynamic>>> menteesStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> groupsStream;
  final Future<void> Function(String name) onCreateGroup;
  final Future<void> Function({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
  }) onDeleteGroup;
  final Future<void> Function({
    required String menteeId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) onAssignMentee;

  String _normalizeName(String value) => value.trim().toLowerCase();

  int _extractIntValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  int _calculateLeaderboardScore(Map<String, dynamic> data) {
    final taskPoints = Map<String, dynamic>.from(
      data['taskPoints'] as Map? ?? <String, dynamic>{},
    );
    final callIntent = _extractIntValue(
      taskPoints,
      ['Call Points', 'call_points', 'callPoints'],
    );
    final meditationMinutes = _extractIntValue(
      taskPoints,
      ['Meditation Points', 'meditation_points', 'meditationPoints'],
    );
    final stepsTaken = _extractIntValue(
          taskPoints,
          ['Steps Points', 'steps_points', 'stepsPoints'],
        ) *
        200;
    final valueEntries = _extractIntValue(
      taskPoints,
      ['Add Value Points', 'value_points', 'addValuePoints'],
    );
    final learningEntries = _extractIntValue(
      taskPoints,
      ['Learning Points', 'learning_points', 'learningPoints'],
    );
    final todoListPoints = _extractIntValue(
      taskPoints,
      ['Goals Points', 'todo_list_points', 'todoListPoints'],
    );

    return callIntent +
        meditationMinutes +
        (stepsTaken / 200).floor() +
        valueEntries +
        learningEntries +
        todoListPoints;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedGroups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
  ) {
    return groups.toList()
      ..sort((a, b) {
        final aName = (a.data()['name'] as String?)?.trim() ?? '';
        final bName = (b.data()['name'] as String?)?.trim() ?? '';
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
  }

  Map<String, int> _scoreByMenteeId(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pointDocs,
  ) {
    final menteeIdsByName = <String, String>{};
    for (final mentee in mentees) {
      final username = (mentee.data()['username'] as String?)?.trim() ?? '';
      if (username.isNotEmpty) {
        menteeIdsByName[_normalizeName(username)] = mentee.id;
      }
    }

    final scores = <String, int>{};
    for (final doc in pointDocs) {
      final data = doc.data();
      final username = (data['username'] as String?)?.trim() ?? '';
      final menteeId = menteeIdsByName[_normalizeName(username)];
      if (menteeId == null) continue;
      final score = _calculateLeaderboardScore(data);
      final currentScore = scores[menteeId] ?? 0;
      if (score > currentScore) {
        scores[menteeId] = score;
      }
    }
    return scores;
  }

  String _displayName(QueryDocumentSnapshot<Map<String, dynamic>> mentee) {
    final data = mentee.data();
    final username = (data['username'] as String?)?.trim() ?? '';
    if (username.isNotEmpty) return username;
    final email = (data['email'] as String?)?.trim() ?? '';
    if (email.isNotEmpty) return email.split('@').first;
    return 'Mentee';
  }

  String _currentGroupName(QueryDocumentSnapshot<Map<String, dynamic>> mentee) {
    final groups =
        Map<String, dynamic>.from(mentee.data()['coachGroups'] as Map? ?? {});
    final current =
        Map<String, dynamic>.from(groups[currentUserId] as Map? ?? {});
    final groupName = (current['groupName'] as String?)?.trim() ?? '';
    return groupName.isNotEmpty ? groupName : teamName;
  }

  List<_CoachGroupMenteeScore> _rankGroupMembers({
    required QueryDocumentSnapshot<Map<String, dynamic>> group,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    required Map<String, int> scores,
  }) {
    final memberIds = List<String>.from(
      group.data()['memberIds'] as List? ?? const <String>[],
    ).toSet();
    final members = mentees.where((mentee) => memberIds.contains(mentee.id));
    final ranked = members.map((mentee) {
      return _CoachGroupMenteeScore(
        mentee: mentee,
        score: scores[mentee.id] ?? 0,
      );
    }).toList()
      ..sort((a, b) {
        if (a.score != b.score) return b.score.compareTo(a.score);
        return _displayName(a.mentee).compareTo(_displayName(b.mentee));
      });
    return ranked;
  }

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    final groupName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _CoachGroupNameDialog(
          hintText: 'Example: Evening group',
        );
      },
    );

    if (groupName == null || groupName.isEmpty) return;
    await onCreateGroup(groupName);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$groupName created.')),
    );
  }

  Future<void> _showAddCoachDialog(
    BuildContext context,
    _CoachApiGroupSummary summary,
  ) async {
    if (summary.coachIds.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This group already has 2 coaches.')),
      );
      return;
    }

    final coaches = await CoachApiService.instance.fetchCoaches();
    final availableCoaches = coaches.where((coach) {
      final coachId = coach['id']?.toString() ?? '';
      return coachId.isNotEmpty &&
          coachId != currentUserId &&
          !summary.coachIds.contains(coachId);
    }).toList();

    if (!context.mounted) return;
    if (availableCoaches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other coaches are available to add.')),
      );
      return;
    }

    final selectedCoachId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add another coach to ${summary.groupName}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: availableCoaches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final coach = availableCoaches[index];
                      final coachId = coach['id']?.toString() ?? '';
                      final coachName =
                          (coach['name'] as String?)?.trim().isNotEmpty == true
                              ? (coach['name'] as String).trim()
                              : 'Coach';
                      final coachEmail =
                          (coach['email'] as String?)?.trim() ?? '';
                      final profilePic =
                          (coach['profilePic'] as String?)?.trim() ?? '';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage: profilePic.isNotEmpty
                              ? NetworkImage(profilePic)
                              : null,
                          backgroundColor:
                              colors.primary.withValues(alpha: 0.10),
                          child: profilePic.isEmpty
                              ? Text(
                                  coachName.isNotEmpty ? coachName[0] : '?',
                                )
                              : null,
                        ),
                        title: Text(
                          coachName,
                          style: TextStyle(color: colors.onSurface),
                        ),
                        subtitle: coachEmail.isEmpty
                            ? null
                            : Text(
                                coachEmail,
                                style: TextStyle(
                                  color:
                                      colors.onSurface.withValues(alpha: 0.68),
                                ),
                              ),
                        onTap: () => Navigator.pop(sheetContext, coachId),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedCoachId == null || selectedCoachId.isEmpty) return;
    final updatedCoachIds = <String>{
      ...summary.coachIds,
      selectedCoachId,
      currentUserId,
    }.toList();
    await CoachApiService.instance.updateGroupCoaches(
      groupId: summary.groupId,
      coachIds: updatedCoachIds,
    );
    if (!context.mounted) return;
    final selectedCoach = availableCoaches.firstWhere(
      (coach) => coach['id']?.toString() == selectedCoachId,
      orElse: () => <String, dynamic>{},
    );
    final selectedCoachName = (selectedCoach['name'] as String?)?.trim() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selectedCoachName.isEmpty
              ? 'Coach added to ${summary.groupName}.'
              : '$selectedCoachName added to ${summary.groupName}.',
        ),
      ),
    );
  }

  Future<void> _showAddMenteeToGroupDialog(
    BuildContext context,
    _CoachApiGroupSummary summary,
  ) async {
    List<Map<String, dynamic>> users;
    try {
      users = await CoachApiService.instance.fetchUsers();
    } catch (error) {
      debugPrint('Failed to load users for group: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load users right now. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final availableUsers = users.where((user) {
      final userId = user['id']?.toString() ?? '';
      final isCoach = user['isCoach'] == true ||
          ((user['role'] as String?)?.toLowerCase() == 'coach');
      final isMyAcceptedMentee = user['assignedToMe'] == true;
      return userId.isNotEmpty &&
          userId != currentUserId &&
          !summary.memberIds.contains(userId) &&
          !isCoach &&
          isMyAcceptedMentee;
    }).toList();

    if (!context.mounted) return;
    if (availableUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No mentees are available to add to ${summary.groupName}.',
          ),
        ),
      );
      return;
    }

    final searchController = TextEditingController();
    try {
      final selectedUser = await showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final query = searchController.text.trim().toLowerCase();
              final filteredUsers = availableUsers.where((user) {
                final name = (user['name'] as String?)?.toLowerCase() ?? '';
                final email = (user['email'] as String?)?.toLowerCase() ?? '';
                return query.isEmpty ||
                    name.contains(query) ||
                    email.contains(query);
              }).toList();

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    8,
                    18,
                    MediaQuery.of(sheetContext).viewInsets.bottom + 18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add mentee to ${summary.groupName}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search mentee',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: filteredUsers.isEmpty
                            ? const Center(child: Text('No mentees found.'))
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredUsers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final user = filteredUsers[index];
                                  final userName = (user['name'] as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? (user['name'] as String).trim()
                                      : ((user['email'] as String?)
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? (user['email'] as String)
                                              .trim()
                                              .split('@')
                                              .first
                                          : 'Mentee');
                                  final profilePic =
                                      (user['profilePic'] as String?)?.trim() ??
                                          '';
                                  final email =
                                      (user['email'] as String?)?.trim() ?? '';

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundImage: profilePic.isNotEmpty
                                          ? NetworkImage(profilePic)
                                          : null,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.08),
                                      child: profilePic.isEmpty
                                          ? Text(
                                              userName.isNotEmpty
                                                  ? userName[0].toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(userName),
                                    subtitle: Text(email),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, user),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (selectedUser == null) return;
      final userId = selectedUser['id']?.toString() ?? '';
      if (userId.isEmpty) return;

      await CoachApiService.instance.assignMentee(
        menteeId: userId,
        teamName: teamName,
        groupId: summary.groupId,
        groupName: summary.groupName,
      );
      if (!context.mounted) return;

      final selectedUserName =
          (selectedUser['name'] as String?)?.trim().isNotEmpty == true
              ? (selectedUser['name'] as String).trim()
              : ((selectedUser['email'] as String?)?.trim().isNotEmpty == true
                  ? (selectedUser['email'] as String).trim().split('@').first
                  : 'Mentee');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$selectedUserName added to ${summary.groupName}.'),
        ),
      );
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _confirmDeleteGroup({
    required BuildContext context,
    required String groupId,
    required String groupName,
    required List<String> memberIds,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Delete group?'),
          content: Text(
            memberIds.isEmpty
                ? 'This will permanently delete $groupName.'
                : 'This will permanently delete $groupName and remove it from ${memberIds.length} mentees.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE56B6F),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;
    await onDeleteGroup(
      groupId: groupId,
      groupName: groupName,
      memberIds: memberIds,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$groupName deleted.')),
    );
  }

  Future<void> _showEditMembersSheet({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> group,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    required Map<String, int> scores,
  }) async {
    final groupName = (group.data()['name'] as String?)?.trim() ?? 'Group';
    final originalMembers = List<String>.from(
      group.data()['memberIds'] as List? ?? const <String>[],
    ).toSet();
    final selectedMembers = originalMembers.toSet();
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  8,
                  18,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 18,
                ),
                child: SizedBox(
                  height: MediaQuery.of(sheetContext).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select mentees for $groupName',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: mentees.length,
                          itemBuilder: (context, index) {
                            final mentee = mentees[index];
                            final name = _displayName(mentee);
                            final currentGroup = _currentGroupName(mentee);
                            final selected =
                                selectedMembers.contains(mentee.id);
                            return CheckboxListTile(
                              value: selected,
                              onChanged: isSaving
                                  ? null
                                  : (value) {
                                      setSheetState(() {
                                        if (value == true) {
                                          selectedMembers.add(mentee.id);
                                        } else {
                                          selectedMembers.remove(mentee.id);
                                        }
                                      });
                                    },
                              title: Text(name),
                              subtitle: Text(
                                '${scores[mentee.id] ?? 0} pts • $currentGroup',
                              ),
                            );
                          },
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(sheetContext),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setSheetState(() => isSaving = true);
                                      for (final mentee in mentees) {
                                        final wasSelected =
                                            originalMembers.contains(mentee.id);
                                        final isSelected =
                                            selectedMembers.contains(mentee.id);
                                        if (isSelected && !wasSelected) {
                                          await onAssignMentee(
                                            menteeId: mentee.id,
                                            teamName: teamName,
                                            groupId: group.id,
                                            groupName: groupName,
                                          );
                                        } else if (!isSelected && wasSelected) {
                                          await onAssignMentee(
                                            menteeId: mentee.id,
                                            teamName: teamName,
                                          );
                                        }
                                      }
                                      if (!sheetContext.mounted) return;
                                      Navigator.pop(sheetContext);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('$groupName updated.'),
                                        ),
                                      );
                                    },
                              child: Text(isSaving ? 'Saving...' : 'Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showGroupLeaderboardSheet({
    required BuildContext context,
    required String groupName,
    required List<_CoachGroupMenteeScore> members,
    required int totalScore,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.68,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total score: $totalScore pts',
                    style: const TextStyle(
                      color: Color(0xFF6B7165),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: members.isEmpty
                        ? const Center(child: Text('No mentees in this group.'))
                        : ListView.builder(
                            itemCount: members.length,
                            itemBuilder: (context, index) {
                              final member = members[index];
                              return _buildRankedMenteeTile(
                                member: member,
                                rank: index + 1,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRankedMenteeTile({
    required _CoachGroupMenteeScore member,
    required int rank,
  }) {
    final data = member.mentee.data();
    final profilePic = (data['profilePic'] as String?)?.trim() ?? '';
    final name = _displayName(member.mentee);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE9EEE4),
        backgroundImage:
            profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
        child: profilePic.isEmpty ? Text('$rank') : null,
      ),
      title: Text(name),
      subtitle: Text('Rank #$rank'),
      trailing: Text(
        '${member.score} pts',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildGroupCard({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> group,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    required Map<String, int> scores,
  }) {
    final colors = Theme.of(context).colorScheme;
    final data = group.data();
    final groupName = (data['name'] as String?)?.trim() ?? 'Group';
    final members = _rankGroupMembers(
      group: group,
      mentees: mentees,
      scores: scores,
    );
    final totalScore = members.fold<int>(
      0,
      (runningTotal, member) => runningTotal + member.score,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.08),
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  CupertinoIcons.rectangle_grid_2x2_fill,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      '${members.length} mentees • $totalScore pts total',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete group',
                onPressed: () => _confirmDeleteGroup(
                  context: context,
                  groupId: group.id,
                  groupName: groupName,
                  memberIds: List<String>.from(
                    data['memberIds'] as List? ?? const <String>[],
                  ),
                ),
                icon: const Icon(CupertinoIcons.trash),
                color: const Color(0xFFE56B6F),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (members.isEmpty)
            Text(
              'No mentees selected yet.',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.68),
              ),
            )
          else
            ...members.take(3).toList().asMap().entries.map((entry) {
              return _buildRankedMenteeTile(
                member: entry.value,
                rank: entry.key + 1,
              );
            }),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showEditMembersSheet(
                    context: context,
                    group: group,
                    mentees: mentees,
                    scores: scores,
                  ),
                  icon: const Icon(CupertinoIcons.person_2),
                  label: const Text('Select mentees'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showGroupLeaderboardSheet(
                    context: context,
                    groupName: groupName,
                    members: members,
                    totalScore: totalScore,
                  ),
                  icon: const Icon(CupertinoIcons.star_fill),
                  label: const Text('Leaderboard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_CoachGroupLeaderboardSummary> _buildGroupSummaries({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    required Map<String, int> scores,
  }) {
    final summaries = groups.map((group) {
      final groupName = (group.data()['name'] as String?)?.trim() ?? 'Group';
      final members = _rankGroupMembers(
        group: group,
        mentees: mentees,
        scores: scores,
      );
      final totalScore = members.fold<int>(
        0,
        (runningTotal, member) => runningTotal + member.score,
      );

      return _CoachGroupLeaderboardSummary(
        groupName: groupName,
        members: members,
        totalScore: totalScore,
      );
    }).toList()
      ..sort((a, b) {
        if (a.totalScore != b.totalScore) {
          return b.totalScore.compareTo(a.totalScore);
        }
        return a.groupName.toLowerCase().compareTo(
              b.groupName.toLowerCase(),
            );
      });

    return summaries;
  }

  Widget _buildSummaryCard({
    required BuildContext context,
    required int groupCount,
    required int menteeCount,
    required int totalMenteeScore,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.chart_bar_alt_fill,
            color: colors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$groupCount groups | $menteeCount mentees | $totalMenteeScore pts',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_CoachApiGroupSummary> _apiGroupSummaries(
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> groups,
  ) {
    final groupsById = <String, Map<String, dynamic>>{
      for (final group in groups) (group['id']?.toString() ?? ''): group,
    };

    final rawSummaries = payload['groupLeaderboards'];
    if (rawSummaries is! List) {
      return const <_CoachApiGroupSummary>[];
    }

    final summaries = rawSummaries.whereType<Map>().map((rawSummary) {
      final summary = Map<String, dynamic>.from(rawSummary);
      final groupId = summary['groupId']?.toString() ?? '';
      final groupMeta = groupsById[groupId] ?? <String, dynamic>{};
      final entries = (summary['entries'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final memberIds = List<String>.from(
        groupMeta['memberIds'] as List? ?? const <String>[],
      );
      final coachIds = List<String>.from(
        groupMeta['coachIds'] as List? ?? const <String>[],
      );
      final coachNames = List<String>.from(
        groupMeta['coachNames'] as List? ?? const <String>[],
      );

      return _CoachApiGroupSummary(
        groupId: groupId,
        groupName: (summary['groupName'] as String?)?.trim() ?? 'Group',
        totalScore: (summary['totalScore'] as num?)?.toInt() ?? 0,
        entries: entries,
        memberCount:
            (groupMeta['memberCount'] as num?)?.toInt() ?? memberIds.length,
        memberIds: memberIds,
        coachIds: coachIds,
        coachNames: coachNames,
      );
    }).toList();

    summaries.sort((a, b) {
      if (a.totalScore != b.totalScore) {
        return b.totalScore.compareTo(a.totalScore);
      }
      return a.groupName.toLowerCase().compareTo(b.groupName.toLowerCase());
    });
    return summaries;
  }

  Widget _buildEmptyGroupsCard(BuildContext context,
      {VoidCallback? onCreated}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.rectangle_grid_2x2_fill,
            size: 42,
            color: colors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Create your first group',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Groups help you organize mentees and compare scores by program, schedule, or focus.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.68),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () =>
                _showCreateGroupDialog(context).then((_) => onCreated?.call()),
            icon: const Icon(CupertinoIcons.plus),
            label: const Text('Create group'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupPodiumItem({
    required _CoachGroupLeaderboardSummary summary,
    required int rank,
    required double height,
    required Color color,
  }) {
    return SizedBox(
      width: 96,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: rank == 1 ? 26 : 22,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: height,
            width: 82,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.85),
                  color,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  summary.groupName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${summary.totalScore} pts',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupStandingsPodium(
    BuildContext context,
    List<_CoachGroupLeaderboardSummary> summaries,
  ) {
    final colors = Theme.of(context).colorScheme;
    if (summaries.isEmpty) {
      return const SizedBox.shrink();
    }

    if (summaries.length < 3) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group standings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            ...summaries.asMap().entries.map((entry) {
              return _buildGroupStandingTile(
                context: context,
                summary: entry.value,
                rank: entry.key + 1,
              );
            }),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group podium',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildGroupPodiumItem(
                summary: summaries[1],
                rank: 2,
                height: 108,
                color: const Color(0xFF8B927E),
              ),
              _buildGroupPodiumItem(
                summary: summaries[0],
                rank: 1,
                height: 132,
                color: const Color(0xFFE0A94F),
              ),
              _buildGroupPodiumItem(
                summary: summaries[2],
                rank: 3,
                height: 92,
                color: const Color(0xFF9B7B60),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupStandingTile({
    required BuildContext context,
    required _CoachGroupLeaderboardSummary summary,
    required int rank,
  }) {
    final colors = Theme.of(context).colorScheme;
    final topMember = summary.members.isNotEmpty
        ? '${_displayName(summary.members.first.mentee)} leads with ${summary.members.first.score} pts'
        : 'No mentees selected yet';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.primary.withValues(alpha: 0.14),
            child: Text(
              '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.groupName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.members.length} mentees | $topMember',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${summary.totalScore} pts',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsTab({
    required BuildContext context,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    required Map<String, int> scores,
    required int totalMenteeScore,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        _buildSummaryCard(
          context: context,
          groupCount: groups.length,
          menteeCount: mentees.length,
          totalMenteeScore: totalMenteeScore,
        ),
        const SizedBox(height: 16),
        if (groups.isEmpty)
          _buildEmptyGroupsCard(context)
        else
          ...groups.map((group) {
            return _buildGroupCard(
              context: context,
              group: group,
              mentees: mentees,
              scores: scores,
            );
          }),
      ],
    );
  }

  Widget _buildLeaderboardTab({
    required BuildContext context,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    required Map<String, int> scores,
    required int totalMenteeScore,
  }) {
    final summaries = _buildGroupSummaries(
      groups: groups,
      mentees: mentees,
      scores: scores,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        _buildSummaryCard(
          context: context,
          groupCount: groups.length,
          menteeCount: mentees.length,
          totalMenteeScore: totalMenteeScore,
        ),
        const SizedBox(height: 16),
        if (groups.isEmpty) ...[
          _buildEmptyGroupsCard(context),
        ] else ...[
          _buildGroupStandingsPodium(context, summaries),
          const SizedBox(height: 16),
          const Text(
            'Leaderboards',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...summaries.asMap().entries.map((entry) {
            final summary = entry.value;
            return Column(
              children: [
                _buildGroupStandingTile(
                  context: context,
                  summary: summary,
                  rank: entry.key + 1,
                ),
                if (summary.members.isNotEmpty)
                  Builder(builder: (context) {
                    final colors = Theme.of(context).colorScheme;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Column(
                        children: summary.members
                            .take(5)
                            .toList()
                            .asMap()
                            .entries
                            .map(
                          (memberEntry) {
                            return _buildRankedMenteeTile(
                              member: memberEntry.value,
                              rank: memberEntry.key + 1,
                            );
                          },
                        ).toList(),
                      ),
                    );
                  }),
              ],
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return _CoachGroupCustomizationBody(
          page: this,
          companyTheme: companyTheme,
        );
      },
    );
  }
}

class _CoachGroupCustomizationBody extends StatefulWidget {
  const _CoachGroupCustomizationBody({
    required this.page,
    required this.companyTheme,
  });

  final CoachGroupCustomizationPage page;
  final CompanyThemeData companyTheme;

  @override
  State<_CoachGroupCustomizationBody> createState() =>
      _CoachGroupCustomizationBodyState();
}

class _CoachGroupCustomizationBodyState
    extends State<_CoachGroupCustomizationBody> {
  List<Map<String, dynamic>>? _groups;
  Map<String, dynamic>? _leaderboardPayload;
  bool _hasError = false;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Refreshes quietly in the background: only the very first load (when
  // _groups is still null) shows a spinner. Later ticks swap in fresh data
  // without ever blanking the screen the user is looking at.
  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final results = await Future.wait<dynamic>([
        CoachApiService.instance.fetchGroups(),
        CoachApiService.instance.fetchLeaderboard(),
      ]);
      if (!mounted) return;
      setState(() {
        _groups = (results[0] as List?)
                ?.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList() ??
            const <Map<String, dynamic>>[];
        _leaderboardPayload =
            Map<String, dynamic>.from(results[1] as Map? ?? {});
        _hasError = false;
      });
    } catch (error) {
      debugPrint('Failed to refresh group customization data: $error');
      if (!mounted || _groups != null) return;
      setState(() {
        _hasError = true;
      });
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyTheme = widget.companyTheme;
    final page = widget.page;

    Widget body;
    if (_groups == null) {
      body = _hasError
          ? Center(
              child: Text(
                'Could not load group data.',
                style: TextStyle(color: companyTheme.mutedInkColor),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      final groups = _groups!;
      final leaderboardPayload =
          _leaderboardPayload ?? const <String, dynamic>{};
      // fetchGroups() (which built `groups`) is already scoped server-side to
      // groups this coach owns/co-coaches. The leaderboard payload, on the
      // other hand, is scoped to the whole company so every coach's groups
      // can be compared against each other — using it unfiltered here was
      // showing (and offering to edit/delete) other coaches' groups on a
      // brand-new coach account. Restrict to groups this coach actually owns.
      final ownedGroupIds =
          groups.map((group) => group['id']?.toString() ?? '').toSet();
      final summaries = page
          ._apiGroupSummaries(leaderboardPayload, groups)
          .where((summary) => ownedGroupIds.contains(summary.groupId))
          .toList();
      final sortedByName = summaries.toList()
        ..sort((a, b) => a.groupName.toLowerCase().compareTo(
              b.groupName.toLowerCase(),
            ));
      final totalMenteeScore = summaries.fold<int>(
        0,
        (runningTotal, summary) => runningTotal + summary.totalScore,
      );
      final totalMentees = summaries.fold<int>(
        0,
        (runningTotal, summary) => runningTotal + summary.memberCount,
      );

      body = TabBarView(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              page._buildSummaryCard(
                context: context,
                groupCount: groups.length,
                menteeCount: totalMentees,
                totalMenteeScore: totalMenteeScore,
              ),
              const SizedBox(height: 16),
              if (sortedByName.isEmpty)
                page._buildEmptyGroupsCard(context, onCreated: _refresh)
              else
                ...sortedByName.map(
                  (summary) => _CoachApiGroupCard(
                    summary: summary,
                    onAddCoach: () =>
                        page._showAddCoachDialog(context, summary).then(
                              (_) => _refresh(),
                            ),
                    onAddMentee: () => page
                        ._showAddMenteeToGroupDialog(context, summary)
                        .then((_) => _refresh()),
                    onDelete: () => page
                        ._confirmDeleteGroup(
                          context: context,
                          groupId: summary.groupId,
                          groupName: summary.groupName,
                          memberIds: summary.memberIds,
                        )
                        .then((_) => _refresh()),
                  ),
                ),
            ],
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              page._buildSummaryCard(
                context: context,
                groupCount: groups.length,
                menteeCount: totalMentees,
                totalMenteeScore: totalMenteeScore,
              ),
              const SizedBox(height: 16),
              if (summaries.isEmpty)
                page._buildEmptyGroupsCard(context, onCreated: _refresh)
              else
                ...summaries.map(
                  (summary) => _CoachApiGroupCard(
                    summary: summary,
                    onAddCoach: () =>
                        page._showAddCoachDialog(context, summary).then(
                              (_) => _refresh(),
                            ),
                    onAddMentee: () => page
                        ._showAddMenteeToGroupDialog(context, summary)
                        .then((_) => _refresh()),
                    onDelete: () => page
                        ._confirmDeleteGroup(
                          context: context,
                          groupId: summary.groupId,
                          groupName: summary.groupName,
                          memberIds: summary.memberIds,
                        )
                        .then((_) => _refresh()),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return DefaultTabController(
      length: 2,
      child: Theme(
        data: AppTheme.company(companyTheme),
        child: Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: companyTheme.surfaceColor,
            foregroundColor: companyTheme.inkColor,
            surfaceTintColor: Colors.transparent,
            title: Text(
              'Group customization',
              style: TextStyle(color: companyTheme.inkColor),
            ),
            actions: [
              IconButton(
                onPressed: () => page._showCreateGroupDialog(context).then(
                      (_) => _refresh(),
                    ),
                icon: const Icon(CupertinoIcons.plus),
              ),
            ],
            bottom: TabBar(
              indicatorColor: companyTheme.primaryColor,
              labelColor: companyTheme.primaryColor,
              unselectedLabelColor: companyTheme.mutedInkColor,
              tabs: const [
                Tab(
                  icon: Icon(CupertinoIcons.rectangle_grid_2x2_fill),
                  text: 'Groups',
                ),
                Tab(
                  icon: Icon(CupertinoIcons.star_fill),
                  text: 'Leaderboard',
                ),
              ],
            ),
          ),
          body: body,
        ),
      ),
    );
  }
}

class CoachManageMenteesPage extends StatelessWidget {
  const CoachManageMenteesPage({
    super.key,
    required this.firestore,
    required this.currentUserId,
    required this.currentUserName,
    required this.teamName,
    required this.menteesStream,
    required this.pendingRequestsStream,
    required this.groupsStream,
    required this.onAssignMentee,
    required this.onRemoveMentee,
    required this.onAcceptRequest,
    required this.onDeclineRequest,
    required this.onCreateGroup,
    required this.onDeleteGroup,
    required this.latestTrackerForUser,
    required this.formatTrackerDate,
  });

  final FirebaseFirestore firestore;
  final String currentUserId;
  final String currentUserName;
  final String teamName;
  final Stream<QuerySnapshot<Map<String, dynamic>>> menteesStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> pendingRequestsStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> groupsStream;
  final Future<void> Function({
    required String menteeId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) onAssignMentee;
  final Future<void> Function(String menteeId) onRemoveMentee;
  final Future<void> Function({
    required String requestId,
    required String menteeId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) onAcceptRequest;
  final Future<void> Function(String requestId) onDeclineRequest;
  final Future<void> Function(String name) onCreateGroup;
  final Future<void> Function({
    required String groupId,
    required String groupName,
    required List<String> memberIds,
  }) onDeleteGroup;
  final Future<Map<String, dynamic>?> Function(String userId)
      latestTrackerForUser;
  final String Function(Map<String, dynamic>? tracker) formatTrackerDate;

  String _normalizeName(String value) => value.trim().toLowerCase();

  String _displayName(QueryDocumentSnapshot<Map<String, dynamic>> userDoc) {
    final data = userDoc.data();
    final username = (data['username'] as String?)?.trim() ?? '';
    if (username.isNotEmpty) return username;
    final email = (data['email'] as String?)?.trim() ?? '';
    if (email.isNotEmpty) return email.split('@').first;
    return 'User';
  }

  int _extractIntValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
    }
    return 0;
  }

  int _calculateLeaderboardScore(Map<String, dynamic> data) {
    final taskPoints = Map<String, dynamic>.from(
      data['taskPoints'] as Map? ?? <String, dynamic>{},
    );

    final callIntent = _extractIntValue(
      taskPoints,
      ['Call Points', 'call_points', 'callPoints'],
    );
    final meditationMinutes = _extractIntValue(
      taskPoints,
      ['Meditation Points', 'meditation_points', 'meditationPoints'],
    );
    final stepsTaken = _extractIntValue(
          taskPoints,
          ['Steps Points', 'steps_points', 'stepsPoints'],
        ) *
        200;
    final valueEntries = _extractIntValue(
      taskPoints,
      ['Add Value Points', 'value_points', 'addValuePoints'],
    );
    final learningEntries = _extractIntValue(
      taskPoints,
      ['Learning Points', 'learning_points', 'learningPoints'],
    );
    final todoListPoints = _extractIntValue(
      taskPoints,
      ['Goals Points', 'todo_list_points', 'todoListPoints'],
    );

    return callIntent +
        meditationMinutes +
        (stepsTaken / 200).floor() +
        valueEntries +
        learningEntries +
        todoListPoints;
  }

  Map<String, _MenteeLeaderboardData> _buildLeaderboardData(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> mentees,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pointDocs,
  ) {
    final menteeNames = <String, String>{};
    for (final mentee in mentees) {
      final username = (mentee.data()['username'] as String?)?.trim() ?? '';
      if (username.isEmpty) continue;
      menteeNames[_normalizeName(username)] = mentee.id;
    }

    final scoresByMenteeId = <String, int>{};
    for (final pointDoc in pointDocs) {
      final data = pointDoc.data();
      final username = (data['username'] as String?)?.trim() ?? '';
      final menteeId = menteeNames[_normalizeName(username)];
      if (menteeId == null) continue;
      final score = _calculateLeaderboardScore(data);
      final currentScore = scoresByMenteeId[menteeId] ?? 0;
      if (score > currentScore) {
        scoresByMenteeId[menteeId] = score;
      }
    }

    final sorted = mentees.toList()
      ..sort((a, b) {
        final aScore = scoresByMenteeId[a.id] ?? 0;
        final bScore = scoresByMenteeId[b.id] ?? 0;
        if (aScore != bScore) return bScore.compareTo(aScore);
        final aName = (a.data()['username'] as String?)?.trim() ?? '';
        final bName = (b.data()['username'] as String?)?.trim() ?? '';
        return aName.compareTo(bName);
      });

    final leaderboard = <String, _MenteeLeaderboardData>{};
    for (var index = 0; index < sorted.length; index++) {
      final mentee = sorted[index];
      leaderboard[mentee.id] = _MenteeLeaderboardData(
        rank: index + 1,
        score: scoresByMenteeId[mentee.id] ?? 0,
      );
    }
    return leaderboard;
  }

  Color _badgeColorForRank(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFE3B341);
      case 2:
        return const Color(0xFF9AA6B2);
      case 3:
        return const Color(0xFFCE8F5A);
      default:
        return const Color(0xFF90A17D);
    }
  }

  String _badgeLabelForRank(int rank) {
    switch (rank) {
      case 1:
        return 'Top 1';
      case 2:
        return 'Top 2';
      case 3:
        return 'Top 3';
      default:
        return 'Rank #$rank';
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedGroups(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> groups,
  ) {
    return groups.toList()
      ..sort((a, b) {
        final aName = (a.data()['name'] as String?)?.trim() ?? '';
        final bName = (b.data()['name'] as String?)?.trim() ?? '';
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
  }

  String _groupNameForMentee(Map<String, dynamic> menteeData) {
    final coachGroups =
        Map<String, dynamic>.from(menteeData['coachGroups'] as Map? ?? {});
    final currentCoachGroup =
        Map<String, dynamic>.from(coachGroups[currentUserId] as Map? ?? {});
    final groupName = (currentCoachGroup['groupName'] as String?)?.trim() ?? '';
    return groupName.isNotEmpty ? groupName : teamName;
  }

  String _requestIdForRequest(dynamic request) {
    final requestData = request is QueryDocumentSnapshot<Map<String, dynamic>>
        ? request.data()
        : request is Map
            ? Map<String, dynamic>.from(request)
            : <String, dynamic>{};
    final explicitId = request is QueryDocumentSnapshot<Map<String, dynamic>>
        ? request.id.trim()
        : (requestData['id'] as String?)?.trim() ?? '';
    if (explicitId.isNotEmpty) return explicitId;

    final menteeId = (requestData['menteeId'] as String?)?.trim() ?? '';
    final coachId =
        (requestData['coachId'] as String?)?.trim() ?? currentUserId;
    if (menteeId.isNotEmpty && coachId.isNotEmpty) {
      return '${menteeId}_$coachId';
    }

    return '';
  }

  Future<void> _showCreateGroupDialog(
    BuildContext context,
  ) async {
    final groupName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _CoachGroupNameDialog(
          hintText: 'Example: Morning group',
        );
      },
    );

    if (groupName == null || groupName.isEmpty) return;
    await onCreateGroup(groupName);
  }

  Future<void> _confirmDeleteGroup({
    required BuildContext context,
    required QueryDocumentSnapshot<Map<String, dynamic>> group,
  }) async {
    final groupData = group.data();
    final groupName = (groupData['name'] as String?)?.trim() ?? 'Group';
    final memberIds = List<String>.from(
      groupData['memberIds'] as List? ?? const <String>[],
    );

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Delete group?'),
          content: Text(
            memberIds.isEmpty
                ? 'This will permanently delete $groupName.'
                : 'This will permanently delete $groupName and remove it from ${memberIds.length} mentees.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE56B6F),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;
    await onDeleteGroup(
      groupId: group.id,
      groupName: groupName,
      memberIds: memberIds,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$groupName deleted.')),
    );
  }

  Widget _buildGroupsPanel() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: groupsStream,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final groups = _sortedGroups(snapshot.data?.docs ?? []);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Groups',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showCreateGroupDialog(context),
                    icon: const Icon(CupertinoIcons.plus, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (groups.isEmpty)
                Text(
                  'Create groups to organize mentees by program, schedule, or focus.',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.68),
                    height: 1.4,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: groups.map((group) {
                    final data = group.data();
                    final name = (data['name'] as String?)?.trim() ?? 'Group';
                    final memberIds = List<String>.from(
                      data['memberIds'] as List? ?? const <String>[],
                    );
                    return Chip(
                      avatar: const Icon(
                        CupertinoIcons.rectangle_grid_2x2_fill,
                        size: 16,
                      ),
                      label: Text('$name (${memberIds.length})'),
                      deleteIcon: const Icon(CupertinoIcons.trash, size: 16),
                      onDeleted: () => _confirmDeleteGroup(
                        context: context,
                        group: group,
                      ),
                      backgroundColor: colors.primary.withValues(alpha: 0.10),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingRequests() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pendingRequestsStream,
      builder: (context, snapshot) {
        final requests = (snapshot.data?.docs ?? []).where((doc) {
          return (doc.data()['status'] as String?) == 'pending';
        }).toList();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (requests.isEmpty) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.16),
              ),
            ),
            child: Text(
              'No pending coach applications right now.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(
                'Pending applications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            ...requests.map((request) {
              final data = request.data();
              final userName =
                  (data['userName'] as String?)?.trim().isNotEmpty == true
                      ? (data['userName'] as String).trim()
                      : 'User';
              final userEmail = (data['userEmail'] as String?)?.trim() ?? '';
              final userId = (data['userId'] as String?)?.trim() ?? '';
              final applicantRole =
                  (data['applicantRole'] as String?)?.trim().toLowerCase() ??
                      '';
              final applicantIsCoach =
                  data['applicantIsCoach'] == true || applicantRole == 'coach';
              final applyingAs =
                  (data['applyingAs'] as String?)?.trim().toLowerCase() ?? '';
              final applicantContext = applicantIsCoach
                  ? 'Coach applying as mentee'
                  : applyingAs == 'mentee'
                      ? 'Mentee application'
                      : '';

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE7E9E2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFDDE7D5),
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (userEmail.isNotEmpty)
                                Text(
                                  userEmail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF6B7165),
                                  ),
                                ),
                              if (applicantContext.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: applicantIsCoach
                                          ? const Color(0xFFE7EDF4)
                                          : const Color(0xFFF4F6F1),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: applicantIsCoach
                                            ? const Color(0xFFC8D6E2)
                                            : const Color(0xFFE0E5D9),
                                      ),
                                    ),
                                    child: Text(
                                      applicantContext,
                                      style: const TextStyle(
                                        color: Color(0xFF4F5F68),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final requestId = _requestIdForRequest(request);
                              if (requestId.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not identify this request.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              await onDeclineRequest(requestId);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('$userName declined.'),
                                ),
                              );
                            },
                            child: const Text('Decline'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: userId.isEmpty
                                ? null
                                : () async {
                                    try {
                                      final requestId =
                                          _requestIdForRequest(request);
                                      if (requestId.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Could not identify this request.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      await onAcceptRequest(
                                        requestId: requestId,
                                        menteeId: userId,
                                        teamName: teamName,
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$userName is now in $teamName.',
                                          ),
                                        ),
                                      );
                                    } catch (error) {
                                      debugPrint(
                                        'Failed to accept coach request '
                                        '${_requestIdForRequest(request)}: $error',
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not accept this application. Please try again.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _showAddMenteeSheet(BuildContext context) async {
    final searchController = TextEditingController();
    Map<String, dynamic>? selectedUser;
    String selectedUserName = '';
    bool isAssigning = false;

    Future<void> assignSelectedMentee(
      BuildContext activeContext,
      StateSetter setSheetState,
      _CoachGroupChoice groupChoice,
    ) async {
      final userData = selectedUser;
      if (userData == null || isAssigning) return;
      final userId = (userData['id'] as String?)?.trim() ?? '';
      if (userId.isEmpty) return;

      setSheetState(() => isAssigning = true);
      await onAssignMentee(
        menteeId: userId,
        teamName: teamName,
        groupId: groupChoice.groupId,
        groupName: groupChoice.groupName,
      );
      if (!activeContext.mounted) return;
      setSheetState(() {
        selectedUser = null;
        selectedUserName = '';
        isAssigning = false;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selectedUserName.isNotEmpty ? selectedUserName : 'Mentee'} added to ${groupChoice.groupName}',
          ),
        ),
      );
    }

    Future<List<List<Map<String, dynamic>>>> loadSheetData() async {
      final results = await Future.wait<List<Map<String, dynamic>>>([
        CoachApiService.instance.fetchUsers(),
        CoachApiService.instance.fetchGroups(),
      ]);
      return results;
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              if (selectedUser != null) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Choose group for $selectedUserName',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: isAssigning
                                ? null
                                : () {
                                    setSheetState(() {
                                      selectedUser = null;
                                      selectedUserName = '';
                                    });
                                  },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 360,
                        child: FutureBuilder<List<List<Map<String, dynamic>>>>(
                          future: loadSheetData(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final data = snapshot.data ??
                                const <List<Map<String, dynamic>>>[];
                            final users = data.isNotEmpty
                                ? data.first
                                : <Map<String, dynamic>>[];
                            final groups = data.length > 1
                                ? data[1]
                                : <Map<String, dynamic>>[];

                            final query =
                                searchController.text.trim().toLowerCase();
                            final filteredUsers = users.where((user) {
                              final userId =
                                  (user['id'] as String?)?.trim() ?? '';
                              final username =
                                  (user['name'] as String?)?.toLowerCase() ??
                                      '';
                              final email =
                                  (user['email'] as String?)?.toLowerCase() ??
                                      '';
                              final isCoach = user['isCoach'] == true ||
                                  ((user['role'] as String?)?.toLowerCase() ==
                                      'coach');
                              final isMyAcceptedMentee =
                                  user['assignedToMe'] == true;
                              return userId != currentUserId &&
                                  !isCoach &&
                                  isMyAcceptedMentee &&
                                  (query.isEmpty ||
                                      username.contains(query) ||
                                      email.contains(query));
                            }).toList();

                            final sortedGroups =
                                List<Map<String, dynamic>>.from(
                              groups,
                            )..sort((a, b) {
                                    final aName =
                                        (a['name'] as String?)?.trim() ?? '';
                                    final bName =
                                        (b['name'] as String?)?.trim() ?? '';
                                    return aName.toLowerCase().compareTo(
                                          bName.toLowerCase(),
                                        );
                                  });

                            return ListView(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFE9EEE4),
                                    child: Icon(CupertinoIcons.person_2_fill),
                                  ),
                                  title: Text(teamName),
                                  subtitle: const Text('Main coach team'),
                                  enabled: !isAssigning,
                                  onTap: isAssigning
                                      ? null
                                      : () => assignSelectedMentee(
                                            sheetContext,
                                            setSheetState,
                                            _CoachGroupChoice(
                                              groupName: teamName,
                                            ),
                                          ),
                                ),
                                ...sortedGroups.map((group) {
                                  final name =
                                      (group['name'] as String?)?.trim() ??
                                          'Group';
                                  final memberCount =
                                      (group['memberCount'] as num?)?.toInt() ??
                                          ((group['memberIds'] as List?)
                                                  ?.length ??
                                              0);
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFDDE7D5),
                                      child: Icon(
                                        CupertinoIcons.rectangle_grid_2x2_fill,
                                      ),
                                    ),
                                    title: Text(name),
                                    subtitle: Text(
                                      '$memberCount mentees',
                                    ),
                                    enabled: !isAssigning,
                                    onTap: isAssigning
                                        ? null
                                        : () => assignSelectedMentee(
                                              sheetContext,
                                              setSheetState,
                                              _CoachGroupChoice(
                                                groupId:
                                                    group['id']?.toString(),
                                                groupName: name,
                                              ),
                                            ),
                                  );
                                }),
                                if (filteredUsers.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: Text('No users found.'),
                                    ),
                                  ),
                                ...filteredUsers.map((user) {
                                  final userName = (user['name'] as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? (user['name'] as String).trim()
                                      : ((user['email'] as String?)
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? (user['email'] as String)
                                              .trim()
                                              .split('@')
                                              .first
                                          : 'Unknown User');
                                  final isCoach = user['isCoach'] == true ||
                                      ((user['role'] as String?)
                                              ?.toLowerCase() ==
                                          'coach');
                                  final assignedToMe =
                                      user['assignedToMe'] == true;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundImage:
                                          (user['profilePic'] as String?)
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? NetworkImage(
                                                  user['profilePic'] as String,
                                                )
                                              : null,
                                      child: ((user['profilePic'] as String?)
                                                  ?.trim()
                                                  .isEmpty ??
                                              true)
                                          ? Text(
                                              userName.isNotEmpty
                                                  ? userName[0].toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(userName),
                                    subtitle: Text(
                                      [
                                        (user['email'] as String?) ?? '',
                                        if (isCoach) 'Coach account',
                                      ].where((value) {
                                        return value
                                            .toString()
                                            .trim()
                                            .isNotEmpty;
                                      }).join(' · '),
                                    ),
                                    trailing: ElevatedButton(
                                      onPressed: () {
                                        setSheetState(() {
                                          selectedUser = user;
                                          selectedUserName = userName;
                                        });
                                      },
                                      child: Text(
                                        assignedToMe ? 'Move' : 'Add',
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Add Mentees',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search by username or email',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 360,
                      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
                        future: loadSheetData(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final data = snapshot.data ??
                              const <List<Map<String, dynamic>>>[];
                          final users = data.isNotEmpty
                              ? data.first
                              : <Map<String, dynamic>>[];

                          final query =
                              searchController.text.trim().toLowerCase();
                          final filteredUsers = users.where((user) {
                            final userId =
                                (user['id'] as String?)?.trim() ?? '';
                            final username =
                                (user['name'] as String?)?.toLowerCase() ?? '';
                            final email =
                                (user['email'] as String?)?.toLowerCase() ?? '';
                            final isCoach = user['isCoach'] == true ||
                                ((user['role'] as String?)?.toLowerCase() ==
                                    'coach');
                            final isMyAcceptedMentee =
                                user['assignedToMe'] == true;
                            return userId != currentUserId &&
                                !isCoach &&
                                isMyAcceptedMentee &&
                                (query.isEmpty ||
                                    username.contains(query) ||
                                    email.contains(query));
                          }).toList();

                          if (filteredUsers.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: Text('No users found.'),
                              ),
                            );
                          }

                          return ListView(
                            children: filteredUsers.map((user) {
                              final userName = (user['name'] as String?)
                                          ?.trim()
                                          .isNotEmpty ==
                                      true
                                  ? (user['name'] as String).trim()
                                  : ((user['email'] as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? (user['email'] as String)
                                          .trim()
                                          .split('@')
                                          .first
                                      : 'Unknown User');
                              final isCoach = user['isCoach'] == true ||
                                  ((user['role'] as String?)?.toLowerCase() ==
                                      'coach');
                              final assignedToMe = user['assignedToMe'] == true;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundImage:
                                      (user['profilePic'] as String?)
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? NetworkImage(
                                              user['profilePic'] as String,
                                            )
                                          : null,
                                  child: ((user['profilePic'] as String?)
                                              ?.trim()
                                              .isEmpty ??
                                          true)
                                      ? Text(
                                          userName.isNotEmpty
                                              ? userName[0].toUpperCase()
                                              : '?',
                                        )
                                      : null,
                                ),
                                title: Text(userName),
                                subtitle: Text(
                                  [
                                    (user['email'] as String?) ?? '',
                                    if (isCoach) 'Coach account',
                                  ].where((value) {
                                    return value.toString().trim().isNotEmpty;
                                  }).join(' · '),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    setSheetState(() {
                                      selectedUser = user;
                                      selectedUserName = userName;
                                    });
                                  },
                                  child: Text(
                                    assignedToMe ? 'Move' : 'Add',
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  void _openChatWithMenteeApi(
    BuildContext context,
    Map<String, dynamic> mentee,
  ) {
    final menteeName = (mentee['name'] as String?)?.trim().isNotEmpty == true
        ? (mentee['name'] as String).trim()
        : ((mentee['email'] as String?)?.trim().isNotEmpty == true
            ? (mentee['email'] as String).trim().split('@').first
            : 'Mentee');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          coach: Coach(
            id: (mentee['userId'] as String?)?.trim() ?? '',
            name: menteeName,
            phone: '',
            bio: (mentee['email'] as String?) ?? '',
            profilePic: (mentee['profilePic'] as String?) ?? '',
            backgroundColor: const Color(0xFF90A17D),
          ),
          userId: currentUserId,
          userName: currentUserName,
        ),
      ),
    );
  }

  List<_CoachApiGroupSummary> _apiGroupSummaries(
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> groups,
  ) {
    final groupsById = <String, Map<String, dynamic>>{
      for (final group in groups) (group['id']?.toString() ?? ''): group,
    };

    final rawSummaries = payload['groupLeaderboards'];
    if (rawSummaries is! List) {
      return const <_CoachApiGroupSummary>[];
    }

    final summaries = rawSummaries.whereType<Map>().map((rawSummary) {
      final summary = Map<String, dynamic>.from(rawSummary);
      final groupId = summary['groupId']?.toString() ?? '';
      final groupMeta = groupsById[groupId] ?? <String, dynamic>{};
      final entries = (summary['entries'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final memberIds = List<String>.from(
        groupMeta['memberIds'] as List? ?? const <String>[],
      );
      final coachIds = List<String>.from(
        groupMeta['coachIds'] as List? ?? const <String>[],
      );
      final coachNames = List<String>.from(
        groupMeta['coachNames'] as List? ?? const <String>[],
      );

      return _CoachApiGroupSummary(
        groupId: groupId,
        groupName: (summary['groupName'] as String?)?.trim() ?? 'Group',
        totalScore: (summary['totalScore'] as num?)?.toInt() ?? 0,
        entries: entries,
        memberCount:
            (groupMeta['memberCount'] as num?)?.toInt() ?? memberIds.length,
        memberIds: memberIds,
        coachIds: coachIds,
        coachNames: coachNames,
      );
    }).toList();

    summaries.sort((a, b) {
      if (a.totalScore != b.totalScore) {
        return b.totalScore.compareTo(a.totalScore);
      }
      return a.groupName.toLowerCase().compareTo(b.groupName.toLowerCase());
    });
    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Manage mentees',
                style: TextStyle(color: companyTheme.inkColor),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  onPressed: () => _showAddMenteeSheet(context),
                ),
              ],
            ),
            body: _ManageMenteesDataScope(
              builder: (
                context, {
                required requests,
                required groups,
                required leaderboardPayload,
                required isLoading,
                required hasError,
                required refresh,
              }) {
                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (hasError) {
                  return Center(
                    child: Text(
                      'Could not load mentee data.',
                      style: TextStyle(color: companyTheme.mutedInkColor),
                    ),
                  );
                }

                final mentees = (leaderboardPayload['menteeEntries'] as List?)
                        ?.whereType<Map>()
                        .map((item) => Map<String, dynamic>.from(item))
                        .toList() ??
                    const <Map<String, dynamic>>[];

                final acceptedTitle = mentees.isEmpty
                    ? 'No accepted mentees yet.'
                    : 'Accepted mentees';

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    CoachPendingApplicationsSection(
                      initialRequests: requests,
                      currentUserId: currentUserId,
                      teamName: teamName,
                      onAcceptRequest: onAcceptRequest,
                      onDeclineRequest: onDeclineRequest,
                      onAccepted: refresh,
                    ),
                    const SizedBox(height: 12),
                    if (groups.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(0, 4, 0, 10),
                        child: Text(
                          'Groups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groups.map((group) {
                          final groupName =
                              (group['name'] as String?)?.trim() ?? 'Group';
                          final memberCount =
                              (group['memberCount'] as num?)?.toInt() ??
                                  ((group['memberIds'] as List?)?.length ?? 0);
                          return Chip(label: Text('$groupName ($memberCount)'));
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
                      child: Text(
                        acceptedTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: companyTheme.inkColor,
                        ),
                      ),
                    ),
                    ...mentees.map((mentee) {
                      final name =
                          (mentee['name'] as String?)?.trim().isNotEmpty == true
                              ? (mentee['name'] as String).trim()
                              : 'Mentee';
                      final profilePic =
                          (mentee['profilePic'] as String?)?.trim() ?? '';
                      final score = (mentee['score'] as num?)?.toInt() ?? 0;
                      final rank = (mentee['rank'] as num?)?.toInt() ?? 0;
                      final groupName =
                          (mentee['teamName'] as String?)?.trim().isNotEmpty ==
                                  true
                              ? (mentee['teamName'] as String).trim()
                              : teamName;
                      final email = (mentee['email'] as String?)?.trim() ?? '';
                      final userId =
                          (mentee['userId'] as String?)?.trim() ?? '';
                      final badgeColor = _badgeColorForRank(rank);
                      final onPrimary =
                          companyTheme.primaryColor.computeLuminance() > 0.48
                              ? Colors.black
                              : Colors.white;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              companyTheme.surfaceColor,
                              Color.alphaBlend(
                                badgeColor.withValues(
                                  alpha: companyTheme.isDark ? 0.12 : 0.10,
                                ),
                                companyTheme.surfaceColor,
                              ),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: badgeColor.withValues(
                              alpha: companyTheme.isDark ? 0.28 : 0.18,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundImage: profilePic.isNotEmpty
                                      ? NetworkImage(profilePic)
                                      : null,
                                  child: profilePic.isEmpty
                                      ? Text(name.isNotEmpty ? name[0] : '?')
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: companyTheme.inkColor,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badgeColor.withValues(
                                                alpha: 0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _badgeLabelForRank(rank),
                                              style: TextStyle(
                                                color: badgeColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        email,
                                        style: TextStyle(
                                          color: companyTheme.mutedInkColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: companyTheme.primaryColor
                                                  .withValues(
                                                alpha: companyTheme.isDark
                                                    ? 0.16
                                                    : 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              '$score pts',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: companyTheme.inkColor,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: companyTheme.iconColor
                                                  .withValues(
                                                alpha: companyTheme.isDark
                                                    ? 0.16
                                                    : 0.10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              groupName,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: companyTheme.inkColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _openChatWithMenteeApi(context, mentee),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          companyTheme.primaryColor,
                                      foregroundColor: onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(
                                      CupertinoIcons.chat_bubble_2_fill,
                                      size: 18,
                                    ),
                                    label: const Text('Message'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: userId.isEmpty
                                        ? null
                                        : () => onRemoveMentee(userId),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFB55D5D),
                                      side: BorderSide(
                                        color: const Color(0xFFB55D5D)
                                            .withValues(alpha: 0.28),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    icon: const Icon(
                                      CupertinoIcons
                                          .person_crop_circle_badge_xmark,
                                      size: 18,
                                    ),
                                    label: const Text('Remove'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// Owns the "manage mentees" data fetch/refresh lifecycle so the page can
// poll for updates without recreating its Future (and blanking to a
// spinner) on every rebuild the way a bare Stream.periodic + inline
// Future.wait did before. Only the very first load shows a spinner;
// later ticks - and the immediate refresh() call fired right after a
// mentee is accepted - swap in fresh data silently.
class _ManageMenteesDataScope extends StatefulWidget {
  const _ManageMenteesDataScope({required this.builder});

  final Widget Function(
    BuildContext context, {
    required List<Map<String, dynamic>> requests,
    required List<Map<String, dynamic>> groups,
    required Map<String, dynamic> leaderboardPayload,
    required bool isLoading,
    required bool hasError,
    required VoidCallback refresh,
  }) builder;

  @override
  State<_ManageMenteesDataScope> createState() =>
      _ManageMenteesDataScopeState();
}

class _ManageMenteesDataScopeState extends State<_ManageMenteesDataScope> {
  List<Map<String, dynamic>>? _requests;
  List<Map<String, dynamic>>? _groups;
  Map<String, dynamic>? _leaderboardPayload;
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait<dynamic>([
        CoachApiService.instance.fetchRequests(),
        CoachApiService.instance.fetchGroups(),
        CoachApiService.instance.fetchLeaderboard(),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = (results[0] as List?)
                ?.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList() ??
            const <Map<String, dynamic>>[];
        _groups = (results[1] as List?)
                ?.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList() ??
            const <Map<String, dynamic>>[];
        _leaderboardPayload =
            Map<String, dynamic>.from(results[2] as Map? ?? {});
        _hasError = false;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Failed to refresh manage-mentees data: $error');
      if (!mounted) return;
      // Only surface an error before the first successful load; a
      // background refresh failure just keeps showing the last-good data.
      if (_requests == null) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      requests: _requests ?? const <Map<String, dynamic>>[],
      groups: _groups ?? const <Map<String, dynamic>>[],
      leaderboardPayload: _leaderboardPayload ?? const <String, dynamic>{},
      isLoading: _isLoading,
      hasError: _hasError,
      refresh: _refresh,
    );
  }
}

class CoachPendingApplicationsSection extends StatefulWidget {
  const CoachPendingApplicationsSection({
    super.key,
    required this.initialRequests,
    required this.currentUserId,
    required this.teamName,
    required this.onAcceptRequest,
    required this.onDeclineRequest,
    this.onAccepted,
  });

  final List<Map<String, dynamic>> initialRequests;
  final String currentUserId;
  final String teamName;
  final Future<void> Function({
    required String requestId,
    required String menteeId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) onAcceptRequest;
  final Future<void> Function(String requestId) onDeclineRequest;
  // Called after a request has been accepted and this section has
  // refreshed its own pending list, so the parent page can immediately
  // refetch the accepted-mentees list instead of waiting for its next
  // periodic refresh (previously the new mentee wouldn't show up until
  // the coach navigated away and back).
  final VoidCallback? onAccepted;

  @override
  State<CoachPendingApplicationsSection> createState() =>
      _CoachPendingApplicationsSectionState();
}

class _CoachPendingApplicationsSectionState
    extends State<CoachPendingApplicationsSection> {
  late List<Map<String, dynamic>> _requests;
  final Set<String> _hiddenRequestIds = <String>{};
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _requests = List<Map<String, dynamic>>.from(widget.initialRequests);
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshRequests();
    });
  }

  @override
  void didUpdateWidget(covariant CoachPendingApplicationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requests = List<Map<String, dynamic>>.from(widget.initialRequests);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _requestIdForRequest(dynamic request) {
    final requestData = request is Map
        ? Map<String, dynamic>.from(request)
        : <String, dynamic>{};
    final explicitId = (requestData['id'] as String?)?.trim() ?? '';
    if (explicitId.isNotEmpty) return explicitId;

    final menteeId = (requestData['menteeId'] as String?)?.trim() ?? '';
    final coachId =
        (requestData['coachId'] as String?)?.trim() ?? widget.currentUserId;
    if (menteeId.isNotEmpty && coachId.isNotEmpty) {
      return '${menteeId}_$coachId';
    }

    return '';
  }

  Future<void> _refreshRequests() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final latestRequests = await CoachApiService.instance.fetchRequests();
      if (!mounted) return;
      setState(() {
        _requests = latestRequests;
      });
    } catch (error) {
      debugPrint('Failed to refresh pending applications: $error');
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _handleAccept(Map<String, dynamic> request) async {
    final userName =
        (request['menteeName'] as String?)?.trim().isNotEmpty == true
            ? (request['menteeName'] as String).trim()
            : 'User';
    final userId = (request['menteeId'] as String?)?.trim() ?? '';
    final requestId = _requestIdForRequest(request);

    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not identify this request.'),
        ),
      );
      return;
    }

    try {
      await widget.onAcceptRequest(
        requestId: requestId,
        menteeId: userId,
        teamName: widget.teamName,
      );
      if (!mounted) return;
      setState(() {
        _hiddenRequestIds.add(requestId);
      });
      await _refreshRequests();
      widget.onAccepted?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$userName is now in ${widget.teamName}.'),
        ),
      );
    } catch (error) {
      debugPrint('Failed to accept coach request $requestId: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not accept this application. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _handleDecline(Map<String, dynamic> request) async {
    final userName =
        (request['menteeName'] as String?)?.trim().isNotEmpty == true
            ? (request['menteeName'] as String).trim()
            : 'User';
    final requestId = _requestIdForRequest(request);

    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not identify this request.'),
        ),
      );
      return;
    }

    try {
      await widget.onDeclineRequest(requestId);
      if (!mounted) return;
      setState(() {
        _hiddenRequestIds.add(requestId);
      });
      await _refreshRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$userName declined.')),
      );
    } catch (error) {
      debugPrint('Failed to decline coach request $requestId: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not decline this application. Please try again.',
          ),
        ),
      );
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final userName =
        (request['menteeName'] as String?)?.trim().isNotEmpty == true
            ? (request['menteeName'] as String).trim()
            : 'User';
    final userEmail = (request['menteeEmail'] as String?)?.trim() ?? '';
    final applicantRole =
        (request['applicantRole'] as String?)?.trim().toLowerCase() ?? '';
    final applicantIsCoach =
        request['applicantIsCoach'] == true || applicantRole == 'coach';
    final applyingAs =
        (request['applyingAs'] as String?)?.trim().toLowerCase() ?? '';
    final applicantContext = applicantIsCoach
        ? 'Coach applying as mentee'
        : applyingAs == 'mentee'
            ? 'Mentee application'
            : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E9E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFDDE7D5),
                child: Text(userName.isNotEmpty ? userName[0] : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (userEmail.isNotEmpty)
                      Text(
                        userEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7165),
                        ),
                      ),
                    if (applicantContext.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        applicantContext,
                        style: const TextStyle(
                          color: Color(0xFF4F5F68),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleDecline(request),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (request['menteeId'] as String?)?.trim().isEmpty == true
                          ? null
                          : () => _handleAccept(request),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRequests = _requests.where((request) {
      final requestId = _requestIdForRequest(request);
      final status = (request['status'] as String?)?.trim().toLowerCase();
      return requestId.isNotEmpty &&
          !_hiddenRequestIds.contains(requestId) &&
          (status == null || status == 'pending');
    }).toList();

    if (visibleRequests.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 4, 0, 10),
          child: Text(
            'Pending applications',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        ...visibleRequests.map(_buildRequestCard),
      ],
    );
  }
}

class _CoachGroupChoice {
  const _CoachGroupChoice({
    this.groupId,
    required this.groupName,
  });

  final String? groupId;
  final String groupName;
}

class _CoachGroupMenteeScore {
  const _CoachGroupMenteeScore({
    required this.mentee,
    required this.score,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> mentee;
  final int score;
}

class _CoachGroupLeaderboardSummary {
  const _CoachGroupLeaderboardSummary({
    required this.groupName,
    required this.members,
    required this.totalScore,
  });

  final String groupName;
  final List<_CoachGroupMenteeScore> members;
  final int totalScore;
}

class _MenteeLeaderboardData {
  const _MenteeLeaderboardData({
    required this.rank,
    required this.score,
  });

  final int rank;
  final int score;
}

class _CoachApiGroupSummary {
  const _CoachApiGroupSummary({
    required this.groupId,
    required this.groupName,
    required this.totalScore,
    required this.entries,
    required this.memberCount,
    required this.memberIds,
    required this.coachIds,
    required this.coachNames,
  });

  final String groupId;
  final String groupName;
  final int totalScore;
  final List<Map<String, dynamic>> entries;
  final int memberCount;
  final List<String> memberIds;
  final List<String> coachIds;
  final List<String> coachNames;
}

class CoachMenteeActivityCalendarPage extends StatefulWidget {
  const CoachMenteeActivityCalendarPage({
    super.key,
    required this.firestore,
    required this.menteesStream,
  });

  final FirebaseFirestore firestore;
  final Stream<QuerySnapshot<Map<String, dynamic>>> menteesStream;

  @override
  State<CoachMenteeActivityCalendarPage> createState() =>
      _CoachMenteeActivityCalendarPageState();
}

class _CoachMenteeActivityCalendarPageState
    extends State<CoachMenteeActivityCalendarPage> {
  DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Map<String, bool> _activityMap(Map<String, dynamic> tracker) {
    return <String, bool>{
      'Call': tracker['call'] == true,
      'Steps': tracker['steps'] == true,
      'Meditation': tracker['meditation'] == true,
      'Learning': tracker['learning'] == true,
      'Add Value': tracker['addValue'] == true,
    };
  }

  int _completedCount(Map<String, dynamic> tracker) {
    return _activityMap(tracker).values.where((value) => value).length;
  }

  Map<DateTime, Map<String, dynamic>> _buildTrackerMap(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final trackers = <DateTime, Map<String, dynamic>>{};
    for (final doc in docs) {
      final data = doc.data();
      final rawDate =
          (data['lastUpdated'] as String?) ?? (data['date'] as String?) ?? '';
      if (rawDate.trim().isEmpty) continue;
      try {
        trackers[_normalizeDate(DateTime.parse(rawDate))] = data;
      } catch (_) {}
    }
    return trackers;
  }

  Widget _buildActivityLegend() {
    final colors = Theme.of(context).colorScheme;
    const items = <MapEntry<Color, String>>[
      MapEntry(Color(0xFFF5E3C8), '1-2 tasks'),
      MapEntry(Color(0xFFCFE1D0), '3-4 tasks'),
      MapEntry(Color(0xFF90A17D), '5 tasks'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: item.key,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Color _calendarColorForCount(int count) {
    if (count >= 5) return const Color(0xFF90A17D);
    if (count >= 3) return const Color(0xFFCFE1D0);
    if (count >= 1) return const Color(0xFFF5E3C8);
    return Colors.transparent;
  }

  Widget _buildActivityDetails(Map<String, dynamic>? tracker) {
    final colors = Theme.of(context).colorScheme;
    final tasks = tracker == null ? <String, bool>{} : _activityMap(tracker);
    if (tracker == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          'No logged activity for this day.',
          style: TextStyle(color: colors.onSurface.withValues(alpha: 0.68)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tasks.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: entry.value
                  ? colors.primary.withValues(alpha: 0.18)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${entry.key}: ${entry.value ? 'Done' : 'Not yet'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenteeCalendarCard(
    Map<String, dynamic> mentee,
    List<Map<String, dynamic>> trackerDocs,
  ) {
    return _CoachMenteeCalendarCard(
      key: ValueKey(mentee['menteeId']?.toString() ?? ''),
      mentee: mentee,
      trackerDocs: trackerDocs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Recent mentee activity',
                style: TextStyle(color: companyTheme.inkColor),
              ),
            ),
            body: _MenteeActivityDataScope(
              builder: (
                context, {
                required mentees,
                required menteeTrackers,
                required isLoading,
                required hasError,
              }) {
                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (hasError) {
                  return Center(
                    child: Text(
                      'Could not load mentee activity.',
                      style: TextStyle(color: companyTheme.mutedInkColor),
                    ),
                  );
                }

                if (mentees.isEmpty) {
                  return Center(
                    child: Text(
                      'No mentees added yet.',
                      style: TextStyle(color: companyTheme.mutedInkColor),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: mentees.length,
                  itemBuilder: (context, index) {
                    final mentee = mentees[index];
                    final trackersForMentee = index < menteeTrackers.length
                        ? menteeTrackers[index]
                        : const <Map<String, dynamic>>[];
                    return _buildMenteeCalendarCard(
                      mentee,
                      trackersForMentee,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// Owns the mentees + per-mentee tracker fetch/refresh lifecycle. Previously
// a bare Timer.periodic called setState() with no payload, forcing build()
// to recreate both the mentees Future and the nested per-mentee trackers
// Future.wait every 20s - flashing the whole list (and every mentee's
// scroll position) to a spinner and back on a timer, even when nothing had
// actually changed. Real state + "spinner only before the first load"
// fixes that, matching the pattern already used for Manage Groups/Mentees.
class _MenteeActivityDataScope extends StatefulWidget {
  const _MenteeActivityDataScope({required this.builder});

  final Widget Function(
    BuildContext context, {
    required List<Map<String, dynamic>> mentees,
    required List<List<Map<String, dynamic>>> menteeTrackers,
    required bool isLoading,
    required bool hasError,
  }) builder;

  @override
  State<_MenteeActivityDataScope> createState() =>
      _MenteeActivityDataScopeState();
}

class _MenteeActivityDataScopeState extends State<_MenteeActivityDataScope> {
  List<Map<String, dynamic>>? _mentees;
  List<List<Map<String, dynamic>>>? _menteeTrackers;
  bool _isLoading = true;
  bool _hasError = false;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final mentees = await CoachApiService.instance.fetchMentees();
      final trackers = await Future.wait(
        mentees.map((mentee) {
          return CoachApiService.instance.fetchMenteeTrackers(
            (mentee['menteeId'] as String?)?.trim() ?? '',
          );
        }),
      );
      if (!mounted) return;
      setState(() {
        _mentees = mentees;
        _menteeTrackers = trackers;
        _hasError = false;
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Failed to refresh mentee activity data: $error');
      if (!mounted) return;
      if (_mentees == null) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      mentees: _mentees ?? const <Map<String, dynamic>>[],
      menteeTrackers: _menteeTrackers ?? const <List<Map<String, dynamic>>>[],
      isLoading: _isLoading,
      hasError: _hasError,
    );
  }
}

class _CoachMenteeCalendarCard extends StatefulWidget {
  const _CoachMenteeCalendarCard({
    super.key,
    required this.mentee,
    required this.trackerDocs,
  });

  final Map<String, dynamic> mentee;
  final List<Map<String, dynamic>> trackerDocs;

  @override
  State<_CoachMenteeCalendarCard> createState() =>
      _CoachMenteeCalendarCardState();
}

class _CoachMenteeCalendarCardState extends State<_CoachMenteeCalendarCard> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  List<Map<String, dynamic>>? _goals;
  List<Task>? _todoTasks;
  bool _recentLogsExpanded = false;
  bool _cardExpanded = false;
  bool _detailsRequested = false;

  @override
  void initState() {
    super.initState();
    final today = _normalizeDate(DateTime.now());
    _focusedDay = today;
    _selectedDay = today;
  }

  // Calendar, goals, todo tasks, and tracker logs are all hidden until the
  // coach actually expands a mentee's card, so goals/todos are only fetched
  // then too - with many mentees, eagerly firing two extra requests per
  // card for detail nobody may ever look at doesn't scale.
  void _toggleExpanded() {
    setState(() => _cardExpanded = !_cardExpanded);
    if (_cardExpanded && !_detailsRequested) {
      _detailsRequested = true;
      _loadGoals();
      _loadTodoTasks();
    }
  }

  Future<void> _loadGoals() async {
    final menteeId = (widget.mentee['menteeId'] as String?)?.trim() ?? '';
    if (menteeId.isEmpty) return;
    try {
      final goals = await CoachApiService.instance.fetchMenteeGoals(menteeId);
      if (!mounted) return;
      setState(() {
        _goals = goals;
      });
    } catch (error) {
      debugPrint('Failed to load mentee goals: $error');
    }
  }

  Future<void> _loadTodoTasks() async {
    final menteeId = (widget.mentee['menteeId'] as String?)?.trim() ?? '';
    if (menteeId.isEmpty) return;
    try {
      final rawTasks =
          await CoachApiService.instance.fetchMenteeTodoTasks(menteeId);
      if (!mounted) return;
      setState(() {
        _todoTasks = rawTasks.map(Task.fromJson).toList();
      });
    } catch (error) {
      debugPrint('Failed to load mentee todo tasks: $error');
    }
  }

  DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Map<String, bool> _activityMap(Map<String, dynamic> tracker) {
    return <String, bool>{
      'Call': tracker['call'] == true,
      'Steps': tracker['steps'] == true,
      'Meditation': tracker['meditation'] == true,
      'Learning': tracker['learning'] == true,
      'Add Value': tracker['addValue'] == true,
    };
  }

  int _completedCount(Map<String, dynamic> tracker) {
    return _activityMap(tracker).values.where((value) => value).length;
  }

  // Real logged value for a completed task, e.g. "20 min" or "4,500 steps",
  // instead of a bare "Done" that hides what the mentee actually recorded.
  String _doneDetailLabel(Map<String, dynamic> tracker, String taskKey) {
    switch (taskKey) {
      case 'Call':
        final count = (tracker['callCount'] as num?)?.toInt() ?? 0;
        return count > 0 ? '$count ${count == 1 ? 'call' : 'calls'}' : 'Done';
      case 'Steps':
        final steps = (tracker['stepCount'] as num?)?.toInt() ?? 0;
        return steps > 0
            ? '${NumberFormat('#,###').format(steps)} steps'
            : 'Done';
      case 'Meditation':
        final minutes = (tracker['meditationMinutes'] as num?)?.toInt() ?? 0;
        return minutes > 0 ? '$minutes min' : 'Done';
      case 'Learning':
        final count = (tracker['learningCount'] as num?)?.toInt() ?? 0;
        return count > 0
            ? '$count ${count == 1 ? 'entry' : 'entries'}'
            : 'Done';
      case 'Add Value':
        final count = (tracker['valueCount'] as num?)?.toInt() ?? 0;
        return count > 0
            ? '$count ${count == 1 ? 'entry' : 'entries'}'
            : 'Done';
      default:
        return 'Done';
    }
  }

  Map<DateTime, Map<String, dynamic>> _buildTrackerMap() {
    final trackers = <DateTime, Map<String, dynamic>>{};
    for (final data in widget.trackerDocs) {
      final rawDate =
          (data['lastUpdated'] as String?) ?? (data['date'] as String?) ?? '';
      if (rawDate.trim().isEmpty) continue;
      try {
        trackers[_normalizeDate(DateTime.parse(rawDate))] = data;
      } catch (_) {}
    }
    return trackers;
  }

  Color _calendarColorForCount(int count) {
    if (count >= 5) return const Color(0xFF90A17D);
    if (count >= 3) return const Color(0xFFCFE1D0);
    if (count >= 1) return const Color(0xFFF5E3C8);
    return Colors.transparent;
  }

  Widget _buildActivityLegend() {
    final colors = Theme.of(context).colorScheme;
    const items = <MapEntry<Color, String>>[
      MapEntry(Color(0xFFF5E3C8), '1-2 tasks'),
      MapEntry(Color(0xFFCFE1D0), '3-4 tasks'),
      MapEntry(Color(0xFF90A17D), '5 tasks'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: item.key,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _buildActivityDetails(Map<String, dynamic>? tracker) {
    final colors = Theme.of(context).colorScheme;
    final tasks = tracker == null ? <String, bool>{} : _activityMap(tracker);
    if (tracker == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          'No logged activity for this day.',
          style: TextStyle(color: colors.onSurface.withValues(alpha: 0.68)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tasks.entries.map((entry) {
          final detail =
              entry.value ? _doneDetailLabel(tracker, entry.key) : 'Not yet';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: entry.value
                  ? colors.primary.withValues(alpha: 0.18)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${entry.key}: $detail',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  DateTime? _trackerDate(Map<String, dynamic> tracker) {
    final rawDate = (tracker['lastUpdated'] as String?) ??
        (tracker['date'] as String?) ??
        '';
    if (rawDate.trim().isEmpty) return null;
    try {
      return _normalizeDate(DateTime.parse(rawDate));
    } catch (_) {
      return null;
    }
  }

  Widget _buildProgressOverview() {
    final colors = Theme.of(context).colorScheme;
    final goals = _goals ?? const <Map<String, dynamic>>[];
    final completedGoals = goals.where((goal) {
      final status = (goal['status'] as String?)?.trim().toLowerCase() ?? '';
      final progress = ((goal['progress'] as num?)?.toInt() ?? 0).clamp(0, 100);
      return status == 'completed' || progress >= 100;
    }).length;
    final goalsPercent =
        goals.isEmpty ? null : (completedGoals / goals.length * 100).round();

    // Same formula as the mentee's own "Goals score" panel on their Goals
    // screen (todo_list.dart _todoScore) - a task with sub-tasks counts
    // proportionally by how many sub-tasks are checked off, not just
    // all-or-nothing, so this reuses taskProgress() directly rather than a
    // simplified completed/total approximation that could disagree with
    // what the mentee actually sees.
    final todoTasks = _todoTasks ?? const <Task>[];
    final todoScorePercent = todoTasks.isEmpty
        ? null
        : (todoTasks.fold<double>(0, (total, t) => total + taskProgress(t)) /
                todoTasks.length)
            .round();

    final trackerMap = _buildTrackerMap();
    final latestTracker = trackerMap.entries.isEmpty
        ? null
        : (trackerMap.entries.toList()..sort((a, b) => b.key.compareTo(a.key)))
            .first
            .value;
    final trackerPercent = latestTracker == null
        ? null
        : (_completedCount(latestTracker) / 5 * 100).round();

    final menteeName = (widget.mentee['menteeName'] as String?)?.trim();

    final stats = <Widget>[
      if (goalsPercent != null)
        _buildOverviewStat(
          label: 'Goals completed',
          percent: goalsPercent,
          color: colors.primary,
        ),
      if (todoScorePercent != null)
        _buildOverviewStat(
          label: 'Goals score',
          percent: todoScorePercent,
          color: colors.tertiary,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CoachMenteeGoalsScreen(
                menteeName:
                    menteeName?.isNotEmpty == true ? menteeName! : 'Mentee',
                tasks: todoTasks,
              ),
            ),
          ),
        ),
      if (trackerPercent != null)
        _buildOverviewStat(
          label: 'Latest daily tracker',
          percent: trackerPercent,
          color: colors.secondary,
        ),
    ];

    if (stats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: stats[i]),
        ],
      ],
    );
  }

  Widget _buildOverviewStat({
    required String label,
    required int percent,
    required Color color,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: colors.onSurface.withValues(alpha: 0.5),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 6,
                    backgroundColor: colors.onSurface.withValues(alpha: 0.12),
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: content,
    );
  }

  Widget _buildGoalsSection() {
    final colors = Theme.of(context).colorScheme;
    final goals = _goals ?? const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Goals',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ...goals.map((goal) {
          final title = (goal['title'] as String?)?.trim().isNotEmpty == true
              ? (goal['title'] as String).trim()
              : 'Goal';
          final status =
              (goal['status'] as String?)?.trim().toLowerCase() ?? '';
          final progress =
              ((goal['progress'] as num?)?.toInt() ?? 0).clamp(0, 100);
          final isCompleted = status == 'completed' || progress >= 100;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          minHeight: 6,
                          backgroundColor:
                              colors.onSurface.withValues(alpha: 0.12),
                          color: isCompleted
                              ? colors.primary
                              : colors.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$progress%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRecentActivityLogs() {
    final colors = Theme.of(context).colorScheme;
    final recentTrackers = widget.trackerDocs.toList()
      ..sort((left, right) {
        final leftDate =
            _trackerDate(left) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            _trackerDate(right) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightDate.compareTo(leftDate);
      });

    final visibleLogs = recentTrackers.take(5).toList();
    if (visibleLogs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _recentLogsExpanded = !_recentLogsExpanded;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent activity logs (${visibleLogs.length})',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Icon(
                  _recentLogsExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 18,
                  color: colors.onSurface.withValues(alpha: 0.68),
                ),
              ],
            ),
          ),
        ),
        if (_recentLogsExpanded) ...[
          const SizedBox(height: 6),
          ...visibleLogs.map((tracker) {
            final logDate = _trackerDate(tracker);
            final completedCount = _completedCount(tracker);
            final tasks = _activityMap(tracker);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          logDate == null
                              ? 'Unknown date'
                              : DateFormat.yMMMd().format(logDate),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        '$completedCount/5 done',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tasks.entries.map((entry) {
                      final isDone = entry.value;
                      final detail = isDone
                          ? _doneDetailLabel(tracker, entry.key)
                          : 'Pending';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isDone
                              ? colors.primary.withValues(alpha: 0.14)
                              : colors.surface.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${entry.key}: $detail',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  List<_CoachApiGroupSummary> _apiGroupSummaries(
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> groups,
  ) {
    final groupsById = <String, Map<String, dynamic>>{
      for (final group in groups) (group['id']?.toString() ?? ''): group,
    };

    final rawSummaries = payload['groupLeaderboards'];
    if (rawSummaries is! List) {
      return const <_CoachApiGroupSummary>[];
    }

    final summaries = rawSummaries.whereType<Map>().map((rawSummary) {
      final summary = Map<String, dynamic>.from(rawSummary);
      final groupId = summary['groupId']?.toString() ?? '';
      final groupMeta = groupsById[groupId] ?? <String, dynamic>{};
      final entries = (summary['entries'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final memberIds = List<String>.from(
        groupMeta['memberIds'] as List? ?? const <String>[],
      );
      final coachIds = List<String>.from(
        groupMeta['coachIds'] as List? ?? const <String>[],
      );
      final coachNames = List<String>.from(
        groupMeta['coachNames'] as List? ?? const <String>[],
      );

      return _CoachApiGroupSummary(
        groupId: groupId,
        groupName: (summary['groupName'] as String?)?.trim() ?? 'Group',
        totalScore: (summary['totalScore'] as num?)?.toInt() ?? 0,
        entries: entries,
        memberCount:
            (groupMeta['memberCount'] as num?)?.toInt() ?? memberIds.length,
        memberIds: memberIds,
        coachIds: coachIds,
        coachNames: coachNames,
      );
    }).toList();

    summaries.sort((a, b) {
      if (a.totalScore != b.totalScore) {
        return b.totalScore.compareTo(a.totalScore);
      }
      return a.groupName.toLowerCase().compareTo(b.groupName.toLowerCase());
    });
    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = widget.mentee;
    final menteeName = (data['menteeName'] as String?)?.trim();
    final trackerMap = _buildTrackerMap();
    final selectedTracker = trackerMap[_normalizeDate(_selectedDay)];
    final latestEntry = trackerMap.entries.isEmpty
        ? null
        : (trackerMap.entries.toList()..sort((a, b) => b.key.compareTo(a.key)))
            .first;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _toggleExpanded,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE9EEE4),
                  child: Text(
                    menteeName?.isNotEmpty == true
                        ? menteeName![0].toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        menteeName?.isNotEmpty == true ? menteeName! : 'Mentee',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                      if (_cardExpanded) ...[
                        const SizedBox(height: 4),
                        Text(
                          latestEntry == null
                              ? 'No recent activity yet'
                              : 'Latest activity: ${DateFormat.yMMMd().format(latestEntry.key)}',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(data['score'] as num?)?.toInt() ?? 0} pts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _cardExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 18,
                  color: colors.onSurface.withValues(alpha: 0.68),
                ),
              ],
            ),
          ),
          if (_cardExpanded) ...[
            const SizedBox(height: 14),
            _buildProgressOverview(),
            if (_goals != null && _goals!.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildGoalsSection(),
            ],
            const SizedBox(height: 16),
            _buildActivityLegend(),
            const SizedBox(height: 14),
            TableCalendar<Map<String, dynamic>>(
              firstDay: DateTime.now().subtract(const Duration(days: 120)),
              lastDay: DateTime.now().add(const Duration(days: 30)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: (day) {
                final tracker = trackerMap[_normalizeDate(day)];
                return tracker == null ? const [] : [tracker];
              },
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
              ),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = _normalizeDate(selected);
                  _focusedDay = _normalizeDate(focused);
                });
              },
              onPageChanged: (focused) {
                setState(() {
                  _focusedDay = _normalizeDate(focused);
                });
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.24),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  final tracker = trackerMap[_normalizeDate(day)];
                  if (tracker == null) return null;
                  final count = _completedCount(tracker);
                  return Container(
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _calendarColorForCount(count),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: count >= 5 ? Colors.white : colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  final tracker = events.first;
                  final count = _completedCount(tracker);
                  return Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Selected day: ${DateFormat.yMMMMd().format(_selectedDay)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            _buildActivityDetails(selectedTracker),
            _buildRecentActivityLogs(),
          ],
        ],
      ),
    );
  }
}

class _CoachDashboardTileTransition {
  const _CoachDashboardTileTransition({
    required this.tileKey,
    required this.rect,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String tileKey;
  final Rect rect;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachGroupNameDialog extends StatefulWidget {
  const _CoachGroupNameDialog({required this.hintText});

  final String hintText;

  @override
  State<_CoachGroupNameDialog> createState() => _CoachGroupNameDialogState();
}

class _CoachGroupNameDialogState extends State<_CoachGroupNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Group name is required.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      title: const Text('Create group'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Group name',
          hintText: widget.hintText,
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText == null) return;
          setState(() => _errorText = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _CoachApiGroupCard extends StatefulWidget {
  const _CoachApiGroupCard({
    required this.summary,
    required this.onAddCoach,
    required this.onAddMentee,
    required this.onDelete,
  });

  final _CoachApiGroupSummary summary;
  final VoidCallback onAddCoach;
  final VoidCallback onAddMentee;
  final VoidCallback onDelete;

  @override
  State<_CoachApiGroupCard> createState() => _CoachApiGroupCardState();
}

class _CoachApiGroupCardState extends State<_CoachApiGroupCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = widget.summary;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            contentPadding: const EdgeInsets.fromLTRB(18, 10, 12, 0),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                CupertinoIcons.rectangle_grid_2x2_fill,
                color: colors.primary,
              ),
            ),
            title: Text(
              summary.groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: colors.onSurface,
              ),
            ),
            subtitle: Text(
              '${summary.memberCount} mentees • ${summary.coachIds.length} coaches • ${summary.totalScore} pts total',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.68)),
            ),
            trailing: Icon(
              _expanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: colors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 12, 10),
            child: Row(
              children: [
                _buildPillButton(
                  colors: colors,
                  icon: CupertinoIcons.person_badge_plus,
                  label: 'Add coach',
                  color: colors.primary,
                  tooltip: summary.coachIds.length >= 2
                      ? 'Coach limit reached'
                      : null,
                  onPressed:
                      summary.coachIds.length >= 2 ? null : widget.onAddCoach,
                ),
                const SizedBox(width: 8),
                _buildPillButton(
                  colors: colors,
                  icon: CupertinoIcons.person_2_fill,
                  label: 'Add mentee',
                  color: colors.tertiary,
                  onPressed: widget.onAddMentee,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete group',
                  onPressed: widget.onDelete,
                  icon: const Icon(CupertinoIcons.trash),
                  color: const Color(0xFFE56B6F),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Text(
                'Coaches',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ),
            if (summary.coachIds.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No coaches added yet.',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ),
              )
            else
              ...List.generate(summary.coachIds.length, (index) {
                final name = index < summary.coachNames.length
                    ? summary.coachNames[index].trim()
                    : '';
                final displayName = name.isNotEmpty ? name : 'Coach';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: colors.primary.withValues(alpha: 0.16),
                    child: Text(displayName[0].toUpperCase()),
                  ),
                  title: Text(displayName),
                  subtitle: const Text('Coach'),
                );
              }),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Text(
                'Mentees',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ),
            if (summary.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No mentees selected yet.',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ),
              )
            else
              ...summary.entries.asMap().entries.map((entry) {
                final data = entry.value;
                final name =
                    (data['name'] as String?)?.trim().isNotEmpty == true
                        ? (data['name'] as String).trim()
                        : 'Mentee';
                final profilePic =
                    (data['profilePic'] as String?)?.trim() ?? '';
                final score = (data['score'] as num?)?.toInt() ?? 0;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 2,
                  ),
                  leading: CircleAvatar(
                    backgroundImage:
                        profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                    child: profilePic.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                          )
                        : null,
                  ),
                  title: Text(name),
                  subtitle: Text('Rank #${entry.key + 1}'),
                  trailing: Text(
                    '$score pts',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
              }),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildPillButton({
    required ColorScheme colors,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    String? tooltip,
  }) {
    final isEnabled = onPressed != null;
    final content = Material(
      color: color.withValues(alpha: isEnabled ? 0.14 : 0.06),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isEnabled ? color : color.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isEnabled ? color : color.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip == null) {
      return content;
    }
    return Tooltip(message: tooltip, child: content);
  }
}
