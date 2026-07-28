import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

const Color _ink = Color(0xFF24311F);
const Color _mutedInk = Color(0xFF6B7165);
const Color _border = Color(0xFFE0E5D9);
const Color ink = _ink;
const Color mutedInk = _mutedInk;
const Color border = _border;

bool isGencysCompany(String name, String code) {
  final normalizedName = name.trim().toLowerCase();
  final normalizedCode = code.trim().toUpperCase();
  return normalizedName.contains('gencys') ||
      normalizedCode.contains('GENCYS') ||
      normalizedCode.startsWith('GEN');
}

bool isIamPlusCompany(String name, String code) {
  final normalizedName =
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9+]'), '');
  final normalizedCode =
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9+]'), '');
  return normalizedName.contains('iamplus') ||
      normalizedName.contains('iam+') ||
      (normalizedName.contains('iam') && normalizedName.contains('plus')) ||
      normalizedCode.contains('IAMPLUS') ||
      normalizedCode.contains('IAM+') ||
      normalizedCode.startsWith('IAM');
}

bool isAbundance12Company(String name, String code) {
  final normalizedName =
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final normalizedCode =
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return normalizedName.contains('abundance12') ||
      (normalizedName.contains('abundance') && normalizedName.contains('12')) ||
      normalizedCode.contains('ABUNDANCE12') ||
      normalizedCode.contains('ABUND12') ||
      normalizedCode == 'A12' ||
      normalizedCode.startsWith('AB12');
}

class ManageCompaniesScreen extends StatefulWidget {
  const ManageCompaniesScreen({super.key});

  @override
  State<ManageCompaniesScreen> createState() => _ManageCompaniesScreenState();
}

class _ManageCompaniesScreenState extends State<ManageCompaniesScreen> {
  final ImagePicker _mediaPicker = ImagePicker();
  final Set<String> _uploadingLogos = <String>{};
  final Set<String> _uploadingImages = <String>{};
  final Set<String> _uploadingVideos = <String>{};

  Stream<List<_ManagedCompany>> _companiesStream() {
    return Stream.fromFuture(_loadCompanies());
  }

  Future<List<_ManagedCompany>> _loadCompanies() async {
    final companies = await CompanyApiService.instance.fetchCompanies();
    return companies
        .map(_ManagedCompany.fromApi)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _refreshCompanies() {
    if (mounted) {
      setState(() {});
    }
  }

  Stream<List<_CompanyMember>> _companyMembersStream(_ManagedCompany company) {
    return Stream.fromFuture(_loadCompanyMembers(company));
  }

  Future<List<_CompanyMember>> _loadCompanyMembers(
    _ManagedCompany company,
  ) async {
    final members = await CompanyApiService.instance.fetchCompanyMembers(
      company.id,
    );
    final parsed = members
        .map(_CompanyMember.fromMap)
        .where((member) => !member.isAdmin)
        .toList()
      ..sort((a, b) {
        final roleSort = a.roleRank.compareTo(b.roleRank);
        if (roleSort != 0) return roleSort;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return parsed;
  }

  Future<String> _createCompany(String companyName) async {
    final trimmedName = companyName.trim();
    final company = await CompanyApiService.instance.createCompany(trimmedName);
    return company.code;
  }

  Future<void> _showAddCompanyDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _AddCompanyDialog(),
    );

    if (name == null || name.trim().isEmpty) return;

    try {
      final code = await _createCompany(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Company added. Code: $code')),
      );
      _refreshCompanies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add company: $e')),
      );
    }
  }

  Future<void> _showEditNameDialog(_ManagedCompany company) async {
    final controller = TextEditingController(text: company.name);
    var isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Company Name'),
              content: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Company name',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = controller.text.trim();
                          if (name.isEmpty || name == company.name) {
                            Navigator.pop(dialogContext);
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            await _updateCompanyName(company, name);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            _refreshCompanies();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Renamed to $name.'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to rename company: $e'),
                              ),
                            );
                            if (dialogContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _updateCompanyName(
    _ManagedCompany company,
    String name,
  ) async {
    await CompanyApiService.instance.updateCompany(
      company.id,
      {'name': name},
    );
  }

  Future<void> _showLeaderboardPeriodDialog(_ManagedCompany company) async {
    DateTime? startDate = company.leaderboardPeriodStart;
    DateTime? endDate = company.leaderboardPeriodEnd;
    var isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: startDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) {
                setDialogState(() => startDate = picked);
              }
            }

            Future<void> pickEndDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: endDate ?? (startDate ?? DateTime.now()),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) {
                setDialogState(() => endDate = picked);
              }
            }

            final formatter = DateFormat('MMM d, yyyy');

            return AlertDialog(
              title: const Text('Leaderboard Period'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Only activity within this date range counts toward "
                    "this company's leaderboard.",
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start date'),
                    subtitle: Text(
                      startDate == null
                          ? 'Not set'
                          : formatter.format(startDate!),
                    ),
                    trailing: const Icon(CupertinoIcons.calendar),
                    onTap: isSaving ? null : pickStartDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End date'),
                    subtitle: Text(
                      endDate == null ? 'Not set' : formatter.format(endDate!),
                    ),
                    trailing: const Icon(CupertinoIcons.calendar),
                    onTap: isSaving ? null : pickEndDate,
                  ),
                ],
              ),
              actions: [
                if (company.leaderboardPeriodStart != null ||
                    company.leaderboardPeriodEnd != null)
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            try {
                              await CompanyApiService.instance.updateCompany(
                                company.id,
                                {'clearLeaderboardPeriod': true},
                              );
                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext);
                              _refreshCompanies();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Leaderboard period removed for '
                                    '${company.name}.',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to remove leaderboard period: $e',
                                  ),
                                ),
                              );
                              if (dialogContext.mounted) {
                                setDialogState(() => isSaving = false);
                              }
                            }
                          },
                    child: const Text('Remove period'),
                  ),
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final start = startDate;
                          final end = endDate;
                          if (start == null || end == null) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please set both a start and end date.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (end.isBefore(start)) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'End date must be on or after the start date.',
                                ),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            final keyFormat = DateFormat('yyyy-MM-dd');
                            await CompanyApiService.instance.updateCompany(
                              company.id,
                              {
                                'leaderboardPeriodStart': keyFormat.format(start),
                                'leaderboardPeriodEnd': keyFormat.format(end),
                              },
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            _refreshCompanies();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Leaderboard period saved for '
                                  '${company.name}.',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to save leaderboard period: $e',
                                ),
                              ),
                            );
                            if (dialogContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied company code: $code')),
    );
  }

  Future<void> _setThemeEnabled(
    _ManagedCompany company,
    bool enabled,
  ) async {
    await CompanyApiService.instance.updateCompany(
      company.id,
      {
        'themeEnabled': enabled,
        'themeSource': 'manual',
      },
    );
    _refreshCompanies();
  }

  Future<void> _showThemeDialog(_ManagedCompany company) async {
    final fallbackTheme = CompanyThemeData.standard;
    final taglineController = TextEditingController(
      text:
          company.tagline.isNotEmpty ? company.tagline : fallbackTheme.tagline,
    );
    var primaryColor = CompanyThemeService.parseColor(
      company.themePrimaryColor,
      fallbackTheme.primaryColor,
    );
    var accentColor = CompanyThemeService.parseColor(
      company.themeAccentColor,
      fallbackTheme.accentColor,
    );
    var textColor = CompanyThemeService.parseColor(
      company.themeInkColor,
      fallbackTheme.inkColor,
    );
    var iconColor = CompanyThemeService.parseColor(
      company.themeIconColor,
      fallbackTheme.iconColor,
    );
    var themeEnabled = company.themeEnabled;
    var themeMode = company.themeMode.toLowerCase() == 'dark'
        ? 'dark'
        : company.themeMode.toLowerCase() == 'light'
            ? 'light'
            : fallbackTheme.isDark
                ? 'dark'
                : 'light';
    var isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final selectedThemeColors = _manualThemeColors(
              mode: themeMode,
              primaryColor: primaryColor,
              accentColor: accentColor,
              textColor: textColor,
              iconColor: iconColor,
            );
            final isDarkPreview = selectedThemeColors.isDark;
            final taglinePreview = taglineController.text.trim().isEmpty
                ? fallbackTheme.tagline
                : taglineController.text.trim();

            return AlertDialog(
              title: Text('${company.name} Theme'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ThemePreviewCard(
                      companyName: company.name,
                      companyCode: company.code,
                      tagline: taglinePreview,
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                      backgroundColor: selectedThemeColors.backgroundColor,
                      surfaceColor: selectedThemeColors.surfaceColor,
                      inkColor: textColor,
                      mutedInkColor: selectedThemeColors.mutedInkColor,
                      iconColor: iconColor,
                      isDark: isDarkPreview,
                      isEnabled: themeEnabled,
                      logoUrl: company.logoUrl,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: themeEnabled,
                      title: const Text('Enable company theme'),
                      subtitle: const Text('Users see company branding.'),
                      onChanged: isSaving
                          ? null
                          : (value) => setDialogState(() {
                                themeEnabled = value;
                              }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: taglineController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Tagline',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Palette samples',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in _themePalettePresets)
                          _PaletteSampleButton(
                            preset: preset,
                            selected: primaryColor.toARGB32() ==
                                    preset.primaryColor.toARGB32() &&
                                accentColor.toARGB32() ==
                                    preset.accentColor.toARGB32() &&
                                themeMode == preset.mode,
                            onTap: () => setDialogState(() {
                              themeMode = preset.mode;
                              primaryColor = preset.primaryColor;
                              accentColor = preset.accentColor;
                              textColor = preset.inkColor;
                              iconColor = preset.iconColor;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ColorChoiceField(
                      label: 'Primary color',
                      color: primaryColor,
                      onTap: () async {
                        final selected = await _pickThemeColor(
                          dialogContext,
                          title: 'Primary color',
                          selectedColor: primaryColor,
                        );
                        if (selected != null) {
                          setDialogState(() => primaryColor = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _ColorChoiceField(
                      label: 'Accent color',
                      color: accentColor,
                      onTap: () async {
                        final selected = await _pickThemeColor(
                          dialogContext,
                          title: 'Accent color',
                          selectedColor: accentColor,
                        );
                        if (selected != null) {
                          setDialogState(() => accentColor = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _ColorChoiceField(
                      label: 'Text color',
                      color: textColor,
                      onTap: () async {
                        final selected = await _pickThemeColor(
                          dialogContext,
                          title: 'Text color',
                          selectedColor: textColor,
                        );
                        if (selected != null) {
                          setDialogState(() => textColor = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _ColorChoiceField(
                      label: 'Icon color',
                      color: iconColor,
                      onTap: () async {
                        final selected = await _pickThemeColor(
                          dialogContext,
                          title: 'Icon color',
                          selectedColor: iconColor,
                        );
                        if (selected != null) {
                          setDialogState(() => iconColor = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'light',
                          label: Text('Light'),
                          icon: Icon(CupertinoIcons.sun_max_fill),
                        ),
                        ButtonSegment(
                          value: 'dark',
                          label: Text('Dark'),
                          icon: Icon(CupertinoIcons.moon_stars_fill),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: isSaving
                          ? null
                          : (selection) => setDialogState(() {
                                themeMode = selection.first;
                                final refreshed = _manualThemeColors(
                                  mode: themeMode,
                                  primaryColor: primaryColor,
                                  accentColor: accentColor,
                                );
                                textColor = refreshed.inkColor;
                                iconColor = refreshed.iconColor;
                              }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          final savedThemeColors = _manualThemeColors(
                            mode: themeMode,
                            primaryColor: primaryColor,
                            accentColor: accentColor,
                            textColor: textColor,
                            iconColor: iconColor,
                          );
                          await CompanyApiService.instance.updateCompany(
                            company.id,
                            {
                              'themeEnabled': themeEnabled,
                              'themeSource': 'manual',
                              'tagline': taglineController.text.trim(),
                              'themePrimaryColor':
                                  CompanyThemeService.colorToHex(
                                      savedThemeColors.primaryColor),
                              'themeAccentColor':
                                  CompanyThemeService.colorToHex(
                                      savedThemeColors.accentColor),
                              'themeBackgroundColor':
                                  CompanyThemeService.colorToHex(
                                      savedThemeColors.backgroundColor),
                              'themeSurfaceColor':
                                  CompanyThemeService.colorToHex(
                                      savedThemeColors.surfaceColor),
                              'themeInkColor': CompanyThemeService.colorToHex(
                                  savedThemeColors.inkColor),
                              'themeMutedInkColor':
                                  CompanyThemeService.colorToHex(
                                      savedThemeColors.mutedInkColor),
                              'themeIconColor': CompanyThemeService.colorToHex(
                                  savedThemeColors.iconColor),
                              'themeMode': savedThemeColors.mode,
                              'themeIsDark': savedThemeColors.isDark,
                            },
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          _refreshCompanies();
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    taglineController.dispose();
  }

  Future<Color?> _pickThemeColor(
    BuildContext context, {
    required String title,
    required Color selectedColor,
  }) {
    return showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _themeColorChoices)
                  _PaletteColorButton(
                    color: color,
                    selected: color.toARGB32() == selectedColor.toARGB32(),
                    onTap: () => Navigator.pop(context, color),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  _ManualThemeColors _manualThemeColors({
    required String mode,
    required Color primaryColor,
    required Color accentColor,
    Color? textColor,
    Color? iconColor,
  }) {
    final isDark = mode.toLowerCase() == 'dark';
    final backgroundColor =
        isDark ? _darken(primaryColor, 0.84) : _lighten(primaryColor, 0.9);
    final surfaceColor =
        isDark ? _darken(accentColor, 0.78) : const Color(0xFFFFFFFF);
    final inkColor =
        textColor ?? (isDark ? Colors.white : const Color(0xFF24311F));
    final mutedInkColor =
        isDark ? _lighten(primaryColor, 0.56) : _darken(primaryColor, 0.36);
    final resolvedIcon = iconColor ??
        _readableAccentOn(
          surfaceColor,
          accentColor,
          isDark: isDark,
        );

    return _ManualThemeColors(
      mode: isDark ? 'dark' : 'light',
      primaryColor: primaryColor,
      accentColor: accentColor,
      backgroundColor: backgroundColor,
      surfaceColor: surfaceColor,
      inkColor: inkColor,
      mutedInkColor: mutedInkColor,
      iconColor: resolvedIcon,
      isDark: isDark,
    );
  }

  static const List<_ThemePalettePreset> _themePalettePresets = [
    _ThemePalettePreset(
      name: 'Soft Sage',
      mode: 'light',
      primaryColor: Color(0xFF90A783),
      accentColor: Color(0xFFC9B395),
      inkColor: Color(0xFF24311F),
      iconColor: Color(0xFF5E6E57),
    ),
    _ThemePalettePreset(
      name: 'Clear Teal',
      mode: 'light',
      primaryColor: Color(0xFF3E9189),
      accentColor: Color(0xFF8ED1B8),
      inkColor: Color(0xFF1F2933),
      iconColor: Color(0xFF245A55),
    ),
    _ThemePalettePreset(
      name: 'Calm Blue',
      mode: 'light',
      primaryColor: Color(0xFF2E7DFF),
      accentColor: Color(0xFFEFD199),
      inkColor: Color(0xFF1F2933),
      iconColor: Color(0xFF1565C0),
    ),
    _ThemePalettePreset(
      name: 'Night Teal',
      mode: 'dark',
      primaryColor: Color(0xFF35CFC5),
      accentColor: Color(0xFF2E7DFF),
      inkColor: Colors.white,
      iconColor: Color(0xFF7FFFF8),
    ),
    _ThemePalettePreset(
      name: 'Deep Focus',
      mode: 'dark',
      primaryColor: Color(0xFF8ED1B8),
      accentColor: Color(0xFF6A5ACD),
      inkColor: Colors.white,
      iconColor: Color(0xFFB7ECEA),
    ),
    _ThemePalettePreset(
      name: 'Warm Night',
      mode: 'dark',
      primaryColor: Color(0xFFE8A13D),
      accentColor: Color(0xFFD95555),
      inkColor: Colors.white,
      iconColor: Color(0xFFEFD199),
    ),
  ];

  static const List<Color> _themeColorChoices = [
    Color(0xFF020B12),
    Color(0xFF071A24),
    Color(0xFF123A4A),
    Color(0xFF0B4A45),
    Color(0xFF245A55),
    Color(0xFF3E9189),
    Color(0xFF59BDB3),
    Color(0xFF8ED1B8),
    Color(0xFF2E7DFF),
    Color(0xFF1565C0),
    Color(0xFF6A5ACD),
    Color(0xFF8E44AD),
    Color(0xFFD95555),
    Color(0xFFE8A13D),
    Color(0xFFEFD199),
    Color(0xFFC9B395),
    Color(0xFF90A783),
    Color(0xFF5E6E57),
    Color(0xFF24311F),
    Color(0xFF1F2933),
    Color(0xFF6B7A78),
    Color(0xFFF7F6F1),
    Color(0xFFF8FBF8),
    Colors.white,
  ];

  Future<void> _uploadImageField(
    _ManagedCompany company, {
    required String field,
    required String fileNameField,
    required String updatedAtField,
    required String fallbackFileName,
    required Set<String> uploadingSet,
    required String successLabel,
    bool applyAutoTheme = false,
  }) async {
    if (uploadingSet.contains(company.id)) return;
    if (field == 'loadingImageUrl' && company.loadingVideoUrl.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove the loading video before uploading an image.'),
        ),
      );
      return;
    }

    final pickedImage = await _mediaPicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (pickedImage == null) return;

    setState(() => uploadingSet.add(company.id));
    try {
      final bytes = await pickedImage.readAsBytes();
      final autoTheme =
          applyAutoTheme ? _extractThemePalette(bytes, company.name) : null;
      final url = await ImageStorageService.uploadImageBytes(
        bytes,
        fileName:
            pickedImage.name.isNotEmpty ? pickedImage.name : fallbackFileName,
      );
      if (url == null || url.isEmpty) {
        final details = ImageStorageService.lastError;
        throw Exception(
          details?.isNotEmpty == true ? details : 'Image upload failed.',
        );
      }

      final payload = <String, dynamic>{
        field: url,
        fileNameField:
            pickedImage.name.isNotEmpty ? pickedImage.name : fallbackFileName,
      };
      if (field == 'loadingImageUrl') {
        payload.addAll({
          'clearLoadingVideo': true,
        });
      }
      if (autoTheme != null) {
        payload.addAll(autoTheme.toApiPayload());
      }

      await CompanyApiService.instance.updateCompany(company.id, payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successLabel)),
      );
      _refreshCompanies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => uploadingSet.remove(company.id));
    }
  }

  _AutoThemePalette? _extractThemePalette(Uint8List bytes, String name) {
    final decoded = image_lib.decodeImage(bytes);
    if (decoded == null) return null;

    final width = decoded.width;
    final height = decoded.height;
    if (width == 0 || height == 0) return null;

    final colorCounts = <int, int>{};
    var sampled = 0;
    var totalLuminance = 0.0;
    final stepX = max(1, width ~/ 90);
    final stepY = max(1, height ~/ 160);

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final alpha = pixel.a.toInt();
        if (alpha < 180) continue;

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

    final averageLuminance = totalLuminance / sampled;
    final isDark = averageLuminance < 0.52;
    final tunedPrimary = _boostBrandColor(primary, preferLight: isDark);
    final tunedAccent = _boostBrandColor(accent, preferLight: isDark);
    final background =
        isDark ? _darken(tunedPrimary, 0.82) : _lighten(tunedPrimary, 0.88);
    final surface = isDark ? _darken(tunedAccent, 0.74) : Colors.white;
    final muted =
        isDark ? _lighten(tunedPrimary, 0.52) : _darken(tunedPrimary, 0.35);

    return _AutoThemePalette(
      primaryColor: tunedPrimary,
      accentColor: tunedAccent,
      backgroundColor: background,
      surfaceColor: surface,
      inkColor: isDark ? Colors.white : const Color(0xFF24311F),
      mutedInkColor: muted,
      iconColor:
          isDark ? _lighten(tunedPrimary, 0.42) : _darken(tunedPrimary, 0.38),
      isDark: isDark,
      tagline: name.trim().isEmpty ? '' : '${name.trim()} workspace',
    );
  }

  double _luminance(int r, int g, int b) {
    return ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)) / 255;
  }

  double _hueDistance(Color a, Color b) {
    final hueA = HSVColor.fromColor(a).hue;
    final hueB = HSVColor.fromColor(b).hue;
    final distance = (hueA - hueB).abs();
    return min(distance, 360 - distance);
  }

  double _colorDistance(Color a, Color b) {
    final valueA = a.toARGB32();
    final valueB = b.toARGB32();
    final dr = ((valueA >> 16) & 0xFF) - ((valueB >> 16) & 0xFF);
    final dg = ((valueA >> 8) & 0xFF) - ((valueB >> 8) & 0xFF);
    final db = (valueA & 0xFF) - (valueB & 0xFF);
    return sqrt((dr * dr) + (dg * dg) + (db * db));
  }

  Color _boostBrandColor(Color color, {required bool preferLight}) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation(hsv.saturation.clamp(0.38, 0.92))
        .withValue(preferLight
            ? hsv.value.clamp(0.68, 1.0)
            : hsv.value.clamp(0.48, 0.86))
        .toColor();
  }

  Color _darken(Color color, double amount) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation((hsv.saturation * 0.88).clamp(0.12, 1.0))
        .withValue((hsv.value * (1 - amount)).clamp(0.03, 0.34))
        .toColor();
  }

  Color _lighten(Color color, double amount) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withSaturation(
            (hsv.saturation * (1 - (amount * 0.7))).clamp(0.05, 0.45))
        .withValue((hsv.value + ((1 - hsv.value) * amount)).clamp(0.72, 1.0))
        .toColor();
  }

  Color _readableAccentOn(
    Color background,
    Color accent, {
    required bool isDark,
  }) {
    final contrast = _contrastRatio(background, accent);
    if (contrast >= 3.0) return accent;
    return isDark ? _lighten(accent, 0.42) : _darken(accent, 0.38);
  }

  double _contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a) + 0.05;
    final l2 = _relativeLuminance(b) + 0.05;
    return l1 > l2 ? l1 / l2 : l2 / l1;
  }

  double _relativeLuminance(Color color) {
    double channel(int value) {
      final normalized = value / 255;
      return normalized <= 0.03928
          ? normalized / 12.92
          : pow((normalized + 0.055) / 1.055, 2.4).toDouble();
    }

    final value = color.toARGB32();
    return (0.2126 * channel((value >> 16) & 0xFF)) +
        (0.7152 * channel((value >> 8) & 0xFF)) +
        (0.0722 * channel(value & 0xFF));
  }

  Future<void> _uploadLoadingVideo(_ManagedCompany company) async {
    if (_uploadingVideos.contains(company.id)) return;
    if (company.loadingImageUrl.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove the loading image before uploading a video.'),
        ),
      );
      return;
    }

    final pickedVideo =
        await _mediaPicker.pickVideo(source: ImageSource.gallery);
    if (pickedVideo == null) return;

    setState(() => _uploadingVideos.add(company.id));
    try {
      final fileName = pickedVideo.name.isNotEmpty
          ? pickedVideo.name
          : '${company.code}-loading-video.mp4';
      final url = await ImageStorageService.uploadVideoBytes(
        await pickedVideo.readAsBytes(),
        fileName: fileName,
      );
      if (url == null || url.isEmpty) {
        final details = ImageStorageService.lastError;
        throw Exception(
          details?.isNotEmpty == true ? details : 'Video upload failed.',
        );
      }

      await CompanyApiService.instance.updateCompany(company.id, {
        'loadingVideoUrl': url,
        'loadingVideoFileName': fileName,
        'clearLoadingImage': true,
      });
      _refreshCompanies();
    } finally {
      if (mounted) setState(() => _uploadingVideos.remove(company.id));
    }
  }

  Map<String, dynamic> _clearAutoThemePayload() {
    return {
      'themeEnabled': false,
      'themeSource': null,
      'themePrimaryColor': null,
      'themeAccentColor': null,
      'themeBackgroundColor': null,
      'themeSurfaceColor': null,
      'themeInkColor': null,
      'themeMutedInkColor': null,
      'themeIconColor': null,
      'themeMode': null,
      'tagline': null,
    };
  }

  Future<void> _deleteField(
    _ManagedCompany company,
    List<String> fields,
  ) async {
    final payload = <String, dynamic>{};
    for (final field in fields) {
      payload[field] = null;
    }
    if (fields.contains('loadingImageUrl') && company.themeSource == 'auto') {
      payload.addAll(_clearAutoThemePayload());
    }
    if (fields.contains('loadingImageUrl')) {
      payload['clearLoadingImage'] = true;
    }
    if (fields.contains('loadingVideoUrl')) {
      payload['clearLoadingVideo'] = true;
    }
    await CompanyApiService.instance.updateCompany(company.id, payload);
    _refreshCompanies();
  }

  Future<void> _showRemoveCompanyDialog(_ManagedCompany company) async {
    final companyMembers = await _loadCompanyMembers(company);
    var isRemoving = false;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('Remove ${company.name}?'),
              content: Text(
                companyMembers.isEmpty
                    ? 'This will remove the company code and its setup from admin.'
                    : 'This company has ${companyMembers.length} account(s). Removing it will unassign those users and coaches from ${company.name}.',
              ),
              actions: [
                TextButton(
                  onPressed:
                      isRemoving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB3261E),
                  ),
                  onPressed: isRemoving
                      ? null
                      : () async {
                          setDialogState(() => isRemoving = true);
                          try {
                            await _removeCompany(company, companyMembers);
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${company.name} removed.'),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to remove company: $e'),
                              ),
                            );
                            if (dialogContext.mounted) {
                              setDialogState(() => isRemoving = false);
                            }
                          }
                        },
                  child: isRemoving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Remove'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _removeCompany(
    _ManagedCompany company,
    List<_CompanyMember> members,
  ) async {
    await CompanyApiService.instance.deleteCompany(company.id);
    _refreshCompanies();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(builder: (context) => _buildContent(context)),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surface,
        title: Text(
          'Manage Companies',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Add company',
            onPressed: _showAddCompanyDialog,
            icon: Icon(
              CupertinoIcons.add_circled_solid,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<_ManagedCompany>>(
        stream: _companiesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final companies = snapshot.data ?? [];
          if (companies.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: _showAddCompanyDialog,
                icon: const Icon(CupertinoIcons.add),
                label: const Text('Add Company'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            itemCount: companies.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) => _CompanyManagementCard(
              company: companies[index],
              isUploadingLogo: _uploadingLogos.contains(companies[index].id),
              isUploadingImage: _uploadingImages.contains(companies[index].id),
              isUploadingVideo: _uploadingVideos.contains(companies[index].id),
              onEditName: () => _showEditNameDialog(companies[index]),
              onCopyCode: () => _copyCode(companies[index].code),
              onEditTheme: () => _showThemeDialog(companies[index]),
              onThemeChanged: (enabled) =>
                  _setThemeEnabled(companies[index], enabled),
              onUploadLogo: () => _uploadImageField(
                companies[index],
                field: 'logoUrl',
                fileNameField: 'logoFileName',
                updatedAtField: 'logoUpdatedAt',
                fallbackFileName: '${companies[index].code}-logo.jpg',
                uploadingSet: _uploadingLogos,
                successLabel: 'Logo updated for ${companies[index].name}.',
              ),
              onUploadLoadingImage: () => _uploadImageField(
                companies[index],
                field: 'loadingImageUrl',
                fileNameField: 'loadingImageFileName',
                updatedAtField: 'loadingImageUpdatedAt',
                fallbackFileName: '${companies[index].code}-loading-image.jpg',
                uploadingSet: _uploadingImages,
                successLabel:
                    'Loading image updated for ${companies[index].name}.',
                applyAutoTheme: true,
              ),
              onRemoveLoadingImage: () => _deleteField(
                companies[index],
                [
                  'loadingImageUrl',
                  'loadingImageFileName',
                  'loadingImageUpdatedAt',
                ],
              ),
              onUploadLoadingVideo: () => _uploadLoadingVideo(companies[index]),
              onRemoveLoadingVideo: () => _deleteField(
                companies[index],
                [
                  'loadingVideoUrl',
                  'loadingVideoFileName',
                  'loadingVideoUpdatedAt',
                ],
              ),
              onRemoveCompany: () => _showRemoveCompanyDialog(companies[index]),
              onEditLeaderboardPeriod: () =>
                  _showLeaderboardPeriodDialog(companies[index]),
              membersStream: _companyMembersStream(companies[index]),
            ),
          );
        },
      ),
    );
  }
}

class _AddCompanyDialog extends StatefulWidget {
  const _AddCompanyDialog();

  @override
  State<_AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends State<_AddCompanyDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Company'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Company name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _CompanyManagementCard extends StatelessWidget {
  const _CompanyManagementCard({
    required this.company,
    required this.isUploadingLogo,
    required this.isUploadingImage,
    required this.isUploadingVideo,
    required this.onEditName,
    required this.onCopyCode,
    required this.onEditTheme,
    required this.onThemeChanged,
    required this.onUploadLogo,
    required this.onUploadLoadingImage,
    required this.onRemoveLoadingImage,
    required this.onUploadLoadingVideo,
    required this.onRemoveLoadingVideo,
    required this.onRemoveCompany,
    required this.onEditLeaderboardPeriod,
    required this.membersStream,
  });

  final _ManagedCompany company;
  final bool isUploadingLogo;
  final bool isUploadingImage;
  final bool isUploadingVideo;
  final VoidCallback onEditName;
  final VoidCallback onCopyCode;
  final VoidCallback onEditTheme;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onUploadLogo;
  final VoidCallback onUploadLoadingImage;
  final VoidCallback onRemoveLoadingImage;
  final VoidCallback onUploadLoadingVideo;
  final VoidCallback onRemoveLoadingVideo;
  final VoidCallback onRemoveCompany;
  final VoidCallback onEditLeaderboardPeriod;
  final Stream<List<_CompanyMember>> membersStream;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGencys = isGencysCompany(
      company.name,
      company.code,
    );
    final isIamPlus = isIamPlusCompany(
      company.name,
      company.code,
    );
    final isAbundance12 = isAbundance12Company(
      company.name,
      company.code,
    );
    const fallbackTheme = CompanyThemeData.standard;
    final primaryColor = CompanyThemeService.parseColor(
      company.themePrimaryColor,
      fallbackTheme.primaryColor,
    );
    final accentColor = CompanyThemeService.parseColor(
      company.themeAccentColor,
      fallbackTheme.accentColor,
    );
    final hasLoadingImage = company.loadingImageUrl.isNotEmpty;
    final hasLoadingVideo = company.loadingVideoUrl.isNotEmpty;
    final canUploadLoadingImage = !isUploadingImage && !hasLoadingVideo;
    final canUploadLoadingVideo = !isUploadingVideo && !hasLoadingImage;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: isUploadingLogo ? null : onUploadLogo,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: primaryColor.withValues(alpha: 0.16),
                  backgroundImage: company.logoUrl.isNotEmpty
                      ? NetworkImage(company.logoUrl)
                      : null,
                  child: company.logoUrl.isEmpty
                      ? isUploadingLogo
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Icon(
                              CupertinoIcons.building_2_fill,
                              color: primaryColor,
                            )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      company.code,
                      style: TextStyle(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit name',
                onPressed: onEditName,
                icon: const Icon(CupertinoIcons.pencil),
              ),
              IconButton(
                tooltip: 'Copy code',
                onPressed: onCopyCode,
                icon: const Icon(CupertinoIcons.doc_on_doc),
              ),
              IconButton(
                tooltip: 'Remove company',
                onPressed: onRemoveCompany,
                icon: const Icon(
                  CupertinoIcons.trash,
                  color: Color(0xFFB3261E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ColorDot(color: primaryColor),
              const SizedBox(width: 6),
              _ColorDot(color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  company.tagline.isNotEmpty
                      ? company.tagline
                      : 'No company theme configured yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit theme',
                onPressed: onEditTheme,
                icon: Icon(CupertinoIcons.paintbrush_fill, color: primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: company.themeEnabled,
            activeThumbColor: primaryColor,
            title: const Text(
              'Enable company theme',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle:
                const Text('Controls whether users see company branding.'),
            onChanged: onThemeChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  company.leaderboardPeriodLabel,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit leaderboard period',
                onPressed: onEditLeaderboardPeriod,
                icon: Icon(CupertinoIcons.calendar, color: primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 116,
              width: double.infinity,
              child: hasLoadingImage
                  ? Image.network(
                      company.loadingImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _loadingPreviewFallback(
                          isGencys, isIamPlus, isAbundance12),
                    )
                  : hasLoadingVideo
                      ? _loadingVideoPreview()
                      : _loadingPreviewFallback(
                          isGencys, isIamPlus, isAbundance12),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: isUploadingLogo ? null : onUploadLogo,
                icon: isUploadingLogo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.photo),
                label: const Text('Logo'),
              ),
              OutlinedButton.icon(
                onPressed: canUploadLoadingImage ? onUploadLoadingImage : null,
                icon: isUploadingImage
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.photo_fill),
                label: Text(
                  hasLoadingVideo
                      ? 'Remove video first'
                      : hasLoadingImage
                          ? 'Replace image'
                          : 'Loading image',
                ),
              ),
              if (hasLoadingImage)
                IconButton.outlined(
                  tooltip: 'Remove loading image',
                  onPressed: onRemoveLoadingImage,
                  icon: const Icon(CupertinoIcons.trash),
                ),
              OutlinedButton.icon(
                onPressed: canUploadLoadingVideo ? onUploadLoadingVideo : null,
                icon: isUploadingVideo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.video_camera),
                label: Text(
                  hasLoadingImage
                      ? 'Remove image first'
                      : hasLoadingVideo
                          ? 'Replace video'
                          : 'Loading video',
                ),
              ),
              if (hasLoadingVideo)
                IconButton.outlined(
                  tooltip: 'Remove loading video',
                  onPressed: onRemoveLoadingVideo,
                  icon: const Icon(CupertinoIcons.trash),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _CompanyMembersPanel(membersStream: membersStream),
        ],
      ),
    );
  }

  Widget _loadingVideoPreview() {
    return Container(
      color: const Color(0xFF071A24),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.video_camera_solid,
            color: Colors.white,
            size: 32,
          ),
          SizedBox(height: 8),
          Text(
            'Loading video uploaded',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingPreviewFallback(
    bool isGencys,
    bool isIamPlus,
    bool isAbundance12,
  ) {
    if (isGencys) {
      return Image.asset(
        'assets/images/gencys_loading.png',
        fit: BoxFit.cover,
      );
    }
    if (isIamPlus) {
      return Image.asset(
        'assets/images/iamplus.png',
        fit: BoxFit.cover,
      );
    }
    if (isAbundance12) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/abundance12_loading.jpg',
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.46),
                ],
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'ENTER THE GAME',
                style: TextStyle(
                  color: Color(0xFFEFD199),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      color: const Color(0xFFF2F7F4),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.photo_on_rectangle,
            color: mutedInk,
          ),
          SizedBox(height: 8),
          Text(
            'No loading image uploaded',
            style: TextStyle(
              color: mutedInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyMembersPanel extends StatelessWidget {
  const _CompanyMembersPanel({required this.membersStream});

  final Stream<List<_CompanyMember>> membersStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_CompanyMember>>(
      stream: membersStream,
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final users = members.where((member) => member.isUser).toList();
        final coaches = members.where((member) => member.isCoach).toList();
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FBF9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.person_2_fill,
                    color: ink,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Company members',
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Flexible(
                      child: Text(
                        '${users.length} user${users.length == 1 ? '' : 's'} • '
                        '${coaches.length} coach${coaches.length == 1 ? '' : 'es'}',
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!isLoading && members.isEmpty)
                const Text(
                  'No users have signed up with this company code yet.',
                  style: TextStyle(color: mutedInk),
                )
              else ...[
                if (coaches.isNotEmpty)
                  _MemberGroup(title: 'Coaches', members: coaches),
                if (users.isNotEmpty)
                  _MemberGroup(title: 'Users', members: users),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MemberRoleBadge extends StatelessWidget {
  const _MemberRoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        role,
        style: const TextStyle(
          color: ink,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MemberGroup extends StatelessWidget {
  const _MemberGroup({
    required this.title,
    required this.members,
  });

  final String title;
  final List<_CompanyMember> members;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          ...members.take(4).map((member) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFE8F6F3),
                    child: Text(
                      member.initial,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          member.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: mutedInk,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MemberRoleBadge(role: member.role),
                ],
              ),
            );
          }),
          if (members.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+${members.length - 4} more $title',
                style: const TextStyle(
                  color: mutedInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
    );
  }
}

class _ColorChoiceField extends StatelessWidget {
  const _ColorChoiceField({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              _ColorDot(color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(CupertinoIcons.chevron_down, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteColorButton extends StatelessWidget {
  const _PaletteColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outlineColor =
        selected ? Theme.of(context).colorScheme.primary : Colors.black12;
    final checkColor =
        color.computeLuminance() > 0.55 ? Colors.black : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: outlineColor,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(
                CupertinoIcons.check_mark,
                color: checkColor,
                size: 19,
              )
            : null,
      ),
    );
  }
}

class _PaletteSampleButton extends StatelessWidget {
  const _PaletteSampleButton({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _ThemePalettePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? Theme.of(context).colorScheme.primary : Colors.black12;
    final background =
        preset.mode == 'dark' ? const Color(0xFF071A24) : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ColorDot(color: preset.primaryColor),
                const SizedBox(width: 5),
                _ColorDot(color: preset.accentColor),
                const Spacer(),
                Icon(
                  preset.mode == 'dark'
                      ? CupertinoIcons.moon_stars_fill
                      : CupertinoIcons.sun_max_fill,
                  color: preset.iconColor,
                  size: 15,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: preset.inkColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard({
    required this.companyName,
    required this.companyCode,
    required this.tagline,
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.inkColor,
    required this.mutedInkColor,
    required this.iconColor,
    required this.isDark,
    required this.isEnabled,
    required this.logoUrl,
  });

  final String companyName;
  final String companyCode;
  final String tagline;
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color inkColor;
  final Color mutedInkColor;
  final Color iconColor;
  final bool isDark;
  final bool isEnabled;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final background = isEnabled ? backgroundColor : const Color(0xFFF7F6F1);
    final surface = isEnabled ? surfaceColor : Colors.white;
    final ink = isEnabled ? inkColor : const Color(0xFF24311F);
    final muted = isEnabled ? mutedInkColor : const Color(0xFF5E6E57);
    final previewPrimary = isEnabled ? primaryColor : const Color(0xFF90A783);
    final previewAccent = isEnabled ? accentColor : const Color(0xFFC9B395);
    final previewIcon = isEnabled ? iconColor : const Color(0xFF3E9189);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: previewPrimary.withValues(alpha: isEnabled ? 0.34 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: previewPrimary.withValues(alpha: 0.18),
                backgroundImage:
                    logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                child: logoUrl.isEmpty
                    ? Icon(
                        CupertinoIcons.building_2_fill,
                        color: previewIcon,
                        size: 18,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEnabled ? '$companyName workspace' : 'InnerU dashboard',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEnabled && companyCode.isNotEmpty
                          ? 'Connected through $companyCode'
                          : 'Company theme disabled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: isEnabled && isDark ? 1.1 : 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              gradient: isEnabled
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        previewPrimary.withValues(alpha: isDark ? 0.22 : 0.22),
                        previewAccent.withValues(alpha: isDark ? 0.18 : 0.28),
                        surface,
                      ],
                    )
                  : null,
              border: Border.all(
                color:
                    previewPrimary.withValues(alpha: isEnabled ? 0.22 : 0.12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEnabled ? 'Hello, User' : 'Hello, User',
                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isEnabled
                      ? tagline
                      : 'Your dashboard is ready with the habits that keep today balanced.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    height: 1.3,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PreviewPill(
                      icon: CupertinoIcons.heart_fill,
                      label: 'Mood',
                      color: previewIcon,
                      isDark: isDark && isEnabled,
                    ),
                    const SizedBox(width: 8),
                    _PreviewPill(
                      icon: CupertinoIcons.sparkles,
                      label: 'Focus',
                      color: previewIcon,
                      isDark: isDark && isEnabled,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ColorDot(color: previewPrimary),
              const SizedBox(width: 6),
              Text(
                'Primary',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 14),
              _ColorDot(color: previewAccent),
              const SizedBox(width: 6),
              Text(
                'Accent',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.18 : 0.24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF24311F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagedCompany {
  const _ManagedCompany({
    required this.id,
    required this.name,
    required this.code,
    required this.themeEnabled,
    required this.logoUrl,
    required this.tagline,
    required this.themePrimaryColor,
    required this.themeAccentColor,
    required this.themeInkColor,
    required this.themeIconColor,
    required this.themeSource,
    required this.themeMode,
    required this.loadingImageUrl,
    required this.loadingVideoUrl,
    required this.leaderboardPeriodStart,
    required this.leaderboardPeriodEnd,
  });

  factory _ManagedCompany.fromApi(CompanyApiCompany company) {
    return _ManagedCompany(
      id: company.id,
      name: company.name,
      code: company.code,
      themeEnabled: company.themeEnabled,
      logoUrl: company.logoUrl?.trim() ?? '',
      tagline: company.tagline?.trim() ?? '',
      themePrimaryColor: company.themePrimaryColor?.trim() ?? '',
      themeAccentColor: company.themeAccentColor?.trim() ?? '',
      themeInkColor: company.themeInkColor?.trim() ?? '',
      themeIconColor: company.themeIconColor?.trim() ?? '',
      themeSource: company.themeSource?.trim() ?? '',
      themeMode: company.themeMode?.trim() ?? '',
      loadingImageUrl: company.loadingImageUrl?.trim() ?? '',
      loadingVideoUrl: company.loadingVideoUrl?.trim() ?? '',
      leaderboardPeriodStart: DateTime.tryParse(
        company.leaderboardPeriodStart ?? '',
      ),
      leaderboardPeriodEnd: DateTime.tryParse(
        company.leaderboardPeriodEnd ?? '',
      ),
    );
  }

  final String id;
  final String name;
  final String code;
  final bool themeEnabled;
  final String logoUrl;
  final String tagline;
  final String themePrimaryColor;
  final String themeAccentColor;
  final String themeInkColor;
  final String themeIconColor;
  final String themeSource;
  final String themeMode;
  final String loadingImageUrl;
  final String loadingVideoUrl;
  final DateTime? leaderboardPeriodStart;
  final DateTime? leaderboardPeriodEnd;

  String get leaderboardPeriodLabel {
    final start = leaderboardPeriodStart;
    final end = leaderboardPeriodEnd;
    if (start == null || end == null) {
      return 'Leaderboard period: Not set';
    }
    final formatter = DateFormat('MMM d, yyyy');
    return 'Leaderboard period: ${formatter.format(start)} - '
        '${formatter.format(end)}';
  }
}

class _ThemePalettePreset {
  const _ThemePalettePreset({
    required this.name,
    required this.mode,
    required this.primaryColor,
    required this.accentColor,
    required this.inkColor,
    required this.iconColor,
  });

  final String name;
  final String mode;
  final Color primaryColor;
  final Color accentColor;
  final Color inkColor;
  final Color iconColor;
}

class _ManualThemeColors {
  const _ManualThemeColors({
    required this.mode,
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.inkColor,
    required this.mutedInkColor,
    required this.iconColor,
    required this.isDark,
  });

  final String mode;
  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color inkColor;
  final Color mutedInkColor;
  final Color iconColor;
  final bool isDark;
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

  Map<String, dynamic> toApiPayload() {
    return {
      'themeEnabled': true,
      'themeSource': 'auto',
      'themePrimaryColor': CompanyThemeService.colorToHex(primaryColor),
      'themeAccentColor': CompanyThemeService.colorToHex(accentColor),
      'themeBackgroundColor': CompanyThemeService.colorToHex(backgroundColor),
      'themeSurfaceColor': CompanyThemeService.colorToHex(surfaceColor),
      'themeInkColor': CompanyThemeService.colorToHex(inkColor),
      'themeMutedInkColor': CompanyThemeService.colorToHex(mutedInkColor),
      'themeIconColor': CompanyThemeService.colorToHex(iconColor),
      'themeMode': isDark ? 'dark' : 'light',
      if (tagline.isNotEmpty) 'tagline': tagline,
    };
  }

  Map<String, dynamic> toFirestore() => toApiPayload();
}

class _CompanyMember {
  const _CompanyMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isCoach,
    required this.isAdmin,
    required this.companyId,
    required this.companyCode,
    required this.companyIds,
    required this.companyCodes,
  });

  factory _CompanyMember.fromMap(Map<String, dynamic> data) {
    final name = (data['name'] as String?)?.trim();
    final email = (data['email'] as String?)?.trim();
    final role = (data['role'] as String?)?.trim().toLowerCase();
    final isCoach = data['isCoach'] == true || role == 'coach';
    final isAdmin = data['isAdmin'] == true || role == 'admin';
    final companyId = (data['companyId'] as String?)?.trim();
    final companyCode = (data['companyCode'] as String?)?.trim().toUpperCase();

    return _CompanyMember(
      id: (data['id'] as String?)?.trim() ?? '',
      name: name?.isNotEmpty == true ? name! : 'Unknown User',
      email: email?.isNotEmpty == true ? email! : 'No email',
      role: isCoach
          ? 'coach'
          : isAdmin
              ? 'admin'
              : role?.isNotEmpty == true
                  ? role!
                  : 'user',
      isCoach: isCoach,
      isAdmin: isAdmin,
      companyId: companyId?.isNotEmpty == true ? companyId! : '',
      companyCode: companyCode?.isNotEmpty == true ? companyCode! : '',
      companyIds: const <String>{},
      companyCodes: const <String>{},
    );
  }

  final String id;
  final String name;
  final String email;
  final String role;
  final bool isCoach;
  final bool isAdmin;
  final String companyId;
  final String companyCode;
  final Set<String> companyIds;
  final Set<String> companyCodes;

  bool belongsTo(_ManagedCompany company) {
    return companyId == company.id ||
        companyCode == company.code ||
        companyIds.contains(company.id) ||
        companyCodes.contains(company.code);
  }

  int get roleRank {
    if (isCoach) return 0;
    if (isUser) return 1;
    return 2;
  }

  bool get isUser => !isCoach && !isAdmin;

  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'U';
    return trimmed.substring(0, 1).toUpperCase();
  }
}
