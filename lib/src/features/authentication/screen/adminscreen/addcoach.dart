import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/chat_room.dart';
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
      home: AddCoachScreen(),
    );
  }
}

class Coach {
  final String name;
  final String phone;
  final String bio;
  final Color backgroundColor;

  Coach({
    required this.name,
    this.phone = '',
    this.bio = '',
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
                  },
                ),
              ],
            ),
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.grey,
              ),
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

class AddCoachScreen extends StatefulWidget {
  const AddCoachScreen({super.key});

  @override
  State<AddCoachScreen> createState() => _AddCoachScreenState();
}

class _AddCoachScreenState extends State<AddCoachScreen> {
  late TextEditingController _searchController;
  final String allowedUserUID =
      "hG1FxGW2xrVXtKZnnDWERJpPQof2"; // Replace with the actual UID
  bool _isAuthorized = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _checkUserAccess();
  }

  Stream<List<Coach>> getCoachesStream() {
    return FirebaseFirestore.instance
        .collection('coaches')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Coach(
          name: data['name'] ?? '',
          phone: data['phone'] ?? '',
          bio: data['bio'] ?? '',
          backgroundColor: data['backgroundColor'] == 'green'
              ? const Color(0xFF90A17D)
              : const Color(0xFF6D849A),
        );
      }).toList();
    });
  }

  Future<void> _checkUserAccess() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && currentUser.uid == allowedUserUID) {
      setState(() {
        _isAuthorized = true;
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthorized) {
      return const Scaffold(
        body: Center(
          child: Text(
            "Access Denied",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.arrow_left),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Our Coaches',
                    style: TextStyle(fontSize: 24),
                  ),
                ],
              ),
            ),
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
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No coaches available.'));
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
                          leading: const CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.person, color: Colors.grey),
                          ),
                          title: Text(
                            coach.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AddCoachDialog(
              onCoachAdded: (coach) {
                setState(() {
                  // Optionally update local state
                });
              },
              currentCoachCount: 0, // This can be replaced with a real count
            ),
          );
        },
        backgroundColor: const Color(0xFFEFD199),
        shape: const CircleBorder(),
        child: const Icon(CupertinoIcons.add, size: 30, color: Colors.white),
      ),
    );
  }
}

class AddCoachDialog extends StatefulWidget {
  final Function(Coach) onCoachAdded;
  final int currentCoachCount;

  const AddCoachDialog({
    super.key,
    required this.onCoachAdded,
    required this.currentCoachCount,
  });

  @override
  State<AddCoachDialog> createState() => _AddCoachDialogState();
}

class _AddCoachDialogState extends State<AddCoachDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isMale = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                const Text(
                  'Add a Coach',
                  style: TextStyle(
                    fontSize: 20,
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Image.asset(
                  'assets/images/star1.png',
                  width: 25,
                  height: 25,
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Full Name',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Bio Description',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Gender:'),
                Radio(
                  value: true,
                  groupValue: _isMale,
                  onChanged: (bool? value) {
                    setState(() {
                      _isMale = value!;
                    });
                  },
                ),
                const Text('Male'),
                Radio(
                  value: false,
                  groupValue: _isMale,
                  onChanged: (bool? value) {
                    setState(() {
                      _isMale = value!;
                    });
                  },
                ),
                const Text('Female'),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (_nameController.text.isNotEmpty) {
                  final isEven = widget.currentCoachCount.isEven;
                  Coach newCoach = Coach(
                    name: _nameController.text,
                    bio: _descriptionController.text,
                    backgroundColor: isEven
                        ? const Color(0xFF90A17D)
                        : const Color(0xFF6D849A),
                  );

                  // Add to Firestore
                  await FirebaseFirestore.instance.collection('coaches').add({
                    'name': newCoach.name,
                    'bio': newCoach.bio,
                    'backgroundColor': isEven ? 'green' : 'blue',
                  });

                  widget.onCoachAdded(newCoach);
                  Navigator.of(context).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEFD199),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                minimumSize: const Size(200, 50),
              ),
              child: const Text(
                'ADD',
                style: TextStyle(
                  fontSize: 22,
                  color: Color(0xFF6D849A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
