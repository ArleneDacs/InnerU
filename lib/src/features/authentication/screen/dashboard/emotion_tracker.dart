import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';

class EmotionTrackerPage extends StatefulWidget {
  @override
  _EmotionTrackerPageState createState() => _EmotionTrackerPageState();
}

class _EmotionTrackerPageState extends State<EmotionTrackerPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Query for all emotions for the user (no date filtering)
  Stream<QuerySnapshot> _allEmotionsStream(String uid) {
    return _firestore
        .collection('emotions')
        .where('userId', isEqualTo: uid)
        .orderBy('date', descending: true)
        .snapshots();
  }

  // Query for emotions in the past 7 days
  Stream<QuerySnapshot> _weekEmotionsStream(String uid) {
    DateTime oneWeekAgo = DateTime.now().subtract(Duration(days: 7));
    return _firestore
        .collection('emotions')
        .where('userId', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(oneWeekAgo))
        .orderBy('date', descending: true)
        .snapshots();
  }

  // Helper function to format date values safely.
  String _getFormattedDate(dynamic dateValue) {
    if (dateValue == null) {
      return 'No date';
    }
    if (dateValue is Timestamp) {
      return dateValue.toDate().toString();
    }
    if (dateValue is String) {
      try {
        return DateTime.parse(dateValue).toString();
      } catch (e) {
        return dateValue;
      }
    }
    return dateValue.toString();
  }

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Emotion Tracker')),
        body: Center(child: Text('User not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Emotion Tracker'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Weekly Emotion Chart Section (Line Chart)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: _weekEmotionsStream(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(
                        child: Text(
                            'Error fetching week emotions: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                        child: Text('No emotions recorded this week.'));
                  }
                  // Pass the documents to the chart widget
                  return WeeklyEmotionLineChart(docs: snapshot.data!.docs);
                },
              ),
            ),
            Divider(),
            // All Emotions List Section
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: _allEmotionsStream(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(
                        child:
                            Text('Error fetching emotions: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text('No emotions recorded.'));
                  }

                  List<Map<String, dynamic>> emotions = snapshot.data!.docs
                      .map((doc) => doc.data() as Map<String, dynamic>)
                      .toList();

                  return ListView.builder(
                    shrinkWrap: true, // Needed inside SingleChildScrollView
                    physics:
                        NeverScrollableScrollPhysics(), // Disable inner scrolling
                    itemCount: emotions.length,
                    itemBuilder: (context, index) {
                      var emotion = emotions[index];
                      return ListTile(
                        leading: Icon(Icons.mood),
                        title: Text(emotion['emotion'] ?? 'Unknown'),
                        subtitle: Text(
                          "Date: ${_getFormattedDate(emotion['date'])}",
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget that builds a line chart for the past week's emotions.
/// It aggregates emotions by type and plots their counts.
class WeeklyEmotionLineChart extends StatelessWidget {
  final List<DocumentSnapshot> docs;

  const WeeklyEmotionLineChart({Key? key, required this.docs})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Aggregate emotion counts
    Map<String, int> emotionCounts = {};
    for (var doc in docs) {
      String emotion = doc['emotion'] ?? 'Unknown';
      emotionCounts[emotion] = (emotionCounts[emotion] ?? 0) + 1;
    }

    // Prepare the data for the line chart
    // Sort the emotions to keep consistent order.
    List<String> emotionLabels = emotionCounts.keys.toList()..sort();
    List<FlSpot> spots = [];
    for (int i = 0; i < emotionLabels.length; i++) {
      spots.add(
          FlSpot(i.toDouble(), emotionCounts[emotionLabels[i]]!.toDouble()));
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(16),
        height: 300,
        child: Column(
          children: [
            Text(
              "Weekly Emotion Distribution (Line Chart)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: _findMaxY(spots),
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          int index = value.toInt();
                          if (index < 0 || index >= emotionLabels.length)
                            return Container();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(emotionLabels[index]),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.black26),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      color: Colors.blue,
                      dotData: FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _findMaxY(List<FlSpot> spots) {
    double maxY = 0;
    for (var spot in spots) {
      if (spot.y > maxY) {
        maxY = spot.y;
      }
    }
    // Add a little extra space for visual padding
    return maxY + 1;
  }
}
