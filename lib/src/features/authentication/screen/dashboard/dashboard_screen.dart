import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String quote = "Your daily inspiration...";
  String author = "Unknown";
  String? selectedEmotion; // ✅ Declared at the class level
  String? currentUserEmotion; // Emotion for the current user
  String? _base64Image;

  @override
  void initState() {
    UserService.getUserData().then((data) => setState(() {
          _base64Image = data["profilePic"];
        }));
    super.initState();
    fetchQuote();
    _loadTodayEmotion(); // Load the emotion for the current user when the app starts
  }

  selectEmotion(String emotion) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String username = await _getUsername(); // Fetch username before saving

    setState(() {
      selectedEmotion = emotion;
    });

    _saveEmotionToDatabase(context, emotion, username); // Pass username
    _saveEmotionToSharedPreferences(emotion);
  }

  Future<void> _saveEmotionToSharedPreferences(String emotion) async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Save emotion with the key as the user's UID to make it specific to the user
    prefs.setString('selected_emotion_${user.uid}', emotion);
    prefs.setString('emotion_date_${user.uid}',
        DateTime.now().toString().split(' ')[0]); // Save today's date
  }

  Future<void> _loadTodayEmotion() async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Load the saved emotion for the current user using the UID as the key
    String? savedEmotion = prefs.getString('selected_emotion_${user.uid}');
    String? savedDate = prefs.getString('emotion_date_${user.uid}');
    String today = DateTime.now().toString().split(' ')[0]; // Get today's date

    if (savedEmotion != null && savedDate == today) {
      // If emotion is logged today, show it
      setState(() {
        currentUserEmotion = savedEmotion; // Load saved emotion for this user
      });
    } else {
      // If no emotion for today, show the picker
      setState(() {
        currentUserEmotion = null; // Clear the emotion display, show the picker
      });
    }
  }

  Future<void> _clearEmotionOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Clear the saved emotion for the current user
    prefs.remove('selected_emotion_${user.uid}');
    prefs.remove('emotion_date_${user.uid}');
    setState(() {
      currentUserEmotion = null; // Reset the selected emotion
    });
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Future<String> _getUsername() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return "User";

    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    return userDoc.exists ? userDoc["username"] ?? "User" : "User";
  }

  Future<void> fetchQuote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedQuote = prefs.getString('quote');
      String? savedAuthor = prefs.getString('author');
      String? savedDate = prefs.getString('quote_date');

      String today = DateTime.now().toString().split(' ')[0];

      if (savedQuote != null && savedAuthor != null && savedDate == today) {
        setState(() {
          quote = savedQuote;
          author = savedAuthor;
        });
        return;
      }

      final response =
          await http.get(Uri.parse("https://zenquotes.io/api/random"));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        String newQuote = data[0]['q'] ?? "No quote available.";
        String newAuthor = data[0]['a'] ?? "Unknown";

        setState(() {
          quote = newQuote;
          author = newAuthor;
        });

        prefs.setString('quote', newQuote);
        prefs.setString('author', newAuthor);
        prefs.setString('quote_date', today);
      } else {
        setState(() {
          quote = "Failed to load quote.";
          author = "Unknown";
        });
      }
    } catch (e) {
      print("Error fetching quote: $e");
      setState(() {
        quote = "Failed to load quote.";
        author = "Unknown";
      });
    }
  }

  Future<void> _saveEmotionToDatabase(
      BuildContext context, String emotion, String username) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String today = DateTime.now().toString().split(' ')[0];

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection("emotions")
          .where("userId", isEqualTo: user.uid)
          .where("username", isEqualTo: username)
          .where("date", isEqualTo: today)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Emotion already recorded today
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("You can only select one emotion per day!")),
        );
        return;
      }

      await FirebaseFirestore.instance.collection("emotions").add({
        "userId": user.uid,
        "username": username.isNotEmpty ? username : "Unknown",
        "emotion": emotion,
        "date": today,
      });

      if (mounted) {
        setState(() {
          selectedEmotion = emotion;
        });
      }

      print("Emotion saved successfully.");
    } catch (e) {
      print("Error saving emotion: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save emotion. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double containerWidth = screenWidth * 0.90;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: _base64Image == null
              ? Image.asset(
                  'assets/images/avatar.png', // Default image if no profilePic is available
                  width: screenWidth * 0.08, // Adjust size as needed
                  height: screenWidth * 0.08,
                )
              : ClipOval(
                  child: Image.memory(
                    base64Decode(
                        _base64Image!), // Decode the base64 string to display the image
                    width: screenWidth * 0.08, // Adjust size as needed
                    height: screenWidth * 0.08,
                    fit: BoxFit.cover,
                  ),
                ),
          onPressed: () => Navigator.pushNamed(context, '/profile'),
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.line_horizontal_3, size: 28),
            onPressed: () {
              BottomSheetWidget.show(context);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              // FutureBuilder for the username
              future: _getUsername(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  UserPreferences.saveUsername(snapshot.data!);
                }
                return Text(
                  snapshot.connectionState == ConnectionState.waiting
                      ? "Loading..."
                      : "Hello, ${snapshot.data}!",
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .copyWith(fontSize: 25),
                );
              },
            ),
            SizedBox(height: 20),
            _buildCardContainer(
              height: 120,
              content: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _buildSectionTitle("Quote of the Day"),
                  SizedBox(height: 8),
                  Text(
                    '"$quote" - $author',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoCard("Steps", "2k", CupertinoIcons.flame_fill,
                    Colors.brown.shade300),
                _buildInfoCard("Meditation", "40%", CupertinoIcons.hourglass,
                    Colors.green.shade400),
              ],
            ),
            SizedBox(height: 20),
            _buildSectionTitle("Today's Coach"),
            _buildCardContainer(
              height: 120,
              content: Text("Maychell Alcorin\nCEO of Valenin, Life Coach",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            SizedBox(height: 10),
            _buildSectionTitle("How do you feel today?"),
            SizedBox(height: 10),
            currentUserEmotion == null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () => selectEmotion("happy"),
                        child: Text("😀", style: TextStyle(fontSize: 36)),
                      ),
                      GestureDetector(
                        onTap: () => selectEmotion("neutral"),
                        child: Text("😐", style: TextStyle(fontSize: 36)),
                      ),
                      GestureDetector(
                        onTap: () => selectEmotion("sad"),
                        child: Text("😔", style: TextStyle(fontSize: 36)),
                      ),
                      GestureDetector(
                        onTap: () => selectEmotion("angry"),
                        child: Text("😡", style: TextStyle(fontSize: 36)),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Text(
                        "Today I'm feeling $currentUserEmotion",
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 20),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => EmotionTrackerPage()),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Track Your Emotions",
                              style:
                                  TextStyle(fontSize: 14, color: Colors.blue),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios,
                                size: 14, color: Colors.blue),
                          ],
                        ),
                      )
                    ],
                  ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

Widget _buildInfoCard(String title, String data, IconData icon, Color color) {
  return Container(
    width: 150,
    height: 100,
    decoration:
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white),
              SizedBox(height: 10),
              Text(data,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _buildCardContainer({required double height, required Widget content}) {
  return Container(
    height: height,
    width: double.infinity,
    decoration: BoxDecoration(
        color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
    child: Center(child: content),
  );
}
