import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SleepSettings extends StatefulWidget {
  const SleepSettings({super.key});

  @override
  _SleepSettingsState createState() => _SleepSettingsState();
}

class _SleepSettingsState extends State<SleepSettings> {
  String? selectedMode = "Alarm";
  List<String> modeOptions = ["Alarm", "Vibrate"];

  TimeOfDay selectedBedtime = TimeOfDay(hour: 22, minute: 0);
  int? selectedSleepGoal = 9;
  List<int> sleepGoalOptions = List.generate(12, (index) => index + 1);

  Future<void> _pickTime(BuildContext context) async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: selectedBedtime,
    );

    if (pickedTime != null) {
      setState(() {
        selectedBedtime = pickedTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _buildDropdownColumn(
                    "Wake up \nnotification", selectedMode, modeOptions,
                    (newValue) {
                  setState(() {
                    selectedMode = newValue;
                  });
                }),
              ),
              _buildTimePickerColumn(),
              Expanded(
                child: _buildDropdownColumn("Set your \nsleep goal",
                    selectedSleepGoal, sleepGoalOptions, (newValue) {
                  setState(() {
                    selectedSleepGoal = newValue;
                  });
                }),
              ),
            ],
          ),
          SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.brown,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text("Save details", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownColumn<T>(
      String label, T value, List<T> items, ValueChanged<T?> onChanged) {
    return Column(
      children: [
        _buildDropdown(value, items, onChanged),
        Text(
          label,
          style: GoogleFonts.roboto(fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildTimePickerColumn() {
    return Column(
      children: [
        InkWell(
          onTap: () => _pickTime(context),
          child: SizedBox(
            child: Container(
              width: 110,
              height: 45,
              padding: EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                selectedBedtime.format(context),
                style: GoogleFonts.roboto(),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Text("Set your bedtime\n", style: TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildDropdown<T>(T value, List<T> items, ValueChanged<T?> onChanged) {
    return Container(
      width: 100,
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: SizedBox(),
        onChanged: onChanged,
        items: items.map((T item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(item.toString(), textAlign: TextAlign.center),
          );
        }).toList(),
      ),
    );
  }
}
