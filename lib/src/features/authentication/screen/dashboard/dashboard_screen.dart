import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/calorie_tracker_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchProfilePic();
    fetchQuote();
    _loadTodayEmotion();
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

  Future<String?> getRandomCoachId() async {
    final prefs = await SharedPreferences.getInstance();
    final storedCoachId = prefs.getString('random_coach_id');
    final storedDate = prefs.getString('random_coach_date');
    final today = DateTime.now().toIso8601String().split('T')[0];

    if (storedCoachId != null && storedDate == today) {
      return storedCoachId;
    }

    final snapshot = await FirebaseFirestore.instance.collection('coaches').get();
    if (snapshot.docs.isEmpty) return null;

    final randomCoach = snapshot.docs[Random().nextInt(snapshot.docs.length)];
    await prefs.setString('random_coach_id', randomCoach.id);
    await prefs.setString('random_coach_date', today);

    return randomCoach.id;
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
        leading: IconButton(
          icon: (_profilePic == null || _profilePic!.trim().isEmpty)
              ? Image.asset(
                  'assets/images/avatar.png',
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                )
              : ClipOval(
                  child: Image.network(
                    _profilePic!,
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
            const SizedBox(height: 24),
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
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = ((screenWidth - 54) / 2).clamp(150.0, 220.0);

    return SizedBox(
      width: cardWidth,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => destinationPage),
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
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Today's Coach",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(
                thickness: 1,
                height: 5,
                indent: 0,
                endIndent: 0,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CoachesScreen(),
                    ),
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "SEE ALL",
                      style: TextStyle(
                        fontWeight: FontWeight.w200,
                        fontSize: 13,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 15,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: FutureBuilder<String?>(
            future: getRandomCoachId(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data == null) {
                return const Center(child: Text("No coach available"));
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('coaches')
                    .doc(snapshot.data)
                    .get(),
                builder: (context, coachSnapshot) {
                  if (coachSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!coachSnapshot.hasData || !coachSnapshot.data!.exists) {
                    return const Center(child: Text("No coach available"));
                  }

                  final data =
                      coachSnapshot.data!.data() as Map<String, dynamic>;
                  final coachName = data['fullName'] ?? 'Unknown Coach';
                  final coachTitle = data['bio'] ?? 'Unknown Title';
                  final profilePic = data['profilePic'] ?? '';

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        margin: const EdgeInsets.all(8.0),
                        constraints: const BoxConstraints(minWidth: 290),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: const Color(0xFFDCE5D4),
                              backgroundImage: profilePic.toString().isNotEmpty
                                  ? NetworkImage(profilePic)
                                  : null,
                              child: profilePic.toString().isEmpty
                                  ? const Icon(Icons.person, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    coachName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    coachTitle,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Positioned(
                        top: -5,
                        left: -3,
                        child: Icon(
                          Icons.star,
                          size: 24,
                          color: Colors.lightBlue,
                        ),
                      ),
                      const Positioned(
                        bottom: -3,
                        right: -3,
                        child: Icon(
                          Icons.star,
                          size: 24,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
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
