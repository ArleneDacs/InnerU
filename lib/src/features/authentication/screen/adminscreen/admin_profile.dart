import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/admin_access.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  late Future<_AdminProfileData> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<_AdminProfileData> _loadProfile() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      throw StateError('No signed-in admin account.');
    }

    final isAdmin = await AdminAccess.isAdmin();
    if (!isAdmin) {
      throw StateError('This account does not have admin access.');
    }

    final data = await UserService.getUserData();

    return _AdminProfileData(
      uid: session.id.toString(),
      username: _stringValue(data['username'], fallback: 'Admin'),
      email: _stringValue(data['email'], fallback: session.email.isNotEmpty ? session.email : 'No email'),
      number: _stringValue(data['number']),
      role: _stringValue(data['role'], fallback: 'admin'),
      companyName: _stringValue(data['companyName']),
      companyCode: _stringValue(data['companyCode']),
      emailVerified: data['emailVerified'] == true,
      photoUrl: _stringValue(data['photoURL'] ?? data['profilePic']),
    );
  }

  static String _stringValue(dynamic value, {String fallback = ''}) {
    final text = value is String ? value.trim() : '';
    return text.isNotEmpty ? text : fallback;
  }

  void _refresh() {
    setState(() {
      _profileFuture = _loadProfile();
    });
  }

  Future<void> _showEditProfileDialog(
      _AdminProfileData profile, ThemeData theme) async {
    final usernameController = TextEditingController(text: profile.username);
    final numberController = TextEditingController(text: profile.number);
    final messenger = ScaffoldMessenger.of(context);
    var isSaving = false;
    var dialogIsOpen = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Edit Profile'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      filled: true,
                      fillColor:
                          theme.colorScheme.primary.withValues(alpha: 0.10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      filled: true,
                      fillColor:
                          theme.colorScheme.primary.withValues(alpha: 0.10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final username = usernameController.text.trim();
                          final number = numberController.text.trim();

                          if (username.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Display name is required.'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            await UserService.updateUserData(
                              name: username,
                              number: number,
                            );

                            if (!dialogContext.mounted) return;
                            dialogIsOpen = false;
                            Navigator.pop(dialogContext);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Admin profile updated.'),
                              ),
                            );
                            _refresh();
                          } catch (e) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Failed to update profile: $e'),
                              ),
                            );
                          } finally {
                            if (dialogIsOpen && dialogContext.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    numberController.dispose();
  }

  Future<void> _signOut() async {
    final session = AuthService.instance.currentSession;
    await SessionCleanupService.clearLocalSession(
      userId: session?.id.toString(),
    );
    await AuthService.instance.signOutGoogle();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(builder: (context) => _buildContent(context)),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          'Admin Profile',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: Icon(CupertinoIcons.arrow_clockwise,
                color: theme.colorScheme.onSurface),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_AdminProfileData>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ProfileMessage(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'Profile could not load',
                body: snapshot.error.toString(),
                action: TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(CupertinoIcons.arrow_clockwise),
                  label: const Text('Try again'),
                ),
              );
            }

            final profile = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
              children: [
                _ProfileHeader(
                  profile: profile,
                  onEdit: () =>
                      _showEditProfileDialog(profile, Theme.of(context)),
                ),
                const SizedBox(height: 16),
                _ProfileSection(
                  title: 'Account',
                  children: [
                    _InfoTile(
                      icon: CupertinoIcons.mail_solid,
                      label: 'Email',
                      value: profile.email,
                    ),
                    _InfoTile(
                      icon: CupertinoIcons.phone_fill,
                      label: 'Phone',
                      value: profile.number.isEmpty
                          ? 'No phone number'
                          : profile.number,
                    ),
                    _InfoTile(
                      icon: CupertinoIcons.checkmark_shield_fill,
                      label: 'Email Status',
                      value:
                          profile.emailVerified ? 'Verified' : 'Not verified',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ProfileSection(
                  title: 'Admin Access',
                  children: [
                    _InfoTile(
                      icon: CupertinoIcons.shield_fill,
                      label: 'Role',
                      value: profile.role,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ProfileSection(
                  title: 'Company',
                  children: [
                    _InfoTile(
                      icon: CupertinoIcons.building_2_fill,
                      label: 'Company',
                      value: profile.companyName.isEmpty
                          ? 'No company assigned'
                          : profile.companyName,
                    ),
                    _InfoTile(
                      icon: CupertinoIcons.barcode,
                      label: 'Company Code',
                      value: profile.companyCode.isEmpty
                          ? 'No code assigned'
                          : profile.companyCode,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: _signOut,
                  icon: const Icon(CupertinoIcons.square_arrow_right),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onEdit,
  });

  final _AdminProfileData profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor:
                theme.colorScheme.primary.withValues(alpha: 0.10),
            backgroundImage: profile.photoUrl.isEmpty
                ? null
                : NetworkImage(profile.photoUrl),
            child: profile.photoUrl.isEmpty
                ? Text(
                    profile.initials,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit profile',
            onPressed: onEdit,
            style: IconButton.styleFrom(
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.10),
            ),
            icon: const Icon(CupertinoIcons.pencil),
            color: theme.colorScheme.onSurface,
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminProfileData {
  const _AdminProfileData({
    required this.uid,
    required this.username,
    required this.email,
    required this.number,
    required this.role,
    required this.companyName,
    required this.companyCode,
    required this.emailVerified,
    required this.photoUrl,
  });

  final String uid;
  final String username;
  final String email;
  final String number;
  final String role;
  final String companyName;
  final String companyCode;
  final bool emailVerified;
  final String photoUrl;

  String get initials {
    final parts = username
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}
