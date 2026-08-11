import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  const AppSession({
    required this.id,
    required this.token,
    required this.name,
    required this.email,
    required this.role,
    required this.isCoach,
    this.number,
    this.companyCode,
    this.companyName,
    this.birthdate,
    this.profilePic,
    this.defaultLandingScreen = 'dashboard',
  });

  final int id;
  final String token;
  final String name;
  final String email;
  final String role;
  final bool isCoach;
  final String? number;
  final String? companyCode;
  final String? companyName;
  final String? birthdate;
  final String? profilePic;
  final String defaultLandingScreen;

  factory AppSession.fromJson(Map<String, dynamic> json) {
    return AppSession(
      id: (json['id'] as num).toInt(),
      token: json['token'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'User',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      isCoach: json['is_coach'] == true,
      number: json['number'] as String?,
      companyCode: json['company_code'] as String?,
      companyName: json['company_name'] as String?,
      birthdate: json['birthdate'] as String?,
      profilePic: json['profile_pic'] as String?,
      defaultLandingScreen: json['default_landing_screen']?.toString() ??
          json['defaultScreen']?.toString() ??
          'dashboard',
    );
  }

  AppSession copyWith({
    String? name,
    String? email,
    String? role,
    bool? isCoach,
    String? number,
    String? companyCode,
    String? companyName,
    String? birthdate,
    String? profilePic,
    String? defaultLandingScreen,
  }) {
    return AppSession(
      id: id,
      token: token,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      isCoach: isCoach ?? this.isCoach,
      number: number ?? this.number,
      companyCode: companyCode ?? this.companyCode,
      companyName: companyName ?? this.companyName,
      birthdate: birthdate ?? this.birthdate,
      profilePic: profilePic ?? this.profilePic,
      defaultLandingScreen: defaultLandingScreen ?? this.defaultLandingScreen,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'token': token,
      'name': name,
      'email': email,
      'role': role,
      'is_coach': isCoach,
      'number': number,
      'company_code': companyCode,
      'company_name': companyName,
      'birthdate': birthdate,
      'profile_pic': profilePic,
      'default_landing_screen': defaultLandingScreen,
    };
  }
}

/// Small adapter around the platform-backed secure store.
///
/// Keeping this behind an interface makes the migration path testable without
/// registering a native plugin in widget/unit tests.
abstract interface class AppSessionSecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterAppSessionSecureStore implements AppSessionSecureStore {
  FlutterAppSessionSecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class AppSessionStore {
  AppSessionStore({AppSessionSecureStore? secureStore})
      : _secureStore = secureStore ?? FlutterAppSessionSecureStore();

  /// The old preference key is kept solely for a one-time, lossless
  /// migration. New sessions are never written here because it stores values
  /// in plaintext on most platforms.
  @visibleForTesting
  static const String legacyStorageKey = 'inneru.app.session';

  @visibleForTesting
  static const String secureStorageKey = 'inneru.secure.app.session';

  final AppSessionSecureStore _secureStore;

  Future<AppSession?> load() async {
    final secureSession = await _readSecureSession();
    if (secureSession != null) {
      // Clean up an old plaintext copy left behind by a previous app version.
      // This is deliberately best-effort: a failure to remove it must never
      // prevent an otherwise valid restored session from being used.
      await _removeLegacySession();
      return secureSession;
    }

    final legacySession = await _readLegacySession();
    if (legacySession == null) return null;

    // Do not erase the old value until the secure write succeeds. That makes
    // upgrades safe if the keychain/keystore is temporarily unavailable.
    try {
      await _secureStore.write(
          secureStorageKey, jsonEncode(legacySession.toJson()));
      await _removeLegacySession();
    } catch (error) {
      debugPrint('Secure session migration will retry later: $error');
    }

    return legacySession;
  }

  Future<void> save(AppSession session) async {
    await _secureStore.write(secureStorageKey, jsonEncode(session.toJson()));
    await _removeLegacySession();
  }

  Future<void> clear() async {
    // Clear both locations so users who log out during/just before migration
    // cannot have a legacy token resurrected on their next launch.
    try {
      await _secureStore.delete(secureStorageKey);
    } catch (error) {
      debugPrint('Could not clear secure session storage: $error');
    }
    await _removeLegacySession();
  }

  Future<AppSession?> _readSecureSession() async {
    try {
      final encoded = await _secureStore.read(secureStorageKey);
      return _decode(encoded);
    } catch (error) {
      // A device lock/keychain error should not sign the user out or discard
      // their legacy session. A later launch can retry the secure read.
      debugPrint('Could not read secure session storage: $error');
      return null;
    }
  }

  Future<AppSession?> _readLegacySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(legacyStorageKey);
      final session = _decode(encoded);
      if (session == null && encoded != null && encoded.isNotEmpty) {
        await prefs.remove(legacyStorageKey);
      }
      return session;
    } catch (error) {
      debugPrint('Could not read legacy session storage: $error');
      return null;
    }
  }

  AppSession? _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final session = AppSession.fromJson(decoded);
      if (session.token.trim().isEmpty) return null;
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLegacySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(legacyStorageKey);
    } catch (error) {
      debugPrint('Could not remove legacy session storage: $error');
    }
  }
}

class AppSessionService {
  AppSessionService._() : _store = AppSessionStore();

  @visibleForTesting
  AppSessionService.forTesting(AppSessionStore store) : _store = store;

  static final AppSessionService instance = AppSessionService._();

  final AppSessionStore _store;
  final StreamController<AppSession?> _controller =
      StreamController<AppSession?>.broadcast();

  AppSession? _current;
  bool _initialized = false;
  bool _restoredSessionOnLaunch = false;
  Future<void>? _initialization;
  final Queue<Future<void> Function()> _pendingPersistenceOperations =
      Queue<Future<void> Function()>();
  bool _persistenceOperationRunning = false;

  Stream<AppSession?> get stream => _controller.stream;
  AppSession? get current => _current;
  String? get currentUserId => _current?.id.toString();
  String? get token => _current?.token;
  bool get isInitialized => _initialized;

  /// True only when the current process loaded a session from device storage.
  /// It lets startup-only presentation code avoid replaying a deliberate
  /// post-login sequence every morning while retaining that experience after
  /// an explicit sign-in.
  bool get restoredSessionOnLaunch => _restoredSessionOnLaunch;

  /// Restores the on-device session exactly once. Concurrent callers share
  /// the same operation instead of observing a transient null user while a
  /// keychain read is still underway.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _restore();
  }

  Future<void> _restore() async {
    try {
      _current = await _store.load();
      _restoredSessionOnLaunch = _current != null;
    } finally {
      _initialized = true;
      _controller.add(_current);
    }
  }

  Future<void> setSession(AppSession session) {
    return _enqueue(() async {
      _current = session;
      await _store.save(session);
      _controller.add(_current);
    });
  }

  Future<void> clear() {
    return _enqueue(_clearCurrentSession);
  }

  /// A stale request must never log out a user who signed in again while that
  /// request was in flight. Queue this check beside saves/clears so its token
  /// comparison and secure-storage deletion are atomic with respect to a new
  /// session being persisted.
  Future<void> clearIfCurrentTokenMatches(String failedToken) {
    return _enqueue(() async {
      if (_current?.token != failedToken) return;
      await _clearCurrentSession();
    });
  }

  Future<void> _clearCurrentSession() async {
    _current = null;
    _restoredSessionOnLaunch = false;
    await _store.clear();
    _controller.add(_current);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _pendingPersistenceOperations.add(() async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _drainPersistenceQueue();
    return completer.future;
  }

  void _drainPersistenceQueue() {
    if (_persistenceOperationRunning || _pendingPersistenceOperations.isEmpty) {
      return;
    }

    _persistenceOperationRunning = true;
    final operation = _pendingPersistenceOperations.removeFirst();
    unawaited(
      operation().whenComplete(() {
        _persistenceOperationRunning = false;
        _drainPersistenceQueue();
      }),
    );
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
