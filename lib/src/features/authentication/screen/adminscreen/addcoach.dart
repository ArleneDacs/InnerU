import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/manage_companies.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/viewalluser.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/admin_access.dart';
import 'package:selfcare_projects/src/services/coach_directory_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/utils/phone_launcher.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Coaches App',
      home: AddCoachScreen(),
    );
  }
}

class CoachDirectoryEntry {
  const CoachDirectoryEntry({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.companyName,
    required this.companyCode,
    required this.profilePic,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String companyName;
  final String companyCode;
  final String profilePic;
  final String role;

  factory CoachDirectoryEntry.fromApi(CoachDirectoryApiCoach coach) {
    return CoachDirectoryEntry(
      id: coach.id,
      name: coach.name,
      email: coach.email,
      phone: coach.number?.trim() ?? '',
      companyName: coach.companyName?.trim() ?? '',
      companyCode: coach.companyCode?.trim() ?? '',
      profilePic: coach.profilePic?.trim() ?? '',
      role: coach.role,
    );
  }
}

class CoachProfileDialog extends StatelessWidget {
  const CoachProfileDialog({
    super.key,
    required this.coach,
  });

  final CoachDirectoryEntry coach;

  ui.Color _backgroundColor(BuildContext context) {
    final palette = <ui.Color>[
      const ui.Color(0xFF90A17D),
      const ui.Color(0xFF6D849A),
      const ui.Color(0xFF8A6D6D),
      const ui.Color(0xFF7F8C5A),
    ];
    return palette[coach.name.hashCode.abs() % palette.length];
  }

  Future<void> _launchDialer(BuildContext context) async {
    final normalizedPhoneNumber = normalizePhoneNumber(coach.phone);
    if (normalizedPhoneNumber.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('This coach does not have a valid phone number yet.'),
        ),
      );
      return;
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final userData = await UserService.getUserData();
      final username = (userData['username'] ?? userData['name'])
          ?.toString()
          .trim();

      final launched = await launchPhoneNumber(normalizedPhoneNumber);
      if (!launched) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't open the dialer on this device. If you're using the iPhone simulator, the Phone app isn't available there.",
            ),
          ),
        );
        return;
      }

      if (username != null && username.isNotEmpty) {
        await DailyTrackerApiService.instance.upsert(
          date: formattedDate,
          username: username,
          call: true,
          callCount: 1,
          companyId: userData['companyId']?.toString(),
          companyCode: userData['companyCode']?.toString(),
          companyName: userData['companyName']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('Failed to log coach call: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _backgroundColor(context);
    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.arrow_left,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.phone_fill,
                    size: 30,
                    color: Colors.white,
                  ),
                  onPressed: () => _launchDialer(context),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white,
                backgroundImage: coach.profilePic.isNotEmpty
                    ? NetworkImage(coach.profilePic)
                    : null,
                child: coach.profilePic.isEmpty
                    ? const Icon(
                        Icons.person,
                        size: 48,
                        color: Colors.grey,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              coach.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: ui.FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: ui.TextAlign.center,
            ),
            GestureDetector(
              onTap: () => _launchDialer(context),
              child: Text(
                coach.phone.isNotEmpty ? coach.phone : 'No phone available',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: ui.FontWeight.bold,
                  color: Colors.white,
                  decoration: ui.TextDecoration.underline,
                ),
                textAlign: ui.TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'About',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: ui.FontWeight.w700,
                  letterSpacing: 1,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coach.companyName.isNotEmpty
                        ? coach.companyName
                        : 'No company assigned yet',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    coach.companyCode.isNotEmpty
                        ? 'Company code: ${coach.companyCode}'
                        : 'Company code not available',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddCoachScreen extends StatefulWidget {
  const AddCoachScreen({super.key});

  @override
  State<AddCoachScreen> createState() => _AddCoachScreenState();
}

class _AddCoachScreenState extends State<AddCoachScreen> {
  late final TextEditingController _searchController;
  Future<List<CoachDirectoryEntry>>? _coachesFuture;
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isCoachUser = false;
  bool _isAuthorized = false;
  bool _coachProfileExists = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _checkUserAccess();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkUserAccess() async {
    try {
      final data = await UserService.getUserData();
      final role = (data['role'] as String?)?.toLowerCase().trim() ?? '';
      final isCoach = data['is_coach'] == true || role == 'coach';
      final isAdmin = AdminAccess.hasAdminRole(data);

      if (!mounted) {
        return;
      }

      setState(() {
        _isAdmin = isAdmin;
        _isCoachUser = isCoach;
        _isAuthorized = isAdmin || isCoach;
        _coachProfileExists =
            (data['number']?.toString().trim().isNotEmpty == true);
        _isLoading = false;
      });

      if (_isAuthorized) {
        _refreshCoaches();
      }
    } catch (e) {
      debugPrint('Failed to load access data: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshCoaches() async {
    setState(() {
      _coachesFuture = CoachDirectoryApiService.instance
          .fetchCoaches()
          .then(
            (items) => items.map(CoachDirectoryEntry.fromApi).toList(),
          );
    });
  }

  Future<void> _showCoachProfileDialog() async {
    final currentUser = await UserService.getUserData();
    final nameController = TextEditingController(
      text: (currentUser['username'] ?? currentUser['name'])?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: currentUser['number']?.toString() ?? '',
    );
    final wasComplete = _coachProfileExists;

    if (!mounted) {
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _coachProfileExists
                ? 'Update Coach Contact'
                : 'Complete Coach Contact',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    phoneController.text.trim().isEmpty) {
                  ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                    const SnackBar(
                      content: Text('Name and phone number are required.'),
                    ),
                  );
                  return;
                }

                await UserService.updateUserData(
                  name: nameController.text.trim(),
                  number: phoneController.text.trim(),
                );

                if (!mounted) {
                  return;
                }

                setState(() {
                  _coachProfileExists = true;
                });
                await _refreshCoaches();
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                  SnackBar(
                    content: Text(
                      wasComplete
                          ? 'Coach contact updated successfully!'
                          : 'Coach contact created successfully!',
                    ),
                  ),
                );
              },
              child: Text(
                _coachProfileExists ? 'Save Changes' : 'Create Contact',
              ),
            ),
          ],
        );
      },
    );
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const ui.Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  CupertinoIcons.lock_shield_fill,
                  color: ui.Color(0xFFD95555),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: ui.FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Only coaches and admins can view this area.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Coaches'),
        actions: [
          if (_isCoachUser)
            IconButton(
              icon: const Icon(CupertinoIcons.person_crop_circle_badge_plus),
              onPressed: _showCoachProfileDialog,
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(CupertinoIcons.building_2_fill),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManageCompaniesScreen(),
                  ),
                );
              },
            ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(CupertinoIcons.person_add),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManageCoachesScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isCoachUser && !_coachProfileExists)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.primary),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Complete your coach contact card',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: ui.FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Add your name and phone number so users can reach you as a coach.',
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _showCoachProfileDialog,
                      child: const Text('Create Contact'),
                    ),
                  ],
                ),
              ),
            if (_isAdmin) _buildCompanySection(theme),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: SizedBox(
                height: _isAdmin ? 180 : 280,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.asset(
                    'assets/images/coachpic.png',
                    width: 400,
                    height: 300,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search coaches',
                  prefixIcon: Icon(CupertinoIcons.search),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<CoachDirectoryEntry>>(
                future: _coachesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Could not load coaches right now.'),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _refreshCoaches,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final coaches = snapshot.data ?? const <CoachDirectoryEntry>[];
                  final query = _searchController.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? coaches
                      : coaches.where((coach) {
                          return coach.name.toLowerCase().contains(query) ||
                              coach.phone.toLowerCase().contains(query) ||
                              coach.companyName.toLowerCase().contains(query) ||
                              coach.companyCode.toLowerCase().contains(query);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No coaches available.'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final coach = filtered[index];
                      final cardColor = <ui.Color>[
                        const ui.Color(0xFF90A17D),
                        const ui.Color(0xFF6D849A),
                        const ui.Color(0xFF8A6D6D),
                        const ui.Color(0xFF7F8C5A),
                      ][index % 4];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10.0),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: cardColor.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const ui.Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.white,
                            backgroundImage: coach.profilePic.isNotEmpty
                                ? NetworkImage(coach.profilePic)
                                : null,
                            child: coach.profilePic.isEmpty
                                ? const Icon(Icons.person, color: Colors.grey)
                                : null,
                          ),
                          title: Text(
                            coach.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: ui.FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            coach.phone.isNotEmpty
                                ? coach.phone
                                : coach.companyName.isNotEmpty
                                    ? coach.companyName
                                    : 'Coach',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            color: Colors.white70,
                            size: 18,
                          ),
                          onTap: () => showDialog(
                            context: context,
                            builder: (context) => CoachProfileDialog(coach: coach),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanySection(ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Companies',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: ui.FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageCompaniesScreen(),
                    ),
                  );
                },
                icon: const Icon(CupertinoIcons.building_2_fill, size: 18),
                label: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Edit names, company codes, theme controls, logos, and loading media on the company management screen.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              height: 1.35,
              fontWeight: ui.FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManageCompaniesScreen(),
                  ),
                );
              },
              icon: const Icon(CupertinoIcons.arrow_right_circle_fill),
              label: const Text('Open company manager'),
            ),
          ),
        ],
      ),
    );
  }
}
