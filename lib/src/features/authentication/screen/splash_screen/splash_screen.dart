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
    this.onOptionalUpdateAvailable,
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

  /// Optional updates are intentionally shown after the startup destination
  /// mounts, so they are visible over either LoginScreen or an authenticated
  /// role/default screen rather than being lost with the splash route.
  final ValueChanged<AppUpdateCheckResult>? onOptionalUpdateAvailable;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _brandingTimer;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    if (!_hasStarted) {
      _hasStarted = true;
      _runSplash();
    }
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
      if (!updateResult.isRequired) {
        final onStartupReady = widget.onStartupReady;
        final onOptionalUpdateAvailable = widget.onOptionalUpdateAvailable;

        // The app root owns this path in production. It first mounts the
        // login/authenticated destination, then presents the dismissible
        // prompt from its stable navigator context. This avoids coupling the
        // prompt to DashboardScreen (or any particular default screen).
        if (onStartupReady != null && onOptionalUpdateAvailable != null) {
          onStartupReady();
          onOptionalUpdateAvailable(updateResult);
          return;
        }

        // Keep SplashScreen self-contained for the direct/legacy route case.
        // The prompt is intentionally dismissible, unlike a forced update.
        await showOptionalUpdateDialog(
          context,
          storeUrl: updateResult.storeUrl!,
          onUpdateNow: widget.onUpdateNow ?? _launchStoreUrl,
        );
        if (!mounted) return;
        final afterOptionalPrompt = widget.onStartupReady;
        if (afterOptionalPrompt != null) {
          afterOptionalPrompt();
        } else {
          navigateToLogin();
        }
        return;
      }

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
