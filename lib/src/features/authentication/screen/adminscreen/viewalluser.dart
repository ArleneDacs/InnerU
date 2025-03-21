import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageCoachesScreen extends StatefulWidget {
  @override
  _ManageCoachesScreenState createState() => _ManageCoachesScreenState();
}

class _ManageCoachesScreenState extends State<ManageCoachesScreen> {
  final CollectionReference usersCollection =
      FirebaseFirestore.instance.collection('users');
  final CollectionReference coachesCollection =
      FirebaseFirestore.instance.collection('coaches');

  Future<void> setAsCoach(String userId, String userName, String email,
      String fullName, String bio, String phonenumber) async {
    try {
      // Fetch user's profile picture
      final userDoc = await usersCollection.doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>?;

      if (userData == null) {
        throw Exception("User data not found.");
      }

      final profilePic = userData['profilePic'] ?? '';

      // Save user as a coach in the 'coaches' collection
      await coachesCollection.doc(userId).set({
        'userId': userId,
        'username': userName,
        'email': email,
        'fullName': fullName,
        'bio': bio,
        'phonenumber': phonenumber,
        'profilePic': profilePic, // Ensuring it's stored correctly
        'backgroundColor': 'blue', // Assigning default background color
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update the user’s document in the 'users' collection
      await usersCollection.doc(userId).update({'isCoach': true});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User successfully set as coach!')),
      );

      setState(() {}); // Refresh the UI if needed
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error setting user as coach: $e')),
      );
    }
  }

  Future<void> showAddCoachDialog(BuildContext context, String userId,
      String userName, String email) async {
    final TextEditingController fullNameController = TextEditingController();
    final TextEditingController bioController = TextEditingController();
    final TextEditingController phonenumberController = TextEditingController();

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add Full Name, Bio, and Phone Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: fullNameController,
                decoration: InputDecoration(labelText: 'Full Name'),
              ),
              TextField(
                controller: bioController,
                decoration: InputDecoration(labelText: 'Bio'),
              ),
              TextField(
                controller: phonenumberController,
                decoration: InputDecoration(labelText: 'Phone Number'),
              ),
            ],
          ),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () {
                if (fullNameController.text.isNotEmpty &&
                    bioController.text.isNotEmpty &&
                    phonenumberController.text.isNotEmpty) {
                  setAsCoach(userId, userName, email, fullNameController.text,
                      bioController.text, phonenumberController.text);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('All fields are required')),
                  );
                }
              },
              child: Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Coaches'),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: usersCollection.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error fetching users.'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No users found.'));
          }

          final users = snapshot.data!.docs.where((user) {
            final data = user.data() as Map<String, dynamic>;
            return data['isCoach'] != true;
          }).toList();

          if (users.isEmpty) {
            return Center(
              child: Text('No users available to assign as coaches.'),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user.id;
              final data = user.data() as Map<String, dynamic>;
              final userName = data['username'] ?? 'Unknown User';
              final email = data['email'] ?? 'No Email';
              final profilePic = data['profilePic'] ?? '';

              return ListTile(
                leading: profilePic.isNotEmpty
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(profilePic),
                        radius: 25,
                      )
                    : Icon(Icons.person, size: 50),
                title: Text(userName),
                subtitle: Text('User'),
                trailing: ElevatedButton(
                  onPressed: () =>
                      showAddCoachDialog(context, userId, userName, email),
                  child: Text('Set as Coach'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
