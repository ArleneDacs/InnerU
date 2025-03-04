import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DailyTrackerPage extends StatefulWidget {
  @override
  _DailyTrackerPageState createState() => _DailyTrackerPageState();
}

class _DailyTrackerPageState extends State<DailyTrackerPage> {
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  Map<String, Map<String, bool>> dailyTasks = {}; // Store tasks for each date

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Tracker'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('MMMM d, y').format(DateTime.now()),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              ExpansionTile(
                title: Text(
                  'View Previous Progress',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                children: [_buildCalendar()],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    int daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
    int firstDayOfWeek = DateTime(selectedYear, selectedMonth, 1).weekday % 7;
    List<String> weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        // Dropdown for selecting the month and year
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButton<int>(
              value: selectedMonth,
              onChanged: (newMonth) {
                setState(() {
                  selectedMonth = newMonth!;
                });
              },
              items: List.generate(
                12,
                (index) => DropdownMenuItem<int>(
                  value: index + 1,
                  child: Text(DateFormat('MMMM')
                      .format(DateTime(selectedYear, index + 1, 1))),
                ),
              ),
            ),
            SizedBox(width: 16),
            DropdownButton<int>(
              value: selectedYear,
              onChanged: (newYear) {
                setState(() {
                  selectedYear = newYear!;
                });
              },
              items: List.generate(
                10,
                (index) => DropdownMenuItem<int>(
                  value: DateTime.now().year - 5 + index,
                  child: Text('${DateTime.now().year - 5 + index}'),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        // Weekday Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: weekdays
              .map((day) => Expanded(
                    child: Center(
                      child: Text(day,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ))
              .toList(),
        ),
        SizedBox(height: 8),
        // Calendar Grid
        GridView.builder(
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: daysInMonth + firstDayOfWeek,
          itemBuilder: (context, index) {
            if (index < firstDayOfWeek) {
              return Container(); // Empty spaces before first day
            }
            int day = index - firstDayOfWeek + 1;
            return InkWell(
              onTap: () => _showDailyTrackerDialog(day),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: (day == DateTime.now().day &&
                          selectedMonth == DateTime.now().month)
                      ? Colors.green
                      : Colors.white,
                  border: Border.all(color: Colors.black),
                ),
                child:
                    Text('$day', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showDailyTrackerDialog(int day) {
    String dateKey = '$selectedYear-$selectedMonth-$day';

    // Initialize tasks if not already set
    dailyTasks.putIfAbsent(
        dateKey,
        () => {
              'Call': false,
              'Steps': false,
              'Meditation': false,
              'Learning': false,
              'Add Value': false,
            });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Daily Tracker - $selectedMonth/$day/$selectedYear"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: dailyTasks[dateKey]!.keys.map((task) {
                  return CheckboxListTile(
                    title: Text(task),
                    value: dailyTasks[dateKey]![task],
                    onChanged: (bool? value) {
                      setState(() {
                        dailyTasks[dateKey]![task] = value!;
                      });
                    },
                  );
                }).toList(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }
}
