import 'package:flutter/material.dart';

class ForceUpdateDialog extends StatefulWidget {
  const ForceUpdateDialog({
    super.key,
    required this.storeUrl,
    required this.onUpdateNow,
  });

  final String storeUrl;
  final Future<void> Function(String storeUrl) onUpdateNow;

  @override
  State<ForceUpdateDialog> createState() => _ForceUpdateDialogState();
}

class _ForceUpdateDialogState extends State<ForceUpdateDialog> {
  bool _isLaunchingStore = false;
  bool _launchFailed = false;

  Future<void> _launchStore() async {
    if (_isLaunchingStore) return;
    setState(() {
      _isLaunchingStore = true;
      _launchFailed = false;
    });

    try {
      await widget.onUpdateNow(widget.storeUrl);
    } catch (_) {
      if (mounted) {
        setState(() => _launchFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLaunchingStore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('A new version is available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please update the app to continue.'),
            if (_launchFailed) ...[
              const SizedBox(height: 12),
              const Text('Could not open the store. Please try again.'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isLaunchingStore ? null : _launchStore,
            child: _isLaunchingStore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}

/// A non-blocking counterpart to [ForceUpdateDialog]. Optional releases keep
/// the update visible at startup without trapping a user who is still on a
/// supported build.
class OptionalUpdateDialog extends StatefulWidget {
  const OptionalUpdateDialog({
    super.key,
    required this.storeUrl,
    required this.onUpdateNow,
  });

  final String storeUrl;
  final Future<void> Function(String storeUrl) onUpdateNow;

  @override
  State<OptionalUpdateDialog> createState() => _OptionalUpdateDialogState();
}

class _OptionalUpdateDialogState extends State<OptionalUpdateDialog> {
  bool _isLaunchingStore = false;
  bool _launchFailed = false;

  Future<void> _launchStore() async {
    if (_isLaunchingStore) return;
    setState(() {
      _isLaunchingStore = true;
      _launchFailed = false;
    });

    try {
      await widget.onUpdateNow(widget.storeUrl);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _launchFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLaunchingStore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('A new version is available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'An update is available. You can install it now or continue for the moment.',
          ),
          if (_launchFailed) ...[
            const SizedBox(height: 12),
            const Text('Could not open the store. Please try again.'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _isLaunchingStore ? null : () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: _isLaunchingStore ? null : _launchStore,
          child: _isLaunchingStore
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Now'),
        ),
      ],
    );
  }
}

Future<void> showForceUpdateDialog(
  BuildContext context, {
  required String storeUrl,
  required Future<void> Function(String storeUrl) onUpdateNow,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ForceUpdateDialog(
      storeUrl: storeUrl,
      onUpdateNow: onUpdateNow,
    ),
  );
}

Future<void> showOptionalUpdateDialog(
  BuildContext context, {
  required String storeUrl,
  required Future<void> Function(String storeUrl) onUpdateNow,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => OptionalUpdateDialog(
      storeUrl: storeUrl,
      onUpdateNow: onUpdateNow,
    ),
  );
}
