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

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  String quote = "Your daily inspiration...";
  String author = "Unknown";
  String? selectedEmotion;
  String? currentUserEmotion;
  String? _profilePic;
  final Map<String, DateTime> _localChatReadOverrides = <String, DateTime>{};
  final Set<String> _pressedTiles = <String>{};
  final GlobalKey _dashboardStackKey = GlobalKey();
  late final AnimationController _introController;
  late final AnimationController _tileTransitionController;
  _DashboardTileTransition? _activeTileTransition;

  String get _todayDate => DateTime.now().toString().split(' ')[0];

  String _getEmojiForEmotion(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😡';
      case 'neutral':
        return '😐';
      default:
        return '❓';
    }
  }

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..forward();
    _tileTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
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
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
        color: Color(0xFF24311F),
      ),
    );
  }

  Widget _buildIntroMotion({
    required Widget child,
    required double start,
    required double end,
    double yOffset = 0.04,
  }) {
    final animation = CurvedAnimation(
      parent: _introController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final value = animation.value;
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 36 * yOffset * 4),
            child: child,
          ),
        );
      },
    );
  }

  Future<Coach?> _loadAssignedCoach(String coachId) async {
    final firestore = FirebaseFirestore.instance;

    final coachDoc = await firestore.collection('coaches').doc(coachId).get();
    if (coachDoc.exists) {
      final data = coachDoc.data() ?? <String, dynamic>{};
      return Coach(
        id: coachDoc.id,
        name: (data['fullName'] as String?)?.trim().isNotEmpty == true
            ? (data['fullName'] as String).trim()
            : ((data['username'] as String?)?.trim().isNotEmpty == true
                ? (data['username'] as String).trim()
                : 'My Coach'),
        phone: (data['phone'] as String?)?.trim().isNotEmpty == true
            ? (data['phone'] as String).trim()
            : ((data['phonenumber'] as String?)?.trim() ?? ''),
        bio: (data['bio'] as String?)?.trim() ?? 'Your support coach',
        profilePic: (data['profilePic'] as String?)?.trim() ?? '',
        backgroundColor: const Color(0xFFDCE5D4),
      );
    }

    final userDoc = await firestore.collection('users').doc(coachId).get();
    final userData = userDoc.data();
    if (userData == null) return null;

    final role = (userData['role'] as String?)?.toLowerCase().trim();
    final isCoach = userData['isCoach'] == true || role == 'coach';
    if (!isCoach) return null;

    return Coach(
      id: userDoc.id,
      name: (userData['fullName'] as String?)?.trim().isNotEmpty == true
          ? (userData['fullName'] as String).trim()
          : ((userData['username'] as String?)?.trim().isNotEmpty == true
              ? (userData['username'] as String).trim()
              : 'My Coach'),
      phone: (userData['phone'] as String?)?.trim().isNotEmpty == true
          ? (userData['phone'] as String).trim()
          : ((userData['phonenumber'] as String?)?.trim() ?? ''),
      bio: (userData['bio'] as String?)?.trim() ?? 'Your support coach',
      profilePic: (userData['profilePic'] as String?)?.trim() ?? '',
      backgroundColor: const Color(0xFFDCE5D4),
    );
  }

  Widget _buildBackdropOrb({
    required double size,
    required List<Color> colors,
  }) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: colors,
          ),
        ),
      ),
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
            Color.alphaBlend(
              const Color(0x40FFFFFF),
              color,
            ),
          ],
        ),
        image: backgroundImage != null
            ? DecorationImage(
                image: AssetImage(backgroundImage),
                fit: BoxFit.cover,
                opacity: 0.3,
              )
            : null,
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
                    "Daily practice",
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
                      "Open",
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
      _activeTileTransition = _DashboardTileTransition(
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

    final targetPage =
        setupIndex != null ? Setuppage(initialIndex: setupIndex) : destinationPage;

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
              ? (1 - Curves.easeInCubic.transform(scatterT)).clamp(0.0, 1.0)
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
      (ax: -0.34, ay: -0.22, size: 26.0, radius: 10.0, dx: -120.0, dy: -88.0, rot: -0.9),
      (ax: 0.28, ay: -0.18, size: 20.0, radius: 8.0, dx: 128.0, dy: -96.0, rot: 1.1),
      (ax: -0.18, ay: 0.08, size: 22.0, radius: 9.0, dx: -96.0, dy: 24.0, rot: 0.8),
      (ax: 0.16, ay: 0.16, size: 18.0, radius: 8.0, dx: 90.0, dy: 46.0, rot: -1.2),
      (ax: -0.04, ay: 0.26, size: 24.0, radius: 10.0, dx: -18.0, dy: 136.0, rot: 1.0),
      (ax: 0.34, ay: 0.02, size: 16.0, radius: 7.0, dx: 144.0, dy: 8.0, rot: 1.4),
    ];

    final eased = Curves.easeOutCubic.transform(progress);
    final fade = (1 - Curves.easeInQuad.transform(progress))
        .clamp(0.0, 1.0)
        .toDouble();
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

  @override
  void dispose() {
    _introController.dispose();
    _tileTransitionController.dispose();
    super.dispose();
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
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth > 600 ? 28.0 : 20.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F1),
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
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.76),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E2D6)),
              ),
              child: IconButton(
                icon: const Icon(CupertinoIcons.line_horizontal_3, size: 24),
                color: const Color(0xFF42523B),
                onPressed: () => BottomSheetWidget.show(context),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        key: _dashboardStackKey,
        children: [
          Positioned(
            top: -56,
            right: -36,
            child: _buildBackdropOrb(
              size: 220,
              colors: [
                const Color(0xFFFFF4E7).withOpacity(0.95),
                const Color(0xFFFFF4E7).withOpacity(0),
              ],
            ),
          ),
          Positioned(
            top: 180,
            left: -70,
            child: _buildBackdropOrb(
              size: 240,
              colors: [
                const Color(0xFFDDEBDD).withOpacity(0.82),
                const Color(0xFFDDEBDD).withOpacity(0),
              ],
            ),
          ),
          Positioned(
            bottom: 80,
            right: -58,
            child: _buildBackdropOrb(
              size: 190,
              colors: [
                const Color(0xFFE9E1F2).withOpacity(0.48),
                const Color(0xFFE9E1F2).withOpacity(0),
              ],
            ),
          ),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIntroMotion(
                  start: 0.0,
                  end: 0.42,
                  child: FutureBuilder<String>(
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
                ),
                const SizedBox(height: 24),
                _buildIntroMotion(
                  start: 0.1,
                  end: 0.42,
                  child: _buildQuickOverviewSection(),
                ),
                const SizedBox(height: 28),
                _buildIntroMotion(
                  start: 0.18,
                  end: 0.62,
                  child: _buildScrollableFeatureRail(context),
                ),
                const SizedBox(height: 28),
                _buildIntroMotion(
                  start: 0.28,
                  end: 0.74,
                  child: _buildDailyInsightsSection(),
                ),
                const SizedBox(height: 28),
                _buildIntroMotion(
                  start: 0.36,
                  end: 0.82,
                  child: _buildCoachSection(context),
                ),
                const SizedBox(height: 28),
                _buildIntroMotion(
                  start: 0.48,
                  end: 1.0,
                  child: _buildMoodSection(context),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _buildTileTransitionOverlay(),
          if (selectedEmotion != null) Positioned.fill(child: _buildMoodEffectsOverlay(selectedEmotion!)),
        ],
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white.withOpacity(0.38)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF9CB58F),
            Color(0xFFC9B395),
            Color(0xFFF2E4D0),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF90A783).withOpacity(0.28),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Text(
                      "Daily reset",
                      style: TextStyle(
                        color: Color(0xFF355033),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Hello, $username",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF24311F),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Your dashboard is ready with the habits that keep today balanced.",
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF42563E),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildHeroStatChip(
                      icon: CupertinoIcons.heart_fill,
                      label: currentUserEmotion == null ? "Mood check" : "Mood logged",
                      value: currentUserEmotion == null ? "Pending" : currentUserEmotion!,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHeroStatChip(
                      icon: CupertinoIcons.sparkles,
                      label: "Focus",
                      value: "5 routines",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.34),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white.withOpacity(0.42)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          CupertinoIcons.quote_bubble_fill,
                          size: 18,
                          color: Color(0xFF4F6047),
                        ),
                        SizedBox(width: 8),
                        Text(
                          "Today's note",
                          style: TextStyle(
                            color: Color(0xFF4F6047),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      quote,
                      style: const TextStyle(
                        color: Color(0xFF24311F),
                        fontSize: 16,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      author,
                      style: const TextStyle(
                        color: Color(0xFF61715B),
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

  Widget _buildHeroStatChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.24),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF42563E), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF52644D),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF24311F),
                    fontSize: 15,
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

  Widget _buildSectionHeader(
    String title, {
    required String subtitle,
    String? actionLabel,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(title),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF5E6E57),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: Color(0xFF708467),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.74)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.92),
            const Color(0xFFF6F1E8).withOpacity(0.88),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD0D8C8).withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildQuickOverviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Overview",
          subtitle: "A quick scan of what matters most today.",
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMiniOverviewCard(
                icon: CupertinoIcons.heart_fill,
                title: "Mood",
                value: currentUserEmotion == null ? "Check in" : "${_getEmojiForEmotion(currentUserEmotion!)} $currentUserEmotion",
                accent: const Color(0xFFE8DCC9),
                onTap: () => Navigator.pushNamed(context, '/emotionScreen'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMiniOverviewCard(
                icon: CupertinoIcons.chat_bubble_2_fill,
                title: "Support",
                value: "Coach ready",
                accent: const Color(0xFFDCE6D6),
                onTap: () => Navigator.pushNamed(context, '/coachesScreen'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniOverviewCard({
    required IconData icon,
    required String title,
    required String value,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.82),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.84)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.26),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: const Color(0xFF4A5E45), size: 21),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF65745E),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF24311F),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
    Widget destinationPage,
    {int? setupIndex, String? backgroundImage,}
  ) {
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
        _buildSectionHeader(
          "Today's focus",
          subtitle: "Scroll through the routines that keep your day steady.",
          actionLabel: "Swipe",
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
                "Steps",
                "Track your movement and keep your body active.",
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
                "Meditate",
                "Create a calm reset with a short guided session.",
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
                "Fasting",
                "Stay on your plan and watch the timer clearly.",
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
                "Calories",
                "Log meals and stay aware of your intake.",
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
                "Sleep",
                "Protect your recovery and spot your rest patterns.",
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

  Widget _buildDailyInsightsSection() {
    final moodTitle = currentUserEmotion == null ? "Mood check-in" : "Mood is logged";
    final moodText = currentUserEmotion == null
        ? "Take a quick moment to label how you feel. It helps make the rest of your tracking more meaningful."
        : "You marked yourself as $currentUserEmotion today. Keep the rest of your habits light and realistic.";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Wellness cues",
          subtitle: "Small, accurate reminders that fit a balanced day.",
        ),
        const SizedBox(height: 16),
        _buildGlassSectionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _buildInsightRow(
                icon: CupertinoIcons.drop_fill,
                title: "Hydrate early",
                description: "A glass of water after waking is a simple way to support energy and focus.",
                color: const Color(0xFFDDEAF3),
              ),
              const SizedBox(height: 14),
              _buildInsightRow(
                icon: CupertinoIcons.person,
                title: "Move in short bursts",
                description: "Short walks and regular movement breaks are easier to sustain than waiting for one perfect workout.",
                color: const Color(0xFFDDE7D5),
              ),
              const SizedBox(height: 14),
              _buildInsightRow(
                icon: CupertinoIcons.heart_fill,
                title: moodTitle,
                description: moodText,
                color: const Color(0xFFF0E1D0),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsightRow({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: const Color(0xFF4B5D45), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF24311F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF5E6E57),
                  height: 1.45,
                ),
              ),
            ],
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'My Coach',
              subtitle: 'Support that feels close and easy to reach.',
            ),
            const SizedBox(height: 14),
            if (coachId.isEmpty)
              _buildNoCoachCard()
            else
              FutureBuilder<Coach?>(
                future: _loadAssignedCoach(coachId),
                builder: (context, coachSnapshot) {
                  if (coachSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final coach = coachSnapshot.data;
                  if (coach == null) {
                    return _buildNoCoachCard(
                      title: 'Coach details unavailable',
                      message:
                          'Your coach is assigned, but the profile details could not be loaded yet.',
                    );
                  }

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

  Widget _buildNoCoachCard({
    String title = 'No coach yet',
    String message = 'You do not have a coach assigned yet. Once you connect with one, they will appear here.',
  }) {
    return _buildGlassSectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEE4),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              CupertinoIcons.person_crop_circle_badge_plus,
              color: Color(0xFF6C7E62),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF24311F),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF667460),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedCoachCard(
    BuildContext context, {
    required Coach coach,
  }) {
    return _buildGlassSectionCard(
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
                        color: Color(0xFF24311F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coach.bio.isEmpty ? 'Your support coach' : coach.bio,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF667460),
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
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF52624A),
                    side: BorderSide(
                      color: const Color(0xFFD8D4C9).withOpacity(0.92),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
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
                    elevation: 0,
                    backgroundColor: const Color(0xFF7E9471),
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
        _buildSectionHeader(
          "Mood check-in",
          subtitle: "Keep track of how today feels, not just what you finish.",
        ),
        const SizedBox(height: 14),
        _buildGlassSectionCard(
          child: currentUserEmotion == null
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
                            child: _buildMoodChoice(
                              icon: CupertinoIcons.smiley_fill,
                              label: "Happy",
                              color: const Color(0xFFF5DEB0),
                              onTap: () => selectEmotion("happy"),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: _buildMoodChoice(
                              icon: CupertinoIcons.minus_circle_fill,
                              label: "Neutral",
                              color: const Color(0xFFE6E4DE),
                              onTap: () => selectEmotion("neutral"),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: _buildMoodChoice(
                              icon: CupertinoIcons.cloud_rain_fill,
                              label: "Sad",
                              color: const Color(0xFFDCE6F3),
                              onTap: () => selectEmotion("sad"),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: _buildMoodChoice(
                              icon: CupertinoIcons.flame_fill,
                              label: "Angry",
                              color: const Color(0xFFF2D2C6),
                              onTap: () => selectEmotion("angry"),
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
                            "Today you're feeling $currentUserEmotion",
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

  Widget _buildMoodChoice({
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
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/rain.jpg'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'angry':
        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/night_firepit.jpg'),
              fit: BoxFit.cover,
              opacity: 0.3,
            ),
          ),
        );
      case 'neutral':
        return Container(
          decoration: BoxDecoration(
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
        return 'Keep the joy going — continue being happy every day and spread positivity to others.';
      case 'sad':
        return 'It’s okay to feel sad. Take a deep breath, be kind to yourself, and let this moment pass.';
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

}

class _DashboardTileTransition {
  const _DashboardTileTransition({
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
