import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class LeaderboardEntry {
  final String name;
  final int score;
  final int rank;

  LeaderboardEntry({
    required this.name,
    required this.score,
    required this.rank,
  });
}

class Leaderboard extends StatelessWidget {

  final bool isLoading;
  final List<LeaderboardEntry> entries = [ // Add placeholder entries
    LeaderboardEntry(name: 'John Angel', score: 2500, rank: 1),
    LeaderboardEntry(name: 'Rose Anne', score: 2300, rank: 2),
    LeaderboardEntry(name: 'Arlene Mae', score: 2100, rank: 3),
    LeaderboardEntry(name: 'Trixie Nicole', score: 2000, rank: 4),
    LeaderboardEntry(name: 'Craig Euwan', score: 1900, rank: 5),
  ];

  Leaderboard({this.isLoading = true});

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
            height: 200,
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

// skeleton loading function

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

  // Add podium builder
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
          margin: EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.orange[100],
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Center(child: Text(entry.score.toString())),
        ),
      ],
    );
  }

  // Add leaderboard item builder
  Widget _buildLeaderboardItem(LeaderboardEntry entry) {
    return Container(
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
                  color: Colors.orange,
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
    );
  }
}

// Loading leaderboard shimmer effect

class ShimmerWidget extends StatefulWidget {
  final double width;
  final double height;
  final bool isCircular;

  const ShimmerWidget.rectangular({
    required this.width,
    required this.height,
  }
  ) : isCircular = false;

  const ShimmerWidget.circular({
    required double size,
  }
  ) : width = size,
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