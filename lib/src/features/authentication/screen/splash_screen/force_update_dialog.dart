import 'package:flutter/material.dart';

class ForceUpdateDialog extends StatelessWidget {
  const ForceUpdateDialog({
    super.key,
    required this.storeUrl,
    required this.onUpdateNow,
  });

  final String storeUrl;
  final Future<void> Function(String storeUrl) onUpdateNow;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('A new version is available'),
        content: const Text('Please update the app to continue.'),
        actions: [
          TextButton(
            onPressed: () => onUpdateNow(storeUrl),
            child: const Text('Update Now'),
          ),
        ],
      ),
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
