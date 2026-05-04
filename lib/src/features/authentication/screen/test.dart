import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/models/test_model.dart';

class Test extends StatefulWidget {
  final TestModel testModel;
  const Test({super.key, required this.testModel});

  @override
  State<Test> createState() => _TestState();
}

class _TestState extends State<Test> {
  final CollectionReference myTest =
      FirebaseFirestore.instance.collection('test');

  String tName = "Loading...";
  String tNote = "Loading...";

  late TextEditingController testNameController;
  late TextEditingController testNoteController;
  late TestModel testModel;

  @override
  void initState() {
    super.initState();
    testModel = widget.testModel;
    tName = testModel.testName;
    tNote = testModel.testNote;

    testNameController = TextEditingController(text: tName);
    testNoteController = TextEditingController(text: tNote);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextField(
            controller: testNameController,
            onChanged: (value) {
              tName = value;
            },
          ),
          TextField(
            controller: testNoteController,
            onChanged: (value) {
              tNote = value;
            },
          ),
          ElevatedButton(onPressed: () => saveTests(), child: Text("Check")),
          Text("hello")
        ],
      ),
    );
  }

  Future<void> saveTests() async {
    DateTime now = DateTime.now();

    try {
      if (tName == '') {
        tName = "this is empty.";
      }

      if (testModel.id.isEmpty) {
        final querySnaphot = await myTest
            .where('testName', isEqualTo: tName)
            .where('testNote', isEqualTo: tNote)
            .get();

        if (querySnaphot.docs.isEmpty) {
          await myTest.add({
            'testName': tName,
            'testNote': tNote,
            'createdAt': now,
          });
        }
      }
    } catch (e) {
      throw Exception(e);
    }
  }
}
