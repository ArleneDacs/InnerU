import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';

class ExerciseTrackerScreen extends StatefulWidget {
  const ExerciseTrackerScreen({super.key});

  @override
  State<ExerciseTrackerScreen> createState() => _ExerciseTrackerScreenState();
}

class _ExerciseTrackerScreenState extends State<ExerciseTrackerScreen> {
  static const List<String> _exerciseTypes = [
    'Pilates',
    'Exercise',
    'Gym',
    'Strength',
    'Yoga',
    'Cycling',
    'Swimming',
    'Dance',
    'HIIT',
    'Stretching',
    'Sports',
    'Other',
  ];

  final ActivityStreakService _activityStreakService = ActivityStreakService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _customTypeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ExerciseApiService _exerciseApi = ExerciseApiService.instance;

  String _selectedType = _exerciseTypes.first;
  int _durationMinutes = 30;
  int _intensity = 2;
  String? _startPhotoUrl;
  String? _endPhotoUrl;
  bool _isUploadingStartPhoto = false;
  bool _isUploadingEndPhoto = false;
  bool _isSaving = false;
  bool _isLoadingLogs = true;
  List<Map<String, dynamic>> _todayLogs = [];

  String get _todayDate => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void dispose() {
    _customTypeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTodayLogs();
  }

  Future<void> _loadTodayLogs() async {
    try {
      final logs = await _exerciseApi.fetchToday();
      if (!mounted) return;
      setState(() {
        _todayLogs = logs;
      });
    } catch (error) {
      debugPrint('Failed to load exercise logs: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLogs = false;
        });
      }
    }
  }

  String _effectiveType() {
    final custom = _customTypeController.text.trim();
    if (_selectedType == 'Other' && custom.isNotEmpty) return custom;
    return _selectedType;
  }

  Future<void> _pickExercisePhoto({required bool isStart}) async {
    if (_isSaving || _isUploadingStartPhoto || _isUploadingEndPhoto) return;

    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (pickedImage == null) return;

    setState(() {
      if (isStart) {
        _isUploadingStartPhoto = true;
      } else {
        _isUploadingEndPhoto = true;
      }
    });

    try {
      final imageUrl = await ImageStorageService.uploadImageFile(
        File(pickedImage.path),
      );
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception(
          ImageStorageService.lastError ?? 'Failed to upload image.',
        );
      }

      if (!mounted) return;
      setState(() {
        if (isStart) {
          _startPhotoUrl = imageUrl;
        } else {
          _endPhotoUrl = imageUrl;
        }
      });
    } catch (error) {
      if (mounted) {
        _showMessage('Could not upload exercise photo. Please try again.');
      }
      debugPrint('Exercise photo upload failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          if (isStart) {
            _isUploadingStartPhoto = false;
          } else {
            _isUploadingEndPhoto = false;
          }
        });
      }
    }
  }

  Future<void> _saveExercise() async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSaving) return;

    final type = _effectiveType();
    if (type.trim().isEmpty) {
      _showMessage('Enter an exercise type.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _exerciseApi.store(
        type: type,
        durationMinutes: _durationMinutes,
        intensity: _intensity,
        notes: _notesController.text.trim(),
        startPhotoUrl: _startPhotoUrl,
        endPhotoUrl: _endPhotoUrl,
        date: _todayDate,
      );
      await _loadTodayLogs();
      final unlockedRewards = await _recordExerciseStreak(session.id.toString());

      if (!mounted) return;
      setState(() {
        _selectedType = _exerciseTypes.first;
        _durationMinutes = 30;
        _intensity = 2;
        _customTypeController.clear();
        _notesController.clear();
        _startPhotoUrl = null;
        _endPhotoUrl = null;
      });
      _showMessage(
        unlockedRewards.isEmpty
            ? 'Exercise logged.'
            : 'Exercise medal unlocked: ${unlockedRewards.last.title}',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not save exercise. Please try again.');
      debugPrint('Exercise save failed: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteExercise(String logId) async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    try {
      await _exerciseApi.delete(logId);
      await _loadTodayLogs();
      if (!mounted) return;
      _showMessage('Exercise removed.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not remove exercise.');
      debugPrint('Exercise delete failed: $error');
    }
  }

  Future<List<ActivityStreakMilestone>> _recordExerciseStreak(
    String userId,
  ) async {
    try {
      return await _activityStreakService.recordCompletedSession(
        userId: userId,
        type: ActivityStreakType.exercise,
      );
    } catch (error) {
      debugPrint('Exercise streak update failed: $error');
      return <ActivityStreakMilestone>[];
    }
  }

  void _openExerciseRewards() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationStreakRewardsScreen(
          activityType: ActivityStreakType.exercise,
        ),
      ),
    );
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.currentSession;
    return CompanyThemeBuilder(
      builder: (context, theme) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            backgroundColor: theme.isDark ? theme.surfaceColor : Colors.white,
            foregroundColor: theme.isDark ? theme.inkColor : null,
            surfaceTintColor: Colors.transparent,
            title: const Text('Exercise'),
            actions: [
              IconButton(
                onPressed: _openExerciseRewards,
                icon: const Icon(Icons.workspace_premium_rounded),
                tooltip: 'Rewards',
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: session == null
              ? Center(
                  child: Text(
                    'Sign in to log exercise.',
                    style: TextStyle(color: theme.inkColor),
                  ),
                )
              : _isLoadingLogs
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      children: [
                        _buildSummary(theme, _todayLogs),
                        const SizedBox(height: 16),
                        _buildLogger(theme),
                        const SizedBox(height: 18),
                        _buildTodayLogs(theme, _todayLogs),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildSummary(
    CompanyThemeData theme,
    List<Map<String, dynamic>> logs,
  ) {
    final totalMinutes = logs.fold<int>(
      0,
      (total, doc) => total + _readInt(doc['durationMinutes']),
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/exercise.gif',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.22),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.26),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.flame_fill,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's exercise",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${logs.length} session${logs.length == 1 ? '' : 's'} - $totalMinutes min',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pilates, gym, yoga, sports, and custom exercise all count.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogger(CompanyThemeData theme) {
    final photoButtonsDisabled =
        _isSaving || _isUploadingStartPhoto || _isUploadingEndPhoto;
    return _ThemedPanel(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log activity',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            isExpanded: true,
            dropdownColor: theme.surfaceColor,
            decoration: _inputDecoration(
              theme,
              label: 'Activity type',
              hint: 'Choose the kind of exercise',
            ),
            items: _exerciseTypes
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedType = value;
                      if (value != 'Other') {
                        _customTypeController.clear();
                      }
                    });
                  },
          ),
          if (_selectedType == 'Other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customTypeController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: theme.inkColor),
              decoration: _inputDecoration(
                theme,
                label: 'Exercise type',
                hint: 'Example: Boxing, barre, tennis',
              ),
            ),
          ],
          const SizedBox(height: 18),
          _buildPhotoSection(
            theme: theme,
            title: 'Start photo',
            subtitle: 'Capture the moment you begin your workout.',
            imageUrl: _startPhotoUrl,
            isUploading: _isUploadingStartPhoto,
            onCapture: photoButtonsDisabled
                ? null
                : () => _pickExercisePhoto(isStart: true),
          ),
          const SizedBox(height: 14),
          _buildPhotoSection(
            theme: theme,
            title: 'End photo',
            subtitle: 'Capture the moment you finish your workout.',
            imageUrl: _endPhotoUrl,
            isUploading: _isUploadingEndPhoto,
            onCapture: photoButtonsDisabled
                ? null
                : () => _pickExercisePhoto(isStart: false),
          ),
          const SizedBox(height: 18),
          _buildDurationControl(theme),
          const SizedBox(height: 16),
          _buildIntensityControl(theme),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            enabled: !_isSaving,
            maxLines: 3,
            style: TextStyle(color: theme.inkColor),
            decoration: _inputDecoration(
              theme,
              label: 'Notes',
              hint: 'What did you work on?',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: photoButtonsDisabled ? null : _saveExercise,
              icon: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.checkmark_circle_fill),
              label: Text(_isSaving ? 'Saving...' : 'Log exercise'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor:
                    theme.isDark ? theme.backgroundColor : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection({
    required CompanyThemeData theme,
    required String title,
    required String subtitle,
    required String? imageUrl,
    required bool isUploading,
    required VoidCallback? onCapture,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.inkColor,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: theme.mutedInkColor,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: onCapture,
              icon: isUploading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.camera_fill),
              label: Text(isUploading ? 'Uploading...' : 'Capture'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor:
                    theme.isDark ? theme.backgroundColor : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            if (imageUrl != null && imageUrl.isNotEmpty)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    imageUrl,
                    height: 68,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Expanded(
                child: Text(
                  'No photo yet.',
                  style: TextStyle(color: theme.mutedInkColor),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDurationControl(CompanyThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controlLabel(theme, 'Duration'),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _durationMinutes <= 5 || _isSaving
                  ? null
                  : () => setState(() => _durationMinutes -= 5),
              icon: const Icon(CupertinoIcons.minus),
            ),
            Expanded(
              child: Slider(
                value: _durationMinutes.toDouble(),
                min: 5,
                max: 180,
                divisions: 35,
                activeColor: theme.primaryColor,
                label: '$_durationMinutes min',
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _durationMinutes =
                              ((value / 5).round() * 5).clamp(5, 180).toInt();
                        });
                      },
              ),
            ),
            IconButton.filledTonal(
              onPressed: _durationMinutes >= 180 || _isSaving
                  ? null
                  : () => setState(() => _durationMinutes += 5),
              icon: const Icon(CupertinoIcons.plus),
            ),
            SizedBox(
              width: 72,
              child: Text(
                '$_durationMinutes min',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: theme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIntensityControl(CompanyThemeData theme) {
    final labels = ['Easy', 'Moderate', 'Hard'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controlLabel(theme, 'Intensity'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < labels.length; i++)
              ButtonSegment<int>(
                value: i + 1,
                label: Text(labels[i]),
                icon: Icon(
                  i == 0
                      ? CupertinoIcons.wind
                      : i == 1
                          ? CupertinoIcons.flame
                          : CupertinoIcons.bolt_fill,
                ),
              ),
          ],
          selected: {_intensity},
          onSelectionChanged: _isSaving
              ? null
              : (values) => setState(() => _intensity = values.first),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? theme.primaryColor
                  : theme.inkColor;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayLogs(
    CompanyThemeData theme,
    List<Map<String, dynamic>> logs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Logged today',
          style: TextStyle(
            color: theme.inkColor,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (logs.isEmpty)
          _ThemedPanel(
            theme: theme,
            child: Text(
              'No exercise logged yet. Add pilates, gym, yoga, sports, or any custom movement.',
              style: TextStyle(color: theme.mutedInkColor, height: 1.4),
            ),
          )
        else
          ...logs.map((doc) {
            final data = doc;
            return _ExerciseLogTile(
              theme: theme,
              title: (data['type'] as String?)?.trim() ?? 'Exercise',
              minutes: _readInt(data['durationMinutes']),
              intensity: _readInt(data['intensity']),
              notes: (data['notes'] as String?)?.trim() ?? '',
              startPhotoUrl: (data['startPhotoUrl'] as String?)?.trim(),
              endPhotoUrl: (data['endPhotoUrl'] as String?)?.trim(),
              onDelete: () => _deleteExercise((data['id'] as String?) ?? ''),
            );
          }),
      ],
    );
  }

  Widget _controlLabel(CompanyThemeData theme, String label) {
    return Text(
      label,
      style: TextStyle(
        color: theme.inkColor,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  InputDecoration _inputDecoration(
    CompanyThemeData theme, {
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: theme.mutedInkColor),
      hintStyle: TextStyle(color: theme.mutedInkColor.withValues(alpha: 0.7)),
      filled: true,
      fillColor: theme.isDark
          ? theme.backgroundColor.withValues(alpha: 0.72)
          : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: theme.mutedInkColor.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: theme.mutedInkColor.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
      ),
    );
  }
}

class _ThemedPanel extends StatelessWidget {
  const _ThemedPanel({
    required this.theme,
    required this.child,
  });

  final CompanyThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.isDark
              ? theme.primaryColor.withValues(alpha: 0.18)
              : theme.mutedInkColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.theme,
    required this.icon,
  });

  final CompanyThemeData theme;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: theme.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: theme.primaryColor),
    );
  }
}

class _ExerciseLogTile extends StatelessWidget {
  const _ExerciseLogTile({
    required this.theme,
    required this.title,
    required this.minutes,
    required this.intensity,
    required this.notes,
    required this.startPhotoUrl,
    required this.endPhotoUrl,
    required this.onDelete,
  });

  final CompanyThemeData theme;
  final String title;
  final int minutes;
  final int intensity;
  final String notes;
  final String? startPhotoUrl;
  final String? endPhotoUrl;
  final VoidCallback onDelete;

  String get _intensityLabel {
    switch (intensity) {
      case 1:
        return 'Easy';
      case 3:
        return 'Hard';
      default:
        return 'Moderate';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _ThemedPanel(
        theme: theme,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBadge(theme: theme, icon: CupertinoIcons.checkmark_alt_circle),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$minutes min - $_intensityLabel',
                    style: TextStyle(
                      color: theme.mutedInkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notes,
                      style: TextStyle(
                        color: theme.mutedInkColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if ((startPhotoUrl?.isNotEmpty ?? false) ||
                      (endPhotoUrl?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (startPhotoUrl?.isNotEmpty ?? false)
                          Expanded(
                            child: _LogPhotoPreview(
                              theme: theme,
                              label: 'Start',
                              imageUrl: startPhotoUrl!,
                            ),
                          ),
                        if ((startPhotoUrl?.isNotEmpty ?? false) &&
                            (endPhotoUrl?.isNotEmpty ?? false))
                          const SizedBox(width: 8),
                        if (endPhotoUrl?.isNotEmpty ?? false)
                          Expanded(
                            child: _LogPhotoPreview(
                              theme: theme,
                              label: 'End',
                              imageUrl: endPhotoUrl!,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove exercise',
              onPressed: onDelete,
              icon: Icon(CupertinoIcons.trash, color: theme.mutedInkColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogPhotoPreview extends StatelessWidget {
  const _LogPhotoPreview({
    required this.theme,
    required this.label,
    required this.imageUrl,
  });

  final CompanyThemeData theme;
  final String label;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.mutedInkColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            imageUrl,
            height: 72,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}
