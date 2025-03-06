import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class UserActivity {
  final int meditationMinutes;
  final int stepsTaken;
  final int journalEntries;

  const UserActivity({
    this.meditationMinutes = 0,
    this.stepsTaken = 0,
    this.journalEntries = 0,
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
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    isLoading = widget.isLoading;
    _loadSampleData();
    
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

  void _loadSampleData() {
    // Add sample users with activities
    _leaderboardService.addUserActivity(
      'John Angel', 
      const UserActivity(meditationMinutes: 1200, stepsTaken: 240000, journalEntries: 50)
    );
    
    _leaderboardService.addUserActivity(
      'Rose Anne', 
      const UserActivity(meditationMinutes: 1000, stepsTaken: 220000, journalEntries: 45)
    );
    
    _leaderboardService.addUserActivity(
      'Arlene Mae', 
      const UserActivity(meditationMinutes: 900, stepsTaken: 200000, journalEntries: 40)
    );
    
    _leaderboardService.addUserActivity(
      'Trixie Nicole', 
      const UserActivity(meditationMinutes: 850, stepsTaken: 190000, journalEntries: 35)
    );
    
    _leaderboardService.addUserActivity(
      'Craig Euwan', 
      const UserActivity(meditationMinutes: 800, stepsTaken: 180000, journalEntries: 30)
    );
    
    entries = _leaderboardService.getLeaderboard();
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
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Enter your code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {},
                  child: Text('Generate a code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5E7582),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 220,
            child: isLoading 
              ? _buildSkeletonPodium()
              : _buildPodium(),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: isLoading ? 5 : entries.length - 3,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: isLoading 
                    ? _buildSkeletonItem()
                    : _buildLeaderboardItem(entries[index + 3]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

// Skeleton loading

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildPodiumItem(entries[1], 120),
        _buildPodiumItem(entries[0], 140),
        _buildPodiumItem(entries[2], 100),
      ],
    );
  }

  Widget _buildPodiumItem(LeaderboardEntry entry, double height) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
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
        SizedBox(height: 8),
        Text('#${entry.rank}', style: TextStyle(fontWeight: FontWeight.bold)),
        Container(
          width: 80,
          height: height,
          margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2), // Added vertical margin
          decoration: BoxDecoration(
            color: Colors.cyan, // Changed color to match your screenshot
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Center(child: Text(entry.score.toString())),
        ),
      ],
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
                  LinearProgressIndicator(
                    value: entry.score / 3000,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange), // Match progress color to screenshot
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${entry.score}', 
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
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
            child: Text(rate, style: TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          Expanded(
            flex: 2,
            child: Text('$points pts', 
              style: TextStyle(fontSize: 16, color: Colors.orange),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ShimmerWidget
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
  }) : width = size,
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