import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String quote = "Your daily inspiration...";
  String author = "Unknown";
  String? selectedEmotion;
  String? currentUserEmotion;
  String? _profilePic;
  final Map<String, DateTime> _localChatReadOverrides = <String, DateTime>{};

  String get _todayDate => DateTime.now().toString().split(' ')[0];

  @override
  void initState() {
    super.initState();
    _fetchProfilePic();
    fetchQuote();
    _loadTodayEmotion();
    _loadLocalChatReadOverrides();
  }

  Future<void> _loadLocalChatReadOverrides() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    final overrides = <String, DateTime>{};
    final prefix = 'chat_read_override_${currentUser.uid}_';
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

  Future<void> _fetchProfilePic() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final rawProfilePic = userDoc["profilePic"];
        final cleanedUrl = rawProfilePic is String ? rawProfilePic.trim() : "";
        setState(() {
          _profilePic = cleanedUrl.isEmpty ? null : cleanedUrl;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile picture: $e");
    }
  }

  Future<void> selectEmotion(String emotion) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final username = await _getUsername();

    setState(() {
      selectedEmotion = emotion;
      currentUserEmotion = emotion;
    });

    await _saveEmotionToDatabase(context, emotion, username);
    await _saveEmotionToSharedPreferences(emotion);
  }

  Future<void> _saveEmotionToSharedPreferences(String emotion) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await prefs.setString('selected_emotion_${user.uid}', emotion);
    await prefs.setString(
      'emotion_date_${user.uid}',
      DateTime.now().toString().split(' ')[0],
    );
  }

  Future<void> _loadTodayEmotion() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final savedEmotion = prefs.getString('selected_emotion_${user.uid}');
    final savedDate = prefs.getString('emotion_date_${user.uid}');
    final today = DateTime.now().toString().split(' ')[0];

    setState(() {
      currentUserEmotion = savedDate == today ? savedEmotion : null;
    });
  }

  Future<void> _clearEmotionOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await prefs.remove('selected_emotion_${user.uid}');
    await prefs.remove('emotion_date_${user.uid}');

    setState(() {
      currentUserEmotion = null;
    });
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

  Future<String> _getUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "User";

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    if (userDoc.exists && userDoc["username"] != null) {
      return userDoc["username"];
    } else if (user.email != null) {
      return user.email!.split('@')[0];
    }

    return "User";
  }

  Future<void> fetchQuote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedQuote = prefs.getString('quote');
      final savedAuthor = prefs.getString('author');
      final savedDate = prefs.getString('quote_date');
      final today = DateTime.now().toString().split(' ')[0];

      if (savedQuote != null && savedAuthor != null && savedDate == today) {
        setState(() {
          quote = savedQuote;
          author = savedAuthor;
        });
        return;
      }

      final response = await http.get(Uri.parse("https://zenquotes.io/api/random"));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final newQuote = data[0]['q'] ?? "No quote available.";
        final newAuthor = data[0]['a'] ?? "Unknown";

        setState(() {
          quote = newQuote;
          author = newAuthor;
        });

        await prefs.setString('quote', newQuote);
        await prefs.setString('author', newAuthor);
        await prefs.setString('quote_date', today);
      } else {
        setState(() {
          quote = "Failed to load quote.";
          author = "Unknown";
        });
      }
    } catch (e) {
      debugPrint("Error fetching quote: $e");
      setState(() {
        quote = "Failed to load quote.";
        author = "Unknown";
      });
    }
  }

  Future<void> _saveEmotionToDatabase(
    BuildContext context,
    String emotion,
    String username,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now().toString().split(' ')[0];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection("emotions")
          .where("userId", isEqualTo: user.uid)
          .where("username", isEqualTo: username)
          .where("date", isEqualTo: today)
          .get();

      if (snapshot.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You can only select one emotion per day!"),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance.collection("emotions").add({
        "userId": user.uid,
        "username": username.isNotEmpty ? username : "Unknown",
        "emotion": emotion,
        "date": today,
      });

      if (mounted) {
        setState(() {
          selectedEmotion = emotion;
        });
      }
    } catch (e) {
      debugPrint("Error saving emotion: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to save emotion. Please try again."),
        ),
      );
    }
  }

  Future<void> _openCoachChat({
    required BuildContext context,
    required Coach coach,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final username = await _getUsername();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomScreen(
          coach: coach,
          userId: currentUser.uid,
          userName: username,
        ),
      ),
    );
  }

  Widget _buildInboxAction() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chatRooms')
          .where('participants', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        var unreadCount = 0;
        for (final doc in snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
          final chatData = doc.data();
          final localReadTime = _localChatReadOverrides[doc.id];
          final lastMessageTimeRaw = chatData['lastMessageTime'];
          final lastMessageTime = lastMessageTimeRaw is Timestamp
              ? lastMessageTimeRaw.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final lastReadAt = Map<String, dynamic>.from(
            chatData['lastReadAt'] as Map? ?? <String, dynamic>{},
          );
          final lastReadAtRaw = lastReadAt[currentUser.uid];
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
          if (unreadCounts.containsKey(currentUser.uid)) {
            final rawValue = unreadCounts[currentUser.uid];
            if (rawValue is int) {
              unreadCount += rawValue;
            } else if (rawValue is num) {
              unreadCount += rawValue.toInt();
            }
          } else {
            final lastSenderId = (chatData['lastSenderId'] as String?)?.trim() ?? '';
            if (lastSenderId.isNotEmpty &&
                lastSenderId != currentUser.uid &&
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
                final username = await _getUsername();
                if (!context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatListScreen(
                      userId: currentUser.uid,
                      userName: username,
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

  Widget _buildProfileAndPoints(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('userpoints')
          .doc('${currentUser.uid}-$_todayDate')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final rawPoints = data?['totalPoints'];
        final totalPoints = rawPoints is int
            ? rawPoints
            : rawPoints is num
                ? rawPoints.toInt()
                : 0;

        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => Navigator.pushNamed(context, '/profile'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFDCE5D4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                (_profilePic == null || _profilePic!.trim().isEmpty)
                    ? Image.asset(
                        'assets/images/avatar.png',
                        width: 28,
                        height: 28,
                      )
                    : ClipOval(
                        child: Image.network(
                          _profilePic!,
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.person, size: 24);
                          },
                        ),
                      ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF3E8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.star_fill,
                        size: 13,
                        color: Color(0xFFCE8F5A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$totalPoints',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D3A25),
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
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth > 600 ? 28.0 : 20.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F2),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 126,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: _buildProfileAndPoints(context),
        ),
        actions: [
          _buildInboxAction(),
          IconButton(
            icon: const Icon(CupertinoIcons.line_horizontal_3, size: 28),
            onPressed: () => BottomSheetWidget.show(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: _getUsername(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  UserPreferences.saveUsername(snapshot.data!);
                }

                final username = snapshot.connectionState == ConnectionState.waiting
                    ? "there"
                    : snapshot.data ?? "there";

                return _buildWelcomeHero(
                  context,
                  username: username,
                  quote: quote,
                  author: author,
                );
              },
            ),
            const SizedBox(height: 22),
            _buildSectionTitle("Today's focus"),
            const SizedBox(height: 6),
            Text(
              "Small actions, steady progress.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            _buildActionRows(context),
            const SizedBox(height: 28),
            _buildCoachSection(context),
            _buildMoodSection(context),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHero(
    BuildContext context, {
    required String username,
    required String quote,
    required String author,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF90A17D),
            Color(0xFFE6D1A9),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF90A17D).withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -18,
            right: -10,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -34,
            left: -18,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  "Daily reset",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Hello, $username",
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Make today feel lighter with one mindful habit at a time.",
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.88),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
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
                          "Today's note",
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClickableInfoCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
    String imagePath,
    Widget destinationPage,
    {int? setupIndex,}
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = ((screenWidth - 54) / 2).clamp(150.0, 220.0);

    return SizedBox(
      width: cardWidth,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => setupIndex != null
                  ? Setuppage(initialIndex: setupIndex)
                  : destinationPage,
            ),
          );
        },
        child: Container(
          height: 196,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
            image: DecorationImage(
              image: AssetImage(imagePath),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.12),
                        Colors.black.withOpacity(0.08),
                        Colors.black.withOpacity(0.34),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: const Color(0xFF2D3A25), size: 18),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        "Wellness",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white.withOpacity(0.82),
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

  Widget _buildActionRows(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildClickableInfoCard(
              context,
              "Steps",
              "Track your movement",
              CupertinoIcons.flame_fill,
              const Color(0xFFDDE7D5),
              "assets/images/steps.gif",
              StepTracker(),
              setupIndex: 1,
            ),
            const SizedBox(width: 14),
            _buildClickableInfoCard(
              context,
              "Meditate",
              "Clear your mind",
              CupertinoIcons.sparkles,
              const Color(0xFFE8E3D8),
              "assets/images/meditation.gif",
              Meditation(),
              setupIndex: 0,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildClickableInfoCard(
              context,
              "Fasting",
              "Stay on your plan",
              CupertinoIcons.timer_fill,
              const Color(0xFFF2E5D2),
              "assets/images/fasting.gif",
              const FastingTimerScreen(),
            ),
            const SizedBox(width: 14),
            _buildClickableInfoCard(
              context,
              "Calories",
              "Log what you eat",
              CupertinoIcons.leaf_arrow_circlepath,
              const Color(0xFFE1EDDF),
              "assets/images/calories1.gif",
              const CalorieTrackerScreen(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: _buildClickableInfoCard(
            context,
            "Sleep",
            "Protect your rest",
            CupertinoIcons.moon_zzz_fill,
            const Color(0xFFDDE4F0),
            "assets/images/sleep.gif",
            const SleepTracker(),
          ),
        ),
      ],
    );
  }

  Widget _buildCoachSection(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = userSnapshot.data?.data();
        final coachId = (userData?['coachId'] as String?)?.trim() ?? '';
        if (coachId.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Coach',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(thickness: 1, height: 12),
            const SizedBox(height: 8),
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('coaches')
                  .doc(coachId)
                  .get(),
              builder: (context, coachSnapshot) {
                if (coachSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!coachSnapshot.hasData || !coachSnapshot.data!.exists) {
                  return const SizedBox.shrink();
                }

                final coachData = coachSnapshot.data!.data()!;
                final coach = Coach(
                  id: coachSnapshot.data!.id,
                  name: (coachData['fullName'] as String?)?.trim().isNotEmpty ==
                          true
                      ? (coachData['fullName'] as String).trim()
                      : 'My Coach',
                  phone: (coachData['phone'] as String?)?.trim() ?? '',
                  bio: (coachData['bio'] as String?)?.trim() ?? 'Your support coach',
                  profilePic: (coachData['profilePic'] as String?)?.trim() ?? '',
                  backgroundColor: const Color(0xFFDCE5D4),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAssignedCoachCard(context, coach: coach),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAssignedCoachCard(
    BuildContext context, {
    required Coach coach,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFFDCE5D4),
                backgroundImage: coach.profilePic.isNotEmpty
                    ? NetworkImage(coach.profilePic)
                    : null,
                child: coach.profilePic.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 30)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coach.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coach.bio.isEmpty ? 'Your support coach' : coach.bio,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.black54,
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
                  onPressed: () => _openCoachChat(context: context, coach: coach),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF90A17D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoodSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("How do you feel today?"),
        const SizedBox(height: 10),
        currentUserEmotion == null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildEmojiMood(
                    emoji: "😀",
                    onTap: () => selectEmotion("happy"),
                  ),
                  _buildEmojiMood(
                    emoji: "😐",
                    onTap: () => selectEmotion("neutral"),
                  ),
                  _buildEmojiMood(
                    emoji: "😔",
                    onTap: () => selectEmotion("sad"),
                  ),
                  _buildEmojiMood(
                    emoji: "😡",
                    onTap: () => selectEmotion("angry"),
                  ),
                ],
              )
            : Column(
                children: [
                  Text(
                    "Today I'm feeling $currentUserEmotion",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                          "Track Your Emotions",
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
      ],
    );
  }

  Widget _buildEmojiMood({
    required String emoji,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 36),
        ),
      ),
    );
  }
}
