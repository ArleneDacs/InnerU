import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel timezoneChannel = MethodChannel('flutter_timezone');
  const MethodChannel notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSessionService.instance.clear();
    AndroidFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async {
      if (call.method == 'getLocalTimezone') {
        return 'Asia/Manila';
      }
      return null;
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
      switch (call.method) {
        case 'initialize':
        case 'requestPermissions':
        case 'requestNotificationPermission':
        case 'requestNotificationsPermission':
        case 'requestExactAlarmsPermission':
        case 'cancel':
        case 'cancelAll':
        case 'cancelAllPendingNotifications':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    await AppSessionService.instance.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
  });

  testWidgets('renders goals copy and opens the add goal dialog',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const TodoListScreen(),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('All Goals'), findsOneWidget);
    expect(find.text('Goals score'), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('New Goal'), findsOneWidget);
    expect(find.text('Goal title'), findsOneWidget);
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Long Term Goal'), findsOneWidget);
    expect(find.text('Everyday Goal'), findsOneWidget);
    expect(find.text('Start Date'), findsOneWidget);
    expect(find.text('End Date'), findsOneWidget);
  });
}
