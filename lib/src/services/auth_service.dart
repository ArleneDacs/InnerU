import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sign up a user and send email verification
  Future<String?> signUpUser({
    required String username,
    required String email,
    required String password,
    required String number,
    required String retypepassword,
  }) async {
    try {
      var result = await _auth.fetchSignInMethodsForEmail(email);
      if (result.isNotEmpty) return "This email is already in use.";

      // Create user with email and password
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      // Send email verification
      await userCredential.user!.sendEmailVerification();

      String uid = userCredential.user!.uid;

      // Add user details to Firestore
      await _firestore.collection("users").doc(uid).set({
        "username": username,
        "email": email,
        "number": number,
        "uid": uid,
        "emailVerified": false, // Initially false until verified
        "createdAt": DateTime.now(),
      });

      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') return "Weak password!";
      if (e.code == 'invalid-email') return "Invalid email!";
      if (e.code == 'email-already-in-use') return "Email already in use!";
      return e.message ?? "Signup failed.";
    } catch (e) {
      return e.toString();
    }
  }

  // Update email verification status in Firestore
  Future<void> updateEmailVerificationStatus() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await user.reload(); // Refresh user data from Firebase
      if (user.emailVerified) {
        // Update the user's email verification status in Firestore
        await _firestore.collection('users').doc(user.uid).update({
          'emailVerified': true,
        });
      }
    }
  }
}
