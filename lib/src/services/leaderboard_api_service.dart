import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class LeaderboardApiCompanyEntry {
  const LeaderboardApiCompanyEntry({
    required this.userId,
    required this.name,
    required this.score,
    required this.rank,
    this.profilePic,
    this.teamName,
  });

  final String userId;
  final String name;
  final num score;
  final int rank;
  final String? profilePic;
  final String? teamName;

  factory LeaderboardApiCompanyEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardApiCompanyEntry(
      userId: json['userId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      score: json['score'] is num
          ? json['score'] as num
          : num.tryParse(json['score']?.toString() ?? '') ?? 0,
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
    required this.rank,
    this.profilePic,
    this.teamName,
  });

  final String userId;
  final String name;
  final num score;
  final int rank;
  final String? profilePic;
  final String? teamName;

  factory LeaderboardApiGroupMember.fromJson(Map<String, dynamic> json) {
    return LeaderboardApiGroupMember(
      userId: json['userId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      score: json['score'] is num
          ? json['score'] as num
          : num.tryParse(json['score']?.toString() ?? '') ?? 0,
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
    required this.totalScore,
    required this.entries,
  });

  final String groupId;
  final String groupName;
  final String coachName;
  final num totalScore;
  final List<LeaderboardApiGroupMember> entries;

  factory LeaderboardApiGroup.fromJson(Map<String, dynamic> json) {
    return LeaderboardApiGroup(
      groupId: json['groupId']?.toString() ?? '',
      groupName: json['groupName']?.toString() ?? 'Group',
      coachName: json['coachName']?.toString() ?? 'Coach',
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
    required this.entries,
    required this.groups,
    required this.menteeEntries,
  });

  final String companyCode;
  final String companyName;
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

    return LeaderboardApiSnapshot(
      companyCode: company['companyCode']?.toString() ?? '',
      companyName: company['companyName']?.toString() ?? '',
      entries: rawEntries
          .whereType<Map>()
          .map((entry) => LeaderboardApiCompanyEntry.fromJson(
              Map<String, dynamic>.from(entry)))
          .toList(),
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
