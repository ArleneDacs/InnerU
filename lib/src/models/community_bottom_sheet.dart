import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class CommunityBottomSheet {
  static Future<void> show(
    BuildContext context, {
    CompanyThemeData? companyTheme,
  }) async {
    final theme = companyTheme ?? _cachedThemeOrStandard();

    showModalBottomSheet(
      backgroundColor: theme.surfaceColor,
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Theme(
          data: AppTheme.company(theme),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              child: ListTileTheme(
                iconColor: theme.iconColor,
                textColor: theme.inkColor,
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
                      color: theme.primaryColor.withValues(alpha: 0.24),
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

  static CompanyThemeData _cachedThemeOrStandard() {
    final session = AuthService.instance.currentSession;
    if (session == null) return CompanyThemeData.standard;
    return CompanyThemeService.cachedThemeForUser(session.id.toString()) ??
        CompanyThemeData.standard;
  }
}
