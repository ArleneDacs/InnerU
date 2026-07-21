import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/admin_user_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class ManageCoachesScreen extends StatefulWidget {
  const ManageCoachesScreen({super.key});

  @override
  State<ManageCoachesScreen> createState() => ManageCoachesScreenState();
}

class ManageCoachesScreenState extends State<ManageCoachesScreen> {
  late Future<List<AdminUserApiUser>> _usersFuture;
  String _savingUserId = '';

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
  }

  Future<List<AdminUserApiUser>> _loadUsers() {
    return AdminUserApiService.instance.fetchUsers();
  }

  void _refresh() {
    setState(() {
      _usersFuture = _loadUsers();
    });
  }

  Future<void> _setAsAdmin(AdminUserApiUser user) async {
    if (_savingUserId.isNotEmpty) return;

    setState(() => _savingUserId = user.id);
    try {
      await AdminUserApiService.instance.updateRole(
        userId: user.id,
        role: 'admin',
        name: user.name,
        number: user.number,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} is now an admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update role: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingUserId = '');
      }
    }
  }

  Future<void> _showSetCoachDialog(AdminUserApiUser user) async {
    final fullNameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.number ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set Coach'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fullNameController,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
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
                Navigator.pop(dialogContext);
                await _setAsCoach(
                  user,
                  fullName: fullNameController.text.trim(),
                  phone: phoneController.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    fullNameController.dispose();
    phoneController.dispose();
  }

  Future<void> _setAsCoach(
    AdminUserApiUser user, {
    required String fullName,
    required String phone,
  }) async {
    if (_savingUserId.isNotEmpty) return;

    setState(() => _savingUserId = user.id);
    try {
      await AdminUserApiService.instance.updateRole(
        userId: user.id,
        role: 'coach',
        name: fullName.isEmpty ? user.name : fullName,
        number: phone.isEmpty ? user.number : phone,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} is now a coach.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update role: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingUserId = '');
      }
    }
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
      appBar: AppBar(
        title: const Text('Manage Coaches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<AdminUserApiUser>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error fetching users: ${snapshot.error}'),
            );
          }

          final users = snapshot.data ?? const <AdminUserApiUser>[];
          final eligibleUsers = users
              .where((user) => !user.isCoach && !user.isAdmin)
              .toList();

          if (eligibleUsers.isEmpty) {
            return const Center(
              child: Text('No users available to assign as coaches.'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: eligibleUsers.length,
              itemBuilder: (context, index) {
                final user = eligibleUsers[index];
                final isSaving = _savingUserId == user.id;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.10),
                              backgroundImage: user.profilePic?.isNotEmpty == true
                                  ? NetworkImage(user.profilePic!)
                                  : null,
                              child: user.profilePic?.isNotEmpty == true
                                  ? null
                                  : Icon(
                                      Icons.person,
                                      color: theme.colorScheme.primary,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.name.isNotEmpty ? user.name : 'Unknown User',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user.email,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: isSaving
                                    ? null
                                    : () => _showSetCoachDialog(user),
                                child: isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Set Coach'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  side: BorderSide(
                                    color: theme.colorScheme.primary,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: isSaving
                                    ? null
                                    : () => _setAsAdmin(user),
                                child: isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Set Admin'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
