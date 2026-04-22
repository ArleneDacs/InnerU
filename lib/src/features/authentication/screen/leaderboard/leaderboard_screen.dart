import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class UserActivity {
  const UserActivity({
    this.callIntent = 0,
    this.meditationMinutes = 0,
    this.stepsTaken = 0,
    this.exerciseCount = 0,
    this.valueEntries = 0,
    this.learningEntries = 0,
  });

  final int callIntent;
  final int meditationMinutes;
  final int stepsTaken;
  final int exerciseCount;
  final int valueEntries;
  final int learningEntries;

  int calculatePoints() {
    return callIntent +
        meditationMinutes +
        (stepsTaken / 200).floor() +
        (exerciseCount * 10) +
        valueEntries +
        learningEntries;
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.name,
    required this.score,
    required this.rank,
    required this.activity,
    this.profilePic,
    this.teamName,
  });

  final String name;
  final int score;
  final int rank;
  final UserActivity activity;
  final String? profilePic;
  final String? teamName;

  LeaderboardEntry copyWith({
    String? name,
    int? score,
    int? rank,
    UserActivity? activity,
    String? profilePic,
    String? teamName,
  }) {
    return LeaderboardEntry(
      name: name ?? this.name,
      score: score ?? this.score,
      rank: rank ?? this.rank,
      activity: activity ?? this.activity,
      profilePic: profilePic ?? this.profilePic,
      teamName: teamName ?? this.teamName,
    );
  }
}

class Leaderboard extends StatefulWidget {
  const Leaderboard({super.key, this.isLoading = true});

  final bool isLoading;

  @override
  State<Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<Leaderboard>
    with SingleTickerProviderStateMixin {
  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final TabController _tabController;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _userPointsSubscription;

  List<LeaderboardEntry> _allEntries = [];
  List<LeaderboardEntry> _teamEntries = [];
  bool _isLoading = true;
  String _teamName = '';
  bool _isCoachUser = false;
  Set<String> _teamMemberNames = <String>{};

  String _normalizeName(String value) => value.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadCurrentUserTeam();
    _setupUserPointsListener();
  }

  @override
  void dispose() {
    _userPointsSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserTeam() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final data = userDoc.data();
      final role = (data?['role'] as String?)?.toLowerCase();
      final isCoach = data?['isCoach'] == true || role == 'coach';
      final username =
          (data?['username'] as String?)?.trim() ?? (isCoach ? 'Coach' : 'User');
      final coachId = (data?['coachId'] as String?)?.trim() ?? '';
      final teamName = ((data?['team'] as String?)?.trim().isNotEmpty ?? false)
          ? (data!['team'] as String).trim()
          : username;

      final teamMemberNames = <String>{};

      if (isCoach) {
        final menteesSnapshot = await _firestore
            .collection('users')
            .where('coachId', isEqualTo: user.uid)
            .get();

        for (final mentee in menteesSnapshot.docs) {
          final menteeUsername = (mentee.data()['username'] as String?)?.trim();
          if (menteeUsername != null && menteeUsername.isNotEmpty) {
            teamMemberNames.add(_normalizeName(menteeUsername));
          }
        }
      } else if (coachId.isNotEmpty) {
        final teammatesSnapshot = await _firestore
            .collection('users')
            .where('coachId', isEqualTo: coachId)
            .get();

        for (final teammate in teammatesSnapshot.docs) {
          final teammateUsername = (teammate.data()['username'] as String?)?.trim();
          if (teammateUsername != null && teammateUsername.isNotEmpty) {
            teamMemberNames.add(_normalizeName(teammateUsername));
          }
        }
      } else if (teamName.isNotEmpty) {
        final teammatesSnapshot = await _firestore
            .collection('users')
            .where('team', isEqualTo: teamName)
            .get();

        for (final teammate in teammatesSnapshot.docs) {
          final teammateUsername = (teammate.data()['username'] as String?)?.trim();
          if (teammateUsername != null && teammateUsername.isNotEmpty) {
            teamMemberNames.add(_normalizeName(teammateUsername));
          }
        }
      } else if (username.isNotEmpty) {
        teamMemberNames.add(_normalizeName(username));
      }

      if (!mounted) return;
      setState(() {
        _teamName = teamName;
        _isCoachUser = isCoach;
        _teamMemberNames = teamMemberNames;
      });
    } catch (_) {}
  }

  void _setupUserPointsListener() {
    _userPointsSubscription?.cancel();
    _userPointsSubscription =
        _firestore.collection('userpoints').snapshots().listen(
      (snapshot) async {
        await _processUserPointsData(snapshot);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
      },
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadUserProfiles() async {
    final usersSnapshot = await _firestore.collection('users').get();
    final profiles = <String, Map<String, dynamic>>{};

    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      final username = (data['username'] as String?)?.trim() ?? '';
      if (username.isEmpty) continue;
      profiles[_normalizeName(username)] = {
        'username': username,
        'profilePic': (data['profilePic'] as String?)?.trim(),
        'team': (data['team'] as String?)?.trim(),
        'email': (data['email'] as String?)?.trim(),
      };
    }

    return profiles;
  }

  Future<void> _processUserPointsData(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    try {
      final profiles = await _loadUserProfiles();
      final entriesByName = <String, LeaderboardEntry>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final username = (data['username'] as String?)?.trim() ?? 'Unknown User';
        final normalizedName = _normalizeName(username);
        final taskPoints = Map<String, dynamic>.from(
          data['taskPoints'] as Map? ?? <String, dynamic>{},
        );

        final activity = UserActivity(
          callIntent: _extractIntValue(
            taskPoints,
            ['Call Points', 'call_points', 'callPoints'],
          ),
          meditationMinutes: _extractIntValue(
            taskPoints,
            ['Meditation Points', 'meditation_points', 'meditationPoints'],
          ),
          stepsTaken: _extractIntValue(
                taskPoints,
                ['Steps Points', 'steps_points', 'stepsPoints'],
              ) *
              200,
          exerciseCount: _extractIntValue(
                taskPoints,
                ['Exercise Points', 'exercise_points', 'exercisePoints'],
              ) ~/
              10,
          valueEntries: _extractIntValue(
            taskPoints,
            ['Add Value Points', 'value_points', 'addValuePoints'],
          ),
          learningEntries: _extractIntValue(
            taskPoints,
            ['Learning Points', 'learning_points', 'learningPoints'],
          ),
        );

        final entry = LeaderboardEntry(
          name: username,
          score: activity.calculatePoints(),
          rank: 0,
          activity: activity,
          profilePic: profiles[normalizedName]?['profilePic'] as String?,
          teamName: profiles[normalizedName]?['team'] as String?,
        );

        if (!entriesByName.containsKey(normalizedName) ||
            entriesByName[normalizedName]!.score < entry.score) {
          entriesByName[normalizedName] = entry;
        }
      }

      for (final teamMemberName in _teamMemberNames) {
        if (entriesByName.containsKey(teamMemberName)) continue;
        final profile = profiles[teamMemberName];
        final displayName =
            (profile?['username'] as String?)?.trim().isNotEmpty == true
                ? (profile!['username'] as String).trim()
                : 'Team Member';

        entriesByName[teamMemberName] = LeaderboardEntry(
          name: displayName,
          score: 0,
          rank: 0,
          activity: const UserActivity(),
          profilePic: profile?['profilePic'] as String?,
          teamName: profile?['team'] as String?,
        );
      }

      final rankedAll = _rankEntries(entriesByName.values.toList());
      final rankedTeam = _teamMemberNames.isEmpty
          ? <LeaderboardEntry>[]
          : _rankEntries(
              rankedAll
                  .where((entry) => _teamMemberNames.contains(_normalizeName(entry.name)))
                  .toList(),
            );

      if (!mounted) return;
      setState(() {
        _allEntries = rankedAll;
        _teamEntries = rankedTeam;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<LeaderboardEntry> _rankEntries(List<LeaderboardEntry> entries) {
    final sorted = [...entries]..sort((a, b) => b.score.compareTo(a.score));
    return sorted.asMap().entries.map((item) {
      return item.value.copyWith(rank: item.key + 1);
    }).toList();
  }

  int _extractIntValue(Map<String, dynamic> data, List<String> possibleKeys) {
    for (final key in possibleKeys) {
      if (!data.containsKey(key) || data[key] == null) continue;
      final value = data[key];
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<void> _refreshLeaderboard() async {
    setState(() {
      _isLoading = true;
    });
    await _loadCurrentUserTeam();
    final snapshot = await _firestore.collection('userpoints').get();
    await _processUserPointsData(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          title: const Text('Leaderboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshLeaderboard,
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.line_horizontal_3, size: 28),
              onPressed: () {
                Navigator.pushNamed(context, '/profile');
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: 'All users'),
              const Tab(text: 'My Team'),
            ],
          ),
        ),
        body: RefreshIndicator(
          key: _refreshKey,
          onRefresh: _refreshLeaderboard,
          child: TabBarView(
            controller: _tabController,
            children: [
              _LeaderboardBoard(
                entries: _allEntries,
                isLoading: _isLoading,
                emptyMessage: 'No leaderboard entries to display.',
                onEntryTap: (entry) => _showPointsBreakdown(context, entry),
              ),
              _LeaderboardBoard(
                entries: _teamEntries,
                isLoading: _isLoading,
                emptyMessage: _isCoachUser
                    ? 'No mentees in your team leaderboard yet.'
                    : _teamName.isEmpty
                        ? 'Join a team to see the team leaderboard.'
                        : 'No team leaderboard data yet.',
                onEntryTap: (entry) => _showPointsBreakdown(context, entry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPointsBreakdown(BuildContext context, LeaderboardEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.name}\'s Points',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if ((entry.teamName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Team: ${entry.teamName}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 16),
                _buildPointsRow(
                  'Call',
                  entry.activity.callIntent,
                  '10 pt/call',
                  entry.activity.callIntent,
                ),
                const Divider(),
                _buildPointsRow(
                  'Steps',
                  entry.activity.stepsTaken,
                  '10 pt/200 steps',
                  (entry.activity.stepsTaken / 200).floor(),
                ),
                const Divider(),
                _buildPointsRow(
                  'Exercise',
                  entry.activity.exerciseCount,
                  '10 pt/exercise',
                  entry.activity.exerciseCount * 10,
                ),
                const Divider(),
                _buildPointsRow(
                  'Meditation',
                  entry.activity.meditationMinutes,
                  '5 pt/minute',
                  entry.activity.meditationMinutes,
                ),
                const Divider(),
                _buildPointsRow(
                  'Add Value',
                  entry.activity.valueEntries,
                  '15 pt/entry',
                  entry.activity.valueEntries,
                ),
                const Divider(),
                _buildPointsRow(
                  'Learning',
                  entry.activity.learningEntries,
                  '15 pt/entry',
                  entry.activity.learningEntries,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Points',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${entry.score}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
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

  Widget _buildPointsRow(String title, int value, String rate, int points) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(title, style: const TextStyle(fontSize: 16))),
          Expanded(flex: 3, child: Text('$value', style: const TextStyle(fontSize: 16))),
          Expanded(
            flex: 2,
            child: Text(rate, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$points pts',
              style: const TextStyle(fontSize: 16, color: Colors.orange),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardBoard extends StatelessWidget {
  const _LeaderboardBoard({
    required this.entries,
    required this.isLoading,
    required this.emptyMessage,
    required this.onEntryTap,
  });

  final List<LeaderboardEntry> entries;
  final bool isLoading;
  final String emptyMessage;
  final ValueChanged<LeaderboardEntry> onEntryTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: isLoading
              ? _buildSkeletonPodium()
              : _buildPodium(context, entries, emptyMessage, onEntryTap),
        ),
        Expanded(
          child: isLoading
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _buildSkeletonItem(),
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length <= 3 ? 0 : entries.length - 3,
                  itemBuilder: (context, index) {
                    final entry = entries[index + 3];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _buildLeaderboardItem(entry, onEntryTap),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSkeletonPodium() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildSkeletonPodiumItem(120),
        _buildSkeletonPodiumItem(140),
        _buildSkeletonPodiumItem(100),
      ],
    );
  }

  Widget _buildSkeletonPodiumItem(double height) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const ShimmerWidget.circular(size: 48),
        const SizedBox(height: 8),
        const ShimmerWidget.rectangular(width: 30, height: 16),
        Container(
          width: 80,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: ShimmerWidget.rectangular(width: 80, height: height),
        ),
      ],
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFE5D3),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const ShimmerWidget.rectangular(width: 30, height: 24),
          const SizedBox(width: 12),
          const ShimmerWidget.circular(size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerWidget.rectangular(width: double.infinity, height: 16),
                SizedBox(height: 8),
                ShimmerWidget.rectangular(width: 140, height: 14),
                SizedBox(height: 8),
                ShimmerWidget.rectangular(width: double.infinity, height: 2),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              ShimmerWidget.rectangular(width: 40, height: 24),
              SizedBox(height: 4),
              ShimmerWidget.rectangular(width: 20, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _buildPodium(
  BuildContext context,
  List<LeaderboardEntry> entries,
  String emptyMessage,
  ValueChanged<LeaderboardEntry> onEntryTap,
) {
  if (entries.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          emptyMessage,
          style: const TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  if (entries.length < 3) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Not enough entries to display podium (need at least 3)',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  return SingleChildScrollView(
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 0,
          top: 20,
          child: SizedBox(
            width: 100,
            height: 180,
            child: Image.asset(
              'assets/images/confetti_left.gif',
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 20,
          child: SizedBox(
            width: 100,
            height: 180,
            child: Image.asset(
              'assets/images/confetti_right.gif',
              fit: BoxFit.cover,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildPodiumItem(entries[1], 120, 2, onEntryTap),
            _buildPodiumItem(entries[0], 140, 1, onEntryTap),
            _buildPodiumItem(entries[2], 100, 3, onEntryTap),
          ],
        ),
      ],
    ),
  );
}

Widget _buildPodiumItem(
  LeaderboardEntry entry,
  double height,
  int position,
  ValueChanged<LeaderboardEntry> onEntryTap,
) {
  return GestureDetector(
    onTap: () => onEntryTap(entry),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Stack(
          alignment: Alignment.topCenter,
          children: [
            entry.profilePic != null && entry.profilePic!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      entry.profilePic!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey[200],
                          child: Icon(
                            Icons.person,
                            size: 30,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  )
                : CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[200],
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.grey[600],
                    ),
                  ),
            if (position == 1)
              Positioned(
                top: 13,
                child: Image.asset(
                  'assets/images/crown.png',
                  height: 50,
                  width: 100,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Stack(
            children: [
              Container(
                width: 80,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF90A17D),
                      Color(0xFF6F7B5C),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Center(
                  child: Text(
                    '${entry.score} pts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: height / 4,
                left: 0,
                right: 0,
                child: Text(
                  entry.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: Text(
                  'Top $position',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildLeaderboardItem(
  LeaderboardEntry entry,
  ValueChanged<LeaderboardEntry> onEntryTap,
) {
  return GestureDetector(
    onTap: () => onEntryTap(entry),
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '#${entry.rank}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[200],
            backgroundImage: entry.profilePic != null && entry.profilePic!.isNotEmpty
                ? NetworkImage(entry.profilePic!)
                : null,
            child: entry.profilePic == null || entry.profilePic!.isEmpty
                ? Icon(Icons.person, size: 30, color: Colors.grey[600])
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: entry.score > 0
                        ? (entry.score / 3000).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.score}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'pts',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class ShimmerWidget extends StatefulWidget {
  const ShimmerWidget.rectangular({
    super.key,
    required this.width,
    required this.height,
  }) : isCircular = false;

  const ShimmerWidget.circular({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        isCircular = true;

  final double width;
  final double height;
  final bool isCircular;

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(
              widget.isCircular ? widget.width / 2 : 4,
            ),
            gradient: LinearGradient(
              begin: Alignment(_animation.value, 0),
              end: Alignment(-_animation.value, 0),
              colors: [
                Colors.grey[300]!,
                Colors.grey[100]!,
                Colors.grey[300]!,
              ],
            ),
          ),
        );
      },
    );
  }
}
