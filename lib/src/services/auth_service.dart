import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static const String userCancelledGoogleFlow = "__google_cancelled__";

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  Future<String?> signUpUser({
    required String username,
    required String email,
    required String password,
    required String number,
    required String retypepassword,
    required String role,
  }) async {
    try {
      final result = await _auth.fetchSignInMethodsForEmail(email);
      if (result.isNotEmpty) return "This email is already in use.";
      if (password != retypepassword) return "Passwords do not match.";

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user!.sendEmailVerification();

      final uid = userCredential.user!.uid;
      await _createOrUpdateUserDocument(
        uid: uid,
        email: email,
        username: username,
        number: number,
        role: role,
        emailVerified: false,
      );

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

  Future<String?> signInWithGoogle() async {
    try {
      final user = await _authenticateWithGoogle();
      if (user == null) return userCancelledGoogleFlow;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await signOutGoogle();
        return "No account found. Please sign up first.";
      }

      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        return "Account already exists with a different sign-in method.";
      }
      return e.message ?? "Google sign-in failed.";
    } catch (e) {
      return "Google sign-in failed. Please try again.";
    }
  }

  Future<String?> signUpWithGoogle({
    required String role,
  }) async {
    try {
      final user = await _authenticateWithGoogle();
      if (user == null) return userCancelledGoogleFlow;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        await signOutGoogle();
        return "Account already used. Please login instead.";
      }

      final fallbackName = (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? 'User');

      await _createOrUpdateUserDocument(
        uid: user.uid,
        email: user.email ?? '',
        username: fallbackName,
        number: '',
        role: role,
        emailVerified: true,
        photoUrl: user.photoURL,
      );

      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        return "Account already exists with a different sign-in method.";
      }
      return e.message ?? "Google sign-up failed.";
    } catch (e) {
      return "Google sign-up failed. Please try again.";
    }
  }

  Future<void> signOutGoogle() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<void> updateEmailVerificationStatus() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      await user.reload();
      user = FirebaseAuth.instance.currentUser;
      if (user != null && user.emailVerified) {
        await _firestore.collection('users').doc(user.uid).update({
          'emailVerified': true,
        });
      }
    }
  }

  Future<User?> _authenticateWithGoogle() async {
    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      final userCredential = await _auth.signInWithPopup(googleProvider);
      return userCredential.user;
    }

    await _googleSignIn.signOut();
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    return userCredential.user;
  }

  Future<void> _createOrUpdateUserDocument({
    required String uid,
    required String email,
    required String username,
    required String number,
    required String role,
    required bool emailVerified,
    String? photoUrl,
  }) async {
    await _firestore.collection("users").doc(uid).set({
      "username": username,
      "email": email,
      "number": number,
      "uid": uid,
      "role": role,
      "isCoach": role == 'coach',
      "emailVerified": emailVerified,
      "photoURL": photoUrl,
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
