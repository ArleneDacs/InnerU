import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AppSession(
    id: 42,
    token: 'persisted-bearer-token',
    name: 'Persistent User',
    email: 'persistent@example.com',
    role: 'user',
    isCoach: false,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('saves and restores a session only through secure storage', () async {
    final secureStore = _MemorySecureStore();
    final store = AppSessionStore(secureStore: secureStore);

    await store.save(session);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppSessionStore.legacyStorageKey), isNull);
    expect(
      secureStore.values[AppSessionStore.secureStorageKey],
      isNotNull,
    );

    final restored = await AppSessionStore(secureStore: secureStore).load();
    expect(restored?.id, session.id);
    expect(restored?.token, session.token);
  });

  test('migrates a valid legacy session without losing it', () async {
    final secureStore = _MemorySecureStore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppSessionStore.legacyStorageKey,
      jsonEncode(session.toJson()),
    );

    final restored = await AppSessionStore(secureStore: secureStore).load();

    expect(restored?.email, session.email);
    expect(
      secureStore.values[AppSessionStore.secureStorageKey],
      jsonEncode(session.toJson()),
    );
    expect(prefs.getString(AppSessionStore.legacyStorageKey), isNull);
  });

  test('keeps a legacy session when secure migration temporarily fails',
      () async {
    final secureStore = _MemorySecureStore(failWrites: true);
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(session.toJson());
    await prefs.setString(AppSessionStore.legacyStorageKey, encoded);

    final restored = await AppSessionStore(secureStore: secureStore).load();

    expect(restored?.token, session.token);
    expect(prefs.getString(AppSessionStore.legacyStorageKey), encoded);
  });

  test('logout clears both secure and legacy session copies', () async {
    final secureStore = _MemorySecureStore()
      ..values[AppSessionStore.secureStorageKey] = jsonEncode(session.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppSessionStore.legacyStorageKey,
      jsonEncode(session.toJson()),
    );

    await AppSessionStore(secureStore: secureStore).clear();

    expect(secureStore.values, isEmpty);
    expect(prefs.getString(AppSessionStore.legacyStorageKey), isNull);
  });

  test('a stale 401 cannot clear a newer queued session', () async {
    final secureStore = _MemorySecureStore();
    final service = AppSessionService.forTesting(
      AppSessionStore(secureStore: secureStore),
    );
    const newerSession = AppSession(
      id: 42,
      token: 'new-bearer-token',
      name: 'Persistent User',
      email: 'persistent@example.com',
      role: 'user',
      isCoach: false,
    );

    await service.setSession(session);
    final persistNewSession = service.setSession(newerSession);
    final rejectOldRequest = service.clearIfCurrentTokenMatches(session.token);
    await Future.wait<void>([persistNewSession, rejectOldRequest]);

    expect(service.current?.token, newerSession.token);
    final stored = jsonDecode(
      secureStore.values[AppSessionStore.secureStorageKey]!,
    ) as Map<String, dynamic>;
    expect(stored['token'], newerSession.token);
  });
}

class _MemorySecureStore implements AppSessionSecureStore {
  _MemorySecureStore({this.failWrites = false});

  final Map<String, String> values = <String, String>{};
  final bool failWrites;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('secure store unavailable');
    values[key] = value;
  }
}
