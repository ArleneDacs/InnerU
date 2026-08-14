import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';

class CompanyThemeData {
  const CompanyThemeData({
    required this.companyName,
    required this.companyCode,
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.inkColor,
    required this.mutedInkColor,
    required this.iconColor,
    required this.logoUrl,
    required this.tagline,
    required this.isDark,
    required this.isCompanyTheme,
  });

  final String companyName;
  final String companyCode;
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color inkColor;
  final Color mutedInkColor;
  final Color iconColor;
  final String logoUrl;
  final String tagline;
  final bool isDark;
  final bool isCompanyTheme;

  static const CompanyThemeData standard = CompanyThemeData(
    companyName: 'InnerU',
    companyCode: '',
    primaryColor: Color(0xFF90A783),
    accentColor: Color(0xFFC9B395),
    backgroundColor: Color(0xFFF7F6F1),
    surfaceColor: Colors.white,
    inkColor: Color(0xFF24311F),
    mutedInkColor: Color(0xFF5E6E57),
    iconColor: Color(0xFF3E9189),
    logoUrl: '',
    tagline:
        'Your dashboard is ready with the habits that keep today balanced.',
    isDark: false,
    isCompanyTheme: false,
  );

  CompanyThemeData copyWith({
    String? companyName,
    String? companyCode,
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? surfaceColor,
    Color? inkColor,
    Color? mutedInkColor,
    Color? iconColor,
    String? logoUrl,
    String? tagline,
    bool? isDark,
    bool? isCompanyTheme,
  }) {
    return CompanyThemeData(
      companyName: companyName ?? this.companyName,
      companyCode: companyCode ?? this.companyCode,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      inkColor: inkColor ?? this.inkColor,
      mutedInkColor: mutedInkColor ?? this.mutedInkColor,
      iconColor: iconColor ?? this.iconColor,
      logoUrl: logoUrl ?? this.logoUrl,
      tagline: tagline ?? this.tagline,
      isDark: isDark ?? this.isDark,
      isCompanyTheme: isCompanyTheme ?? this.isCompanyTheme,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'companyName': companyName,
      'companyCode': companyCode,
      'primaryColor': CompanyThemeService.colorToHex(primaryColor),
      'accentColor': CompanyThemeService.colorToHex(accentColor),
      'backgroundColor': CompanyThemeService.colorToHex(backgroundColor),
      'surfaceColor': CompanyThemeService.colorToHex(surfaceColor),
      'inkColor': CompanyThemeService.colorToHex(inkColor),
      'mutedInkColor': CompanyThemeService.colorToHex(mutedInkColor),
      'iconColor': CompanyThemeService.colorToHex(iconColor),
      'logoUrl': logoUrl,
      'tagline': tagline,
      'isDark': isDark,
      'isCompanyTheme': isCompanyTheme,
    };
  }

  static CompanyThemeData? fromJson(Map<String, dynamic> json) {
    try {
      return CompanyThemeData(
        companyName: (json['companyName'] as String?)?.trim() ??
            CompanyThemeData.standard.companyName,
        companyCode: (json['companyCode'] as String?)?.trim().toUpperCase() ??
            CompanyThemeData.standard.companyCode,
        primaryColor: CompanyThemeService.parseColor(
          json['primaryColor'] as String?,
          CompanyThemeData.standard.primaryColor,
        ),
        accentColor: CompanyThemeService.parseColor(
          json['accentColor'] as String?,
          CompanyThemeData.standard.accentColor,
        ),
        backgroundColor: CompanyThemeService.parseColor(
          json['backgroundColor'] as String?,
          CompanyThemeData.standard.backgroundColor,
        ),
        surfaceColor: CompanyThemeService.parseColor(
          json['surfaceColor'] as String?,
          CompanyThemeData.standard.surfaceColor,
        ),
        inkColor: CompanyThemeService.parseColor(
          json['inkColor'] as String?,
          CompanyThemeData.standard.inkColor,
        ),
        mutedInkColor: CompanyThemeService.parseColor(
          json['mutedInkColor'] as String?,
          CompanyThemeData.standard.mutedInkColor,
        ),
        iconColor: CompanyThemeService.parseColor(
          json['iconColor'] as String?,
          CompanyThemeData.standard.iconColor,
        ),
        logoUrl: (json['logoUrl'] as String?)?.trim() ??
            CompanyThemeData.standard.logoUrl,
        tagline: (json['tagline'] as String?)?.trim() ??
            CompanyThemeData.standard.tagline,
        isDark: json['isDark'] == true,
        isCompanyTheme: json['isCompanyTheme'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

class CompanyThemeService {
  const CompanyThemeService._();

  static const String companyThemeChoice = 'company';
  static const String lightThemeChoice = 'light';
  static const String darkThemeChoice = 'dark';
  static const String sageThemeChoice = 'sage';
  static const String tealThemeChoice = 'teal';
  static const String duskThemeChoice = 'dusk';

  static final ValueNotifier<int> themePreferenceVersion = ValueNotifier(0);

  static final Map<String, CompanyThemeData> _userThemeCache =
      <String, CompanyThemeData>{};

  static final List<CompanyThemeChoice> suggestedThemeChoices = [
    CompanyThemeChoice(
      id: sageThemeChoice,
      title: 'Soft Sage',
      subtitle: 'Warm, light, and gentle on the eyes.',
      theme: CompanyThemeData.standard,
    ),
    CompanyThemeChoice(
      id: tealThemeChoice,
      title: 'Clear Teal',
      subtitle: 'Fresh green-blue with clean contrast.',
      theme: CompanyThemeData.standard.copyWith(
        primaryColor: const Color(0xFF3E9189),
        accentColor: const Color(0xFF8ED1B8),
        backgroundColor: const Color(0xFFF4FAF8),
        surfaceColor: Colors.white,
        inkColor: const Color(0xFF1F2933),
        mutedInkColor: const Color(0xFF55716E),
        iconColor: const Color(0xFF245A55),
        tagline: 'A calm space for steady progress.',
      ),
    ),
    CompanyThemeChoice(
      id: duskThemeChoice,
      title: 'Dusk Focus',
      subtitle: 'Dark mode with softer teal highlights.',
      theme: CompanyThemeData.standard.copyWith(
        primaryColor: const Color(0xFF8ED1B8),
        accentColor: const Color(0xFF59BDB3),
        backgroundColor: const Color(0xFF07120F),
        surfaceColor: const Color(0xFF10221D),
        inkColor: Colors.white,
        mutedInkColor: const Color(0xFFB7ECEA),
        iconColor: const Color(0xFF8ED1B8),
        tagline: 'Low-light focus for quieter sessions.',
        isDark: true,
      ),
    ),
  ];

  static CompanyThemeData? cachedThemeForUser(String uid) {
    return _userThemeCache[uid];
  }

  static Future<CompanyThemeData?> loadPersistedThemeForUser(String uid) async {
    final cachedTheme = _userThemeCache[uid];
    if (cachedTheme != null) return cachedTheme;

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawTheme = prefs.getString(_themeCacheKey(uid));
      if (rawTheme == null || rawTheme.isEmpty) return null;
      final decoded = jsonDecode(rawTheme);
      if (decoded is! Map<String, dynamic>) return null;
      final theme = CompanyThemeData.fromJson(decoded);
      if (theme == null) return null;
      _userThemeCache[uid] = theme;
      return theme;
    } catch (_) {
      return null;
    }
  }

  static void cacheThemeForUser(String uid, CompanyThemeData theme) {
    final previous = _userThemeCache[uid];
    _userThemeCache[uid] = theme;
    unawaited(_persistThemeForUser(uid, theme));
    if (previous == null || !_sameTheme(previous, theme)) {
      themePreferenceVersion.value++;
    }
  }

  static void clearCachedThemeForUser(String uid) {
    _userThemeCache.remove(uid);
    unawaited(_clearPersistedThemeForUser(uid));
    themePreferenceVersion.value++;
  }

  static Future<CompanyThemeData> resolveForUser(String uid) async {
    // If resolution fails (e.g. no network), fall back to this user's own
    // last-known-good theme instead of the generic default -- otherwise
    // every rebuild while offline (this runs fresh each time, it isn't
    // memoized) would silently overwrite a correctly-loaded company theme
    // with CompanyThemeData.standard the moment the fetch failed, and that
    // wrong value would then itself get cached, making it "stick" until a
    // later successful fetch happened to overwrite it again.
    final lastKnownGood = _userThemeCache[uid];
    final companyTheme = await resolveCompanyThemeForUser(
      uid,
      fallback: lastKnownGood,
    );
    final themeChoice = await selectedThemeChoiceForUser(uid);
    final theme = _ensureReadableDarkTheme(
      applyThemeChoice(companyTheme, themeChoice),
    );
    cacheThemeForUser(uid, theme);
    return theme;
  }

  static Future<CompanyThemeData> resolveCompanyThemeForUser(
    String uid, {
    CompanyThemeData? fallback,
  }) async {
    try {
      final userData = await UserService.getUserData();
      if (userData.isNotEmpty) {
        final companyData = await _companyDataForUser(userData);
        if (companyData != null) {
          return await _resolveFromCompanyData(
            companyData,
            fallbackName: (companyData['name'] as String?)?.trim() ?? '',
            fallbackCode: (companyData['code'] as String?)?.trim() ?? '',
          );
        }

        final companyName =
            ((userData['activeCompanyName'] as String?)?.trim() ??
                    (userData['companyName'] as String?)?.trim() ??
                    '')
                .trim();
        final companyCode =
            ((userData['activeCompanyCode'] as String?)?.trim() ??
                    (userData['companyCode'] as String?)?.trim() ??
                    '')
                .toUpperCase();
        if (companyName.isNotEmpty || companyCode.isNotEmpty) {
          return await _resolveFromCompanyData(
            <String, dynamic>{
              'name': companyName,
              'code': companyCode,
              'themeEnabled': false,
            },
            fallbackName: companyName,
            fallbackCode: companyCode,
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve company theme from API: $e');
    }
    return fallback ?? CompanyThemeData.standard;
  }

  static Future<String> selectedThemeChoiceForUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themePreferenceKey(uid)) ?? companyThemeChoice;
  }

  static Future<void> setSelectedThemeChoiceForUser(
    String uid,
    String choiceId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePreferenceKey(uid), choiceId);
    _userThemeCache.remove(uid);
    await prefs.remove(_themeCacheKey(uid));
    themePreferenceVersion.value++;
  }

  static CompanyThemeData applyThemeChoice(
    CompanyThemeData companyTheme,
    String choiceId,
  ) {
    final normalizedChoice = choiceId.trim().toLowerCase();
    if (normalizedChoice == companyThemeChoice && companyTheme.isCompanyTheme) {
      return _ensureReadableDarkTheme(companyTheme);
    }

    final suggested = suggestedThemeChoices
        .where((choice) => choice.id == normalizedChoice)
        .map((choice) => choice.theme)
        .firstOrNull;
    if (suggested != null) {
      return _preserveCompanyIdentity(companyTheme, suggested);
    }

    if (normalizedChoice == darkThemeChoice) {
      return _preserveCompanyIdentity(
        companyTheme,
        CompanyThemeData.standard.copyWith(
          primaryColor: const Color(0xFF8ED1B8),
          accentColor: const Color(0xFF59BDB3),
          backgroundColor: const Color(0xFF07120F),
          surfaceColor: const Color(0xFF10221D),
          inkColor: Colors.white,
          mutedInkColor: const Color(0xFFB7ECEA),
          iconColor: const Color(0xFF8ED1B8),
          isDark: true,
        ),
      );
    }

    return _preserveCompanyIdentity(
      companyTheme,
      CompanyThemeData.standard.copyWith(isDark: false),
    );
  }

  static List<CompanyThemeChoice> availableThemeChoicesFor(
    CompanyThemeData companyTheme,
  ) {
    return [
      if (companyTheme.isCompanyTheme)
        CompanyThemeChoice(
          id: companyThemeChoice,
          title: '${companyTheme.companyName} theme',
          subtitle: 'Use your company colors.',
          theme: companyTheme,
        ),
      ...suggestedThemeChoices,
      CompanyThemeChoice(
        id: lightThemeChoice,
        title: 'Light mode',
        subtitle: 'Bright InnerU default.',
        theme: CompanyThemeData.standard.copyWith(isDark: false),
      ),
      CompanyThemeChoice(
        id: darkThemeChoice,
        title: 'Dark mode',
        subtitle: 'Low-light InnerU default.',
        theme: CompanyThemeData.standard.copyWith(
          primaryColor: const Color(0xFF8ED1B8),
          accentColor: const Color(0xFF59BDB3),
          backgroundColor: const Color(0xFF07120F),
          surfaceColor: const Color(0xFF10221D),
          inkColor: Colors.white,
          mutedInkColor: const Color(0xFFB7ECEA),
          iconColor: const Color(0xFF8ED1B8),
          isDark: true,
        ),
      ),
    ];
  }

  static CompanyThemeData _preserveCompanyIdentity(
    CompanyThemeData companyTheme,
    CompanyThemeData visualTheme,
  ) {
    return _ensureReadableDarkTheme(
      visualTheme.copyWith(
        companyName: companyTheme.companyName,
        companyCode: companyTheme.companyCode,
        logoUrl: companyTheme.logoUrl,
        isCompanyTheme: companyTheme.isCompanyTheme,
      ),
    );
  }

  static CompanyThemeData _ensureReadableDarkTheme(CompanyThemeData theme) {
    if (!theme.isDark) return theme;

    const readableInk = Colors.white;
    const readableMutedInk = Color(0xFFE4F8F6);
    final readablePrimary = _readableDarkColor(
      theme.primaryColor,
      theme.backgroundColor,
    );
    final readableAccent = _readableDarkColor(
      theme.accentColor,
      theme.backgroundColor,
      fallback: readableMutedInk,
    );
    final readableIcon = _readableDarkColor(
      theme.iconColor,
      theme.surfaceColor,
    );

    return theme.copyWith(
      primaryColor: readablePrimary,
      accentColor: readableAccent,
      inkColor: readableInk,
      mutedInkColor: readableMutedInk,
      iconColor: readableIcon,
    );
  }

  static Color _readableDarkColor(
    Color color,
    Color background, {
    Color fallback = Colors.white,
  }) {
    const minimumContrast = 4.5;
    if (_contrastRatio(background, color) >= minimumContrast) return color;

    final lightened = _lighten(color, 0.68);
    if (_contrastRatio(background, lightened) >= minimumContrast) {
      return lightened;
    }

    final mixed = Color.alphaBlend(
      fallback.withValues(alpha: 0.9),
      lightened,
    );
    if (_contrastRatio(background, mixed) >= minimumContrast) return mixed;

    return fallback;
  }

  static String _themePreferenceKey(String uid) {
    return 'inneru_theme_choice_$uid';
  }

  static String _themeCacheKey(String uid) {
    return 'inneru_company_theme_cache_$uid';
  }

  static Future<void> _persistThemeForUser(
    String uid,
    CompanyThemeData theme,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeCacheKey(uid), jsonEncode(theme.toJson()));
    } catch (_) {}
  }

  static Future<void> _clearPersistedThemeForUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_themeCacheKey(uid));
    } catch (_) {}
  }

  static bool _sameTheme(CompanyThemeData left, CompanyThemeData right) {
    return left.companyName == right.companyName &&
        left.companyCode == right.companyCode &&
        left.primaryColor == right.primaryColor &&
        left.accentColor == right.accentColor &&
        left.backgroundColor == right.backgroundColor &&
        left.surfaceColor == right.surfaceColor &&
        left.inkColor == right.inkColor &&
        left.mutedInkColor == right.mutedInkColor &&
        left.iconColor == right.iconColor &&
        left.logoUrl == right.logoUrl &&
        left.tagline == right.tagline &&
        left.isDark == right.isDark &&
        left.isCompanyTheme == right.isCompanyTheme;
  }

  static CompanyThemeData fromCompanyData(
    Map<String, dynamic> data, {
    String fallbackName = '',
    String fallbackCode = '',
  }) {
    final name = ((data['name'] as String?)?.trim().isNotEmpty == true)
        ? (data['name'] as String).trim()
        : fallbackName;
    final code = ((data['code'] as String?)?.trim().isNotEmpty == true)
        ? (data['code'] as String).trim().toUpperCase()
        : fallbackCode.toUpperCase();
    final themeSource = (data['themeSource'] as String?)?.trim() ?? '';
    final loadingImageUrl = (data['loadingImageUrl'] as String?)?.trim() ?? '';
    final hasUsableThemeSource = themeSource == 'manual' ||
        themeSource == 'auto' ||
        (themeSource.isEmpty && loadingImageUrl.isNotEmpty);
    final themeEnabled = hasUsableThemeSource && data['themeEnabled'] == true;
    if (!themeEnabled) return CompanyThemeData.standard;

    final base = CompanyThemeData.standard.copyWith(
      isCompanyTheme: name.isNotEmpty || code.isNotEmpty,
    );
    final savedMode =
        (data['themeMode'] as String?)?.trim().toLowerCase() ?? '';
    final requestedDark = savedMode == 'dark' ||
        (savedMode.isEmpty && data['themeIsDark'] == true) ||
        (savedMode.isEmpty && base.isDark);

    final primary = parseColor(
      data['themePrimaryColor'] as String?,
      base.primaryColor,
    );
    final accent = parseColor(
      data['themeAccentColor'] as String?,
      base.accentColor,
    );
    var background = parseColor(
      data['themeBackgroundColor'] as String?,
      requestedDark ? const Color(0xFF020B12) : base.backgroundColor,
    );
    var surface = parseColor(
      data['themeSurfaceColor'] as String?,
      requestedDark ? const Color(0xFF071A24) : base.surfaceColor,
    );

    final bool isDark;
    if (savedMode == 'light') {
      if (background.computeLuminance() < 0.45) {
        background = base.backgroundColor;
      }
      if (surface.computeLuminance() < 0.55) {
        surface = base.surfaceColor;
      }
      isDark = false;
    } else if (savedMode == 'dark') {
      if (background.computeLuminance() > 0.45) {
        background = const Color(0xFF020B12);
      }
      if (surface.computeLuminance() > 0.55) {
        surface = const Color(0xFF071A24);
      }
      isDark = true;
    } else {
      // No explicit theme mode was configured. Trust the actual background
      // color (custom or default) over the separate themeIsDark flag, which
      // can drift out of sync when an admin only configures colors -- e.g. a
      // custom dark themeBackgroundColor without also flipping themeIsDark,
      // which previously left ink/icon colors defaulting to light-theme
      // values and made text and icons invisible against the dark background.
      isDark = requestedDark || background.computeLuminance() < 0.45;
    }

    final theme = base.copyWith(
      companyName: name.isNotEmpty ? name : base.companyName,
      companyCode: code.isNotEmpty ? code : base.companyCode,
      primaryColor: primary,
      accentColor: accent,
      backgroundColor: background,
      surfaceColor: surface,
      inkColor: parseColor(
        data['themeInkColor'] as String?,
        isDark ? Colors.white : base.inkColor,
      ),
      mutedInkColor: parseColor(
        data['themeMutedInkColor'] as String?,
        isDark ? const Color(0xFFB7ECEA) : base.mutedInkColor,
      ),
      iconColor: parseColor(
        data['themeIconColor'] as String?,
        _readableAccentOn(surface, primary, isDark: isDark),
      ),
      logoUrl: (data['logoUrl'] as String?)?.trim() ?? base.logoUrl,
      tagline: ((data['tagline'] as String?)?.trim().isNotEmpty == true)
          ? (data['tagline'] as String).trim()
          : base.tagline,
      isDark: isDark,
      isCompanyTheme: true,
    );
    return _ensureReadableDarkTheme(theme);
  }

  static Future<CompanyThemeData> _resolveFromCompanyData(
    Map<String, dynamic> data, {
    String fallbackName = '',
    String fallbackCode = '',
  }) async {
    final name = ((data['name'] as String?)?.trim().isNotEmpty == true)
        ? (data['name'] as String).trim()
        : fallbackName;
    final code = ((data['code'] as String?)?.trim().isNotEmpty == true)
        ? (data['code'] as String).trim().toUpperCase()
        : fallbackCode.toUpperCase();
    final themeSource = (data['themeSource'] as String?)?.trim() ?? '';

    if (themeSource == 'manual') {
      return fromCompanyData(
        data,
        fallbackName: name,
        fallbackCode: code,
      );
    }

    final imageBytes = await _loadThemeImageBytes(data, name, code);
    if (imageBytes != null) {
      final palette = _extractThemePalette(imageBytes, name);
      if (palette != null) {
        return palette.toTheme(
          companyName: name,
          companyCode: code,
          logoUrl: (data['logoUrl'] as String?)?.trim() ?? '',
          fallbackTagline: (data['tagline'] as String?)?.trim() ?? '',
        );
      }
    }

    if (themeSource == 'auto' || data['themeEnabled'] == true) {
      return fromCompanyData(
        data,
        fallbackName: name,
        fallbackCode: code,
      );
    }

    return CompanyThemeData.standard;
  }

  static Future<Map<String, dynamic>?> _companyDataForUser(
    Map<String, dynamic> userData,
  ) async {
    final lookupKeys =
        CompanyMembershipService.lookupKeysFromUserData(userData);
    for (final lookupKey in lookupKeys) {
      try {
        final company = await CompanyApiService.instance.findByCode(lookupKey);
        if (company == null || !company.isActive) {
          continue;
        }

        return {
          'name': company.name,
          'code': company.code,
          'themeEnabled': company.themeEnabled,
          'themeSource': company.themeSource,
          'tagline': company.tagline,
          'themePrimaryColor': company.themePrimaryColor,
          'themeAccentColor': company.themeAccentColor,
          'themeBackgroundColor': company.themeBackgroundColor,
          'themeSurfaceColor': company.themeSurfaceColor,
          'themeInkColor': company.themeInkColor,
          'themeMutedInkColor': company.themeMutedInkColor,
          'themeIconColor': company.themeIconColor,
          'themeMode': company.themeMode,
          'themeIsDark': company.themeIsDark,
          'logoUrl': company.logoUrl,
          'loadingImageUrl': company.loadingImageUrl,
          'loadingVideoUrl': company.loadingVideoUrl,
        };
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          return null;
        }
        debugPrint('Failed to resolve company theme lookup [$lookupKey]: $e');
      } catch (e) {
        debugPrint('Failed to resolve company theme lookup [$lookupKey]: $e');
      }
    }

    return null;
  }

  static Future<Uint8List?> _loadThemeImageBytes(
    Map<String, dynamic> data,
    String companyName,
    String companyCode,
  ) async {
    final loadingImageUrl = (data['loadingImageUrl'] as String?)?.trim() ?? '';
    if (loadingImageUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(loadingImageUrl));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response.bodyBytes;
        }
      } catch (_) {
        return null;
      }
    }

    final fallbackAsset = _fallbackLoadingAsset(companyName, companyCode);
    if (fallbackAsset == null) return null;

    try {
      final bytes = await rootBundle.load(fallbackAsset);
      return bytes.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static String? _fallbackLoadingAsset(String companyName, String companyCode) {
    if (_matchesGencys(companyName, companyCode)) {
      return 'assets/images/gencys_loading.png';
    }
    if (_matchesIamPlus(companyName, companyCode)) {
      return 'assets/images/iamplus.png';
    }
    if (_matchesAbundanceCompany(companyName, companyCode)) {
      return 'assets/images/abundance12_loading.jpg';
    }
    return null;
  }

  static _AutoThemePalette? _extractThemePalette(Uint8List bytes, String name) {
    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null || decoded.width == 0 || decoded.height == 0) {
      return null;
    }

    final colorCounts = <int, int>{};
    var sampled = 0;
    var totalLuminance = 0.0;
    final stepX = math.max(1, decoded.width ~/ 90);
    final stepY = math.max(1, decoded.height ~/ 160);

    for (var y = 0; y < decoded.height; y += stepY) {
      for (var x = 0; x < decoded.width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        if (pixel.a.toInt() < 180) continue;

        final luminance = _luminance(r, g, b);
        totalLuminance += luminance;
        sampled++;
        if (luminance < 0.08 || luminance > 0.94) continue;

        final color = Color.fromARGB(
          255,
          (r ~/ 24) * 24,
          (g ~/ 24) * 24,
          (b ~/ 24) * 24,
        );
        final hsv = HSVColor.fromColor(color);
        if (hsv.saturation < 0.18) continue;
        final score = (1 + (hsv.saturation * 3) + (hsv.value * 1.2)).round();
        colorCounts[color.toARGB32()] =
            (colorCounts[color.toARGB32()] ?? 0) + score;
      }
    }

    if (colorCounts.isEmpty || sampled == 0) return null;

    final ranked = colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final primary = Color(ranked.first.key);
    var accent = primary;
    for (final entry in ranked.skip(1)) {
      final candidate = Color(entry.key);
      if (_hueDistance(primary, candidate) >= 28 ||
          _colorDistance(primary, candidate) >= 82) {
        accent = candidate;
        break;
      }
    }
    if (accent == primary && ranked.length > 1) {
      accent = Color(ranked[1].key);
    }

    final isDark = (totalLuminance / sampled) < 0.52;
    final tunedPrimary = _boostBrandColor(primary, preferLight: isDark);
    final tunedAccent = _boostBrandColor(accent, preferLight: isDark);

    return _AutoThemePalette(
      primaryColor: tunedPrimary,
      accentColor: tunedAccent,
      backgroundColor:
          isDark ? _darken(tunedPrimary, 0.82) : _lighten(tunedPrimary, 0.88),
      surfaceColor: isDark ? _darken(tunedAccent, 0.74) : Colors.white,
      inkColor: isDark ? Colors.white : const Color(0xFF24311F),
      mutedInkColor:
          isDark ? _lighten(tunedPrimary, 0.52) : _darken(tunedPrimary, 0.35),
      iconColor: _readableAccentOn(
        isDark ? _darken(tunedAccent, 0.74) : Colors.white,
        tunedPrimary,
        isDark: isDark,
      ),
      isDark: isDark,
      tagline: name.trim().isEmpty ? '' : '${name.trim()} workspace',
    );
  }

  static double _luminance(int r, int g, int b) {
    return ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)) / 255;
  }

  static double _hueDistance(Color a, Color b) {
    final hueA = HSVColor.fromColor(a).hue;
    final hueB = HSVColor.fromColor(b).hue;
    final distance = (hueA - hueB).abs();
    return math.min(distance, 360 - distance);
  }

  static double _colorDistance(Color a, Color b) {
    final valueA = a.toARGB32();
    final valueB = b.toARGB32();
    final dr = ((valueA >> 16) & 0xFF) - ((valueB >> 16) & 0xFF);
    final dg = ((valueA >> 8) & 0xFF) - ((valueB >> 8) & 0xFF);
    final db = (valueA & 0xFF) - (valueB & 0xFF);
    return math.sqrt((dr * dr) + (dg * dg) + (db * db));
  }

  static Color _boostBrandColor(Color color, {required bool preferLight}) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation(hsv.saturation.clamp(0.38, 0.92))
        .withValue(preferLight
            ? hsv.value.clamp(0.68, 1.0)
            : hsv.value.clamp(0.48, 0.86))
        .toColor();
  }

  static Color _darken(Color color, double amount) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation((hsv.saturation * 0.88).clamp(0.12, 1.0))
        .withValue((hsv.value * (1 - amount)).clamp(0.03, 0.34))
        .toColor();
  }

  static Color _lighten(Color color, double amount) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation(
            (hsv.saturation * (1 - (amount * 0.7))).clamp(0.05, 0.45))
        .withValue((hsv.value + ((1 - hsv.value) * amount)).clamp(0.72, 1.0))
        .toColor();
  }

  static Color _readableAccentOn(
    Color background,
    Color accent, {
    required bool isDark,
  }) {
    final contrast = _contrastRatio(background, accent);
    if (contrast >= 3.0) return accent;
    return isDark ? _lighten(accent, 0.42) : _darken(accent, 0.38);
  }

  static double _contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a) + 0.05;
    final l2 = _relativeLuminance(b) + 0.05;
    return l1 > l2 ? l1 / l2 : l2 / l1;
  }

  static double _relativeLuminance(Color color) {
    double channel(int value) {
      final normalized = value / 255;
      return normalized <= 0.03928
          ? normalized / 12.92
          : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
    }

    final value = color.toARGB32();
    return (0.2126 * channel((value >> 16) & 0xFF)) +
        (0.7152 * channel((value >> 8) & 0xFF)) +
        (0.0722 * channel(value & 0xFF));
  }

  static Color parseColor(String? rawValue, Color fallback) {
    final cleaned = rawValue?.trim().replaceAll('#', '');
    if (cleaned == null || cleaned.isEmpty) return fallback;
    final normalized = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) return fallback;
    return Color(value);
  }

  static String colorToHex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static bool _matchesGencys(String companyName, String companyCode) {
    final normalizedName = companyName.toLowerCase();
    final normalizedCode = companyCode.toUpperCase();
    return normalizedName.contains('gencys') ||
        normalizedCode.contains('GENCYS') ||
        normalizedCode.startsWith('GEN');
  }

  static bool _matchesIamPlus(String companyName, String companyCode) {
    final normalizedName =
        companyName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '');
    final normalizedCode =
        companyCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9+]'), '');
    return normalizedName.contains('iamplus') ||
        normalizedName.contains('iam+') ||
        (normalizedName.contains('iam') && normalizedName.contains('plus')) ||
        normalizedCode.contains('IAMPLUS') ||
        normalizedCode.contains('IAM+') ||
        normalizedCode.startsWith('IAM');
  }

  static bool _matchesAbundanceCompany(String companyName, String companyCode) {
    return AbundanceCompany.matches(companyCode, companyName);
  }
}

class _AutoThemePalette {
  const _AutoThemePalette({
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.inkColor,
    required this.mutedInkColor,
    required this.iconColor,
    required this.isDark,
    required this.tagline,
  });

  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color inkColor;
  final Color mutedInkColor;
  final Color iconColor;
  final bool isDark;
  final String tagline;

  CompanyThemeData toTheme({
    required String companyName,
    required String companyCode,
    required String logoUrl,
    required String fallbackTagline,
  }) {
    return CompanyThemeService._ensureReadableDarkTheme(
      CompanyThemeData.standard.copyWith(
        companyName: companyName.isNotEmpty ? companyName : companyCode,
        companyCode: companyCode,
        primaryColor: primaryColor,
        accentColor: accentColor,
        backgroundColor: backgroundColor,
        surfaceColor: surfaceColor,
        inkColor: inkColor,
        mutedInkColor: mutedInkColor,
        iconColor: iconColor,
        logoUrl: logoUrl,
        tagline: fallbackTagline.isNotEmpty ? fallbackTagline : tagline,
        isDark: isDark,
        isCompanyTheme: true,
      ),
    );
  }
}

class CompanyThemeChoice {
  const CompanyThemeChoice({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.theme,
  });

  final String id;
  final String title;
  final String subtitle;
  final CompanyThemeData theme;
}

class CompanyThemeBuilder extends StatefulWidget {
  const CompanyThemeBuilder({
    super.key,
    required this.builder,
    this.loadingBuilder,
    this.applyUserPreference = true,
  });

  final Widget Function(BuildContext context, CompanyThemeData theme) builder;
  final WidgetBuilder? loadingBuilder;
  final bool applyUserPreference;

  @override
  State<CompanyThemeBuilder> createState() => _CompanyThemeBuilderState();
}

class _CompanyThemeBuilderState extends State<CompanyThemeBuilder> {
  String? _userId;
  Future<CompanyThemeData>? _themeFuture;
  CompanyThemeData? _cachedTheme;
  int _observedPreferenceVersion = CompanyThemeService.themePreferenceVersion.value;

  @override
  void initState() {
    super.initState();
    CompanyThemeService.themePreferenceVersion.addListener(_refreshTheme);
    _syncThemeFuture();
  }

  @override
  void didUpdateWidget(covariant CompanyThemeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncThemeFuture();
  }

  @override
  void dispose() {
    CompanyThemeService.themePreferenceVersion.removeListener(_refreshTheme);
    super.dispose();
  }

  void _refreshTheme() {
    final currentVersion = CompanyThemeService.themePreferenceVersion.value;
    if (_observedPreferenceVersion == currentVersion) return;
    _observedPreferenceVersion = currentVersion;
    _syncThemeFuture(forceRefresh: true);
  }

  void _syncThemeFuture({bool forceRefresh = false}) {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (_userId != null || _themeFuture != null || _cachedTheme != null) {
        setState(() {
          _userId = null;
          _themeFuture = null;
          _cachedTheme = null;
        });
      }
      return;
    }

    final userId = session.id.toString();
    final cachedTheme = CompanyThemeService.cachedThemeForUser(userId);
    final userChanged = _userId != userId;
    if (!forceRefresh && !userChanged && _themeFuture != null) {
      return;
    }

    _userId = userId;
    _cachedTheme = cachedTheme;
    _themeFuture = widget.applyUserPreference
        ? CompanyThemeService.resolveForUser(userId)
        : CompanyThemeService.resolveCompanyThemeForUser(
            userId,
            fallback: cachedTheme,
          );
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return widget.builder(context, CompanyThemeData.standard);
    }
    final userId = session.id.toString();
    if (_userId != userId || _themeFuture == null) {
      _syncThemeFuture(forceRefresh: _userId != userId);
    }

    return FutureBuilder<CompanyThemeData>(
      future: _themeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_cachedTheme != null) {
            return widget.builder(context, _cachedTheme!);
          }
          if (widget.loadingBuilder != null) {
            return widget.loadingBuilder!(context);
          }
        }

        return widget.builder(
          context,
          snapshot.data ?? _cachedTheme ?? CompanyThemeData.standard,
        );
      },
    );
  }
}
