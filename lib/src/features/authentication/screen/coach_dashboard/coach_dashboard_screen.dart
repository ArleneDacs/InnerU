import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/calorie_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/chat_room.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coaches_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isSavingProfile = false;
  String? selectedEmotion;
  String? _currentUserEmotion;
  String _quote = 'Your daily inspiration...';
  String _author = 'Unknown';
  final Map<String, DateTime> _localChatReadOverrides = <String, DateTime>{};
  final Set<String> _pressedTiles = <String>{};
  final GlobalKey _dashboardStackKey = GlobalKey();
  late final AnimationController _tileTransitionController;
  _CoachDashboardTileTransition? _activeTileTransition;

  String get _userId => _auth.currentUser!.uid;

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _userStream =>
      _firestore.collection('users').doc(_userId).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _coachStream =>
      _firestore.collection('coaches').doc(_userId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _menteesStream => _firestore
      .collection('users')
      .where('coachId', isEqualTo: _userId)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _tileTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _loadTodayEmotion();
    _fetchQuote();
    _loadLocalChatReadOverrides();
  }

  @override
  void dispose() {
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

      final response = await http.get(Uri.parse('https://zenquotes.io/api/random'));
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

  Future<void> _loadTodayEmotion() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return;

    final savedEmotion = prefs.getString('selected_emotion_${user.uid}');
    final savedDate = prefs.getString('emotion_date_${user.uid}');
    final today = DateTime.now().toString().split(' ')[0];

    if (!mounted) return;
    setState(() {
      _currentUserEmotion = savedDate == today ? savedEmotion : null;
    });
  }

  Future<void> _saveEmotionToSharedPreferences(String emotion) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    if (user == null) return;

    await prefs.setString('selected_emotion_${user.uid}', emotion);
    await prefs.setString(
      'emotion_date_${user.uid}',
      DateTime.now().toString().split(' ')[0],
    );
  }

  Future<String> _getUsername() async {
    final user = _auth.currentUser;
    if (user == null) return 'Coach';

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists && userDoc['username'] != null) {
      return userDoc['username'] as String;
    }
    return user.email?.split('@').first ?? 'Coach';
  }

  Future<void> _saveEmotionToDatabase(
    BuildContext context,
    String emotion,
    String username,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final today = DateTime.now().toString().split(' ')[0];

    try {
      final snapshot = await _firestore
          .collection('emotions')
          .where('userId', isEqualTo: user.uid)
          .where('username', isEqualTo: username)
          .where('date', isEqualTo: today)
          .get();

      if (snapshot.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only select one emotion per day!'),
          ),
        );
        return;
      }

      await _firestore.collection('emotions').add({
        'userId': user.uid,
        'username': username,
        'emotion': emotion,
        'date': today,
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save emotion. Please try again.'),
        ),
      );
    }
  }

  Future<void> _selectEmotion(String emotion) async {
    final username = await _getUsername();

    setState(() {
      selectedEmotion = emotion;
      _currentUserEmotion = emotion;
    });

    await _saveEmotionToDatabase(context, emotion, username);
    await _saveEmotionToSharedPreferences(emotion);
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

                          await _firestore.collection('coaches').doc(_userId).set({
                            'userId': _userId,
                            'username': userData?['username'] ?? '',
                            'email':
                                userData?['email'] ?? _auth.currentUser?.email ?? '',
                            'fullName': teamName,
                            'bio': bioController.text.trim(),
                            'phonenumber': phoneController.text.trim(),
                            'profilePic': userData?['profilePic'] ?? '',
                            'backgroundColor':
                                coachData?['backgroundColor'] ?? 'blue',
                            'createdAt': coachData?['createdAt'] ??
                                FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          await _firestore.collection('users').doc(_userId).set({
                            'role': 'coach',
                            'isCoach': true,
                            'team': teamName,
                          }, SetOptions(merge: true));

                          final menteesSnapshot = await _firestore
                              .collection('users')
                              .where('coachId', isEqualTo: _userId)
                              .get();

                          for (final mentee in menteesSnapshot.docs) {
                            await mentee.reference.set({
                              'coachName': teamName,
                              'team': teamName,
                            }, SetOptions(merge: true));
                          }

                          if (!mounted) return;
                          setState(() => _isSavingProfile = false);
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Coach profile saved successfully'),
                            ),
                          );
                        },
                  child: Text(
                    (coachData == null || coachData.isEmpty) ? 'Create' : 'Save',
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
  }) async {
    final coachDoc = await _firestore.collection('coaches').doc(_userId).get();
    final coachName = (coachDoc.data()?['fullName'] as String?) ??
        (coachDoc.data()?['username'] as String?) ??
        'Coach';

    await _firestore.collection('users').doc(menteeId).set({
      'coachId': _userId,
      'coachName': coachName,
      'team': teamName,
    }, SetOptions(merge: true));
  }

  Future<void> _removeMentee(String menteeId) async {
    await _firestore.collection('users').doc(menteeId).update({
      'coachId': FieldValue.delete(),
      'coachName': FieldValue.delete(),
      'team': FieldValue.delete(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mentee removed from your team')),
    );
  }

  Future<Map<String, dynamic>?> _latestTrackerForUser(String userId) async {
    final snapshot = await _firestore
        .collection('dailytracker')
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.data();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.black54,
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
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInboxAction() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('chatRooms')
          .where('participants', arrayContains: _userId)
          .snapshots(),
      builder: (context, snapshot) {
        var unreadCount = 0;
        for (final doc
            in snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final chatData = doc.data();
          final localReadTime = _localChatReadOverrides[doc.id];
          final lastMessageTimeRaw = chatData['lastMessageTime'];
          final lastMessageTime = lastMessageTimeRaw is Timestamp
              ? lastMessageTimeRaw.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final lastReadAt = Map<String, dynamic>.from(
            chatData['lastReadAt'] as Map? ?? <String, dynamic>{},
          );
          final lastReadAtRaw = lastReadAt[_userId];
          final readTime =
              lastReadAtRaw is Timestamp ? lastReadAtRaw.toDate() : null;
          final effectiveReadTime = [
            if (readTime != null) readTime,
            if (localReadTime != null) localReadTime,
          ].fold<DateTime?>(
            null,
            (latest, candidate) =>
                latest == null || candidate.isAfter(latest) ? candidate : latest,
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
            final lastSenderId = (chatData['lastSenderId'] as String?)?.trim() ?? '';
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
              icon: const Icon(CupertinoIcons.chat_bubble_2, size: 24),
              onPressed: () async {
                final coachDoc = await _firestore.collection('coaches').doc(_userId).get();
                final coachData = coachDoc.data();
                final userName =
                    (coachData?['fullName'] as String?)?.trim().isNotEmpty == true
                        ? (coachData!['fullName'] as String).trim()
                        : await _getUsername();
                if (!context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatListScreen(
                      userId: _userId,
                      userName: userName,
                      allowGroupChat: true,
                      groupName: (coachData?['fullName'] as String?)?.trim(),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth > 600 ? 28.0 : 20.0;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() ?? <String, dynamic>{};

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _coachStream,
          builder: (context, coachSnapshot) {
            final coachData = coachSnapshot.data?.data() ?? <String, dynamic>{};
            final teamName = (coachData['fullName'] as String?) ??
                (userData['team'] as String?) ??
                (userData['username'] as String?) ??
                'My Team';
            final displayName = (coachData['fullName'] as String?) ??
                (userData['username'] as String?) ??
                'Coach';
            final profilePic = (userData['profilePic'] as String?)?.trim();

            return Scaffold(
              backgroundColor: const Color(0xFFF5F7F2),
              appBar: AppBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: (profilePic == null || profilePic.isEmpty)
                      ? Image.asset(
                          'assets/images/avatar.png',
                          width: screenWidth * 0.08,
                          height: screenWidth * 0.08,
                        )
                      : ClipOval(
                          child: Image.network(
                            profilePic,
                            width: screenWidth * 0.08,
                            height: screenWidth * 0.08,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.person, size: screenWidth * 0.08);
                            },
                          ),
                        ),
                  onPressed: () => Navigator.pushNamed(context, '/profile'),
                ),
                actions: [
                  _buildInboxAction(),
                  IconButton(
                    icon: const Icon(CupertinoIcons.line_horizontal_3, size: 28),
                    onPressed: () => BottomSheetWidget.show(context),
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
    final theme = Theme.of(context);
    final bio = (coachData['bio'] as String?)?.trim();
    final phone = (coachData['phonenumber'] as String?)?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF90A17D), Color(0xFF6D849A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF90A17D).withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Coach hub',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Hello, Coach $displayName',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bio?.isNotEmpty == true
                ? bio!
                : 'Keep your team aligned, support your mentees, and track the day with intention.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withOpacity(0.88),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildHeroChip('Team', teamName),
              _buildHeroChip('Mentees', '$menteeCount'),
              _buildHeroChip('Phone', phone?.isNotEmpty == true ? phone! : 'Not set'),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.quote_bubble_fill,
                      size: 18,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Today\'s note',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  quote,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  author,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
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
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.5)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Today's focus"),
        const SizedBox(height: 6),
        Text(
          'Lead by example and keep your habits visible.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
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
                setupIndex: 2,
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
                setupIndex: 3,
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
                setupIndex: 4,
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: 184,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.72)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.82),
            Color.alphaBlend(const Color(0x1FFFFFFF), color),
            Color.alphaBlend(const Color(0x40FFFFFF), color),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB9C7B6).withOpacity(isPressed ? 0.14 : 0.24),
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
                    Colors.white.withOpacity(0.36),
                    Colors.white.withOpacity(0.02),
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
                      Colors.white.withOpacity(0.3),
                      Colors.white.withOpacity(0.06),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 58,
            right: 42,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
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
                    Colors.white.withOpacity(0.1),
                    Colors.transparent,
                    Colors.black.withOpacity(0.06),
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
                color: Colors.white.withOpacity(0.62),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.6)),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF53654C),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Coach practice',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: Color(0xFF697960),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2A1A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Color(0xFF43523D),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text(
                      'Open',
                      style: TextStyle(
                        color: Color(0xFF506149),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.56),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: Color(0xFF506149),
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

    final targetPage = setupIndex != null
        ? CoachSetuppage(initialIndex: setupIndex)
        : destinationPage;

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
          final t = Curves.easeInOutCubic.transform(_tileTransitionController.value);
          final size = MediaQuery.of(context).size;
          final targetWidth = size.width.clamp(280.0, 420.0) * 0.82;
          final targetHeight = 260.0;
          final targetRect = Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: targetWidth,
            height: targetHeight,
          );
          final moveT = Curves.easeOutCubic.transform((t / 0.42).clamp(0.0, 1.0));
          final scatterT = ((t - 0.58) / 0.42).clamp(0.0, 1.0);
          final currentRect = Rect.lerp(transition.rect, targetRect, moveT)!;
          final overlayOpacity = Tween<double>(begin: 0, end: 0.22).transform(t);
          final tileOpacity = scatterT > 0
              ? (1 - Curves.easeInCubic.transform(scatterT)).clamp(0.0, 1.0).toDouble()
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
      (ax: -0.34, ay: -0.22, size: 26.0, radius: 10.0, dx: -120.0, dy: -88.0, rot: -0.9),
      (ax: 0.28, ay: -0.18, size: 20.0, radius: 8.0, dx: 128.0, dy: -96.0, rot: 1.1),
      (ax: -0.18, ay: 0.08, size: 22.0, radius: 9.0, dx: -96.0, dy: 24.0, rot: 0.8),
      (ax: 0.16, ay: 0.16, size: 18.0, radius: 8.0, dx: 90.0, dy: 46.0, rot: -1.2),
      (ax: -0.04, ay: 0.26, size: 24.0, radius: 10.0, dx: -18.0, dy: 136.0, rot: 1.0),
      (ax: 0.34, ay: 0.02, size: 16.0, radius: 7.0, dx: 144.0, dy: 8.0, rot: 1.4),
    ];

    final eased = Curves.easeOutCubic.transform(progress);
    final fade = (1 - Curves.easeInQuad.transform(progress)).clamp(0.0, 1.0).toDouble();
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
            angle: fragment.rot * Curves.easeInOut.transform(progress) * 3.141592653589793,
            child: Container(
              width: fragment.size,
              height: fragment.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fragment.radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.84),
                    Color.alphaBlend(const Color(0x33FFFFFF), color),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.14),
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
                  currentUserName:
                      (userData['username'] as String?) ??
                      (coachData['fullName'] as String?) ??
                      'Coach',
                  teamName: teamName,
                  menteesStream: _menteesStream,
                  onAssignMentee: _assignMentee,
                  onRemoveMentee: _removeMentee,
                  latestTrackerForUser: _latestTrackerForUser,
                  formatTrackerDate: _formatTrackerDate,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildNavigationCard(
          title: 'Recent activity',
          subtitle: 'See all mentee progress in a calendar view like user progress.',
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xFF2D3A25)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onTap,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('How do you feel today?'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
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
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
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
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Track Your Emotions',
                            style: TextStyle(fontSize: 14, color: Colors.blue),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Colors.blue,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Mood check-in",
          subtitle: "Keep track of how today feels, not just what you finish.",
        ),
        const SizedBox(height: 14),
        _buildGlassSectionCard(
          child: _currentUserEmotion == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Choose the mood that feels closest right now.",
                      style: TextStyle(
                        color: Color(0xFF5E6E57),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
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
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
                            color: const Color(0xFFDDE7D5),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            CupertinoIcons.heart_fill,
                            color: Color(0xFF5E7652),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            "Today you're feeling $_currentUserEmotion",
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF24311F),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Nice check-in. You can keep a longer emotion history in the tracker whenever you want.",
                      style: TextStyle(
                        color: Color(0xFF5E6E57),
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
                        foregroundColor: const Color(0xFF6E8464),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.76)),
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
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF30402A),
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
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width / 2,
              child: Image.asset('assets/images/confetti_left.gif', fit: BoxFit.cover),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width / 2,
              child: Image.asset('assets/images/confetti_right.gif', fit: BoxFit.cover),
            ),
          ],
        );
      case 'sad':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/rain.jpg'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'angry':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/night_firepit.jpg'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'neutral':
        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/ocean_waves.jpg'),
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
          color: Colors.black.withOpacity(0.24),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22.0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.98),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Team overview')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasProfile ? (coachData['fullName'] as String? ?? teamName) : username,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasProfile
                      ? (coachData['bio'] as String? ?? 'Coach profile ready')
                      : 'Create your coach profile so users can connect with you and your team stays organized.',
                  style: const TextStyle(
                    height: 1.45,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _OverviewChip('Team name', teamName),
                    _OverviewChip('Assigned mentees', '$menteeCount'),
                    _OverviewChip(
                      'Phone',
                      (coachData['phonenumber'] as String?)?.isNotEmpty == true
                          ? coachData['phonenumber'] as String
                          : 'Not set',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onEditProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(hasProfile ? 'Edit profile' : 'Create profile'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenInbox,
                      icon: const Icon(CupertinoIcons.chat_bubble_2_fill),
                      label: const Text('Open inbox'),
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
}

class CoachManageMenteesPage extends StatelessWidget {
  const CoachManageMenteesPage({
    super.key,
    required this.firestore,
    required this.currentUserId,
    required this.currentUserName,
    required this.teamName,
    required this.menteesStream,
    required this.onAssignMentee,
    required this.onRemoveMentee,
    required this.latestTrackerForUser,
    required this.formatTrackerDate,
  });

  final FirebaseFirestore firestore;
  final String currentUserId;
  final String currentUserName;
  final String teamName;
  final Stream<QuerySnapshot<Map<String, dynamic>>> menteesStream;
  final Future<void> Function({
    required String menteeId,
    required String teamName,
  }) onAssignMentee;
  final Future<void> Function(String menteeId) onRemoveMentee;
  final Future<Map<String, dynamic>?> Function(String userId) latestTrackerForUser;
  final String Function(Map<String, dynamic>? tracker) formatTrackerDate;

  String _normalizeName(String value) => value.trim().toLowerCase();

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
    final stepsTaken =
        _extractIntValue(
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

    return callIntent +
        meditationMinutes +
        (stepsTaken / 200).floor() +
        valueEntries +
        learningEntries;
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

  Future<void> _showAddMenteeSheet(BuildContext context) async {
    final searchController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: firestore.collection('users').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final query = searchController.text.trim().toLowerCase();
                        final users = snapshot.data!.docs.where((doc) {
                          final data = doc.data();
                          final isCoach = data['isCoach'] == true ||
                              ((data['role'] as String?)?.toLowerCase() == 'coach');
                          final username =
                              (data['username'] as String? ?? '').toLowerCase();
                          final email = (data['email'] as String? ?? '').toLowerCase();
                          return doc.id != currentUserId &&
                              !isCoach &&
                              (query.isEmpty ||
                                  username.contains(query) ||
                                  email.contains(query));
                        }).toList();

                        if (users.isEmpty) {
                          return const Center(child: Text('No users found.'));
                        }

                        return ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final userDoc = users[index];
                            final data = userDoc.data();
                            final assignedCoachId = data['coachId'] as String?;
                            final assignedToMe = assignedCoachId == currentUserId;
                            final assignedElsewhere = assignedCoachId != null &&
                                assignedCoachId.isNotEmpty &&
                                !assignedToMe;

                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  ((data['username'] as String?)?.isNotEmpty ?? false)
                                      ? (data['username'] as String)[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(data['username'] ?? 'Unknown User'),
                              subtitle: Text(data['email'] ?? ''),
                              trailing: assignedToMe
                                  ? TextButton(
                                      onPressed: () => onRemoveMentee(userDoc.id),
                                      child: const Text('Remove'),
                                    )
                                  : ElevatedButton(
                                      onPressed: assignedElsewhere
                                          ? null
                                          : () async {
                                              await onAssignMentee(
                                                menteeId: userDoc.id,
                                                teamName: teamName,
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '${data['username']} added to your team',
                                                  ),
                                                ),
                                              );
                                            },
                                      child: Text(
                                        assignedElsewhere ? 'Assigned' : 'Add',
                                      ),
                                    ),
                            );
                          },
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
  }

  void _openChatWithMentee(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> mentee,
  ) {
    final data = mentee.data();
    final menteeName = (data['username'] as String?)?.trim();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          coach: Coach(
            id: mentee.id,
            name: menteeName?.isNotEmpty == true ? menteeName! : 'Mentee',
            phone: '',
            bio: data['email'] as String? ?? '',
            profilePic: data['profilePic'] as String? ?? '',
            backgroundColor: const Color(0xFF90A17D),
          ),
          userId: currentUserId,
          userName: currentUserName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage mentees'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => _showAddMenteeSheet(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: menteesStream,
        builder: (context, snapshot) {
          final mentees = snapshot.data?.docs ?? [];
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (mentees.isEmpty) {
            return const Center(child: Text('No mentees added yet.'));
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: firestore.collection('userpoints').snapshots(),
            builder: (context, pointsSnapshot) {
              final pointDocs = pointsSnapshot.data?.docs ?? [];
              final leaderboard = _buildLeaderboardData(mentees, pointDocs);
              final sortedMentees = mentees.toList()
                ..sort((a, b) {
                  final aRank = leaderboard[a.id]?.rank ?? 9999;
                  final bRank = leaderboard[b.id]?.rank ?? 9999;
                  return aRank.compareTo(bRank);
                });

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: sortedMentees.length,
                itemBuilder: (context, index) {
                  final mentee = sortedMentees[index];
                  final data = mentee.data();
                  final leaderboardData = leaderboard[mentee.id] ??
                      _MenteeLeaderboardData(
                        rank: index + 1,
                        score: 0,
                      );
                  final badgeColor = _badgeColorForRank(leaderboardData.rank);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          badgeColor.withOpacity(0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: badgeColor.withOpacity(0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withOpacity(0.10),
                          blurRadius: 20,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: badgeColor.withOpacity(0.45),
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 28,
                                    backgroundColor: badgeColor.withOpacity(0.16),
                                    backgroundImage: (data['profilePic'] as String?)
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? NetworkImage(data['profilePic'] as String)
                                        : null,
                                    child:
                                        ((data['profilePic'] as String?)?.trim().isEmpty ??
                                                true)
                                            ? Text(
                                                ((data['username'] as String?)
                                                            ?.isNotEmpty ??
                                                        false)
                                                    ? (data['username'] as String)[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              )
                                            : null,
                                  ),
                                ),
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor,
                                      borderRadius: BorderRadius.circular(999),
                                      boxShadow: [
                                        BoxShadow(
                                          color: badgeColor.withOpacity(0.35),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      '#${leaderboardData.rank}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        data['username'] ?? 'Unknown',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _badgeLabelForRank(leaderboardData.rank),
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
                                    data['email'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF6F2EA),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          '${leaderboardData.score} pts',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF2D3A25),
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
                                onPressed: () => _openChatWithMentee(
                                  context,
                                  mentee,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF90A17D),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
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
                                onPressed: () => onRemoveMentee(mentee.id),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFB55D5D),
                                  side: BorderSide(
                                    color: const Color(0xFFB55D5D).withOpacity(0.28),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: const Icon(
                                  CupertinoIcons.person_crop_circle_badge_xmark,
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
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MenteeLeaderboardData {
  const _MenteeLeaderboardData({
    required this.rank,
    required this.score,
  });

  final int rank;
  final int score;
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
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
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
    final tasks = tracker == null ? <String, bool>{} : _activityMap(tracker);
    if (tracker == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F4EE),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'No logged activity for this day.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
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
                  ? const Color(0xFFDDE7D5)
                  : const Color(0xFFF0E5D3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${entry.key}: ${entry.value ? 'Done' : 'Not yet'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenteeCalendarCard(
    QueryDocumentSnapshot<Map<String, dynamic>> mentee,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> trackerDocs,
  ) {
    return _CoachMenteeCalendarCard(
      key: ValueKey(mentee.id),
      mentee: mentee,
      trackerDocs: trackerDocs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent mentee activity')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.menteesStream,
        builder: (context, menteeSnapshot) {
          if (menteeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final mentees = menteeSnapshot.data?.docs ?? [];
          if (mentees.isEmpty) {
            return const Center(
              child: Text('No mentees added yet.'),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.firestore.collection('dailytracker').snapshots(),
            builder: (context, trackerSnapshot) {
              if (trackerSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final trackerDocs = trackerSnapshot.data?.docs ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: mentees.length,
                itemBuilder: (context, index) {
                  final mentee = mentees[index];
                  final menteeTrackers = trackerDocs.where(
                    (doc) => (doc.data()['userId'] as String?) == mentee.id,
                  ).toList();
                  return _buildMenteeCalendarCard(mentee, menteeTrackers);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CoachMenteeCalendarCard extends StatefulWidget {
  const _CoachMenteeCalendarCard({
    super.key,
    required this.mentee,
    required this.trackerDocs,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> mentee;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> trackerDocs;

  @override
  State<_CoachMenteeCalendarCard> createState() =>
      _CoachMenteeCalendarCardState();
}

class _CoachMenteeCalendarCardState extends State<_CoachMenteeCalendarCard> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final today = _normalizeDate(DateTime.now());
    _focusedDay = today;
    _selectedDay = today;
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

  Map<DateTime, Map<String, dynamic>> _buildTrackerMap() {
    final trackers = <DateTime, Map<String, dynamic>>{};
    for (final doc in widget.trackerDocs) {
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

  Color _calendarColorForCount(int count) {
    if (count >= 5) return const Color(0xFF90A17D);
    if (count >= 3) return const Color(0xFFCFE1D0);
    if (count >= 1) return const Color(0xFFF5E3C8);
    return Colors.transparent;
  }

  Widget _buildActivityLegend() {
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
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _buildActivityDetails(Map<String, dynamic>? tracker) {
    final tasks = tracker == null ? <String, bool>{} : _activityMap(tracker);
    if (tracker == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F4EE),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'No logged activity for this day.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
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
                  ? const Color(0xFFDDE7D5)
                  : const Color(0xFFF0E5D3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${entry.key}: ${entry.value ? 'Done' : 'Not yet'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.mentee.data();
    final menteeName = (data['username'] as String?)?.trim();
    final profilePic = (data['profilePic'] as String?)?.trim() ?? '';
    final trackerMap = _buildTrackerMap();
    final selectedTracker = trackerMap[_normalizeDate(_selectedDay)];
    final latestEntry = trackerMap.entries.isEmpty
        ? null
        : (trackerMap.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key))).first;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              CircleAvatar(
                radius: 24,
                backgroundImage:
                    profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                child: profilePic.isEmpty
                    ? Text(
                        menteeName?.isNotEmpty == true
                            ? menteeName![0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      menteeName?.isNotEmpty == true ? menteeName! : 'Mentee',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latestEntry == null
                          ? 'No recent activity yet'
                          : 'Latest activity: ${DateFormat.yMMMd().format(latestEntry.key)}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                color: const Color(0xFFCE8F5A).withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Color(0xFF6D849A),
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
                      color: count >= 5 ? Colors.white : Colors.black87,
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
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
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
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          _buildActivityDetails(selectedTracker),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F2EB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
