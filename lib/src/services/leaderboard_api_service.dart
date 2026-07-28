import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class LeaderboardApiCompanyEntry {
  const LeaderboardApiCompanyEntry({
    required this.userId,
    required this.name,
    required this.score,
    required this.goalScore,
    required this.coreTaskScore,
    required this.overallScore,
    required this.rank,
    this.profilePic,
    this.teamName,
  });

  final String userId;
  final String name;
  final num score;
  final num goalScore;
  final num coreTaskScore;
  final num overallScore;
  final int rank;
  final String? profilePic;
  final String? teamName;

  factory LeaderboardApiCompanyEntry.fromJson(Map<String, dynamic> json) {
    final score = _parseApiNumber(json['score']);
    final goalScore = _parseApiNumber(json['goalScore'], fallback: score);
    final coreTaskScore = _parseApiNumber(json['coreTaskScore']);
    final overallScore = _parseApiNumber(
      json['overallScore'],
      fallback: score,
    );

    return LeaderboardApiCompanyEntry(
      userId: json['userId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      score: score,
      goalScore: goalScore,
      coreTaskScore: coreTaskScore,
      overallScore: overallScore,
      rank: json['rank'] is int
          ? json['rank'] as int
          : int.tryParse(json['rank']?.toString() ?? '') ?? 0,
      profilePic: json['profilePic']?.toString(),
      teamName: json['teamName']?.toString(),
    );
  }
}

class LeaderboardApiGroupMember {
  const LeaderboardApiGroupMember({
    required this.userId,
    required this.name,
    required this.score,
    required this.goalScore,
    required this.coreTaskScore,
    required this.overallScore,
    required this.rank,
    this.profilePic,
    this.teamName,
  });

  final String userId;
  final String name;
  final num score;
  final num goalScore;
  final num coreTaskScore;
  final num overallScore;
  final int rank;
  final String? profilePic;
  final String? teamName;

  factory LeaderboardApiGroupMember.fromJson(Map<String, dynamic> json) {
    final score = _parseApiNumber(json['score']);
    final goalScore = _parseApiNumber(json['goalScore'], fallback: score);
    final coreTaskScore = _parseApiNumber(json['coreTaskScore']);
    final overallScore = _parseApiNumber(
      json['overallScore'],
      fallback: score,
    );

    return LeaderboardApiGroupMember(
      userId: json['userId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      score: score,
      goalScore: goalScore,
      coreTaskScore: coreTaskScore,
      overallScore: overallScore,
      rank: json['rank'] is int
          ? json['rank'] as int
          : int.tryParse(json['rank']?.toString() ?? '') ?? 0,
      profilePic: json['profilePic']?.toString(),
      teamName: json['teamName']?.toString(),
    );
  }
}

class LeaderboardApiGroup {
  const LeaderboardApiGroup({
    required this.groupId,
    required this.groupName,
    required this.coachName,
    required this.companyName,
    required this.totalScore,
    required this.entries,
  });

  final String groupId;
  final String groupName;
  final String coachName;
  final String companyName;
  final num totalScore;
  final List<LeaderboardApiGroupMember> entries;

  factory LeaderboardApiGroup.fromJson(Map<String, dynamic> json) {
    return LeaderboardApiGroup(
      groupId: json['groupId']?.toString() ?? '',
      groupName: json['groupName']?.toString() ?? 'Group',
      coachName: json['coachName']?.toString() ?? 'Coach',
      companyName: json['companyName']?.toString() ?? '',
      totalScore: json['totalScore'] is num
          ? json['totalScore'] as num
          : num.tryParse(json['totalScore']?.toString() ?? '') ?? 0,
      entries: (json['entries'] as List?)
              ?.whereType<Map>()
              .map((entry) => LeaderboardApiGroupMember.fromJson(
                  Map<String, dynamic>.from(entry)))
              .toList() ??
          const <LeaderboardApiGroupMember>[],
    );
  }
}

class LeaderboardApiSnapshot {
  const LeaderboardApiSnapshot({
    required this.companyCode,
    required this.companyName,
    required this.leaderboardPeriodStart,
    required this.leaderboardPeriodEnd,
    required this.entries,
    required this.groups,
    required this.menteeEntries,
  });

  final String companyCode;
  final String companyName;
  final DateTime? leaderboardPeriodStart;
  final DateTime? leaderboardPeriodEnd;
  final List<LeaderboardApiCompanyEntry> entries;
  final List<LeaderboardApiGroup> groups;
  final List<LeaderboardApiGroupMember> menteeEntries;

  factory LeaderboardApiSnapshot.fromJson(Map<String, dynamic> json) {
    final company = json['company'] is Map
        ? Map<String, dynamic>.from(json['company'] as Map)
        : <String, dynamic>{};
    final rawEntries = <dynamic>[
      ...(json['companyLeaderboard'] as List? ?? const <dynamic>[]),
      ...(json['entries'] as List? ?? const <dynamic>[]),
    ];
    final seenUserIds = <String>{};
    final dedupedEntries = <LeaderboardApiCompanyEntry>[];
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map) continue;
      final entry = LeaderboardApiCompanyEntry.fromJson(
        Map<String, dynamic>.from(rawEntry),
      );
      if (entry.userId.isEmpty || !seenUserIds.add(entry.userId)) {
        continue;
      }
      dedupedEntries.add(entry);
    }

    return LeaderboardApiSnapshot(
      companyCode: company['companyCode']?.toString() ?? '',
      companyName: company['companyName']?.toString() ?? '',
      leaderboardPeriodStart: _parseApiDate(company['leaderboardPeriodStart']),
      leaderboardPeriodEnd: _parseApiDate(company['leaderboardPeriodEnd']),
      entries: dedupedEntries,
      groups: (json['groupLeaderboards'] as List?)
              ?.whereType<Map>()
              .map((group) =>
                  LeaderboardApiGroup.fromJson(Map<String, dynamic>.from(group)))
              .toList() ??
          const <LeaderboardApiGroup>[],
      menteeEntries: (json['menteeEntries'] as List?)
              ?.whereType<Map>()
              .map((entry) => LeaderboardApiGroupMember.fromJson(
                  Map<String, dynamic>.from(entry)))
              .toList() ??
          const <LeaderboardApiGroupMember>[],
    );
  }
}

class LeaderboardApiService {
  LeaderboardApiService._();

  static final LeaderboardApiService instance = LeaderboardApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<LeaderboardApiSnapshot> fetchLeaderboard() async {
    final response = await _api.getJson(
      '/api/leaderboard',
      token: _token,
    );
    return LeaderboardApiSnapshot.fromJson(response);
  }
}

num _parseApiNumber(dynamic value, {num fallback = 0}) {
  if (value is num) {
    return value;
  }

  final parsed = num.tryParse(value?.toString() ?? '');
  return parsed ?? fallback;
}

DateTime? _parseApiDate(dynamic value) {
  if (value == null) {
    return null;
  }

  final raw = value.toString().trim();
  if (raw.isEmpty) {
    return null;
  }

  return DateTime.tryParse(raw);
}
