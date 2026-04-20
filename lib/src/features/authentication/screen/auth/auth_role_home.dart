import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_dashboard_screen.dart';

class AuthRoleHome extends StatelessWidget {
  const AuthRoleHome({
    super.key,
    this.preferredRole,
  });

  final String? preferredRole;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return FutureBuilder<bool>(
      future: _resolveCoachStatus(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final preferredCoach = preferredRole?.toLowerCase() == 'coach';
        final isCoach = preferredCoach || (snapshot.data ?? false);

        if (isCoach) {
          return const CoachDashboardScreen();
        }

        return const Setuppage();
      },
    );
  }

  Future<bool> _resolveCoachStatus(String uid) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = userDoc.data();
    final role = (data?['role'] as String?)?.toLowerCase();
    final isCoachFlag = data?['isCoach'] == true || role == 'coach';

    if (isCoachFlag) {
      return true;
    }

    final coachDoc =
        await FirebaseFirestore.instance.collection('coaches').doc(uid).get();
    return coachDoc.exists;
  }
}
