import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_room.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coaches App',
      home: CoachesScreen(),
    );
  }
}

class Coach {
  final String name;
  final String phone;
  final String bio;
  final String profilePic; // New field for profile picture URL
  final Color backgroundColor;

  Coach({
    required this.name,
    this.phone = '',
    this.bio = '',
    this.profilePic = '', // Default empty if no image
    required this.backgroundColor,
  });
}

class CoachProfileDialog extends StatelessWidget {
  final Coach coach;

  const CoachProfileDialog({
    super.key,
    required this.coach,
  });

  void _launchDialer(String phoneNumber) async {
    final Uri url = Uri(scheme: 'tel', path: phoneNumber);

    // Get current date dynamically in the format 'yyyy-MM-dd'
    String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Get the current logged-in user from FirebaseAuth
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      String userId = currentUser.uid; // Get the userId from the Firebase user

      try {
        // Fetch username from Firestore user document
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        String? username = userDoc.get('username');

        if (username != null) {
          String documentId =
              '$username-$formattedDate'; // Firestore document ID

          // Try to launch the phone dialer
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
            debugPrint("Dialer launched successfully");

            // Update or create Firestore document for the current user and date
            try {
              await FirebaseFirestore.instance
                  .collection('dailytracker')
                  .doc(documentId)
                  .set({
                'username': username,
                'date': formattedDate,
                'call': true, // Set 'call' field to true
              }, SetOptions(merge: true));

              debugPrint(
                  "Firestore updated successfully: 'call' field set to true");
            } catch (e) {
              debugPrint("Error updating Firestore: $e");
            }
          } else {
            debugPrint("Could not launch dialer");
          }
        } else {
          debugPrint("Error: Username not found for userId: $userId");
        }
      } catch (e) {
        debugPrint("Error fetching user data: $e");
      }
    } else {
      debugPrint("No user logged in");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: coach.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.arrow_left,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.chat_bubble_2_fill,
                    size: 30,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          coach: coach,
                          userId: 'user_123', // Replace with dynamic user ID
                          userName:
                              'Current User', // Replace with dynamic username
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              backgroundImage: coach.profilePic.isNotEmpty
                  ? NetworkImage(coach.profilePic)
                  : null,
              child: coach.profilePic.isEmpty
                  ? const Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.grey,
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            Text(
              coach.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            GestureDetector(
              onTap: () {
                _launchDialer(coach
                    .phone); // Call the launcher with the coach's phone number
              },
              child: Text(
                coach.phone.isNotEmpty ? coach.phone : 'No phone available',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  decoration: TextDecoration.underline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Bio:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                coach.bio.isEmpty ? 'No bio available' : coach.bio,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachesScreen extends StatefulWidget {
  const CoachesScreen({super.key});

  @override
  State<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> {
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<Coach>> getCoachesStream() {
    return FirebaseFirestore.instance
        .collection('coaches')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Coach(
          name: data['fullName'] ?? '',
          phone: data['phonenumber'] ?? '',
          bio: data['bio'] ?? '',
          profilePic: data['profilePic'] ?? '', // Fetch profile picture URL
          backgroundColor: data['backgroundColor'] == 'green'
              ? const Color(0xFF90A17D)
              : const Color(0xFF6D849A),
        );
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Coaches'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: SizedBox(
                height: 280,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.asset(
                    'assets/images/coachpic.png',
                    width: 400,
                    height: 300,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search',
                  filled: true,
                  fillColor: Colors.grey.shade200,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Coach>>(
                stream: getCoachesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text('No coaches available.'));
                  }

                  final coaches = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: coaches.length,
                    itemBuilder: (context, index) {
                      final coach = coaches[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        decoration: BoxDecoration(
                          color: coach.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white,
                            backgroundImage: coach.profilePic.isNotEmpty
                                ? NetworkImage(
                                    coach.profilePic) // Load image from URL
                                : null,
                            child: coach.profilePic.isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.grey) // Default icon
                                : null,
                          ),
                          title: Text(
                            coach.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            coach.bio,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  CoachProfileDialog(coach: coach),
                            );
                          },
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
