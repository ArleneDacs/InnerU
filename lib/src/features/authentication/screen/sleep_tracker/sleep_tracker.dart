import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_settings.dart';

class SleepTracker extends StatefulWidget {
  const SleepTracker({super.key});

  @override
  State<SleepTracker> createState() => _SleepTrackerState();
}

class _SleepTrackerState extends State<SleepTracker> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Image.asset('assets/images/sleeping.png'),
          Row(
            children: <Widget>[
              Padding(padding: EdgeInsets.only(left: 30.0)),
              Flexible(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                        "Set your bedtime and sleep goal,\nand let us do the rest!")),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 30.0),
                  child: Text(
                    "Sleep Tracking",
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 32),
                  ),
                ),
              )
            ],
          ),
          Divider(
            indent: 200,
            color: Color(0xFF000000),
          ),
          SleepSettings()
        ],
      ),
    );
  }
}
