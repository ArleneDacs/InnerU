import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String quote = "Your daily inspiration...";
  String author = "Unknown";
  String? selectedEmotion;
  String? currentUserEmotion;
  String? _base64Image;

  @override
  void initState() {
    UserService.getUserData().then((data) => setState(() {
          _base64Image = data["profilePic"];
        }));
    super.initState();
    fetchQuote();
    _loadTodayEmotion();
  }

  selectEmotion(String emotion) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String username = await _getUsername();

    setState(() {
      selectedEmotion = emotion;
      currentUserEmotion = emotion; // Immediately update the current emotion
    });

    _saveEmotionToDatabase(context, emotion, username);
    _saveEmotionToSharedPreferences(emotion);
  }

  Future<void> _saveEmotionToSharedPreferences(String emotion) async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    prefs.setString('selected_emotion_${user.uid}', emotion);
    prefs.setString(
        'emotion_date_${user.uid}', DateTime.now().toString().split(' ')[0]);
  }

  Future<void> _loadTodayEmotion() async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? savedEmotion = prefs.getString('selected_emotion_${user.uid}');
    String? savedDate = prefs.getString('emotion_date_${user.uid}');
    String today = DateTime.now().toString().split(' ')[0];

    if (savedEmotion != null && savedDate == today) {
      setState(() {
        currentUserEmotion = savedEmotion;
      });
    } else {
      setState(() {
        currentUserEmotion = null;
      });
    }
  }

  Future<void> _clearEmotionOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    prefs.remove('selected_emotion_${user.uid}');
    prefs.remove('emotion_date_${user.uid}');
    setState(() {
      currentUserEmotion = null;
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

    // Check if the username exists, if not, extract the first part of the email
    if (userDoc.exists && userDoc["username"] != null) {
      return userDoc["username"];
    } else if (user.email != null) {
      String email = user.email!;
      String fallbackName = email.split('@')[0]; // Get the part before '@'
      return fallbackName;
    }

    return "User";
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

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: _base64Image == null
              ? Image.asset(
                  'assets/images/avatar.png', // Default image if no profilePic is available
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                )
              : ClipOval(
                  child: Image.memory(
                    base64Decode(
                        _base64Image!), // Decode the base64 string to display the image
                    width: screenWidth * 0.08,
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
        padding: EdgeInsets.only(left: 16.0, right: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Hello, User" - Positioned Above the Image
            SizedBox(height: kToolbarHeight - 50.0),
            FutureBuilder<String>(
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
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        fontSize: 25,
                      ),
                );
              },
            ),

            SizedBox(
                height: 10), // Adjust space so the quote overlaps the image

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center, // Aligns left
                children: [
                  Text(
                    "\"$quote\"",
                    style: TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "- $author",
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /* _buildSectionTitle("Recommended for you"),*/
                      SizedBox(height: 12), // Space between title and cards
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Flexible(
                            child: _buildClickableInfoCard(
                              context,
                              "Steps",
                              "Track your Steps",
                              CupertinoIcons.flame_fill,
                              Color.fromARGB(255, 216, 220, 206),
                              "assets/images/steps.gif",
                              StepTracker(),
                            ),
                          ),
                          SizedBox(width: 12), // Space between cards
                          Flexible(
                            child: _buildClickableInfoCard(
                              context,
                              "Meditate",
                              "Clear your Mind",
                              CupertinoIcons.hourglass,
                              Color.fromARGB(255, 226, 223, 215),
                              "assets/images/meditation.gif",
                              Meditation(),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 20),
                      _buildSectionTitle("Today's Coach"),
                      Container(
                        padding: EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.white, // Background color
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              spreadRadius: 2,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildCoachCard(
                              context,
                              "Maychell Alcorin",
                              "CEO of Valenin, Life Coach",
                            ),

                            // Top Left Star
                            Positioned(
                              top: -10,
                              left: -10,
                              child: Icon(Icons.star,
                                  size: 24, color: Colors.lightBlueAccent),
                            ),

                            // Bottom Right Star
                            Positioned(
                              bottom: -10,
                              right: -10,
                              child: Icon(Icons.star,
                                  size: 24, color: Colors.orangeAccent),
                            ),
                          ],
                        ),
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
                                  child: Text("😀",
                                      style: TextStyle(fontSize: 36)),
                                ),
                                GestureDetector(
                                  onTap: () => selectEmotion("neutral"),
                                  child: Text("😐",
                                      style: TextStyle(fontSize: 36)),
                                ),
                                GestureDetector(
                                  onTap: () => selectEmotion("sad"),
                                  child: Text("😔",
                                      style: TextStyle(fontSize: 36)),
                                ),
                                GestureDetector(
                                  onTap: () => selectEmotion("angry"),
                                  child: Text("😡",
                                      style: TextStyle(fontSize: 36)),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Text(
                                  "Today I'm feeling $currentUserEmotion", // Display the selected emotion
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 20),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              EmotionTrackerPage()),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "Track Your Emotions",
                                        style: TextStyle(
                                            fontSize: 14, color: Colors.blue),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.arrow_forward_ios,
                                          size: 14, color: Colors.blue),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                      SizedBox(height: 20),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableInfoCard(
      BuildContext context,
      String title,
      String description,
      IconData icon,
      Color color,
      String imagePath,
      Widget destinationPage) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    Color textColor = isDarkMode ? Colors.white : Colors.black;
    Color iconColor = isDarkMode ? Colors.white : Colors.black54;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => destinationPage),
        );
      },
      child: Container(
        width: 160,
        height: 195,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          image: DecorationImage(
            image: AssetImage(imagePath),
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(icon, color: iconColor, size: 20),
              SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
              SizedBox(height: 2),
              Text(
                description,
                style:
                    TextStyle(fontSize: 12, color: textColor.withOpacity(0.7)),
              ),
              SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoachCard(
      BuildContext context, String coachName, String coachTitle) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Profile Image
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.black,
            child: Icon(Icons.person, size: 40, color: Colors.white),
          ),
          SizedBox(width: 12),
          // Name and Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                coachName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                coachTitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardContainer(
      {required BuildContext context,
      required double height,
      required Widget content}) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.grey[800]
            : const Color.fromARGB(255, 240, 247, 237),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: DefaultTextStyle(
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black, // Adapt text color
          ),
          child: content,
        ),
      ),
    );
  }
}
