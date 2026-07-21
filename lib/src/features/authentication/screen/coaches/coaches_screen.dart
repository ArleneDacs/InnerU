import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'chat_room.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/coach_directory_api_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';
import 'package:selfcare_projects/src/utils/phone_launcher.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coaches App',
      home: CoachesScreen(),
    );
  }
}

class Coach {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String bio;
  final String profilePic; // New field for profile picture URL
  final String companyId;
  final String companyName;
  final Color backgroundColor;

  Coach({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.bio = '',
    this.profilePic = '', // Default empty if no image
    this.companyId = '',
    this.companyName = '',
    required this.backgroundColor,
  });
}

enum CoachApplicationStatus {
  none,
  pending,
  accepted,
  rejected,
}

class CoachApplication {
  const CoachApplication({
    required this.coachId,
    required this.status,
  });

  final String coachId;
  final CoachApplicationStatus status;

  factory CoachApplication.fromJson(Map<String, dynamic> data) {
    final statusName = (data['status'] as String?)?.toLowerCase().trim() ?? '';
    return CoachApplication(
      coachId: (data['coachId'] as String?)?.trim() ?? '',
      status: switch (statusName) {
        'pending' => CoachApplicationStatus.pending,
        'accepted' => CoachApplicationStatus.accepted,
        'rejected' => CoachApplicationStatus.rejected,
        _ => CoachApplicationStatus.none,
      },
    );
  }
}

class CoachProfileDialog extends StatelessWidget {
  final Coach coach;
  final CoachApplicationStatus applicationStatus;

  const CoachProfileDialog({
    super.key,
    required this.coach,
    this.applicationStatus = CoachApplicationStatus.accepted,
  });

  Future<void> _launchDialer(BuildContext context, String phoneNumber) async {
    final normalizedPhoneNumber = normalizePhoneNumber(phoneNumber);
    if (normalizedPhoneNumber.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('This coach does not have a valid phone number yet.'),
        ),
      );
      return;
    }

    final session = AuthService.instance.currentSession;
    if (session == null) {
      debugPrint('No user logged in');
      return;
    }

    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final userData = await UserService.getUserData();
      final username = (userData['username'] as String?)?.trim().isNotEmpty == true
          ? (userData['username'] as String).trim()
          : (session.name.trim().isNotEmpty ? session.name.trim() : 'Unknown User');
      final membershipData = await CompanyMembershipService.loadForUser(
        session.id.toString(),
      );

      final launched = await launchPhoneNumber(normalizedPhoneNumber);
      if (!launched) {
        debugPrint('Could not launch dialer');
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

      final companyFields = CompanyMembershipService.activeCompanyFields(
        membershipData.activeMembership,
      );
      await DailyTrackerApiService.instance.upsert(
        date: formattedDate,
        call: true,
        username: username,
        companyId: companyFields['companyId']?.toString(),
        companyCode: companyFields['companyCode']?.toString(),
        companyName: companyFields['companyName']?.toString(),
      );
      debugPrint('Daily tracker call saved successfully.');
    } catch (e) {
      debugPrint('Error saving call tracker: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: coach.backgroundColor,
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
                    CupertinoIcons.chat_bubble_2_fill,
                    size: 30,
                    color: Colors.white,
                  ),
                  onPressed: () async {
                    if (applicationStatus != CoachApplicationStatus.accepted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Chat opens after this coach accepts your application.',
                          ),
                        ),
                      );
                      return;
                    }

                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final session = AuthService.instance.currentSession;
                    if (session == null) {
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('Please log in first.')),
                      );
                      return;
                    }

                    String userName = 'User';
                    try {
                      final data = await UserService.getUserData();
                      userName =
                          (data['username'] as String?)?.trim().isNotEmpty ==
                                  true
                              ? (data['username'] as String)
                              : (session.email.trim().isNotEmpty
                                  ? session.email.split('@').first
                                  : 'User');
                    } catch (_) {
                      userName = session.email.trim().isNotEmpty
                          ? session.email.split('@').first
                          : 'User';
                    }

                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute(
                        builder: (context) => ChatRoomScreen(
                          coach: coach,
                          userId: session.id.toString(),
                          userName: userName,
                        ),
                      ),
                    );
                  },
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
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            GestureDetector(
              onTap: () {
                _launchDialer(
                    context,
                    coach
                        .phone); // Call the launcher with the coach's phone number
              },
              child: Text(
                coach.phone.isNotEmpty ? coach.phone : 'No phone available',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  decoration: TextDecoration.underline,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'About',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
              child: Text(
                coach.bio.isEmpty ? 'No bio available' : coach.bio,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoachesScreen extends StatefulWidget {
  const CoachesScreen({super.key});

  @override
  State<CoachesScreen> createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> {
  late TextEditingController _searchController;
  String _currentCompanyId = '';
  String _currentCompanyName = '';
  String _currentCompanyCode = '';
  Future<List<Coach>> _coachesFuture = Future.value(const <Coach>[]);
  Future<Map<String, CoachApplication>> _applicationsFuture =
      Future.value(const <String, CoachApplication>{});

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _companyIdFromData(Map<String, dynamic>? data) {
    return ((data?['activeCompanyId'] as String?)?.trim() ??
            (data?['companyId'] as String?)?.trim() ??
            '')
        .toLowerCase();
  }

  String _companyNameFromData(Map<String, dynamic>? data) {
    return ((data?['activeCompanyName'] as String?)?.trim() ??
            (data?['companyName'] as String?)?.trim() ??
            '')
        .toLowerCase();
  }

  String _companyCodeFromData(Map<String, dynamic>? data) {
    return ((data?['activeCompanyCode'] as String?)?.trim() ??
            (data?['companyCode'] as String?)?.trim() ??
            '')
        .toLowerCase();
  }

  Future<void> _bootstrap() async {
    await _loadCurrentCompany();
    if (!mounted) return;
    setState(() {
      _coachesFuture = _loadCoaches();
      _applicationsFuture = _loadApplications();
    });
  }

  Future<void> _loadCurrentCompany() async {
    try {
      final data = await UserService.getUserData();
      if (!mounted) return;
      setState(() {
        _currentCompanyId = _companyIdFromData(data);
        _currentCompanyName = _companyNameFromData(data);
        _currentCompanyCode = _companyCodeFromData(data);
      });
    } catch (error) {
      debugPrint('Failed to load current company for coaches: $error');
    }
  }

  bool _isSameCompanyCoach(Coach coach) {
    if (_currentCompanyCode.isNotEmpty && coach.companyId.isNotEmpty) {
      return coach.companyId == _currentCompanyCode;
    }
    if (_currentCompanyId.isNotEmpty && coach.companyId.isNotEmpty) {
      return coach.companyId == _currentCompanyId;
    }
    if (_currentCompanyName.isNotEmpty && coach.companyName.isNotEmpty) {
      return coach.companyName == _currentCompanyName;
    }
    return false;
  }

  List<Coach> _filterCoaches(
    List<Coach> coaches, {
    required bool sameCompanyOnly,
  }) {
    final query = _searchController.text.trim().toLowerCase();
    return coaches.where((coach) {
      if (sameCompanyOnly && !_isSameCompanyCoach(coach)) return false;
      if (query.isEmpty) return true;
      return coach.name.toLowerCase().contains(query) ||
          coach.bio.toLowerCase().contains(query) ||
          coach.email.toLowerCase().contains(query) ||
          coach.phone.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _applyToCoach(Coach coach) async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first.')),
      );
      return;
    }
    if (coach.id == session.id.toString()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose another coach to apply as a mentee.'),
        ),
      );
      return;
    }

    final userData = await UserService.getUserData();
    final role = (userData['role'] as String?)?.trim().toLowerCase() ?? '';
    final isCoachApplicant = userData['isCoach'] == true || role == 'coach';
    final userName =
        (userData['username'] as String?)?.trim().isNotEmpty == true
            ? (userData['username'] as String).trim()
            : (session.name.trim().isNotEmpty
                ? session.name.trim()
                : (session.email.split('@').first));
    await CoachApiService.instance.createRequest(
      coachId: coach.id,
      coachName: coach.name,
      coachEmail: coach.email,
      applicantRole:
          isCoachApplicant ? 'coach' : (role.isNotEmpty ? role : 'user'),
      applicantIsCoach: isCoachApplicant,
      applyingAs: 'mentee',
      status: 'pending',
      menteeName: userName,
      menteeEmail: (userData['email'] as String?)?.trim() ?? session.email,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Application sent to ${coach.name}.')),
    );
  }

  Future<List<Coach>> _loadCoaches() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return const <Coach>[];

    final currentUserId = session.id.toString();
    final currentCompanyId = _currentCompanyId;
    final currentCompanyName = _currentCompanyName;

    final directory = await CoachDirectoryApiService.instance.fetchCoaches();
    final coaches = directory
        .where((coach) => coach.id != currentUserId)
        .where((coach) {
          if (currentCompanyId.isEmpty && currentCompanyName.isEmpty) {
            return true;
          }
          final sameCompanyId =
              currentCompanyId.isNotEmpty &&
                  coach.companyCode?.trim().isNotEmpty == true &&
                  coach.companyCode!.trim().toLowerCase() ==
                      currentCompanyId.toLowerCase();
          final sameCompanyName =
              currentCompanyName.isNotEmpty &&
                  coach.companyName?.trim().isNotEmpty == true &&
                  coach.companyName!.trim().toLowerCase() ==
                      currentCompanyName.toLowerCase();
          return sameCompanyId || sameCompanyName;
        })
        .map(
          (entry) => Coach(
            id: entry.id,
            name: entry.name.isNotEmpty ? entry.name : 'Coach',
            email: entry.email,
            phone: entry.number ?? '',
            bio: '',
            profilePic: entry.profilePic ?? '',
            companyId: entry.companyCode ?? '',
            companyName: entry.companyName ?? '',
            backgroundColor: const Color(0xFF6D849A),
          ),
        )
        .toList();

    coaches.sort((a, b) => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ));
    return coaches;
  }

  Future<Map<String, CoachApplication>> _loadApplications() async {
    try {
      final requests = await CoachApiService.instance.fetchRequests();
      final applications = <String, CoachApplication>{};
      for (final request in requests) {
        final application = CoachApplication.fromJson(request);
        if (application.coachId.isNotEmpty) {
          applications[application.coachId] = application;
        }
      }
      return applications;
    } catch (_) {
      return const <String, CoachApplication>{};
    }
  }

  String _applicationLabel(CoachApplicationStatus status) {
    return switch (status) {
      CoachApplicationStatus.pending => 'Pending',
      CoachApplicationStatus.accepted => 'Connected',
      CoachApplicationStatus.rejected => 'Apply again',
      CoachApplicationStatus.none => 'Apply',
    };
  }

  IconData _applicationIcon(CoachApplicationStatus status) {
    return switch (status) {
      CoachApplicationStatus.pending => CupertinoIcons.clock,
      CoachApplicationStatus.accepted =>
        CupertinoIcons.check_mark_circled_solid,
      CoachApplicationStatus.rejected => CupertinoIcons.arrow_clockwise,
      CoachApplicationStatus.none => CupertinoIcons.person_badge_plus,
    };
  }

  Widget _buildCoachList({
    required BuildContext context,
    required List<Coach> coaches,
    required Map<String, CoachApplication> applications,
    required CompanyThemeData companyTheme,
    required String emptyMessage,
  }) {
    if (coaches.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: TextStyle(color: companyTheme.mutedInkColor),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(context.responsiveValue(16)),
      itemCount: coaches.length,
      itemBuilder: (context, index) {
        final coach = coaches[index];
        final application = applications[coach.id];
        final status = application?.status ?? CoachApplicationStatus.none;
        final canApply = status == CoachApplicationStatus.none ||
            status == CoachApplicationStatus.rejected;
        return Container(
          margin: EdgeInsets.only(
            bottom: context.responsiveValue(10),
          ),
          decoration: BoxDecoration(
            color: companyTheme.isDark
                ? companyTheme.surfaceColor
                : coach.backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: companyTheme.isDark
                ? Border.all(
                    color: companyTheme.primaryColor.withValues(alpha: 0.18),
                  )
                : null,
            boxShadow: companyTheme.isDark
                ? null
                : [
                    BoxShadow(
                      color: coach.backgroundColor.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.responsiveValue(16),
              vertical: context.responsiveValue(6),
            ),
            leading: CircleAvatar(
              backgroundColor: companyTheme.isDark
                  ? companyTheme.primaryColor.withValues(alpha: 0.16)
                  : Colors.white,
              backgroundImage: coach.profilePic.isNotEmpty
                  ? NetworkImage(coach.profilePic)
                  : null,
              child: coach.profilePic.isEmpty
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            title: Text(
              coach.name,
              style: TextStyle(
                color:
                    companyTheme.isDark ? companyTheme.inkColor : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: context.responsiveFont(16),
              ),
            ),
            subtitle: Text(
              coach.bio.isEmpty ? 'Coach profile' : coach.bio,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: companyTheme.isDark
                    ? companyTheme.mutedInkColor
                    : Colors.white70,
                fontSize: context.responsiveFont(13),
              ),
            ),
            trailing: FilledButton.icon(
              onPressed: canApply ? () => _applyToCoach(coach) : null,
              icon: Icon(
                _applicationIcon(status),
                size: 18,
              ),
              label: Text(
                _applicationLabel(status),
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: status == CoachApplicationStatus.accepted
                    ? companyTheme.primaryColor
                    : companyTheme.accentColor,
                disabledBackgroundColor:
                    companyTheme.primaryColor.withValues(alpha: 0.18),
                disabledForegroundColor:
                    companyTheme.inkColor.withValues(alpha: 0.72),
              ),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => CoachProfileDialog(
                  coach: coach,
                  applicationStatus: status,
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = context.isTabletWidth ? 320.0 : 220.0;

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: companyTheme.surfaceColor,
            foregroundColor: companyTheme.inkColor,
            surfaceTintColor: Colors.transparent,
            title: Text(
              'Our Coaches',
              style: TextStyle(color: companyTheme.inkColor),
            ),
          ),
          body: SafeArea(
            child: ResponsiveContent(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: context.responsiveValue(20),
                      ),
                      child: SizedBox(
                        height: heroHeight,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Image.asset(
                            'assets/images/coachpic.png',
                            width: context.isTabletWidth ? 520 : 320,
                            height: context.isTabletWidth ? 360 : 240,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(context.responsiveValue(16)),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search coaches',
                          filled: true,
                          fillColor: companyTheme.isDark
                              ? companyTheme.surfaceColor
                              : Colors.white,
                          hintStyle:
                              TextStyle(color: companyTheme.mutedInkColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: companyTheme.isDark
                                ? BorderSide(
                                    color: companyTheme.primaryColor
                                        .withValues(alpha: 0.2),
                                  )
                                : const BorderSide(color: Color(0xFFE3EAE8)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: companyTheme.isDark
                                ? BorderSide(
                                    color: companyTheme.primaryColor
                                        .withValues(alpha: 0.2),
                                  )
                                : const BorderSide(color: Color(0xFFE3EAE8)),
                          ),
                          prefixIcon: Icon(
                            CupertinoIcons.search,
                            color: companyTheme.isDark
                                ? companyTheme.primaryColor
                                : null,
                          ),
                        ),
                        style: TextStyle(color: companyTheme.inkColor),
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: context.responsiveValue(16),
                      ),
                      decoration: BoxDecoration(
                        color: companyTheme.isDark
                            ? companyTheme.surfaceColor
                            : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: companyTheme.mutedInkColor.withValues(
                            alpha: companyTheme.isDark ? 0.22 : 0.16,
                          ),
                        ),
                      ),
                      child: TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor:
                            companyTheme.iconColor.computeLuminance() > 0.48
                                ? Colors.black
                                : Colors.white,
                        unselectedLabelColor: companyTheme.inkColor,
                        indicator: BoxDecoration(
                          color: companyTheme.iconColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        tabs: const [
                          Tab(text: 'All Coaches'),
                          Tab(text: 'Same Company'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: FutureBuilder<Map<String, CoachApplication>>(
                        future: _applicationsFuture,
                        builder: (context, applicationsSnapshot) {
                          final applications = applicationsSnapshot.data ??
                              const <String, CoachApplication>{};
                          return FutureBuilder<List<Coach>>(
                            future: _coachesFuture,
                            builder: (context, coachesSnapshot) {
                              if (coachesSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (!coachesSnapshot.hasData ||
                                  coachesSnapshot.data!.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No coaches are available yet.',
                                    style: TextStyle(
                                      color: companyTheme.mutedInkColor,
                                    ),
                                  ),
                                );
                              }

                              final allCoaches = _filterCoaches(
                                coachesSnapshot.data!,
                                sameCompanyOnly: false,
                              );
                              final sameCompanyCoaches = _filterCoaches(
                                coachesSnapshot.data!,
                                sameCompanyOnly: true,
                              );

                              return TabBarView(
                                children: [
                                  _buildCoachList(
                                    context: context,
                                    coaches: allCoaches,
                                    applications: applications,
                                    companyTheme: companyTheme,
                                    emptyMessage:
                                        'No coaches match your search.',
                                  ),
                                  _buildCoachList(
                                    context: context,
                                    coaches: sameCompanyCoaches,
                                    applications: applications,
                                    companyTheme: companyTheme,
                                    emptyMessage: _currentCompanyId.isEmpty &&
                                            _currentCompanyName.isEmpty &&
                                            _currentCompanyCode.isEmpty
                                        ? 'Join a company to see company coaches.'
                                        : 'No coaches from your company match your search.',
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
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
