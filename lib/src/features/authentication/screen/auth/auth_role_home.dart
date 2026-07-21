import 'package:flutter/material.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class AuthRoleHome extends StatelessWidget {
  const AuthRoleHome({
    super.key,
    this.preferredRole,
  });

  final String? preferredRole;

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.currentSession;

    if (session == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final preferredCoach = preferredRole?.toLowerCase() == 'coach';
    final isCoach = preferredCoach || session.isCoach || session.role.toLowerCase() == 'coach';

    if (isCoach) {
      return const CoachSetuppage();
    }

    return const Setuppage();
  }
}
