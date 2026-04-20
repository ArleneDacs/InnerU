import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageCoachesScreen extends StatefulWidget {
  const ManageCoachesScreen({super.key});

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
      final userDoc = await usersCollection.doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>?;

      if (userData == null) {
        throw Exception("User data not found.");
      }

      final profilePic = userData['profilePic'] ?? '';

      await coachesCollection.doc(userId).set({
        'userId': userId,
        'username': userName,
        'email': email,
        'fullName': fullName,
        'bio': bio,
        'phonenumber': phonenumber,
        'profilePic': profilePic,
        'backgroundColor': 'blue',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await usersCollection.doc(userId).update({'isCoach': true});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User successfully set as coach!')),
      );

      setState(() {});
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text('Add Full Name, Bio, and Phone Number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: fullNameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: bioController,
                decoration: InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              SizedBox(height: 10),
              TextField(
                controller: phonenumberController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color.fromARGB(255, 255, 255, 255),
                const Color.fromARGB(255, 255, 255, 255)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
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
            padding: EdgeInsets.all(10),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user.id;
              final data = user.data() as Map<String, dynamic>;
              final userName = data['username'] ?? 'Unknown User';
              final email = data['email'] ?? 'No Email';
              final profilePic = data['profilePic'] ?? '';

              return Card(
                margin: EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
                child: ListTile(
                  leading: profilePic.isNotEmpty
                      ? CircleAvatar(
                          backgroundImage: NetworkImage(profilePic),
                          radius: 30,
                        )
                      : Icon(Icons.person, size: 50),
                  title: Text(
                    userName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18, // Reduced font size for the name
                    ),
                  ),
                  subtitle: Text(
                    email,
                    style: TextStyle(
                      fontSize: 15, // Set the font size here
                    ),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF589675),
                      padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical:
                              7), // Adjust the padding for a smaller button
                      minimumSize: Size(50,
                          40), // Smaller button size (smaller width and height)
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        showAddCoachDialog(context, userId, userName, email),
                    child: Text('Set as Coach',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                        )),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
