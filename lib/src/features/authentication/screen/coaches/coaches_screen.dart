import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_room.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coaches App',
      home: CoachesScreen(),
    );
  }
}

class Coach {
  final String id;
  final String name;
  final String phone;
  final String bio;
  final String profilePic; // New field for profile picture URL
  final Color backgroundColor;

  Coach({
    required this.id,
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
      String userId = currentUser.uid; // Get the userId from FirebaseAuth

      try {
        // Fetch username from Firestore user document
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        if (userDoc.exists) {
          String username = userDoc.get('username') ?? 'Unknown User';

          // Use UID instead of username for Firestore document ID
          String documentId = '$userId-$formattedDate';

          // Try to launch the phone dialer
          if (await canLaunchUrl(url)) {
            await launchUrl(url);
            debugPrint("Dialer launched successfully");

            // Update or create Firestore document using UID instead of username
            await FirebaseFirestore.instance
                .collection('dailytracker')
                .doc(documentId)
                .set({
              'userId': userId, // Store userId
              'username': username, // Store username for display purposes
              'date': formattedDate,
              'call': true, // Mark 'call' as true
            }, SetOptions(merge: true));

            debugPrint(
                "Firestore updated successfully: 'call' field set to true");
          } else {
            debugPrint("Could not launch dialer");
          }
        } else {
          debugPrint("Error: User document not found for userId: $userId");
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
                  onPressed: () async {
                    Navigator.pop(context);
                    final currentUser = FirebaseAuth.instance.currentUser;
                    if (currentUser == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please log in first.')),
                      );
                      return;
                    }

                    String userName = 'User';
                    try {
                      final userDoc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .get();
                      final data = userDoc.data();
                      userName = (data?['username'] as String?)?.trim().isNotEmpty ==
                              true
                          ? (data!['username'] as String)
                          : (currentUser.email?.split('@').first ?? 'User');
                    } catch (_) {
                      userName = currentUser.email?.split('@').first ?? 'User';
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          coach: coach,
                          userId: currentUser.uid,
                          userName: userName,
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
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return Stream.value(const <Coach>[]);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .asyncMap((userSnapshot) async {
      final userData = userSnapshot.data();
      final coachId = (userData?['coachId'] as String?)?.trim() ?? '';
      if (coachId.isEmpty) {
        return <Coach>[];
      }

      final coachDoc = await FirebaseFirestore.instance
          .collection('coaches')
          .doc(coachId)
          .get();
      if (!coachDoc.exists) {
        return <Coach>[];
      }

      final data = coachDoc.data() ?? <String, dynamic>{};
      return [
        Coach(
          id: coachDoc.id,
          name: data['fullName'] ?? '',
          phone: data['phonenumber'] ?? '',
          bio: data['bio'] ?? '',
          profilePic: data['profilePic'] ?? '',
          backgroundColor: data['backgroundColor'] == 'green'
              ? const Color(0xFF90A17D)
              : const Color(0xFF6D849A),
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = context.isTabletWidth ? 320.0 : 220.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Coaches'),
      ),
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: context.responsiveValue(20),
                ),
                child: SizedBox(
                  height: heroHeight,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Image.asset(
                      'assets/images/coachpic.png',
                      width: context.isTabletWidth ? 520 : 320,
                      height: context.isTabletWidth ? 360 : 240,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(context.responsiveValue(16)),
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
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('No coach assigned to your account yet.'),
                      );
                    }

                    final query = _searchController.text.trim().toLowerCase();
                    final coaches = snapshot.data!.where((coach) {
                      if (query.isEmpty) return true;
                      return coach.name.toLowerCase().contains(query) ||
                          coach.bio.toLowerCase().contains(query) ||
                          coach.phone.toLowerCase().contains(query);
                    }).toList();

                    if (coaches.isEmpty) {
                      return const Center(
                        child: Text('No coaches match your search.'),
                      );
                    }

                    return ListView.builder(
                      padding: EdgeInsets.all(context.responsiveValue(16)),
                      itemCount: coaches.length,
                      itemBuilder: (context, index) {
                        final coach = coaches[index];
                        return Container(
                          margin: EdgeInsets.only(
                            bottom: context.responsiveValue(8),
                          ),
                          decoration: BoxDecoration(
                            color: coach.backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: context.responsiveValue(16),
                              vertical: context.responsiveValue(6),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: Colors.white,
                              backgroundImage: coach.profilePic.isNotEmpty
                                  ? NetworkImage(coach.profilePic)
                                  : null,
                              child: coach.profilePic.isEmpty
                                  ? const Icon(Icons.person, color: Colors.grey)
                                  : null,
                            ),
                            title: Text(
                              coach.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: context.responsiveFont(16),
                              ),
                            ),
                            subtitle: Text(
                              coach.bio,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: context.responsiveFont(13),
                              ),
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
      ),
    );
  }
}
