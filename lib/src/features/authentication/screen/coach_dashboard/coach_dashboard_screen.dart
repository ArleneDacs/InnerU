import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key});

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isSavingProfile = false;
  String? _currentUserEmotion;

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
    _loadTodayEmotion();
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
    await _saveEmotionToDatabase(context, emotion, username);
    await _saveEmotionToSharedPreferences(emotion);

    if (!mounted) return;
    setState(() {
      _currentUserEmotion = emotion;
    });
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

                  return SingleChildScrollView(
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
                        ),
                        const SizedBox(height: 22),
                        _buildSectionTitle("Today's focus"),
                        const SizedBox(height: 6),
                        Text(
                          'Lead by example and keep your habits visible.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.black54,
                              ),
                        ),
                        const SizedBox(height: 16),
                        _buildActionRows(context),
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
                        _buildMoodSection(context),
                      ],
                    ),
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
                        'Wellness',
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
              'Steps',
              'Track your movement',
              CupertinoIcons.flame_fill,
              const Color(0xFFDDE7D5),
              'assets/images/steps.gif',
              StepTracker(),
            ),
            const SizedBox(width: 14),
            _buildClickableInfoCard(
              context,
              'Meditate',
              'Clear your mind',
              CupertinoIcons.sparkles,
              const Color(0xFFE8E3D8),
              'assets/images/meditation.gif',
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
              'Fasting',
              'Stay on your plan',
              CupertinoIcons.timer_fill,
              const Color(0xFFF2E5D2),
              'assets/images/fasting.gif',
              const FastingTimerScreen(),
            ),
            const SizedBox(width: 14),
            _buildClickableInfoCard(
              context,
              'Calories',
              'Log what you eat',
              CupertinoIcons.leaf_arrow_circlepath,
              const Color(0xFFE1EDDF),
              'assets/images/calories1.gif',
              const CalorieTrackerScreen(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: _buildClickableInfoCard(
            context,
            'Sleep',
            'Protect your rest',
            CupertinoIcons.moon_zzz_fill,
            const Color(0xFFDDE4F0),
            'assets/images/sleep.gif',
            const SleepTracker(),
          ),
        ),
      ],
    );
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
          title: 'Team overview',
          subtitle: 'Open a dedicated page for team details and coach profile.',
          icon: CupertinoIcons.square_grid_2x2_fill,
          color: const Color(0xFFF0E5D3),
          actionLabel: 'Open',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CoachTeamOverviewPage(
                  teamName: teamName,
                  userData: userData,
                  coachData: coachData,
                  menteeCount: mentees.length,
                  onEditProfile: () => _showCoachProfileDialog(
                    userData: userData,
                    coachData: coachData,
                  ),
                  onOpenInbox: () {
                    final username = (userData['username'] as String?) ?? 'Coach';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatListScreen(
                          userId: _userId,
                          userName: username,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
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

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: mentees.length,
            itemBuilder: (context, index) {
              final mentee = mentees[index];
              final data = mentee.data();

              return FutureBuilder<Map<String, dynamic>?>(
                future: latestTrackerForUser(mentee.id),
                builder: (context, trackerSnapshot) {
                  final tracker = trackerSnapshot.data;
                  final completedTasks = <String>[
                    if (tracker?['call'] == true) 'Call',
                    if (tracker?['steps'] == true) 'Steps',
                    if (tracker?['meditation'] == true) 'Meditation',
                    if (tracker?['learning'] == true) 'Learning',
                    if (tracker?['addValue'] == true) 'Add Value',
                  ];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: (data['profilePic'] as String?)
                                      ?.trim()
                                      .isNotEmpty ==
                                  true
                              ? NetworkImage(data['profilePic'] as String)
                              : null,
                          child: ((data['profilePic'] as String?)?.trim().isEmpty ??
                                  true)
                              ? Text(
                                  ((data['username'] as String?)?.isNotEmpty ?? false)
                                      ? (data['username'] as String)[0].toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['username'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data['email'] ?? '',
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Latest activity: ${formatTrackerDate(tracker)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                completedTasks.isEmpty
                                    ? 'No completed tasks yet'
                                    : completedTasks.join(', '),
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            TextButton(
                              onPressed: () => _openChatWithMentee(
                                context,
                                mentee,
                              ),
                              child: const Text('Message'),
                            ),
                            TextButton(
                              onPressed: () => onRemoveMentee(mentee.id),
                              child: const Text('Remove'),
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
