import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  static const String userCancelledGoogleFlow = "__google_cancelled__";
  static const String userCancelledAppleFlow = "__apple_cancelled__";

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
    required bool termsAccepted,
  }) async {
    try {
      if (!termsAccepted) {
        return "You must accept the Terms and Conditions to create an account.";
      }
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
    required bool termsAccepted,
  }) async {
    try {
      if (!termsAccepted) {
        return "You must accept the Terms and Conditions to create an account.";
      }
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
        authProvider: 'google.com',
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

  Future<String?> signInWithApple() async {
    try {
      final user = await _authenticateWithApple();
      if (user == null) return userCancelledAppleFlow;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        await _createOrUpdateUserDocument(
          uid: user.uid,
          email: user.email ?? '',
          username: _fallbackUsername(user),
          number: '',
          role: 'user',
          emailVerified: true,
          photoUrl: user.photoURL,
          authProvider: 'apple.com',
        );
      }

      return null;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return userCancelledAppleFlow;
      }
      return e.message;
    } on SignInWithAppleNotSupportedException {
      return "Sign in with Apple is not available on this device.";
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        return "Account already exists with a different sign-in method.";
      }
      return e.message ?? "Apple sign-in failed.";
    } catch (e) {
      debugPrint('Apple sign-in failed: $e');
      return "Apple sign-in failed. Please try again.";
    }
  }

  Future<String?> signUpWithApple({
    required String role,
    required bool termsAccepted,
  }) async {
    try {
      if (!termsAccepted) {
        return "You must accept the Terms and Conditions to create an account.";
      }

      final user = await _authenticateWithApple();
      if (user == null) return userCancelledAppleFlow;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        await _auth.signOut();
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
        authProvider: 'apple.com',
      );

      return null;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return userCancelledAppleFlow;
      }
      return e.message;
    } on SignInWithAppleNotSupportedException {
      return "Sign in with Apple is not available on this device.";
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        return "Account already exists with a different sign-in method.";
      }
      return e.message ?? "Apple sign-up failed.";
    } catch (e) {
      debugPrint('Apple sign-up failed: $e');
      return "Apple sign-up failed. Please try again.";
    }
  }

  Future<void> signOutGoogle() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<void> deleteCurrentUserAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No user signed in.',
      );
    }

    await _reauthenticateForDeletion(user, password: password);
    await _deleteUserData(user.uid);
    await user.delete();
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

  Future<User?> _authenticateWithApple() async {
    final appleAuth = await _getAppleAuthCredential();
    final userCredential =
        await _auth.signInWithCredential(appleAuth.credential);
    final user = userCredential.user;

    if (user != null &&
        appleAuth.fullName.isNotEmpty &&
        (user.displayName?.trim().isEmpty ?? true)) {
      await user.updateDisplayName(appleAuth.fullName);
      await user.reload();
    }

    return _auth.currentUser ?? userCredential.user;
  }

  Future<_AppleAuthCredential> _getAppleAuthCredential() async {
    final rawNonce = generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final identityToken = appleCredential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw StateError('Apple identity token is missing.');
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: identityToken,
      rawNonce: rawNonce,
    );

    final fullNameParts = [
      appleCredential.givenName?.trim(),
      appleCredential.familyName?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    final fullName = fullNameParts.join(' ').trim();

    return _AppleAuthCredential(
      credential: oauthCredential,
      fullName: fullName,
    );
  }

  Future<void> _reauthenticateForDeletion(
    User user, {
    String? password,
  }) async {
    final providerIds =
        user.providerData.map((provider) => provider.providerId).toSet();

    if (providerIds.contains('apple.com')) {
      final appleAuth = await _getAppleAuthCredential();
      await user.reauthenticateWithCredential(appleAuth.credential);
      return;
    }

    if (providerIds.contains('google.com')) {
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'reauth-cancelled',
          message: 'Google confirmation was cancelled.',
        );
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (user.email != null && (password?.trim().isNotEmpty ?? false)) {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password!.trim(),
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    throw FirebaseAuthException(
      code: 'password-required',
      message: 'Enter your password to confirm account deletion.',
    );
  }

  Future<void> _deleteUserData(String uid) async {
    await _deleteCollectionDocs(
      _firestore.collection('users').doc(uid).collection('tasks'),
    );
    await _deleteCollectionDocs(
      _firestore.collection('users').doc(uid).collection('walkInvites'),
    );
    await _deleteCollectionDocs(
      _firestore.collection('users').doc(uid).collection('recorded_walks'),
    );
    await _deleteCollectionDocs(
      _firestore.collection('steps').doc(uid).collection('tracking'),
    );

    await Future.wait([
      _deleteTopLevelDocsByField('notes', 'userId', uid),
      _deleteTopLevelDocsByField('dailytracker', 'userId', uid),
      _deleteTopLevelDocsByField('emotions', 'userId', uid),
      _deleteTopLevelDocsByField('userpoints', 'userId', uid),
      _deleteTopLevelDocsByField('walk_sessions', 'createdBy', uid),
    ]);

    final batch = _firestore.batch();
    batch.delete(_firestore.collection('users').doc(uid));
    batch.delete(_firestore.collection('coaches').doc(uid));
    batch.delete(_firestore.collection('steps').doc(uid));
    await batch.commit();
  }

  Future<void> _deleteTopLevelDocsByField(
    String collection,
    String field,
    String value,
  ) async {
    final snapshot = await _firestore
        .collection(collection)
        .where(field, isEqualTo: value)
        .limit(450)
        .get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _deleteCollectionDocs(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.limit(450).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> _createOrUpdateUserDocument({
    required String uid,
    required String email,
    required String username,
    required String number,
    required String role,
    required bool emailVerified,
    String? photoUrl,
    String? authProvider,
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
      if (authProvider != null) "authProvider": authProvider,
      "termsAccepted": true,
      "termsVersion": "2026-05-05",
      "termsAcceptedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _fallbackUsername(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email.split('@').first;

    return 'Apple User';
  }
}

class _AppleAuthCredential {
  const _AppleAuthCredential({
    required this.credential,
    required this.fullName,
  });

  final OAuthCredential credential;
  final String fullName;
}
