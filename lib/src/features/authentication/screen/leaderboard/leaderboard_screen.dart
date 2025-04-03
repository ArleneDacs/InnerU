import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class UserActivity {
  final int callIntent;
  final int meditationMinutes;
  final int stepsTaken;
  final int valueEntries;
  final int learningEntries;
  final String server;

  const UserActivity({
    this.callIntent = 0,
    this.meditationMinutes = 0,
    this.stepsTaken = 0,
    this.valueEntries = 0,
    this.learningEntries = 0,
    this.server = "",
  });

  int calculatePoints() {
    int callPoints = callIntent;
    int meditationPoints = meditationMinutes;
    int stepPoints = (stepsTaken / 200).floor();
    int valuePoints = valueEntries;
    int learningPoints = learningEntries;

    return callPoints + meditationPoints + stepPoints + valuePoints + learningPoints;
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

  // Get filtered leaderboard
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
  late List<LeaderboardEntry> displayedEntries;
  bool isLoading = true;
  String selectedServer = "Default"; // Default server to show first
  String username = "Valenin";
  bool hasJoinedTeam = false; // Flag to determine if user has joined a team
  bool isFilteredByUser = false;

  @override
  void initState() {
    super.initState();
    isLoading = widget.isLoading;
    _loadUserData();
    _checkUserTeamStatus(); // Check if user has joined a team

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

  // Check if user has joined a team
  void _checkUserTeamStatus() async {
    try {
      // Fetch user data from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(username) // Assuming username is used as document ID
          .get();

      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        
        // Check if user has a team field and it's not empty
        if (userData.containsKey('team') && userData['team'] != null && userData['team'].toString().isNotEmpty) {
          setState(() {
            hasJoinedTeam = true;
            // If user has a team, set it as selected server
            selectedServer = userData['team'];
          });
        } else {
          setState(() {
            hasJoinedTeam = false;
            // User hasn't joined a team, keep default server
            selectedServer = "Default";
          });
        }
      }
    } catch (e) {
      print('Error checking user team status: $e');
      // Default to false if error occurs
      setState(() {
        hasJoinedTeam = false;
      });
    }
  }

  void _loadUserData() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('userpoints').get();

    // Create a map to store the latest entry for each user
    Map<String, LeaderboardEntry> userEntries = {};

    // Process all documents
    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      String username = data['username'] ?? "Unknown User";
      
      // Get task points from Firestore - ensure it's properly initialized
      Map<String, dynamic> taskPoints = data['taskPoints'] ?? {};
      
      // Calculate total points correctly (casting to int)
      int totalPoints = 0;
      taskPoints.forEach((key, value) {
        // Cast the dynamic value to int
        if (value != null) {
          totalPoints += (value is int) ? value : (value as num).toInt();
        }
      });
      
      // Extract server information if available, otherwise use "Default"
      String server = data['server'] ?? "Default";

      // FIXED: Make sure to correctly extract data using consistent field names
      // This is likely the main issue - the field names might not match what's in Firestore
      UserActivity activity = UserActivity(
        // Check both possible field name variants for each activity type
        callIntent: _extractIntValue(taskPoints, ['Call Points', 'call_points', 'callPoints']),
        meditationMinutes: _extractIntValue(taskPoints, ['Meditation Points', 'meditation_points', 'meditationPoints']),
        stepsTaken: _extractIntValue(taskPoints, ['Steps Points', 'steps_points', 'stepsPoints']) * 200,
        valueEntries: _extractIntValue(taskPoints, ['Add Value Points', 'value_points', 'addValuePoints']),
        learningEntries: _extractIntValue(taskPoints, ['Learning Points', 'learning_points', 'learningPoints']),
        server: server,
      );
      
      // Calculate the score from our activity model
      int modelCalculatedScore = activity.calculatePoints();
      
      // Create entry with the correct score
      LeaderboardEntry entry = LeaderboardEntry(
        name: username,
        score: modelCalculatedScore, // Use model's calculation
        rank: 0, // Will be updated after sorting
        activity: activity,
      );

      // Only store the entry if we don't already have one for this user,
      // or if this entry has a higher score than the one we already have
      if (!userEntries.containsKey(username) || userEntries[username]!.score < modelCalculatedScore) {
        userEntries[username] = entry;
      }
    }

    // Convert map to list and sort by score
    List<LeaderboardEntry> fetchedEntries = userEntries.values.toList();
    fetchedEntries.sort((a, b) => b.score.compareTo(a.score));

    // Update ranks
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
      _filterByServer(selectedServer); // Initially filter by the selected server
    });
  }

  // Helper method to safely extract integer values from the taskPoints map
  // Tries multiple possible field names and handles type conversion
  int _extractIntValue(Map<String, dynamic> data, List<String> possibleKeys) {
    // Try each possible key
    for (String key in possibleKeys) {
      if (data.containsKey(key) && data[key] != null) {
        var value = data[key];
        // Handle different possible types
        if (value is int) {
          return value;
        } else if (value is double) {
          return value.toInt();
        } else if (value is num) {
          return value.toInt();
        } else if (value is String) {
          // Try to parse string to int
          return int.tryParse(value) ?? 0;
        }
      }
    }
    return 0; // Default if none of the keys exist or conversion fails
  }

  // Function to filter entries by server
  void _filterByServer(String server) {
    setState(() {
      if (server == "All") {
        // Show all servers
        displayedEntries = List.from(entries);
        isFilteredByUser = false;
        selectedServer = "All";
      } else {
        // Filter by specific server
        List<LeaderboardEntry> filtered = entries.where((entry) => entry.activity.server == server).toList();

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
        selectedServer = server;
        isFilteredByUser = server == username;
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
          // Only show server/user selector if user has joined a team
          if (hasJoinedTeam)
            Padding(
              padding: EdgeInsets.all(16),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Color(0xFFCEA47E), width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // Filter by username
                          _filterByServer(username);
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
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // Show all servers or the server the user belongs to
                          _filterByServer(selectedServer == username ? "All" : selectedServer);
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
                            selectedServer == username ? "All" : selectedServer,
                            style: TextStyle(
                              color: !isFilteredByUser
                                  ? Colors.white
                                  : Color(0xFFCEA47E),
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
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
    if (displayedEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "No entries to display",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }
    
    if (displayedEntries.length < 3) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Not enough entries to display podium (need at least 3)",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Stack(
        clipBehavior: Clip.none,
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
                  top: 13,
                  child: Image.asset(
                    'assets/images/crown.png',
                    height: 50,
                    width: 100,
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('#${entry.rank}', style: TextStyle(fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text('.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              ),
              Text(
                entry.name, 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1
              ),
            ],
          ),
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
                  Text(entry.name, style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  // Only show server info if hasJoinedTeam is true
                  if (hasJoinedTeam)
                    Text(
                      entry.activity.server,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: entry.score > 0 ? (entry.score / 3000) : 0.0,  // Prevent division by zero
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

  // Replace the _showPointsBreakdown method with this updated version
void _showPointsBreakdown(BuildContext context, LeaderboardEntry entry) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // Allow the sheet to be larger
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return SingleChildScrollView( // Add scrolling capability
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16, // Handle keyboard
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              // Only show server info if hasJoinedTeam is true
              if (hasJoinedTeam)
                Text(
                  'Server: ${entry.activity.server}',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              SizedBox(height: 16),
              _buildPointsRow('Call', entry.activity.callIntent,
                '10 pt/call', entry.activity.callIntent),
              Divider(),    
              _buildPointsRow('Steps', entry.activity.stepsTaken,
                '10 pt/200 steps', (entry.activity.stepsTaken / 200).floor()),    
              Divider(),
              _buildPointsRow('Meditation', entry.activity.meditationMinutes,
                '5 pt/minute', entry.activity.meditationMinutes),
              Divider(),
              _buildPointsRow('Add Value', entry.activity.valueEntries,
                '15 pt/entry', entry.activity.valueEntries),
              Divider(),
              _buildPointsRow('Learning', entry.activity.learningEntries,
                '15 pt/entry', entry.activity.learningEntries),
              Divider(),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Points',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold
                        )
                    ),
                    Text('${entry.score}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange
                        )
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8), // Add some padding at the bottom
            ],
          ),
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
            child: Text(rate, style: TextStyle(fontSize: 14, color: Colors.grey)),
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

class _ShimmerWidgetState extends State<ShimmerWidget> with SingleTickerProviderStateMixin {
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