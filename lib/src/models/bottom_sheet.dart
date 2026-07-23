import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/addcoach.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/privacy/privacy_screen.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class BottomSheetWidget {
  static void show(BuildContext context) {
    final currentUser = AuthService.instance.currentSession;
    const allowedUserId = "hG1FxGW2xrVXtKZnnDWERJpPQof2";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return CompanyThemeBuilder(
          builder: (context, companyTheme) {
            final background = companyTheme.isDark
                ? companyTheme.surfaceColor
                : companyTheme.primaryColor;
            final foreground = companyTheme.isDark
                ? companyTheme.inkColor
                : _onSurfaceFor(companyTheme.primaryColor);

            return Theme(
              data: AppTheme.company(companyTheme),
              child: Container(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: ListTileTheme(
                  iconColor: foreground,
                  textColor: foreground,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildHandle(companyTheme),
                            const SizedBox(height: 8),
                            _buildMenuTile(
                              icon: Icons.person,
                              title: 'Profile',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.pushNamed(context, '/profile');
                              },
                            ),
                            _buildDivider(companyTheme),
                            _buildMenuTile(
                              icon: Icons.receipt_long_rounded,
                              title: 'Activity Logs',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.pushNamed(context, '/activityLogs');
                              },
                            ),
                            _buildDivider(companyTheme),
                            _buildMenuTile(
                              icon: Icons.settings,
                              title: 'Account Settings',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PrivacyScreen(title: 'Privacy'),
                                  ),
                                );
                              },
                            ),
                            _buildDivider(companyTheme),
                            _buildMenuTile(
                              icon: Icons.face,
                              title: 'Mood Tracker',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.pushNamed(context, '/emotionScreen');
                              },
                            ),
                            _buildDivider(companyTheme),
                            _buildMenuTile(
                              icon: Icons.star,
                              title: 'Leaderboard',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.pushNamed(context, '/leaderboard');
                              },
                            ),
                            _buildDivider(companyTheme),
                            _buildMenuTile(
                              icon: CupertinoIcons.rosette,
                              title: 'Coaches',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                Navigator.pushNamed(context, '/coachesScreen');
                              },
                            ),
                            if (currentUser?.id.toString() ==
                                allowedUserId) ...[
                              _buildDivider(companyTheme),
                              _buildMenuTile(
                                icon: Icons.supervisor_account,
                                title: 'Add Coach',
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddCoachScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                            _buildDivider(companyTheme),
                            _buildMenuTile(
                              icon: Icons.logout_rounded,
                              title: 'Log out',
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _showLogOutDialog(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildHandle(CompanyThemeData theme) {
    return Container(
      width: 44,
      height: 4,
      decoration: BoxDecoration(
        color: theme.isDark
            ? theme.primaryColor.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  static Widget _buildDivider(CompanyThemeData theme) {
    return Divider(
      color: theme.isDark
          ? theme.iconColor.withValues(alpha: 0.14)
          : Colors.white.withValues(alpha: 0.18),
      height: 8,
    );
  }

  static Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }

  static Future<void> _showLogOutDialog(BuildContext context) async {
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await SessionCleanupService.signOut();
              await AppSessionService.instance.clear();
              if (!navigator.mounted) return;
              navigator.pop();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }
}

Color _onSurfaceFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}
