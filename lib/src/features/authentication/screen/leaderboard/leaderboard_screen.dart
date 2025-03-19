import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserActivity {
  final int meditationMinutes;
  final int stepsTaken;
  final int journalEntries;
  final String server; // Added server field

  const UserActivity({
    this.meditationMinutes = 0,
    this.stepsTaken = 0,
    this.journalEntries = 0,
    this.server = "", // Default empty server
  });

  int calculatePoints() {
    // Meditation: 1pt per minute
    int meditationPoints = meditationMinutes;

    // Step Tracker: 1pt per 200 steps
    int stepPoints = (stepsTaken / 200).floor();

    // Journal: 1pt per entry
    int journalPoints = journalEntries;

    return meditationPoints + stepPoints + journalPoints;
  }
}

class LeaderboardService {
  List<LeaderboardEntry> _entries = [];

  void addUserActivity(String userName, UserActivity activity) {
    int existingIndex = _entries.indexWhere((entry) => entry.name == userName);

    if (existingIndex != -1) {
      _entries.removeAt(existingIndex);
    }

    _entries.add(LeaderboardEntry(
      name: userName,
      score: activity.calculatePoints(),
      rank: 0,
      activity: activity,
    ));

    // Sort and update ranks
    _entries.sort((a, b) => b.score.compareTo(a.score));

    for (int i = 0; i < _entries.length; i++) {
      _entries[i] = LeaderboardEntry(
        name: _entries[i].name,
        score: _entries[i].score,
        rank: i + 1,
        activity: _entries[i].activity,
      );
    }
  }

  List<LeaderboardEntry> getLeaderboard() {
    return List.from(_entries);
  }

  // New method to get filtered leaderboard
  List<LeaderboardEntry> getFilteredLeaderboard(String server) {
    if (server.isEmpty) {
      return List.from(_entries);
    }

    return _entries.where((entry) => entry.activity.server == server).toList();
  }
}

class LeaderboardEntry {
  final String name;
  final int score;
  final int rank;
  final UserActivity activity;

  const LeaderboardEntry({
    required this.name,
    required this.score,
    required this.rank,
    this.activity = const UserActivity(),
  });
}

class Leaderboard extends StatefulWidget {
  final bool isLoading;

  Leaderboard({this.isLoading = true});

  @override
  _LeaderboardState createState() => _LeaderboardState();
}

class _LeaderboardState extends State<Leaderboard> {
  final LeaderboardService _leaderboardService = LeaderboardService();
  late List<LeaderboardEntry> entries;
  late List<LeaderboardEntry>
      displayedEntries; // New variable for displayed entries
  bool isLoading = true;
  String selectedServer = "Server"; // Default selected server
  String username = "Valenin"; // Default username
  bool isFilteredByUser = false; // Track if we're filtering by user

  @override
  void initState() {
    super.initState();
    isLoading = widget.isLoading;
    _loadUserData();

    // Simulate loading for demo
    if (isLoading) {
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      });
    }
  }

  void _loadUserData() async {
  QuerySnapshot snapshot =
      await FirebaseFirestore.instance.collection('userpoints').get();

  List<LeaderboardEntry> fetchedEntries = snapshot.docs.map((doc) {
    var data = doc.data() as Map<String, dynamic>;

    return LeaderboardEntry(
      name: data['username'],
      score: data['totalPoints'],
      rank: 0, // Will be updated after sorting
      activity: UserActivity(
        meditationMinutes: data['taskPoints']['Meditation Points'] ?? 0,
        stepsTaken: (data['taskPoints']['Steps Points'] ?? 0) * 200, // Reverse calculation
        journalEntries: 
        (data['taskPoints']['Learning Points'] ?? 0) ~/ 15 +  // Convert Learning points
        (data['taskPoints']['Add Value Points'] ?? 0) ~/ 15,  // Convert Add Value points
      ),
    );
  }).toList();

  fetchedEntries.sort((a, b) => b.score.compareTo(a.score));

  for (int i = 0; i < fetchedEntries.length; i++) {
    fetchedEntries[i] = LeaderboardEntry(
      name: fetchedEntries[i].name,
      score: fetchedEntries[i].score,
      rank: i + 1,
      activity: fetchedEntries[i].activity,
    );
  }

  setState(() {
    entries = fetchedEntries;
    displayedEntries = List.from(entries);
    isLoading = false;
  });
}


  // Function to filter entries by server - FIXED VERSION
  void _filterByServer(String server) {
    setState(() {
      if (server == "Server") {
        // Show all servers
        displayedEntries = List.from(entries);
        isFilteredByUser = false;
        selectedServer = "Server";
      } else {
        // Filter by specific server
        List<LeaderboardEntry> filtered =
            entries.where((entry) => entry.activity.server == server).toList();

        // Re-rank the filtered entries from 1 to N
        for (int i = 0; i < filtered.length; i++) {
          filtered[i] = LeaderboardEntry(
            name: filtered[i].name,
            score: filtered[i].score,
            rank: i + 1, // Reassign ranks starting from 1
            activity: filtered[i].activity,
          );
        }

        displayedEntries = filtered;
        isFilteredByUser = true;
        selectedServer = server; // Store the actual server name
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text('Leaderboard'),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.line_horizontal_3, size: 28),
            onPressed: () {
              Navigator.pushNamed(context, "/profile");
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Server/User selector with tappable areas
          Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              height: 36, // Reduced height
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                    18), // Adjusted to match half of height
                border: Border.all(color: Color(0xFFCEA47E), width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Filter by Valenin server
                        _filterByServer("Valenin");
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isFilteredByUser
                              ? Color(0xFFCEA47E)
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(17),
                            bottomLeft: Radius.circular(17),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          username,
                          style: TextStyle(
                            color: isFilteredByUser
                                ? Colors.white
                                : Color(0xFFCEA47E),
                            fontWeight: FontWeight.w500,
                            fontSize: 15, // Slightly smaller text
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Show all servers
                        _filterByServer("Server");
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: !isFilteredByUser
                              ? Color(0xFFCEA47E)
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(17),
                            bottomRight: Radius.circular(17),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Server",
                          style: TextStyle(
                            color: !isFilteredByUser
                                ? Colors.white
                                : Color(0xFFCEA47E),
                            fontWeight: FontWeight.w500,
                            fontSize: 15, // Slightly smaller text
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 220,
            child: isLoading ? _buildSkeletonPodium() : _buildPodium(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: isLoading
                  ? 5
                  : (displayedEntries.length <= 3
                      ? 0
                      : displayedEntries.length - 3),
              itemBuilder: (context, index) {
                // Use actual rank from entry rather than calculating from index
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: isLoading
                      ? _buildSkeletonItem()
                      : _buildLeaderboardItem(displayedEntries[index + 3]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Skeleton loading methods
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
        ShimmerWidget.circular(size: 48),
        SizedBox(height: 8),
        ShimmerWidget.rectangular(width: 30, height: 16),
        Container(
          width: 80,
          height: height,
          margin: EdgeInsets.symmetric(horizontal: 4),
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
          color: Color(0xFFFFE5D3),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(12),
      child: Row(
        children: [
          ShimmerWidget.rectangular(width: 30, height: 24),
          SizedBox(width: 12),
          ShimmerWidget.circular(size: 48),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerWidget.rectangular(width: double.infinity, height: 16),
                SizedBox(height: 8),
                ShimmerWidget.rectangular(width: 140, height: 14),
                SizedBox(height: 8),
                ShimmerWidget.rectangular(width: double.infinity, height: 2),
              ],
            ),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShimmerWidget.rectangular(width: 40, height: 24),
              SizedBox(height: 4),
              ShimmerWidget.rectangular(width: 20, height: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPodium() {
  // Check if we have enough entries to show in podium
  if (displayedEntries.length < 3) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          "Not enough entries to display podium",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }

   return SingleChildScrollView( // Add this widget to make the content scrollable if needed
    child: Stack(
      clipBehavior: Clip.none, // Change to allow overflow without warnings
      alignment: Alignment.center,
      children: [
        // Left confetti
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

        // Right confetti
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

        // Podium content
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildPodiumItem(displayedEntries[1], 120, 2),
            _buildPodiumItem(displayedEntries[0], 140, 1),
            _buildPodiumItem(displayedEntries[2], 100, 3),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildPodiumItem(LeaderboardEntry entry, double height, int position) {
    return GestureDetector(
      onTap: () {
        // Show detailed breakdown of points when tapping on podium item
        _showPointsBreakdown(context, entry);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Stack(
            alignment: Alignment.topCenter,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey[200],
                child: Icon(
                  Icons.person,
                  size: 30,
                  color: Colors.grey[600],
                ),
              ),
              // Add crown to first place
              if (position == 1)
                Positioned(
                  top: 70,
                  child: Image.asset(
                    'assets/images/crown.png',
                    height: 30,
                    width: 30,
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text('#${entry.rank}', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            width: 80,
            height: height,
            margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.cyan,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Center(
              child: Text(
                entry.score.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardItem(LeaderboardEntry entry) {
    return GestureDetector(
      onTap: () {
        // Show detailed breakdown of points
        _showPointsBreakdown(context, entry);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Color(0xFFFFE5D3),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Text('#${entry.rank}', style: TextStyle(fontSize: 18)),
            SizedBox(width: 12),
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[200],
              child: Icon(
                Icons.person,
                size: 30,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name,
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text(
                    entry.activity.server,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: entry.score / 3000,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(entry.score.toString(), style: TextStyle(fontSize: 18)),
                Text('points', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPointsBreakdown(BuildContext context, LeaderboardEntry entry) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.name}\'s Points',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Server: ${entry.activity.server}',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              SizedBox(height: 16),
              _buildPointsRow('Meditation', entry.activity.meditationMinutes,
                  '1 pt/minute', entry.activity.meditationMinutes),
              Divider(),
              _buildPointsRow('Steps', entry.activity.stepsTaken,
                  '1 pt/200 steps', (entry.activity.stepsTaken / 200).floor()),
              Divider(),
              _buildPointsRow('Journal', entry.activity.journalEntries,
                  '1 pt/entry', entry.activity.journalEntries),
              Divider(),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Points',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${entry.score}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPointsRow(String title, int value, String rate, int points) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(title, style: TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 3,
            child: Text('$value', style: TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 2,
            child:
                Text(rate, style: TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$points pts',
              style: TextStyle(fontSize: 16, color: Colors.orange),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ShimmerWidget class
class ShimmerWidget extends StatefulWidget {
  final double width;
  final double height;
  final bool isCircular;

  const ShimmerWidget.rectangular({
    required this.width,
    required this.height,
  }) : isCircular = false;

  const ShimmerWidget.circular({
    required double size,
  })  : width = size,
        height = size,
        isCircular = true;

  @override
  _ShimmerWidgetState createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 1500),
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