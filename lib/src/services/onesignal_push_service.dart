import 'dart:async';

import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:selfcare_projects/src/config/onesignal_config.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/notification_push_router.dart';

class OneSignalPushService {
  OneSignalPushService._() : _clickListener = _handleNotificationClick;

  static final OneSignalPushService instance = OneSignalPushService._();

  final void Function(OSNotificationClickEvent) _clickListener;
  StreamSubscription<AppSession?>? _sessionSubscription;
  String? _externalId;
  bool _initialized = false;

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;

    final appId = OneSignalConfig.appId.trim();
    if (appId.isEmpty) {
      debugPrint(
        'OneSignal push is disabled. Provide ONESIGNAL_APP_ID to enable it.',
      );
      return;
    }

    await OneSignal.initialize(appId);
    NotificationPushRouter.instance.configure(navigatorKey);
    OneSignal.Notifications.addClickListener(_clickListener);
    final permissionGranted =
        await OneSignal.Notifications.requestPermission(false);
    if (!permissionGranted) {
      debugPrint(
        'OneSignal initialized, but notification permission is not granted. '
        'Enable notifications for InnerU in the device settings.',
      );
    }

    _sessionSubscription = AuthService.instance.sessionStream.listen(
      _syncSession,
      onError: (error, stackTrace) {
        debugPrint('OneSignal session sync failed: $error');
      },
    );
    await _syncSession(AuthService.instance.currentSession);

    _initialized = true;
  }

  Future<void> dispose() async {
    await _sessionSubscription?.cancel();
    _sessionSubscription = null;
    OneSignal.Notifications.removeClickListener(_clickListener);
    if (_externalId != null) {
      try {
        await OneSignal.logout();
      } catch (error) {
        debugPrint('OneSignal logout failed: $error');
      }
    }
    _externalId = null;
    _initialized = false;
  }

  Future<void> _syncSession(AppSession? session) async {
    final nextExternalId = session?.id.toString().trim();
    if (nextExternalId == null || nextExternalId.isEmpty) {
      if (_externalId != null) {
        try {
          await OneSignal.logout();
        } catch (error) {
          debugPrint('OneSignal logout failed: $error');
        }
      }
      _externalId = null;
      return;
    }

    if (_externalId == nextExternalId) return;

    try {
      if (_externalId != null) {
        await OneSignal.logout();
      }
      await OneSignal.login(nextExternalId);
      _externalId = nextExternalId;
    } catch (error) {
      debugPrint('OneSignal login failed: $error');
    }
  }

  static Future<void> _handleNotificationClick(
    OSNotificationClickEvent event,
  ) async {
    final additionalData = event.notification.additionalData;
    final payload = additionalData is Map
        ? Map<String, dynamic>.from(additionalData as Map)
        : <String, dynamic>{};

    if (payload.isEmpty) return;
    await NotificationPushRouter.instance.handlePushTap(payload);
  }
}
