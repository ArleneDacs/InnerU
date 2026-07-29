library onesignal_flutter;

typedef OSNotificationClickListener = void Function(OSNotificationClickEvent event);

class OneSignal {
  static final _NotificationsApi Notifications = _NotificationsApi();

  static Future<void> initialize(String appId) async {}

  static Future<void> login(String externalId) async {}

  static Future<void> logout() async {}
}

class _NotificationsApi {
  final List<OSNotificationClickListener> _clickListeners = <OSNotificationClickListener>[];

  void addClickListener(OSNotificationClickListener listener) {
    if (!_clickListeners.contains(listener)) {
      _clickListeners.add(listener);
    }
  }

  void removeClickListener(OSNotificationClickListener listener) {
    _clickListeners.remove(listener);
  }

  Future<void> requestPermission(bool fallbackToSettings) async {}

  @pragma('vm:entry-point')
  void simulateClick(Map<String, dynamic>? additionalData) {
    final event = OSNotificationClickEvent(
      notification: OSNotification(additionalData: additionalData),
    );
    for (final listener in List<OSNotificationClickListener>.from(_clickListeners)) {
      listener(event);
    }
  }
}

class OSNotificationClickEvent {
  OSNotificationClickEvent({required this.notification});

  final OSNotification notification;
}

class OSNotification {
  OSNotification({this.additionalData});

  final Map<String, dynamic>? additionalData;
}
