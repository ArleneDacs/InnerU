import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/constants/image_strings.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/force_update_dialog.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.checkForUpdate,
    this.onUpdateNow,
    this.waitForSessionRestore,
    this.hasRestoredSession,
    this.skipBrandingDelayForRestoredSession = false,
    this.onStartupReady,
  });

  final Future<AppUpdateCheckResult> Function()? checkForUpdate;
  final Future<void> Function(String storeUrl)? onUpdateNow;

  /// Local session restoration is deliberately separate from server
  /// validation: it is fast, works offline, and prevents this splash from
  /// racing ahead to LoginScreen while a persisted session is still loading.
  final Future<void> Function()? waitForSessionRestore;
  final bool Function()? hasRestoredSession;
  final bool skipBrandingDelayForRestoredSession;

  /// Lets the app root decide whether the user lands in the restored home or
  /// login screen after the forced-update gate has safely completed.
  final VoidCallback? onStartupReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _brandingTimer;

  @override
  void initState() {
    super.initState();
    _runSplash();
  }

  Future<void> _runSplash() async {
    final checkForUpdate =
        widget.checkForUpdate ?? AppUpdateService.instance.checkForUpdate;

    final brandingDelay = Completer<void>();
    _brandingTimer = Timer(const Duration(seconds: 3), brandingDelay.complete);
    // Attach the error handler synchronously, right when the future is
    // created, rather than after `brandingDelay` completes. Otherwise, if
    // `checkForUpdate()` fails, Dart's zone reports it as an unhandled
    // Future error during the 3-second wait (no listener attached yet),
    // which crashes the widget before this method's own error handling
    // ever gets a chance to run.
    final updateCheck = checkForUpdate().then<AppUpdateCheckResult>(
      (result) => result,
      onError: (_) => AppUpdateCheckResult.upToDate,
    );

    // Start restoring at the same time as the update request. It only reads
    // local secure storage; do not make the first frame wait for the network
    // validation that follows in AuthService.initialize().
    try {
      await widget.waitForSessionRestore?.call();
    } catch (_) {
      // The regular no-session path below remains safe if storage is
      // unavailable. AppSessionStore also retains a legacy copy until a
      // secure migration has succeeded.
    }

    final restoredSession = widget.hasRestoredSession?.call() ?? false;
    if (!restoredSession || !widget.skipBrandingDelayForRestoredSession) {
      await brandingDelay.future;
      _brandingTimer = null;
    } else {
      // The timer was started before local storage finished so a signed-out
      // visitor still receives the intended three-second brand moment. A
      // restored session deliberately skips it, so cancel it rather than
      // leave background test/runtime work behind.
      _brandingTimer?.cancel();
      _brandingTimer = null;
    }

    final updateResult = await updateCheck;

    if (!mounted) return;

    if (updateResult.isOutdated && updateResult.storeUrl != null) {
      await showForceUpdateDialog(
        context,
        storeUrl: updateResult.storeUrl!,
        onUpdateNow: widget.onUpdateNow ?? _launchStoreUrl,
      );
      return;
    }

    final onStartupReady = widget.onStartupReady;
    if (onStartupReady != null) {
      onStartupReady();
      return;
    }

    navigateToLogin();
  }

  Future<void> _launchStoreUrl(String storeUrl) async {
    final uri = Uri.parse(storeUrl);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        _showLaunchFailureMessage();
      }
    } catch (error, stack) {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: false);
      _showLaunchFailureMessage();
    }
  }

  void _showLaunchFailureMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the store automatically. Please update the app manually from the App Store or Play Store.',
        ),
      ),
    );
  }

  void navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _brandingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(tSplashTopIcon),
          fit: BoxFit.cover, // Ensures full coverage
        ),
      ),
    );
  }
}
