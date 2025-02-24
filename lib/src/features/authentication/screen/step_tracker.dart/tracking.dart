import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.title});
  final String title;

  @override
  State<TrackingScreen> createState() => _TrackingScreen();
}

class _TrackingScreen extends State<TrackingScreen> {
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
                    maxY: 10,
                    barGroups: [
                      makeGroupData(0, 7),
                      makeGroupData(1, 5),
                      makeGroupData(2, 6),
                      makeGroupData(3, 9),
                      makeGroupData(4, 8),
                      makeGroupData(5, 5),
                      makeGroupData(6, 4),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
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

              // Total Steps Card
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
                        '0',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Congratulations in reaching your goal!',
                        style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // Milestones Section
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
                    milestoneCard('5k', 'assets/images/milestone1.jpg'),
                    milestoneCard('10k', 'assets/images/milestone2.jpg'),
                    milestoneCard('15k', 'assets/images/milestone3.jpg'),
                    milestoneCard('20k', 'assets/images/milestone4.jpg'),
                    milestoneCard('30k', 'assets/images/milestone4.jpg'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Function to generate bar chart data
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


Widget milestoneCard(String steps, String imagePath) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Stack(
      children: [
        Container(
          width: 80,
          height: 100,
           decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.grey[300], // Default gray background
            image: DecorationImage(
              image: AssetImage(imagePath),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.grey.withOpacity(0.5), // Apply gray overlay
                BlendMode.darken,
              ),
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey[200], // Light gray background for text box
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  steps,
                  style: const TextStyle(
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
              color: Colors.white.withOpacity(0.8), // Light background for contrast
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
