import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign Up User
  Future<String?> signUpUser({
    required String username,
    required String email,
    required String password,
    required String number,
  }) async {
    try {
      // Check if email is already in use
      var result = await _auth.fetchSignInMethodsForEmail(email);
      if (result.isNotEmpty) {
        return "This email is already in use. Try logging in.";
      }

      // Create user in Firebase Auth
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Get user ID
      String uid = userCredential.user!.uid;

      // Save user data in Firestore
      await _firestore.collection("users").doc(uid).set({
        "username": username,
        "email": email,
        "number": number,
        "uid": uid,
        "createdAt": DateTime.now(),
      });

      return null; // No error
    } catch (e) {
      return e.toString(); // Return error message
    }
  }
}

