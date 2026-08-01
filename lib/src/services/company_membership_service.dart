import 'package:flutter/foundation.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

enum CompanyScoreMode {
  merged,
  separate,
}

extension CompanyScoreModeX on CompanyScoreMode {
  String get id {
    return switch (this) {
      CompanyScoreMode.merged => 'merged',
      CompanyScoreMode.separate => 'separate',
    };
  }

  String get title {
    return switch (this) {
      CompanyScoreMode.merged => 'Merged score',
      CompanyScoreMode.separate => 'Separate score',
    };
  }

  static CompanyScoreMode fromValue(Object? value) {
    final raw = value is String ? value.trim().toLowerCase() : '';
    return raw == CompanyScoreMode.separate.id
        ? CompanyScoreMode.separate
        : CompanyScoreMode.merged;
  }
}

class CompanyMembership {
  const CompanyMembership({
    required this.id,
    required this.code,
    required this.name,
    required this.scoreMode,
  });

  factory CompanyMembership.fromCompanyDoc(
    Map<String, dynamic> data, {
    CompanyScoreMode scoreMode = CompanyScoreMode.merged,
  }) {
    final code = (data['code'] as String?)?.trim().toUpperCase();
    final name = (data['name'] as String?)?.trim();
    return CompanyMembership(
      id: (data['id'] as String?)?.trim() ?? code ?? '',
      code: code?.isNotEmpty == true
          ? code!
          : (data['id'] as String?)?.trim() ?? '',
      name: name?.isNotEmpty == true ? name! : 'Company',
      scoreMode: scoreMode,
    );
  }

  factory CompanyMembership.fromMap(Map<String, dynamic> data) {
    final id = (data['companyId'] as String?)?.trim() ??
        (data['id'] as String?)?.trim() ??
        '';
    final code = ((data['companyCode'] as String?)?.trim() ??
            (data['code'] as String?)?.trim() ??
            '')
        .toUpperCase();
    final name = (data['companyName'] as String?)?.trim() ??
        (data['name'] as String?)?.trim() ??
        '';
    return CompanyMembership(
      id: id.isNotEmpty ? id : code,
      code: code.isNotEmpty ? code : id.toUpperCase(),
      name: name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Company'),
      scoreMode: CompanyScoreModeX.fromValue(data['scoreMode']),
    );
  }

  final String id;
  final String code;
  final String name;
  final CompanyScoreMode scoreMode;

  bool get isValid => id.trim().isNotEmpty || code.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'companyId': id,
      'companyCode': code,
      'companyName': name,
      'scoreMode': scoreMode.id,
    };
  }

  CompanyMembership copyWith({
    String? id,
    String? code,
    String? name,
    CompanyScoreMode? scoreMode,
  }) {
    return CompanyMembership(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      scoreMode: scoreMode ?? this.scoreMode,
    );
  }
}

class CompanyMembershipData {
  const CompanyMembershipData({
    required this.memberships,
    required this.activeMembership,
  });

  final List<CompanyMembership> memberships;
  final CompanyMembership? activeMembership;
}

class CompanyMembershipService {
  const CompanyMembershipService._();

  static Future<CompanyMembershipData> loadForUser(String uid) async {
    try {
      final userData = await UserService.getUserData();
      if (userData.isNotEmpty) {
        return fromUserData(userData);
      }
    } catch (e) {
      debugPrint('Failed to load company membership from API: $e');
    }
    return const CompanyMembershipData(
      memberships: <CompanyMembership>[],
      activeMembership: null,
    );
  }

  static List<String> lookupKeysFromUserData(Map<String, dynamic>? userData) {
    if (userData == null || userData.isEmpty) {
      return const <String>[];
    }

    final keys = <String>[
      (userData['activeCompanyId'] as String?)?.trim() ?? '',
      (userData['activeCompanyCode'] as String?)?.trim() ?? '',
      (userData['companyId'] as String?)?.trim() ?? '',
      (userData['companyCode'] as String?)?.trim() ?? '',
    ];

    final memberships = _membershipsFromUserData(userData);
    final activeMembership =
        _activeMembershipFromUserData(userData, memberships);
    if (activeMembership != null) {
      keys.addAll([
        activeMembership.id,
        activeMembership.code,
      ]);
    }

    final companyIds = userData['companyIds'];
    if (companyIds is List) {
      keys.addAll(companyIds.whereType<String>().map((value) => value.trim()));
    }

    final companyCodes = userData['companyCodes'];
    if (companyCodes is List) {
      keys.addAll(
          companyCodes.whereType<String>().map((value) => value.trim()));
    }

    return keys
        .where((value) => value.isNotEmpty)
        .map((value) => value.trim())
        .toSet()
        .toList();
  }

  static CompanyMembership? activeMembershipFromUserDataPublic(
    Map<String, dynamic>? userData,
  ) {
    if (userData == null || userData.isEmpty) {
      return null;
    }

    final memberships = _membershipsFromUserData(userData);
    return _activeMembershipFromUserData(userData, memberships);
  }

  static CompanyMembershipData fromUserData(Map<String, dynamic>? userData) {
    if (userData == null) {
      return const CompanyMembershipData(
        memberships: <CompanyMembership>[],
        activeMembership: null,
      );
    }

    final memberships = _membershipsFromUserData(userData);
    final active = _activeMembershipFromUserData(userData, memberships);
    return CompanyMembershipData(
      memberships: memberships,
      activeMembership: active,
    );
  }

  static Future<CompanyMembership?> findCompanyByCode(
      String companyCode) async {
    final normalizedCode = companyCode.trim().toUpperCase();
    if (normalizedCode.isEmpty) return null;

    try {
      final company =
          await CompanyApiService.instance.findByCode(normalizedCode);
      if (company == null || !company.isActive) return null;
      return CompanyMembership.fromCompanyDoc({
        'id': company.id,
        'code': company.code,
        'name': company.name,
      });
    } catch (e) {
      debugPrint('Failed to load company from API: $e');
      return null;
    }
  }

  static Future<CompanyMembership> joinCompany({
    required String uid,
    required String companyCode,
    required CompanyScoreMode scoreMode,
  }) async {
    final company = await findCompanyByCode(companyCode);
    if (company == null) {
      throw StateError(CompanyApiService.invalidCompanyCodeMessage);
    }

    final membership = company.copyWith(scoreMode: scoreMode);
    await setActiveCompany(
        uid: uid, membership: membership, addIfMissing: true);
    return membership;
  }

  static Future<void> setActiveCompany({
    required String uid,
    required CompanyMembership membership,
    bool addIfMissing = false,
  }) async {
    final userData = await UserService.getUserData();
    final memberships = _membershipsFromUserData(userData);
    final existingIndex = memberships.indexWhere(
      (item) => _sameCompany(item, membership),
    );

    if (existingIndex >= 0) {
      memberships[existingIndex] = membership;
    } else if (addIfMissing) {
      memberships.add(membership);
    }

    await UserService.updateUserFields({
      'has_company': memberships.isNotEmpty,
      'company_id': membership.id,
      'company_code': membership.code,
      'company_name': membership.name,
      'active_company_id': membership.id,
      'active_company_code': membership.code,
      'active_company_name': membership.name,
      'active_company_score_mode': membership.scoreMode.id,
      'score_mode': membership.scoreMode.id,
      'company_memberships': memberships.map((item) => item.toMap()).toList(),
      'company_ids': memberships.map((item) => item.id).toList(),
      'company_codes': memberships.map((item) => item.code).toList(),
    });

    CompanyThemeService.clearCachedThemeForUser(uid);
  }

  static Future<void> removeCompanyAccess({
    required String uid,
    required CompanyMembership membership,
  }) async {
    final userData = await UserService.getUserData();
    final memberships = _membershipsFromUserData(userData);
    final existingIndex = memberships.indexWhere(
      (item) => _sameCompany(item, membership),
    );
    if (existingIndex < 0) return;

    final activeMembership = _activeMembershipFromUserData(
      userData,
      memberships,
    );
    final removedMembership = memberships.removeAt(existingIndex);
    final removedWasActive = activeMembership != null &&
        _sameCompany(activeMembership, removedMembership);
    final nextActiveMembership = removedWasActive
        ? memberships.isNotEmpty
            ? memberships.first
            : null
        : activeMembership;

    final update = <String, dynamic>{
      'has_company': memberships.isNotEmpty,
      'company_memberships': memberships.map((item) => item.toMap()).toList(),
      'company_ids': memberships.map((item) => item.id).toList(),
      'company_codes': memberships.map((item) => item.code).toList(),
    };

    if (nextActiveMembership == null) {
      update.addAll({
        'company_id': null,
        'company_code': null,
        'company_name': null,
        'active_company_id': null,
        'active_company_code': null,
        'active_company_name': null,
        'active_company_score_mode': null,
        'score_mode': null,
      });
    } else if (removedWasActive) {
      update.addAll({
        'company_id': nextActiveMembership.id,
        'company_code': nextActiveMembership.code,
        'company_name': nextActiveMembership.name,
        'active_company_id': nextActiveMembership.id,
        'active_company_code': nextActiveMembership.code,
        'active_company_name': nextActiveMembership.name,
        'active_company_score_mode': nextActiveMembership.scoreMode.id,
        'score_mode': nextActiveMembership.scoreMode.id,
      });
    }

    await UserService.updateUserFields(update);

    CompanyThemeService.clearCachedThemeForUser(uid);
  }

  static Map<String, dynamic> activeCompanyFields(
    CompanyMembership? membership,
  ) {
    if (membership == null) {
      return const <String, dynamic>{};
    }

    return {
      'companyId': membership.id,
      'companyCode': membership.code,
      'companyName': membership.name,
      'activeCompanyId': membership.id,
      'activeCompanyCode': membership.code,
      'activeCompanyName': membership.name,
      'activeCompanyScoreMode': membership.scoreMode.id,
      'scoreMode': membership.scoreMode.id,
    };
  }

  static Future<Map<String, dynamic>> activeCompanyFieldsForUser(
    String uid,
  ) async {
    final data = await loadForUser(uid);
    return activeCompanyFields(data.activeMembership);
  }

  static Future<String> pointsDocId({
    required String uid,
    required String date,
  }) async {
    final data = await loadForUser(uid);
    return scopedDailyDocId(
      uid: uid,
      date: date,
      membership: data.activeMembership,
    );
  }

  static String scopedDailyDocId({
    required String uid,
    required String date,
    required CompanyMembership? membership,
  }) {
    if (membership?.scoreMode != CompanyScoreMode.separate) {
      return '$uid-$date';
    }

    final scope = membership!.id.isNotEmpty ? membership.id : membership.code;
    return '$uid-$scope-$date';
  }

  static List<CompanyMembership> _membershipsFromUserData(
    Map<String, dynamic> userData,
  ) {
    final memberships = <CompanyMembership>[];
    final rawMemberships = userData['companyMemberships'];
    if (rawMemberships is List) {
      for (final rawMembership in rawMemberships) {
        if (rawMembership is! Map) continue;
        final membership = CompanyMembership.fromMap(
          Map<String, dynamic>.from(rawMembership),
        );
        if (membership.isValid) {
          _upsertMembership(memberships, membership);
        }
      }
    }

    final legacy = CompanyMembership.fromMap({
      'companyId': userData['companyId'],
      'companyCode': userData['companyCode'],
      'companyName': userData['companyName'],
      'scoreMode': userData['activeCompanyScoreMode'] ?? userData['scoreMode'],
    });
    if (legacy.isValid) {
      _upsertMembership(memberships, legacy);
    }

    return memberships;
  }

  static CompanyMembership? _activeMembershipFromUserData(
    Map<String, dynamic> userData,
    List<CompanyMembership> memberships,
  ) {
    final activeId = ((userData['activeCompanyId'] as String?)?.trim() ??
        (userData['companyId'] as String?)?.trim() ??
        '');
    final activeCode = (((userData['activeCompanyCode'] as String?)?.trim() ??
            (userData['companyCode'] as String?)?.trim() ??
            '')
        .toUpperCase());

    for (final membership in memberships) {
      if ((activeId.isNotEmpty && membership.id == activeId) ||
          (activeCode.isNotEmpty && membership.code == activeCode)) {
        return membership.copyWith(
          scoreMode: CompanyScoreModeX.fromValue(
            userData['activeCompanyScoreMode'] ?? membership.scoreMode.id,
          ),
        );
      }
    }

    return memberships.firstOrNull;
  }

  static void _upsertMembership(
    List<CompanyMembership> memberships,
    CompanyMembership membership,
  ) {
    final existingIndex = memberships.indexWhere(
      (item) => _sameCompany(item, membership),
    );
    if (existingIndex >= 0) {
      memberships[existingIndex] = membership;
      return;
    }
    memberships.add(membership);
  }

  static bool _sameCompany(
    CompanyMembership left,
    CompanyMembership right,
  ) {
    return (left.id.isNotEmpty && left.id == right.id) ||
        (left.code.isNotEmpty && left.code == right.code);
  }
}

@visibleForTesting
List<CompanyMembership> membershipsFromUserDataForTest(
  Map<String, dynamic> userData,
) {
  return CompanyMembershipService.fromUserData(userData).memberships;
}

@visibleForTesting
List<String> lookupKeysFromUserDataForTest(
  Map<String, dynamic> userData,
) {
  return CompanyMembershipService.lookupKeysFromUserData(userData);
}
