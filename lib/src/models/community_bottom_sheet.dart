import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class CommunityBottomSheet {
  static Future<void> show(BuildContext context) async {
    final session = AuthService.instance.currentSession;
    final companyTheme = session == null
        ? CompanyThemeData.standard
        : await CompanyThemeService.resolveForUser(session.id.toString());
    if (!context.mounted) return;

    showModalBottomSheet(
      backgroundColor: companyTheme.surfaceColor,
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              child: ListTileTheme(
                iconColor: companyTheme.iconColor,
                textColor: companyTheme.inkColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text("Profile Settings"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/profileSettings');
                      },
                    ),
                    Divider(
                      color: companyTheme.primaryColor.withValues(alpha: 0.24),
                    ),
                    ListTile(
                      leading: const Icon(Icons.list),
                      title: const Text("View Other User Progress"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/userprogress');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
