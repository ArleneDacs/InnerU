import 'dart:async';
import 'dart:convert';

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
    };
  }
}

class AppSessionStore {
  static const String _storageKey = 'inneru.app.session';

  Future<AppSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      return AppSession.fromJson(decoded);
    } catch (_) {
      await prefs.remove(_storageKey);
      return null;
    }
  }

  Future<void> save(AppSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

class AppSessionService {
  AppSessionService._();

  static final AppSessionService instance = AppSessionService._();

  final AppSessionStore _store = AppSessionStore();
  final StreamController<AppSession?> _controller =
      StreamController<AppSession?>.broadcast();

  AppSession? _current;
  bool _initialized = false;

  Stream<AppSession?> get stream => _controller.stream;
  AppSession? get current => _current;
  String? get currentUserId => _current?.id.toString();
  String? get token => _current?.token;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _current = await _store.load();
    _controller.add(_current);
  }

  Future<void> setSession(AppSession session) async {
    _current = session;
    await _store.save(session);
    _controller.add(_current);
  }

  Future<void> clear() async {
    _current = null;
    await _store.clear();
    _controller.add(_current);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
