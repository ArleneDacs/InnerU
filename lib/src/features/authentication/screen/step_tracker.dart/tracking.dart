      import 'package:flutter/material.dart';
      import 'package:fl_chart/fl_chart.dart';
      import 'package:cloud_firestore/cloud_firestore.dart';
      import 'package:firebase_auth/firebase_auth.dart';
      import 'package:intl/intl.dart';

      class TrackingScreen extends StatefulWidget {
        const TrackingScreen({super.key, required this.title});
        final String title;

        @override
        State<TrackingScreen> createState() => _TrackingScreenState();
      }

      class _TrackingScreenState extends State<TrackingScreen> {
        final FirebaseFirestore firestore = FirebaseFirestore.instance;
        final FirebaseAuth auth = FirebaseAuth.instance;
        
        List<double> weeklySteps = List.filled(7, 0); // Holds step counts for each day
        int totalSteps = 0;

        @override
        void initState() {
          super.initState();
          fetchWeeklySteps();
        }

    Future<void> fetchWeeklySteps() async {
   String userId = auth.currentUser?.uid ?? "";
   if (userId.isEmpty) return;

   DateTime now = DateTime.now();
   DateFormat formatter = DateFormat('yyyy-MM-dd');

   List<double> newWeeklySteps = List.filled(7, 0);
   int newTotalSteps = 0;

   for (int i = 0; i < 7; i++) {
     DateTime date = now.subtract(Duration(days: now.weekday - i - 1));
     String dateStr = formatter.format(date);

     DocumentSnapshot stepDoc = await firestore
         .collection('steps')
         .doc(userId)
         .collection('tracking')
         .doc(dateStr)
         .get();

     if (stepDoc.exists) {
       int steps = (stepDoc.data() as Map<String, dynamic>)['steps'] ?? 0;
       newWeeklySteps[i] = steps.toDouble();
       newTotalSteps += steps;
     }
   }

   if (mounted) {
     setState(() {
       weeklySteps = newWeeklySteps;
       totalSteps = newTotalSteps;
     });
   }
}


        @override
        Widget build(BuildContext context) {
          double screenWidth = MediaQuery.of(context).size.width;

          return Scaffold(
            appBar: AppBar(
              actions: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: Offset(screenWidth * 0.023, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          color: Color(0xFFCE8F5A),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 5,
                              offset: Offset(2, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          'WEEKLY STEPS REPORT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Steps Chart
                    SizedBox(
                      height: 400,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: weeklySteps.reduce((a, b) => a > b ? a : b) + 20000, // Adjust max Y
                          barGroups: List.generate(7, (index) => makeGroupData(index, weeklySteps[index])),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (double value, TitleMeta meta) {
                                  const days = ['Mon', 'Tue', 'Wed', 'Th', 'Fri', 'Sat', 'Sun'];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 0),
                                    child: Text(
                                      days[value.toInt()],
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    Card(
                      color: Color(0xFFFCF9F6),
                      elevation: 5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
                        child: Column(
                          children: [
                            Text(
                              "This week's total steps taken:",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '$totalSteps', 
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text(
                              totalSteps >= 5000
                                  ? 'Amazing! You’ve surpassed your first goal!'
                                  : totalSteps >= 10000
                                      ? 'Great job! Keep going!'
                                      : 'Keep moving!',
                            textAlign: TextAlign.center, 
                              style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Milestones',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                        milestoneCard('5k', 'assets/images/milestone1.jpg', totalSteps),
                        milestoneCard('10k', 'assets/images/milestone2.jpg', totalSteps),
                        milestoneCard('15k', 'assets/images/milestone3.jpg', totalSteps),
                        milestoneCard('20k', 'assets/images/milestone4.jpg', totalSteps),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        BarChartGroupData makeGroupData(int x, double y) {
          return BarChartGroupData(
            x: x,
            barRods: [
              BarChartRodData(
                toY: y,
                color: Colors.teal,
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }

   Widget milestoneCard(String steps, String imagePath, int totalSteps) {
  int milestoneValue = int.parse(steps.replaceAll('k', '')) * 1000; // Convert "5k" to 5000

  bool isAchieved = totalSteps >= milestoneValue; // Check if milestone is achieved

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Stack(
      children: [
        Container(
          width: 80,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isAchieved ? null : Colors.grey[600], // Remove grey if achieved
            image: DecorationImage(
              image: AssetImage(imagePath),
              fit: BoxFit.cover,
              colorFilter: isAchieved
                  ? null
                  : ColorFilter.mode(Colors.grey.withOpacity(0.5), BlendMode.darken),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                 color: isAchieved ? Colors.white : Colors.grey[400],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  steps,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFce8f5a),
                    fontSize: 25,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 5,
          left: 5,
          child: Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.star, color: Colors.amber, size: 20),
          ),
        ),
      ],
    ),
  );
}

      }
