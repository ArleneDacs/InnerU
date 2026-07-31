import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

class CompanySelectionGate extends StatefulWidget {
  const CompanySelectionGate({
    super.key,
    required this.uid,
    required this.builder,
  });

  final String uid;
  final WidgetBuilder builder;

  @override
  State<CompanySelectionGate> createState() => _CompanySelectionGateState();
}

class _CompanySelectionGateState extends State<CompanySelectionGate> {
  static final Set<String> _selectedLoginSessions = <String>{};

  bool _isChecking = true;
  bool _requiresSelection = false;
  List<CompanyMembership> _memberships = const <CompanyMembership>[];
  CompanyMembership? _activeMembership;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareCompanySelection());
  }

  Future<void> _prepareCompanySelection() async {
    try {
      final userData = await UserService.getUserData();
      if (userData.isEmpty) {
        if (!mounted) return;
        setState(() => _isChecking = false);
        return;
      }

      final role = (userData['role'] as String?)?.trim().toLowerCase() ?? '';
      if (role == 'admin' || userData['isAdmin'] == true) {
        if (!mounted) return;
        setState(() => _isChecking = false);
        return;
      }

      final membershipData = CompanyMembershipService.fromUserData(userData);
      final memberships = membershipData.memberships;
      if (memberships.length <= 1) {
        if (memberships.length == 1 &&
            !_sameCompany(memberships.first, membershipData.activeMembership)) {
          await CompanyMembershipService.setActiveCompany(
            uid: widget.uid,
            membership: memberships.first,
          );
        }
        if (!mounted) return;
        setState(() => _isChecking = false);
        return;
      }

      final loginSessionKey = _currentLoginSessionKey();
      if (_selectedLoginSessions.contains(loginSessionKey)) {
        if (!mounted) return;
        setState(() => _isChecking = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _memberships = memberships;
        _activeMembership = membershipData.activeMembership;
        _requiresSelection = true;
        _isChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isChecking = false);
    }
  }

  Future<void> _selectCompany(CompanyMembership membership) async {
    await CompanyMembershipService.setActiveCompany(
      uid: widget.uid,
      membership: membership,
    );
    _selectedLoginSessions.add(_currentLoginSessionKey());
    if (!mounted) return;
    setState(() {
      _activeMembership = membership;
      _requiresSelection = false;
    });
  }

  String _currentLoginSessionKey() {
    final session = AuthService.instance.currentSession;
    return '${widget.uid}:${session?.token.hashCode ?? 'active'}';
  }

  bool _sameCompany(CompanyMembership left, CompanyMembership? right) {
    if (right == null) return false;
    return (left.id.isNotEmpty && left.id == right.id) ||
        (left.code.isNotEmpty && left.code == right.code);
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_requiresSelection) {
      return _CompanySelectionScreen(
        memberships: _memberships,
        activeMembership: _activeMembership,
        onSelect: _selectCompany,
      );
    }

    return widget.builder(context);
  }
}

class _CompanySelectionScreen extends StatefulWidget {
  const _CompanySelectionScreen({
    required this.memberships,
    required this.activeMembership,
    required this.onSelect,
  });

  final List<CompanyMembership> memberships;
  final CompanyMembership? activeMembership;
  final Future<void> Function(CompanyMembership membership) onSelect;

  @override
  State<_CompanySelectionScreen> createState() =>
      _CompanySelectionScreenState();
}

class _CompanySelectionScreenState extends State<_CompanySelectionScreen> {
  String _savingCompanyId = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F1),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Text(
                  'Choose company',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF24311F),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick the company workspace you want to enter for this session.',
                  style: TextStyle(
                    color: Color(0xFF5E6E57),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                ...widget.memberships.map((membership) {
                  final isActive = _sameCompany(
                    membership,
                    widget.activeMembership,
                  );
                  final isSaving = _savingCompanyId == membership.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: isSaving
                            ? null
                            : () async {
                                setState(() {
                                  _savingCompanyId = membership.id;
                                });
                                await widget.onSelect(membership);
                              },
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFF3E9189)
                                  : const Color(0xFFE3EAE8),
                              width: isActive ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE9EEE4),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.business_rounded,
                                  color: Color(0xFF3E9189),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      membership.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF24311F),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${membership.code} · ${membership.scoreMode.title}',
                                      style: const TextStyle(
                                        color: Color(0xFF5E6E57),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSaving)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Icon(
                                  isActive
                                      ? Icons.check_circle_rounded
                                      : Icons.arrow_forward_ios_rounded,
                                  color: isActive
                                      ? const Color(0xFF3E9189)
                                      : const Color(0xFF5E6E57),
                                  size: isActive ? 24 : 16,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _sameCompany(CompanyMembership left, CompanyMembership? right) {
    if (right == null) return false;
    return (left.id.isNotEmpty && left.id == right.id) ||
        (left.code.isNotEmpty && left.code == right.code);
  }
}

class CompanyLoadingGate extends StatefulWidget {
  const CompanyLoadingGate({
    super.key,
    required this.uid,
    required this.child,
  });

  final String uid;
  final Widget child;

  @override
  State<CompanyLoadingGate> createState() => _CompanyLoadingGateState();
}

class _CompanyLoadingGateState extends State<CompanyLoadingGate>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static final Set<String> _playedLoginSessions = <String>{};

  late final AnimationController _controller;
  bool _isChecking = true;
  bool _showLoading = false;
  bool _isDisposed = false;
  String _loadingImageUrl = '';
  String _loadingVideoUrl = '';
  _CompanyLoadingBrand _loadingBrand = _CompanyLoadingBrand.gencys;
  double _loadingVideoScale = 1;
  BoxFit _loadingVideoFit = BoxFit.cover;
  double _loadingVideoVolume = 0;
  String _loadingAudioAssetPath = '';
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  Timer? _timer;
  Duration _loadingDuration = const Duration(milliseconds: 4400);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    unawaited(_prepareLoadingScreen());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // A video actively decoding while the app is backgrounded is a
        // known source of native crashes on iOS once the GPU surface is
        // invalidated -- pause playback rather than let it keep running.
        unawaited(_videoController?.pause());
        unawaited(_audioPlayer?.pause());
        break;
      case AppLifecycleState.resumed:
        if (_showLoading) {
          unawaited(_videoController?.play());
          unawaited(_audioPlayer?.resume());
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _prepareLoadingScreen() async {
    try {
      final loginSessionKey = _currentLoginSessionKey();
      if (_playedLoginSessions.contains(loginSessionKey)) {
        if (!mounted) return;
        setState(() {
          _isChecking = false;
        });
        return;
      }

      final data = await UserService.getUserData();
      final role = (data['role'] as String?)?.trim().toLowerCase() ?? '';
      final membershipData = CompanyMembershipService.fromUserData(data);
      final activeMembership = membershipData.activeMembership;
      final companyName = ((data['activeCompanyName'] as String?)?.trim() ??
              (data['companyName'] as String?)?.trim() ??
              activeMembership?.name ??
              '')
          .toLowerCase();
      final companyCode = ((data['activeCompanyCode'] as String?)?.trim() ??
              (data['companyCode'] as String?)?.trim() ??
              activeMembership?.code ??
              '')
          .toUpperCase();
      final companyId = ((data['activeCompanyId'] as String?)?.trim() ??
              (data['companyId'] as String?)?.trim() ??
              activeMembership?.id ??
              '')
          .trim();
      final loadingConfig = await _resolveCompanyLoadingConfig(
        companyName: companyName,
        companyCode: companyCode,
        companyId: companyId,
        lookupKeys: CompanyMembershipService.lookupKeysFromUserData(data),
      );

      if (!mounted) return;
      CompanyThemeService.cacheThemeForUser(
        widget.uid,
        loadingConfig.initialTheme,
      );
      if (loadingConfig.showLoading && role != 'admin') {
        _loadingImageUrl = loadingConfig.imageUrl;
        _loadingVideoUrl = loadingConfig.videoUrl;
        _loadingBrand = loadingConfig.brand;
        _loadingVideoScale = loadingConfig.brand.loadingVideoScale;
        _loadingVideoFit = loadingConfig.brand.loadingVideoFit;
        _loadingVideoVolume = loadingConfig.brand.loadingVideoVolume;
        _loadingAudioAssetPath = loadingConfig.brand.loadingAudioAssetPath;

        await _startLoadingSequence(loginSessionKey);
        return;
      }
    } catch (_) {
      // Fall through to the normal app if company lookup fails.
    }

    if (!mounted) return;
    setState(() {
      _isChecking = false;
    });
  }

  Future<void> _startLoadingSequence(String loginSessionKey) async {
    await _prepareLoadingVideo(
      videoUrl: _loadingVideoUrl,
      assetPath: _loadingBrand.loadingVideoAssetPath,
    );
    if (!mounted) return;
    _playedLoginSessions.add(loginSessionKey);
    setState(() {
      _isChecking = false;
      _showLoading = true;
    });
    _controller.duration = _loadingDuration;
    _controller.forward(from: 0);
    unawaited(_playLoadingAudio());
    _timer?.cancel();
    _timer = Timer(_loadingDuration, () {
      if (!mounted) return;
      unawaited(_videoController?.pause());
      unawaited(_stopLoadingAudio());
      setState(() {
        _showLoading = false;
      });
    });
  }

  String _currentLoginSessionKey() {
    final session = AuthService.instance.currentSession;
    return '${widget.uid}:${session?.token.hashCode ?? 'active'}';
  }

  Future<void> _prepareLoadingVideo({
    required String videoUrl,
    required String assetPath,
  }) async {
    await _disposeLoadingVideo();
    _loadingDuration = const Duration(milliseconds: 4400);
    if (videoUrl.isEmpty && assetPath.isEmpty) return;

    final controller = videoUrl.isNotEmpty
        ? VideoPlayerController.networkUrl(Uri.parse(videoUrl))
        : VideoPlayerController.asset(assetPath);
    try {
      await controller.setLooping(false);
      await controller.initialize();
      await controller.setVolume(_loadingVideoVolume);
      if (controller.value.duration > Duration.zero) {
        _loadingDuration =
            controller.value.duration > const Duration(seconds: 8)
                ? const Duration(seconds: 8)
                : controller.value.duration;
      }
      await controller.play();
      if (_isDisposed) {
        // The widget was disposed while initialize()/play() were in
        // flight. dispose() already ran and won't run again, so this
        // controller would otherwise leak as an orphaned, still-playing
        // native video player -- dispose it directly instead of storing it.
        await controller.dispose();
        return;
      }
      _videoController = controller;
    } catch (_) {
      await controller.dispose();
    }
  }

  Future<void> _disposeLoadingVideo() async {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> _playLoadingAudio() async {
    if (_loadingAudioAssetPath.isEmpty) return;
    await _stopLoadingAudio();
    final player = AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer);
    _audioPlayer = player;
    try {
      await player.setReleaseMode(ReleaseMode.release);
      await player.setVolume(1);
      await player.play(AssetSource(_loadingAudioAssetPath));
    } catch (_) {
      await _stopLoadingAudio();
    }
  }

  Future<void> _stopLoadingAudio() async {
    final player = _audioPlayer;
    _audioPlayer = null;
    if (player != null) {
      await player.stop();
      await player.release();
      await player.dispose();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_disposeLoadingVideo());
    unawaited(_stopLoadingAudio());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_showLoading) return widget.child;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final rawProgress = _controller.value;
          final progress = Curves.easeInOutCubic.transform(rawProgress);
          final pulse = (math.sin(rawProgress * math.pi * 6) + 1) / 2;
          final status = _loadingStatus(progress);
          final hasUploadedVideo =
              _videoController != null && _videoController!.value.isInitialized;

          if (hasUploadedVideo) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _CompanyLoadingMedia(
                  imageUrl: _loadingImageUrl,
                  videoController: _videoController,
                  fallbackAsset: _loadingBrand.assetPath,
                  videoScale: _loadingVideoScale,
                  videoFit: _loadingVideoFit,
                ),
                _GameLoadingOverlay(
                  progress: progress,
                  shimmer: rawProgress,
                  pulse: pulse,
                  brand: _loadingBrand,
                  status: status,
                ),
              ],
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                scale: 1 + (progress * 0.035),
                child: Opacity(
                  opacity: 0.88 + (progress * 0.12),
                  child: _CompanyLoadingMedia(
                    imageUrl: _loadingImageUrl,
                    videoController: _videoController,
                    fallbackAsset: _loadingBrand.assetPath,
                    videoScale: _loadingVideoScale,
                    videoFit: _loadingVideoFit,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.12),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                    stops: const [0, 0.48, 1],
                  ),
                ),
              ),
              CustomPaint(
                painter: _GencysLoadingPainter(
                  progress: rawProgress,
                  pulse: pulse,
                  primaryColor: _loadingBrand.primaryColor,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.08 + (pulse * 0.04)),
                        radius: 0.46 + (pulse * 0.08),
                        colors: [
                          _loadingBrand.primaryColor.withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.paddingOf(context).top + 18,
                child: Opacity(
                  opacity: 0.68 + (pulse * 0.22),
                  child: Text(
                    _loadingBrand.connectingText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _loadingBrand.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 34,
                right: 34,
                bottom: 74,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: Text(
                        status,
                        key: ValueKey(status),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _GencysProgressBar(
                      progress: progress,
                      shimmer: rawProgress,
                      primaryColor: _loadingBrand.primaryColor,
                      accentColor: _loadingBrand.accentColor,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(progress * 100).clamp(0, 100).round()}%',
                          style: TextStyle(
                            color: _loadingBrand.primaryColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: 0.55 + (pulse * 0.35),
                      child: Text(
                        _loadingBrand.tagline.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _loadingBrand.softColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: (1 - (rawProgress / 0.16)).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _loadingStatus(double progress) {
    if (_loadingBrand.displayName ==
        _CompanyLoadingBrand.abundance12.displayName) {
      if (progress < 0.24) return 'FORGING PLAYER SESSION';
      if (progress < 0.48) return 'CHARGING LEGEND HUD';
      if (progress < 0.74) return 'SYNCING QUEST PROFILE';
      if (progress < 0.94) return 'OPENING ARENA GATES';
      return 'READY PLAYER';
    }
    if (progress < 0.24) return 'AUTHENTICATING COMPANY ACCESS';
    if (progress < 0.48) return 'SYNCING WORKSPACE PROFILE';
    if (progress < 0.74) return 'ACTIVATING AUTOMATION MODULES';
    if (progress < 0.94) return 'FINALIZING SECURE SESSION';
    return 'WELCOME TO ${_loadingBrand.displayName.toUpperCase()}';
  }

  Future<_CompanyLoadingConfig> _resolveCompanyLoadingConfig({
    required String companyName,
    required String companyCode,
    required String companyId,
    required List<String> lookupKeys,
  }) async {
    final profileBrand = _brandForCompany(companyName, companyCode);
    final searchKeys = lookupKeys.isNotEmpty
        ? lookupKeys
        : <String>[
            if (companyId.isNotEmpty) companyId,
            if (companyCode.isNotEmpty) companyCode,
          ];

    for (final lookupKey in searchKeys) {
      final company = await CompanyApiService.instance.findByCode(lookupKey);
      if (company == null) continue;

      final companyData = _companyDataFromApi(company);
      final docName = company.name.trim().toLowerCase();
      final docCode = company.code.trim().toUpperCase();
      final loadingImageUrl = company.loadingImageUrl?.trim() ?? '';
      final loadingVideoUrl = company.loadingVideoUrl?.trim() ?? '';
      final brand = _brandForCompany(docName, docCode);
      final themeBrand = _brandFromCompanyData(
        companyData,
        fallbackName: docName,
        fallbackCode: docCode,
      );
      final initialTheme = CompanyThemeService.fromCompanyData(
        companyData,
        fallbackName: docName,
        fallbackCode: docCode,
      );

      if (brand != null ||
          loadingImageUrl.isNotEmpty ||
          loadingVideoUrl.isNotEmpty) {
        return _CompanyLoadingConfig(
          showLoading: true,
          brand: brand ??
              themeBrand ??
              profileBrand ??
              _CompanyLoadingBrand.gencys,
          imageUrl: loadingImageUrl,
          videoUrl: loadingVideoUrl,
          initialTheme: initialTheme,
        );
      }
    }

    return _CompanyLoadingConfig(
      showLoading: profileBrand != null,
      brand: profileBrand ?? _CompanyLoadingBrand.gencys,
      initialTheme: CompanyThemeData.standard,
    );
  }

  _CompanyLoadingBrand? _brandForCompany(
      String companyName, String companyCode) {
    if (_matchesGencys(companyName, companyCode)) {
      return _CompanyLoadingBrand.gencys;
    }
    if (_matchesIamPlus(companyName, companyCode)) {
      return _CompanyLoadingBrand.iamPlus;
    }
    if (_matchesAbundanceCompany(companyName, companyCode)) {
      return _CompanyLoadingBrand.abundance12;
    }
    return null;
  }

  _CompanyLoadingBrand? _brandFromCompanyData(
    Map<String, dynamic> data, {
    required String fallbackName,
    required String fallbackCode,
  }) {
    final hasTheme = data['themeEnabled'] == true ||
        ((data['themePrimaryColor'] as String?)?.trim().isNotEmpty == true) ||
        ((data['themeAccentColor'] as String?)?.trim().isNotEmpty == true);
    final hasCompanyIdentity =
        fallbackName.isNotEmpty || fallbackCode.isNotEmpty;
    if (!hasTheme && !hasCompanyIdentity) return null;

    final theme = CompanyThemeService.fromCompanyData(
      data,
      fallbackName: fallbackName,
      fallbackCode: fallbackCode,
    );
    final displayName =
        (fallbackName.isNotEmpty ? fallbackName : fallbackCode).toUpperCase();
    final safeDisplayName = displayName.isEmpty ? 'YOUR COMPANY' : displayName;
    final primaryColor =
        hasTheme ? theme.primaryColor : CompanyThemeData.standard.primaryColor;
    final accentColor =
        hasTheme ? theme.accentColor : CompanyThemeData.standard.accentColor;

    return _CompanyLoadingBrand(
      displayName: safeDisplayName,
      connectingText: 'ENTERING $safeDisplayName',
      tagline: theme.tagline,
      assetPath: _CompanyLoadingBrand.gencys.assetPath,
      primaryColor: primaryColor,
      accentColor: accentColor,
      softColor:
          hasTheme ? theme.iconColor : CompanyThemeData.standard.iconColor,
    );
  }

  Map<String, dynamic> _companyDataFromApi(CompanyApiCompany company) {
    return {
      'name': company.name,
      'code': company.code,
      'themeEnabled': company.themeEnabled,
      'themePrimaryColor': company.themePrimaryColor,
      'themeAccentColor': company.themeAccentColor,
      'themeBackgroundColor': company.themeBackgroundColor,
      'themeSurfaceColor': company.themeSurfaceColor,
      'themeInkColor': company.themeInkColor,
      'themeMutedInkColor': company.themeMutedInkColor,
      'themeIconColor': company.themeIconColor,
      'themeMode': company.themeMode,
      'themeSource': company.themeSource,
      'logoUrl': company.logoUrl,
      'tagline': company.tagline,
      'loadingImageUrl': company.loadingImageUrl,
      'loadingVideoUrl': company.loadingVideoUrl,
    };
  }

  bool _matchesGencys(String companyName, String companyCode) {
    final normalizedName = companyName.toLowerCase();
    final normalizedCode = companyCode.toUpperCase();
    return normalizedName.contains('gencys') ||
        normalizedCode.contains('GENCYS') ||
        normalizedCode.startsWith('GEN');
  }

  bool _matchesIamPlus(String companyName, String companyCode) {
    final normalizedName =
        companyName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '');
    final normalizedCode =
        companyCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9+]'), '');
    return normalizedName.contains('iamplus') ||
        normalizedName.contains('iam+') ||
        normalizedName.contains('iam') && normalizedName.contains('plus') ||
        normalizedCode.contains('IAMPLUS') ||
        normalizedCode.contains('IAM+') ||
        normalizedCode.startsWith('IAM');
  }

  bool _matchesAbundanceCompany(String companyName, String companyCode) {
    return AbundanceCompany.matches(companyCode, companyName);
  }
}

class _CompanyLoadingConfig {
  const _CompanyLoadingConfig({
    required this.showLoading,
    required this.brand,
    required this.initialTheme,
    this.imageUrl = '',
    this.videoUrl = '',
  });

  final bool showLoading;
  final _CompanyLoadingBrand brand;
  final CompanyThemeData initialTheme;
  final String imageUrl;
  final String videoUrl;
}

class _CompanyLoadingBrand {
  const _CompanyLoadingBrand({
    required this.displayName,
    required this.connectingText,
    required this.tagline,
    required this.assetPath,
    required this.primaryColor,
    required this.accentColor,
    required this.softColor,
    this.loadingVideoAssetPath = '',
    this.loadingVideoScale = 1,
    this.loadingVideoFit = BoxFit.cover,
    this.loadingVideoVolume = 0,
    this.loadingAudioAssetPath = '',
  });

  final String displayName;
  final String connectingText;
  final String tagline;
  final String assetPath;
  final Color primaryColor;
  final Color accentColor;
  final Color softColor;
  final String loadingVideoAssetPath;
  final double loadingVideoScale;
  final BoxFit loadingVideoFit;
  final double loadingVideoVolume;
  final String loadingAudioAssetPath;

  static const gencys = _CompanyLoadingBrand(
    displayName: 'GENCYS',
    connectingText: 'CONNECTING TO GENCYS',
    tagline: 'Connect. Automate. Evolve.',
    assetPath: 'assets/images/gencys_loading.png',
    primaryColor: Color(0xFF35FFF4),
    accentColor: Color(0xFF2E7DFF),
    softColor: Color(0xFF7FFFF8),
  );

  static const iamPlus = _CompanyLoadingBrand(
    displayName: 'I AM PLUS',
    connectingText: 'CONNECTING TO I AM PLUS',
    tagline: 'Coaching & Training Systems',
    assetPath: 'assets/images/iamplus.png',
    primaryColor: Color(0xFF22E5FF),
    accentColor: Color(0xFFE237FF),
    softColor: Color(0xFFFFB8FF),
  );

  static const abundance12 = _CompanyLoadingBrand(
    displayName: 'ABUNDANCE 12',
    connectingText: 'ENTERING ABUNDANCE 12',
    tagline: 'Where legends are made',
    assetPath: 'assets/images/abundance12_loading.jpg',
    primaryColor: Color(0xFFEFD199),
    accentColor: Color(0xFF2E7DFF),
    softColor: Color(0xFFFFF2C2),
    loadingVideoAssetPath: 'assets/videos/abundance12_loading.mp4',
    loadingVideoScale: 1,
    loadingVideoFit: BoxFit.cover,
    loadingVideoVolume: 0,
    loadingAudioAssetPath: 'audio/abundance12_loading.m4a',
  );
}

class _CompanyLoadingMedia extends StatelessWidget {
  const _CompanyLoadingMedia({
    required this.imageUrl,
    required this.videoController,
    required this.fallbackAsset,
    this.videoScale = 1,
    this.videoFit = BoxFit.cover,
  });

  final String imageUrl;
  final VideoPlayerController? videoController;
  final String fallbackAsset;
  final double videoScale;
  final BoxFit videoFit;

  @override
  Widget build(BuildContext context) {
    final controller = videoController;
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      return SizedBox.expand(
        child: Transform.scale(
          scale: videoScale,
          child: FittedBox(
            fit: videoFit,
            child: SizedBox(
              width: size.width > 0 ? size.width : 1080,
              height: size.height > 0 ? size.height : 1920,
              child: IgnorePointer(child: VideoPlayer(controller)),
            ),
          ),
        ),
      );
    }

    if (imageUrl.isNotEmpty) {
      return SizedBox.expand(
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _fallbackImage(),
        ),
      );
    }

    return SizedBox.expand(child: _fallbackImage());
  }

  Widget _fallbackImage() {
    return Image.asset(
      fallbackAsset,
      fit: BoxFit.cover,
    );
  }
}

class _GameLoadingOverlay extends StatelessWidget {
  const _GameLoadingOverlay({
    required this.progress,
    required this.shimmer,
    required this.pulse,
    required this.brand,
    required this.status,
  });

  final double progress;
  final double shimmer;
  final double pulse;
  final _CompanyLoadingBrand brand;
  final String status;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final percent = (progress * 100).clamp(0, 100).round();

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.28),
                  Colors.black.withValues(alpha: 0.82),
                ],
                stops: const [0, 0.42, 0.68, 1],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: bottomPadding + 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$percent%',
                    style: TextStyle(
                      color: brand.softColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _LegendProgressBar(
                  progress: progress,
                  shimmer: shimmer,
                  pulse: pulse,
                  primaryColor: brand.primaryColor,
                  accentColor: brand.accentColor,
                  softColor: brand.softColor,
                ),
                const SizedBox(height: 11),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    status,
                    key: ValueKey(status),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                      shadows: [
                        Shadow(
                          color: brand.accentColor.withValues(alpha: 0.65),
                          blurRadius: 12,
                        ),
                      ],
                    ),
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

class _LegendProgressBar extends StatelessWidget {
  const _LegendProgressBar({
    required this.progress,
    required this.shimmer,
    required this.pulse,
    required this.primaryColor,
    required this.accentColor,
    required this.softColor,
  });

  final double progress;
  final double shimmer;
  final double pulse;
  final Color primaryColor;
  final Color accentColor;
  final Color softColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: CustomPaint(
        painter: _LegendProgressPainter(
          progress: progress,
          shimmer: shimmer,
          pulse: pulse,
          primaryColor: primaryColor,
          accentColor: accentColor,
          softColor: softColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LegendProgressPainter extends CustomPainter {
  const _LegendProgressPainter({
    required this.progress,
    required this.shimmer,
    required this.pulse,
    required this.primaryColor,
    required this.accentColor,
    required this.softColor,
  });

  final double progress;
  final double shimmer;
  final double pulse;
  final Color primaryColor;
  final Color accentColor;
  final Color softColor;

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = 12.0;
    final centerY = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, centerY - barHeight / 2, size.width, barHeight),
      const Radius.circular(999),
    );
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.2 + pulse * 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(trackRect.inflate(4), glowPaint);

    final trackPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.48)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(trackRect, trackPaint);

    final borderPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(trackRect, borderPaint);

    final clamped = progress.clamp(0.0, 1.0);
    final fillWidth = size.width * clamped;
    if (fillWidth > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, centerY - barHeight / 2, fillWidth, barHeight),
        const Radius.circular(999),
      );
      final fillPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            accentColor,
            primaryColor,
            softColor,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawRRect(fillRect, fillPaint);
    }

    final notchPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(
        Offset(x, centerY - 5),
        Offset(x + 6, centerY + 5),
        notchPaint,
      );
    }

    final cursorX = (size.width * clamped).clamp(10.0, size.width - 10);
    final cursorPaint = Paint()
      ..color = softColor.withValues(alpha: 0.86)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(cursorX, centerY), 6 + pulse * 2, cursorPaint);

    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;
    final diamond = Path()
      ..moveTo(cursorX, centerY - 7)
      ..lineTo(cursorX + 7, centerY)
      ..lineTo(cursorX, centerY + 7)
      ..lineTo(cursorX - 7, centerY)
      ..close();
    canvas.drawPath(diamond, edgePaint);

    final shimmerX = (size.width + 54) * shimmer - 27;
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.42),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(shimmerX, 0, 28, size.height));
    canvas.save();
    canvas.clipRRect(trackRect);
    canvas.drawRect(
      Rect.fromLTWH(shimmerX, 0, 28, size.height),
      shimmerPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LegendProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.shimmer != shimmer ||
        oldDelegate.pulse != pulse ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.softColor != softColor;
  }
}

class _GencysProgressBar extends StatelessWidget {
  const _GencysProgressBar({
    required this.progress,
    required this.shimmer,
    required this.primaryColor,
    required this.accentColor,
  });

  final double progress;
  final double shimmer;
  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.72),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.22),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth = constraints.maxWidth * progress.clamp(0, 1);
              final shimmerX = (constraints.maxWidth + 80) * shimmer - 40;

              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: fillWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentColor,
                                primaryColor,
                                Colors.white,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: shimmerX,
                    top: -6,
                    bottom: -6,
                    child: Container(
                      width: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GencysLoadingPainter extends CustomPainter {
  const _GencysLoadingPainter({
    required this.progress,
    required this.pulse,
    required this.primaryColor,
  });

  final double progress;
  final double pulse;
  final Color primaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.38);
    final scanY = (size.height * 0.1) + (size.height * 0.76 * progress);
    final circuitPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.12 + pulse * 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.18 + pulse * 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          primaryColor.withValues(alpha: 0.4),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, scanY - 18, size.width, 36));

    canvas.drawRect(Rect.fromLTWH(0, scanY - 18, size.width, 36), scanPaint);

    for (var i = 0; i < 5; i++) {
      final radius = size.width * (0.22 + i * 0.055) + (pulse * 8);
      canvas.drawCircle(center, radius, i.isEven ? glowPaint : circuitPaint);
    }

    final linePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.13)
      ..strokeWidth = 1;
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.18 + i * 0.095);
      final offset = math.sin((progress * math.pi * 2) + i) * 18;
      canvas.drawLine(
        Offset(0, y + offset),
        Offset(size.width * (0.2 + (i % 3) * 0.18), y - offset),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width, y - offset),
        Offset(size.width * (0.78 - (i % 3) * 0.15), y + offset),
        linePaint,
      );
    }

    final nodePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.42 + pulse * 0.25);
    for (var i = 0; i < 18; i++) {
      final x = (size.width * ((i * 37) % 100) / 100) +
          math.sin(progress * math.pi * 2 + i) * 7;
      final y = size.height * (0.12 + (((i * 19) % 76) / 100));
      final radius = 1.4 + ((i % 3) * 0.7) + (pulse * 0.5);
      canvas.drawCircle(Offset(x, y), radius, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GencysLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.primaryColor != primaryColor;
  }
}
