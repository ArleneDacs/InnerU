import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/admin_dashboard.dart';
import 'package:selfcare_projects/src/features/authentication/screen/company_loading/company_loading_screen.dart';
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
    final preferredAdmin = preferredRole?.toLowerCase() == 'admin';
    final isCoach = preferredCoach || session.isCoach || session.role.toLowerCase() == 'coach';
    final isAdmin = preferredAdmin || session.role.toLowerCase() == 'admin';
    final companyGate = CompanyLoadingGate(
      uid: session.id.toString(),
      child: isCoach ? const CoachSetuppage() : const Setuppage(),
    );

    if (isAdmin) {
      return const AdminDashboardScreen();
    }

    return companyGate;
  }
}
