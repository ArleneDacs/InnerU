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
  });

  final Future<AppUpdateCheckResult> Function()? checkForUpdate;
  final Future<void> Function(String storeUrl)? onUpdateNow;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _runSplash();
  }

  Future<void> _runSplash() async {
    final checkForUpdate =
        widget.checkForUpdate ?? AppUpdateService.instance.checkForUpdate;

    final brandingDelay = Future<void>.delayed(const Duration(seconds: 3));
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

    await brandingDelay;

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
