import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class CompanyApiCompany {
  const CompanyApiCompany({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
    required this.themeEnabled,
    required this.themeSource,
    required this.tagline,
    required this.themePrimaryColor,
    required this.themeAccentColor,
    required this.themeBackgroundColor,
    required this.themeSurfaceColor,
    required this.themeInkColor,
    required this.themeMutedInkColor,
    required this.themeIconColor,
    required this.themeMode,
    required this.themeIsDark,
    required this.logoUrl,
    required this.logoFileName,
    required this.loadingImageUrl,
    required this.loadingImageFileName,
    required this.loadingVideoUrl,
    required this.loadingVideoFileName,
  });

  final String id;
  final String name;
  final String code;
  final bool isActive;
  final bool themeEnabled;
  final String? themeSource;
  final String? tagline;
  final String? themePrimaryColor;
  final String? themeAccentColor;
  final String? themeBackgroundColor;
  final String? themeSurfaceColor;
  final String? themeInkColor;
  final String? themeMutedInkColor;
  final String? themeIconColor;
  final String? themeMode;
  final bool themeIsDark;
  final String? logoUrl;
  final String? logoFileName;
  final String? loadingImageUrl;
  final String? loadingImageFileName;
  final String? loadingVideoUrl;
  final String? loadingVideoFileName;

  factory CompanyApiCompany.fromJson(Map<String, dynamic> json) {
    return CompanyApiCompany(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      isActive: json['isActive'] == true,
      themeEnabled: json['themeEnabled'] == true,
      themeSource: json['themeSource']?.toString(),
      tagline: json['tagline']?.toString(),
      themePrimaryColor: json['themePrimaryColor']?.toString(),
      themeAccentColor: json['themeAccentColor']?.toString(),
      themeBackgroundColor: json['themeBackgroundColor']?.toString(),
      themeSurfaceColor: json['themeSurfaceColor']?.toString(),
      themeInkColor: json['themeInkColor']?.toString(),
      themeMutedInkColor: json['themeMutedInkColor']?.toString(),
      themeIconColor: json['themeIconColor']?.toString(),
      themeMode: json['themeMode']?.toString(),
      themeIsDark: json['themeIsDark'] == true,
      logoUrl: json['logoUrl']?.toString(),
      logoFileName: json['logoFileName']?.toString(),
      loadingImageUrl: json['loadingImageUrl']?.toString(),
      loadingImageFileName: json['loadingImageFileName']?.toString(),
      loadingVideoUrl: json['loadingVideoUrl']?.toString(),
      loadingVideoFileName: json['loadingVideoFileName']?.toString(),
    );
  }
}

class CompanyApiService {
  CompanyApiService._();

  static final CompanyApiService instance = CompanyApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<CompanyApiCompany>> fetchCompanies() async {
    final response = await _api.getJson(
      '/api/companies',
      token: _token,
    );
    final companies = response['companies'];
    if (companies is! List) {
      return const <CompanyApiCompany>[];
    }

    return companies
        .whereType<Map>()
        .map((item) => CompanyApiCompany.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<CompanyApiCompany> createCompany(String name) async {
    final response = await _api.postJson(
      '/api/companies',
      {'name': name},
      token: _token,
    );
    final company = response['company'];
    if (company is Map<String, dynamic>) {
      return CompanyApiCompany.fromJson(company);
    }
    return CompanyApiCompany.fromJson(<String, dynamic>{});
  }

  Future<CompanyApiCompany> updateCompany(
    String companyId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _api.patchJson(
      '/api/companies/$companyId',
      payload,
      token: _token,
    );
    final company = response['company'];
    if (company is Map<String, dynamic>) {
      return CompanyApiCompany.fromJson(company);
    }
    return CompanyApiCompany.fromJson(<String, dynamic>{});
  }

  Future<void> deleteCompany(String companyId) async {
    await _api.deleteJson(
      '/api/companies/$companyId',
      token: _token,
    );
  }

  Future<List<Map<String, dynamic>>> fetchCompanyMembers(String companyId) async {
    final response = await _api.getJson(
      '/api/companies/$companyId/members',
      token: _token,
    );
    final members = response['members'];
    if (members is! List) {
      return const <Map<String, dynamic>>[];
    }

    return members
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<CompanyApiCompany?> findByCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return null;

    try {
      final response = await _api.getJson(
        Uri(path: '/api/companies/lookup', queryParameters: {
          'code': normalizedCode,
        }).toString(),
        token: _token,
      );
      final company = response['company'];
      if (company is Map<String, dynamic>) {
        return CompanyApiCompany.fromJson(company);
      }
    } catch (_) {
      // Fall through to a broader search.
    }

    final companies = await fetchCompanies();
    for (final company in companies) {
      if (company.code.toUpperCase() == normalizedCode ||
          company.id.toUpperCase() == normalizedCode) {
        return company;
      }
    }

    return null;
  }
}
