import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/viewalluser.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selfcare_projects/src/utils/phone_launcher.dart';

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
      home: AddCoachScreen(),
    );
  }
}

class Coach {
  final String fullname;
  final String phone;
  final String bio;
  final String profilePic; // New field for image URL
  final Color backgroundColor;

  Coach({
    required this.fullname,
    this.phone = '',
    this.bio = '',
    this.profilePic = '', // Default empty
    required this.backgroundColor,
  });
}

class CoachProfileDialog extends StatelessWidget {
  final Coach coach;

  const CoachProfileDialog({
    super.key,
    required this.coach,
  });

  Future<void> _launchDialer(BuildContext context, String phoneNumber) async {
    final normalizedPhoneNumber = normalizePhoneNumber(phoneNumber);
    if (normalizedPhoneNumber.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('This coach does not have a valid phone number yet.'),
        ),
      );
      return;
    }

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

          bool launched = false;
          try {
            launched = await launchPhoneNumber(normalizedPhoneNumber);
          } catch (e) {
            debugPrint("Error launching dialer: $e");
          }

          if (launched) {
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
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text(
                  "Couldn't open the dialer on this device. If you're using the iPhone simulator, the Phone app isn't available there.",
                ),
              ),
            );
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
              coach.fullname,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            GestureDetector(
              onTap: () {
                _launchDialer(
                    context,
                    coach
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
  User? _currentUser;
  bool _isAdmin = false;
  bool _isCoachUser = false;
  bool _isAuthorized = false;
  bool _isLoading = true;
  bool _coachProfileExists = false;

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
          fullname: data['fullName'] ?? '',
          phone: data['phonenumber'] ?? '',
          bio: data['bio'] ?? '',
          profilePic: data['profilePic'] ?? '', // Get profile picture URL
          backgroundColor: data['backgroundColor'] == 'green'
              ? const Color(0xFF90A17D)
              : const Color(0xFF6D849A),
        );
      }).toList();
    });
  }

  Future<void> _checkUserAccess() async {
    _currentUser = FirebaseAuth.instance.currentUser;

    if (_currentUser != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
      final data = userDoc.data() ?? {};
      final role = (data['role'] as String?)?.toLowerCase();
      final isCoach = data['isCoach'] == true || role == 'coach';

      _isAdmin = _currentUser!.uid == allowedUserUID;
      _isCoachUser = isCoach;
      _isAuthorized = _isAdmin || _isCoachUser;

      if (_isCoachUser) {
        final coachDoc = await FirebaseFirestore.instance
            .collection('coaches')
            .doc(_currentUser!.uid)
            .get();
        _coachProfileExists = coachDoc.exists;
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _showCoachProfileDialog() async {
    if (_currentUser == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .get();
    final userData = userDoc.data() ?? {};
    final existingCoachDoc = await FirebaseFirestore.instance
        .collection('coaches')
        .doc(_currentUser!.uid)
        .get();
    final coachData = existingCoachDoc.data() ?? {};

    final fullNameController = TextEditingController(
      text: (coachData['fullName'] as String?) ??
          (userData['username'] as String?) ??
          '',
    );
    final bioController = TextEditingController(
      text: (coachData['bio'] as String?) ?? '',
    );
    final phoneController = TextEditingController(
      text: (coachData['phonenumber'] as String?) ??
          (userData['number'] as String?) ??
          '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(_coachProfileExists
              ? 'Edit Coach Profile'
              : 'Create Coach Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bioController,
                decoration: InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (fullNameController.text.trim().isEmpty ||
                    bioController.text.trim().isEmpty ||
                    phoneController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All fields are required')),
                  );
                  return;
                }

                await FirebaseFirestore.instance
                    .collection('coaches')
                    .doc(_currentUser!.uid)
                    .set({
                  'userId': _currentUser!.uid,
                  'username': userData['username'] ?? '',
                  'email': userData['email'] ?? _currentUser!.email ?? '',
                  'fullName': fullNameController.text.trim(),
                  'bio': bioController.text.trim(),
                  'phonenumber': phoneController.text.trim(),
                  'profilePic': userData['profilePic'] ?? '',
                  'backgroundColor': coachData['backgroundColor'] ?? 'blue',
                  'createdAt':
                      coachData['createdAt'] ?? FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_currentUser!.uid)
                    .set({
                  'role': 'coach',
                  'isCoach': true,
                }, SetOptions(merge: true));

                setState(() {
                  _coachProfileExists = true;
                });

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _coachProfileExists
                          ? 'Coach profile updated successfully!'
                          : 'Coach profile created successfully!',
                    ),
                  ),
                );
              },
              child:
                  Text(_coachProfileExists ? 'Save Changes' : 'Create Profile'),
            ),
          ],
        );
      },
    );
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
      appBar: AppBar(
        title: const Text('Our Coaches'),
        actions: [
          if (_isCoachUser)
            IconButton(
              icon: const Icon(CupertinoIcons.person_crop_circle_badge_plus),
              onPressed: _showCoachProfileDialog,
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(CupertinoIcons.person_add),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ManageCoachesScreen()),
                );
              },
            ),
        ],
      ),
      floatingActionButton: null,
      body: SafeArea(
        child: Column(
          children: [
            if (_isCoachUser && !_coachProfileExists)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F4EE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF90A17D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Complete your coach profile',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add your full name, bio, and phone number so users can find you as a coach.',
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _showCoachProfileDialog,
                      child: const Text('Create Coach Profile'),
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
                            coach.fullname,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            coach.bio,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () => showDialog(
                            context: context,
                            builder: (context) =>
                                CoachProfileDialog(coach: coach),
                          ),
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
