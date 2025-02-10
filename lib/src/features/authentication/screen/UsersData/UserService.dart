import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final _auth = FirebaseAuth.instance;
  static final _firestore = FirebaseFirestore.instance;

  static Future<Map<String, dynamic>> getUserData() async {
    var user = _auth.currentUser;
    if (user == null) return {};

    var doc = await _firestore.collection("users").doc(user.uid).get();
    return doc.exists ? doc.data() ?? {} : {};
  }
}
