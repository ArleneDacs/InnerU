import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/authentication/screen/edit_profile/edit_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/privacy/privacy_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_goal_screen.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/default_landing_screen.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

class ProfileSettings extends StatelessWidget {
  const ProfileSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        final session = AuthService.instance.currentSession;
        final isAdmin = session?.role.toLowerCase() == 'admin';
        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor:
                companyTheme.isDark ? companyTheme.surfaceColor : null,
            foregroundColor: companyTheme.isDark ? companyTheme.inkColor : null,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            child: ResponsiveContent(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Profile Settings",
                      style: TextStyle(
                        fontSize: 28,
                        color: companyTheme.inkColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Manage your account and preferences.",
                      style: TextStyle(
                        fontSize: 14,
                        color: companyTheme.mutedInkColor,
                      ),
                    ),
                    SizedBox(height: 28),
                    _buildSectionTitle("Company", companyTheme),
                    _CompanyMembershipSettingsPanel(pageTheme: companyTheme),
                    _buildSectionTitle("Theme", companyTheme),
                    _ThemeSettingsPanel(pageTheme: companyTheme),
                    _buildSectionTitle("General", companyTheme),
                    _buildButton(
                      context,
                      "Edit Profile",
                      EditProfile(title: 'Edit Profile'),
                      companyTheme,
                    ),
                    _buildButton(
                      context,
                      "Step Goal",
                      StepGoalScreen(),
                      companyTheme,
                    ),
                    _buildSectionTitle("Audio Settings", companyTheme),
                    _buildButton(
                      context,
                      "Change Meditation Song",
                      MeditationSong(),
                      companyTheme,
                    ),
                    _buildSectionTitle("Account Settings", companyTheme),
                    if (companyTheme.isCompanyTheme &&
                        companyTheme.companyCode.isNotEmpty)
                      _buildCompanyCodeCard(companyTheme),
                    if (!isAdmin)
                      _DefaultLandingScreenPanel(pageTheme: companyTheme),
                    _buildButton(
                      context,
                      "Privacy",
                      PrivacyScreen(title: 'Privacy'),
                      companyTheme,
                    ),
                    _buildButton(
                      context,
                      "Delete Account",
                      PrivacyScreen(title: 'Delete Account'),
                      companyTheme,
                      textColor: Colors.red.shade700,
                    ),
                    SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, CompanyThemeData companyTheme) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: companyTheme.isDark
              ? companyTheme.primaryColor
              : companyTheme.mutedInkColor,
        ),
      ),
    );
  }

  Widget _buildCompanyCodeCard(CompanyThemeData companyTheme) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: companyTheme.isDark ? companyTheme.surfaceColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE3EAE8),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.business_rounded,
            size: 19,
            color: companyTheme.iconColor,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Company code',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: companyTheme.inkColor,
              ),
            ),
          ),
          Text(
            companyTheme.companyCode,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: companyTheme.mutedInkColor,
            ),
          ),
        ],
      ),
    );
  }

  // Button Widget with Navigation
  Widget _buildButton(
    BuildContext context,
    String label,
    Widget targetScreen,
    CompanyThemeData companyTheme, {
    Color textColor = Colors.black,
  }) {
    final effectiveColor =
        textColor == Colors.black ? companyTheme.inkColor : textColor;
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: companyTheme.isDark ? companyTheme.surfaceColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: companyTheme.isDark
              ? companyTheme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE3EAE8),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => targetScreen),
            );
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 15, color: effectiveColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultLandingScreenPanel extends StatefulWidget {
  const _DefaultLandingScreenPanel({required this.pageTheme});

  final CompanyThemeData pageTheme;

  @override
  State<_DefaultLandingScreenPanel> createState() =>
      _DefaultLandingScreenPanelState();
}

class _DefaultLandingScreenPanelState
    extends State<_DefaultLandingScreenPanel> {
  late DefaultLandingScreen _selected;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _selected = DefaultLandingScreen.fromStorageValue(
      AuthService.instance.currentSession?.defaultLandingScreen,
    );
  }

  bool get _isAbundance => AbundanceCompany.matches(
        widget.pageTheme.companyCode,
        widget.pageTheme.companyName,
      );

  List<DefaultLandingScreen> get _availableScreens =>
      DefaultLandingScreen.availableFor(isAbundance: _isAbundance);

  DefaultLandingScreen get _visibleSelection =>
      _availableScreens.contains(_selected)
          ? _selected
          : DefaultLandingScreen.dashboard;

  Future<void> _save(DefaultLandingScreen next) async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSaving) return;

    final previous = _selected;
    setState(() {
      _selected = next;
      _isSaving = true;
      _saveError = null;
    });

    try {
      final profile = await UserService.updateUserFields({
        'default_landing_screen': next.storageValue,
      });
      final saved = DefaultLandingScreen.fromStorageValue(
        profile['defaultScreen'] ?? next.storageValue,
      );

      // The backend remains the source of truth, while the existing secure
      // session cache makes the saved destination immediately available on
      // the next authenticated app restore without another startup request.
      await AuthService.instance.updateDefaultLandingScreen(
        saved.storageValue,
      );

      if (!mounted) return;
      setState(() {
        _selected = saved;
        _isSaving = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Default screen saved.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selected = previous;
        _isSaving = false;
        _saveError = 'Could not save your default screen. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.pageTheme;
    final availableScreens = _availableScreens;
    final selected = _visibleSelection;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.surfaceColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.isDark
              ? theme.primaryColor.withValues(alpha: 0.18)
              : const Color(0xFFE3EAE8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home_outlined, size: 19, color: theme.iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Default screen',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: theme.inkColor,
                  ),
                ),
              ),
              if (_isSaving)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.primaryColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Choose where InnerU opens after you sign in.',
            style: TextStyle(fontSize: 13, color: theme.mutedInkColor),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DefaultLandingScreen>(
            key: ValueKey(selected.storageValue),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.primaryColor.withValues(alpha: 0.28),
                ),
              ),
            ),
            items: availableScreens
                .map(
                  (screen) => DropdownMenuItem(
                    value: screen,
                    child: Text(screen.labelFor(isAbundance: _isAbundance)),
                  ),
                )
                .toList(growable: false),
            onChanged: _isSaving
                ? null
                : (screen) {
                    if (screen != null) {
                      _save(screen);
                    }
                  },
          ),
          if (_isAbundance) ...[
            const SizedBox(height: 8),
            Text(
              'This workspace currently supports Home, Quests, and Profile.',
              style: TextStyle(fontSize: 12, color: theme.mutedInkColor),
            ),
          ],
          if (_saveError != null) ...[
            const SizedBox(height: 8),
            Text(
              _saveError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompanyMembershipSettingsPanel extends StatefulWidget {
  const _CompanyMembershipSettingsPanel({required this.pageTheme});

  final CompanyThemeData pageTheme;

  @override
  State<_CompanyMembershipSettingsPanel> createState() =>
      _CompanyMembershipSettingsPanelState();
}

class _CompanyMembershipSettingsPanelState
    extends State<_CompanyMembershipSettingsPanel> with WidgetsBindingObserver {
  late Future<CompanyMembershipData> _membershipFuture;
  final TextEditingController _codeController = TextEditingController();
  CompanyScoreMode _selectedScoreMode = CompanyScoreMode.merged;
  bool _isJoining = false;
  String _activeChangingId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _membershipFuture = _loadMemberships();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _membershipFuture = _loadMemberships();
      });
    }
  }

  bool _isAbundance12Code(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized == 'A12' ||
        normalized.startsWith('AB12') ||
        normalized.contains('ABUND12') ||
        normalized.contains('ABUNDANCE12');
  }

  Future<CompanyMembershipData> _loadMemberships() async {
    final uid = AuthService.instance.currentSession?.id.toString();
    if (uid == null) {
      return const CompanyMembershipData(
        memberships: <CompanyMembership>[],
        activeMembership: null,
      );
    }
    return CompanyMembershipService.loadForUser(uid);
  }

  Future<void> _joinCompany() async {
    final uid = AuthService.instance.currentSession?.id.toString();
    if (uid == null || _isJoining) return;

    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showMessage('Enter a company code.');
      return;
    }
    if (code.length < 4 && !_isAbundance12Code(code)) {
      _showMessage(CompanyApiService.invalidCompanyCodeMessage);
      return;
    }

    setState(() => _isJoining = true);
    try {
      final membership = await CompanyMembershipService.joinCompany(
        uid: uid,
        companyCode: code,
        scoreMode: _selectedScoreMode,
      );
      if (!mounted) return;
      _codeController.clear();
      setState(() {
        _membershipFuture = _loadMemberships();
      });
      _showMessage('Joined ${membership.name}.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Future<void> _switchCompany(CompanyMembership membership) async {
    final uid = AuthService.instance.currentSession?.id.toString();
    if (uid == null || _activeChangingId.isNotEmpty) return;

    setState(() => _activeChangingId = membership.id);
    try {
      await CompanyMembershipService.setActiveCompany(
        uid: uid,
        membership: membership,
      );
      if (!mounted) return;
      setState(() {
        _membershipFuture = _loadMemberships();
      });
      _showMessage('Switched to ${membership.name}.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not switch company.');
    } finally {
      if (mounted) {
        setState(() => _activeChangingId = '');
      }
    }
  }

  Future<void> _removeCompany(CompanyMembership membership) async {
    final uid = AuthService.instance.currentSession?.id.toString();
    if (uid == null || _activeChangingId.isNotEmpty) return;

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Remove company access?'),
              content: Text(
                'This will remove ${membership.name} (${membership.code}) from your company list.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) return;

    setState(() => _activeChangingId = membership.id);
    try {
      await CompanyMembershipService.removeCompanyAccess(
        uid: uid,
        membership: membership,
      );
      if (!mounted) return;
      setState(() {
        _membershipFuture = _loadMemberships();
      });
      _showMessage('Removed ${membership.name}.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not remove company access.');
    } finally {
      if (mounted) {
        setState(() => _activeChangingId = '');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageTheme = widget.pageTheme;
    return FutureBuilder<CompanyMembershipData>(
      future: _membershipFuture,
      builder: (context, snapshot) {
        final memberships =
            snapshot.data?.memberships ?? const <CompanyMembership>[];
        final activeMembership = snapshot.data?.activeMembership;

        return Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(16),
          decoration: _panelDecoration(pageTheme),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Company access',
                style: TextStyle(
                  color: pageTheme.inkColor,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Join more companies and choose how scores are counted.',
                style: TextStyle(
                  color: pageTheme.mutedInkColor,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                onChanged: (value) {
                  final upperValue = value.toUpperCase();
                  if (value != upperValue) {
                    _codeController.value = _codeController.value.copyWith(
                      text: upperValue,
                      selection: TextSelection.collapsed(
                        offset: upperValue.length,
                      ),
                    );
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Company code',
                  filled: true,
                  fillColor: pageTheme.isDark
                      ? pageTheme.backgroundColor.withValues(alpha: 0.38)
                      : const Color(0xFFF7F8F4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                style: TextStyle(color: pageTheme.inkColor),
              ),
              SizedBox(height: 10),
              _ScoreModeTile(
                pageTheme: pageTheme,
                mode: CompanyScoreMode.merged,
                selected: _selectedScoreMode == CompanyScoreMode.merged,
                onTap: () {
                  setState(() => _selectedScoreMode = CompanyScoreMode.merged);
                },
              ),
              SizedBox(height: 8),
              _ScoreModeTile(
                pageTheme: pageTheme,
                mode: CompanyScoreMode.separate,
                selected: _selectedScoreMode == CompanyScoreMode.separate,
                onTap: () {
                  setState(
                      () => _selectedScoreMode = CompanyScoreMode.separate);
                },
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isJoining ? null : _joinCompany,
                  icon: _isJoining
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: pageTheme.backgroundColor,
                          ),
                        )
                      : const Icon(Icons.add_business_rounded),
                  label: Text(_isJoining ? 'Joining...' : 'Join company'),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting) ...[
                SizedBox(height: 14),
                LinearProgressIndicator(color: pageTheme.iconColor),
              ] else if (memberships.isNotEmpty) ...[
                SizedBox(height: 18),
                Divider(
                  color: pageTheme.mutedInkColor.withValues(alpha: 0.16),
                ),
                SizedBox(height: 10),
                Text(
                  'Your companies',
                  style: TextStyle(
                    color: pageTheme.inkColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                ...memberships.map((membership) {
                  final isActive = _sameCompany(membership, activeMembership);
                  final isSwitching = _activeChangingId == membership.id;
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: _CompanyMembershipTile(
                      membership: membership,
                      pageTheme: pageTheme,
                      isActive: isActive,
                      isSwitching: isSwitching,
                      onTap: isActive ? null : () => _switchCompany(membership),
                      onDelete: () => _removeCompany(membership),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _panelDecoration(CompanyThemeData pageTheme) {
    return BoxDecoration(
      color: pageTheme.isDark ? pageTheme.surfaceColor : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: pageTheme.isDark
            ? pageTheme.primaryColor.withValues(alpha: 0.18)
            : const Color(0xFFE3EAE8),
      ),
    );
  }

  bool _sameCompany(CompanyMembership left, CompanyMembership? right) {
    if (right == null) return false;
    return (left.id.isNotEmpty && left.id == right.id) ||
        (left.code.isNotEmpty && left.code == right.code);
  }
}

class _ScoreModeTile extends StatelessWidget {
  const _ScoreModeTile({
    required this.pageTheme,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final CompanyThemeData pageTheme;
  final CompanyScoreMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = mode == CompanyScoreMode.merged
        ? 'Keep one continuous record across companies and tag activity logs by company.'
        : 'Keep a separate score document for this company when scoring is synced.';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? pageTheme.iconColor.withValues(alpha: 0.12)
                : pageTheme.backgroundColor.withValues(
                    alpha: pageTheme.isDark ? 0.24 : 0.55,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? pageTheme.iconColor
                  : pageTheme.mutedInkColor.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? pageTheme.iconColor : pageTheme.mutedInkColor,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.title,
                      style: TextStyle(
                        color: pageTheme.inkColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: pageTheme.mutedInkColor,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyMembershipTile extends StatelessWidget {
  const _CompanyMembershipTile({
    required this.membership,
    required this.pageTheme,
    required this.isActive,
    required this.isSwitching,
    required this.onTap,
    required this.onDelete,
  });

  final CompanyMembership membership;
  final CompanyThemeData pageTheme;
  final bool isActive;
  final bool isSwitching;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pageTheme.backgroundColor.withValues(
              alpha: pageTheme.isDark ? 0.24 : 0.55,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? pageTheme.iconColor
                  : pageTheme.mutedInkColor.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.business_rounded,
                color: pageTheme.iconColor,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.name,
                      style: TextStyle(
                        color: pageTheme.inkColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '${membership.code} · ${membership.scoreMode.title}',
                      style: TextStyle(
                        color: pageTheme.mutedInkColor,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSwitching)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: pageTheme.iconColor,
                  ),
                )
              else if (isActive)
                Icon(
                  Icons.check_circle_rounded,
                  color: pageTheme.iconColor,
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  size: 15,
                  color: pageTheme.mutedInkColor,
                ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Remove company access',
                onPressed: isSwitching ? null : onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSettingsPanel extends StatefulWidget {
  const _ThemeSettingsPanel({required this.pageTheme});

  final CompanyThemeData pageTheme;

  @override
  State<_ThemeSettingsPanel> createState() => _ThemeSettingsPanelState();
}

class _ThemeSettingsPanelState extends State<_ThemeSettingsPanel> {
  late Future<_ThemeSettingsData> _themeDataFuture;
  String? _selectedThemeId;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _themeDataFuture = _loadThemeData();
  }

  Future<_ThemeSettingsData> _loadThemeData() async {
    final uid = AuthService.instance.currentSession?.id.toString();
    if (uid == null) {
      return _ThemeSettingsData(
        uid: '',
        companyTheme: CompanyThemeData.standard,
        selectedThemeId: CompanyThemeService.lightThemeChoice,
      );
    }

    final companyTheme = await CompanyThemeService.resolveCompanyThemeForUser(
      uid,
    );
    final selectedThemeId =
        await CompanyThemeService.selectedThemeChoiceForUser(
      uid,
    );
    _selectedThemeId = selectedThemeId;

    return _ThemeSettingsData(
      uid: uid,
      companyTheme: companyTheme,
      selectedThemeId: selectedThemeId,
    );
  }

  Future<void> _selectTheme(String uid, String themeId) async {
    setState(() => _selectedThemeId = themeId);
    await CompanyThemeService.setSelectedThemeChoiceForUser(uid, themeId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ThemeSettingsData>(
      future: _themeDataFuture,
      builder: (context, snapshot) {
        final pageTheme = widget.pageTheme;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.all(16),
            decoration: _panelDecoration(pageTheme),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: pageTheme.iconColor,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading theme options...',
                  style: TextStyle(
                    color: pageTheme.mutedInkColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data;
        if (data == null || data.uid.isEmpty) {
          return const SizedBox.shrink();
        }

        final selectedThemeId = _selectedThemeId ?? data.selectedThemeId;
        final choices = CompanyThemeService.availableThemeChoicesFor(
          data.companyTheme,
        );
        final effectiveSelectedThemeId = !data.companyTheme.isCompanyTheme &&
                selectedThemeId == CompanyThemeService.companyThemeChoice
            ? CompanyThemeService.lightThemeChoice
            : selectedThemeId;
        final selectedChoice = choices.firstWhere(
          (choice) => effectiveSelectedThemeId == choice.id,
          orElse: () => choices.first,
        );
        final selectedPreviewTheme = CompanyThemeService.applyThemeChoice(
          data.companyTheme,
          selectedChoice.id,
        );

        return Container(
          margin: EdgeInsets.only(bottom: 10),
          decoration: _panelDecoration(pageTheme),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 18,
                    ),
                    child: Row(
                      children: [
                        _ThemeSwatch(theme: selectedPreviewTheme),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Theme',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: pageTheme.inkColor,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                selectedChoice.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: pageTheme.mutedInkColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            size: 15,
                            color: pageTheme.inkColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 1,
                          color: pageTheme.mutedInkColor.withValues(
                            alpha: 0.16,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          data.companyTheme.isCompanyTheme
                              ? 'Choose your app theme. Your company theme is available here.'
                              : 'Choose your app theme.',
                          style: TextStyle(
                            color: pageTheme.mutedInkColor,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 12),
                        ...choices.map((choice) {
                          final previewTheme =
                              CompanyThemeService.applyThemeChoice(
                            data.companyTheme,
                            choice.id,
                          );
                          return Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: _ThemeChoiceTile(
                              choice: choice,
                              previewTheme: previewTheme,
                              pageTheme: pageTheme,
                              selected: selectedThemeId == choice.id ||
                                  (!data.companyTheme.isCompanyTheme &&
                                      selectedThemeId ==
                                          CompanyThemeService
                                              .companyThemeChoice &&
                                      choice.id ==
                                          CompanyThemeService.lightThemeChoice),
                              onTap: () => _selectTheme(data.uid, choice.id),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _panelDecoration(CompanyThemeData pageTheme) {
    return BoxDecoration(
      color: pageTheme.isDark ? pageTheme.surfaceColor : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: pageTheme.isDark
            ? pageTheme.primaryColor.withValues(alpha: 0.18)
            : const Color(0xFFE3EAE8),
      ),
    );
  }
}

class _ThemeChoiceTile extends StatelessWidget {
  const _ThemeChoiceTile({
    required this.choice,
    required this.previewTheme,
    required this.pageTheme,
    required this.selected,
    required this.onTap,
  });

  final CompanyThemeChoice choice;
  final CompanyThemeData previewTheme;
  final CompanyThemeData pageTheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? pageTheme.iconColor.withValues(alpha: 0.12)
                : pageTheme.backgroundColor.withValues(
                    alpha: pageTheme.isDark ? 0.24 : 0.55,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? pageTheme.iconColor
                  : pageTheme.mutedInkColor.withValues(alpha: 0.16),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              _ThemeSwatch(theme: previewTheme),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pageTheme.inkColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      choice.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: pageTheme.mutedInkColor,
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? pageTheme.iconColor : pageTheme.mutedInkColor,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});

  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 40,
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.mutedInkColor.withValues(alpha: 0.2),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 7,
            top: 7,
            child: _SwatchDot(color: theme.primaryColor),
          ),
          Positioned(
            left: 19,
            top: 7,
            child: _SwatchDot(color: theme.accentColor),
          ),
          Positioned(
            right: 7,
            bottom: 7,
            child: Container(
              width: 20,
              height: 14,
              decoration: BoxDecoration(
                color: theme.surfaceColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ThemeSettingsData {
  const _ThemeSettingsData({
    required this.uid,
    required this.companyTheme,
    required this.selectedThemeId,
  });

  final String uid;
  final CompanyThemeData companyTheme;
  final String selectedThemeId;
}
