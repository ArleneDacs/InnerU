import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/spotify_native_service.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class Meditation extends StatefulWidget {
  const Meditation({super.key});

  @override
  State<Meditation> createState() => _MeditationState();
}

class _MeditationState extends State<Meditation> with WidgetsBindingObserver {
  static const MethodChannel _feedbackChannel =
      MethodChannel('inneru/meditation_feedback');

  String favoriteSong = "No favorite selected";
  String favoriteSongSource = "default";
  String? favoriteSpotifyTrackId;
  bool _spotifyConnecting = false;
  bool _completionAlertHandled = false;
  bool _completionFlowHandled = false;
  bool _completionDialogVisible = false;
  Timer? _completionAlarmTimer;
  final ImagePicker _memoryPicker = ImagePicker();
  final MeditationStreakService _meditationStreakService =
      MeditationStreakService();
  final DailyTrackerApiService _dailyTrackerApiService =
      DailyTrackerApiService.instance;
  String? playingSong;
  String? favoriteSongPath;

  static const List<String> _completionAffirmations = [
    'You showed up for yourself. Carry this calm into the rest of your day.',
    'Your mind is allowed to rest. You are doing enough.',
    'Breathe gently. You just made space for yourself.',
    'Peace is a practice, and today you practiced.',
    'You are grounded, steady, and ready for what comes next.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleDailyMeditationReminder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _completionAlarmTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadFavorite();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<TimeProvider>().reconcileWithClock();
    }
  }

  Future<void> _scheduleDailyMeditationReminder() async {
    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance.scheduleDailyMeditationReminder();
  }

  Future<void> loadFavorite() async {
    final userId = AuthService.instance.currentSession?.id.toString();
    if (userId == null || userId.isEmpty) return;

    final legacyUsername = await UserPreferences.loadUsername();
    final song = await UserPreferences.loadFavoriteSong(userId) ??
        (legacyUsername == null
            ? null
            : await UserPreferences.loadFavoriteSong(legacyUsername));
    final source = await UserPreferences.loadFavoriteSongSource(userId) ??
        (legacyUsername == null
            ? null
            : await UserPreferences.loadFavoriteSongSource(legacyUsername));
    final spotifyUrl = await UserPreferences.loadFavoriteSpotifyUrl(userId) ??
        (legacyUsername == null
            ? null
            : await UserPreferences.loadFavoriteSpotifyUrl(legacyUsername));
    if (!mounted) return;

    setState(() {
      favoriteSong = song ?? "No favorite selected";
      favoriteSongSource = source ?? "default";
      favoriteSpotifyTrackId = _extractSpotifyTrackId(spotifyUrl);
      favoriteSongPath = _getSongPath(favoriteSong);
      playingSong = AudioHelper.playingSong;
    });
  }

  Future<void> _saveDailyActivity({
    bool meditation = false,
    bool steps = false,
    int? meditationSeconds,
  }) async {
    final userId = AuthService.instance.currentSession?.id.toString();
    if (userId == null) return;

    final userData = await UserService.getUserData();
    final username = userData['username']?.toString() ??
        userData['name']?.toString() ??
        userData['displayName']?.toString();
    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final meditationMinutes = meditationSeconds == null
        ? null
        : (meditationSeconds / Duration.secondsPerMinute).ceil();

    await _dailyTrackerApiService.recordCompletedActivities(
      date: formattedDate,
      meditation: meditation,
      steps: steps,
      meditationMinutes: meditationMinutes,
      username: username,
      companyId: userData['company_id']?.toString() ??
          userData['companyId']?.toString(),
      companyCode: userData['company_code']?.toString() ??
          userData['companyCode']?.toString(),
      companyName: userData['company_name']?.toString() ??
          userData['companyName']?.toString(),
    );
  }

  Future<List<MeditationStreakMilestone>> _onMeditationComplete({
    required int completedSeconds,
  }) async {
    await _saveDailyActivity(
      meditation: true,
      meditationSeconds: completedSeconds,
    );

    final userId = AuthService.instance.currentSession?.id.toString();
    if (userId == null) return <MeditationStreakMilestone>[];

    try {
      final milestones = await _meditationStreakService.recordCompletedSession(
        userId: userId,
      );
      unawaited(_syncMeditationToWatch(userId));
      return milestones;
    } catch (error) {
      debugPrint('Meditation streak update failed: $error');
      return <MeditationStreakMilestone>[];
    }
  }

  Future<void> _syncMeditationToWatch(String userId) async {
    try {
      final data = await UserService.getUserData();
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: data[ActivityStreakService.lastDateFieldFor(
          ActivityStreakType.meditation,
        )],
        currentStreak: ActivityStreakService.readInt(
          data[ActivityStreakService.currentFieldFor(
            ActivityStreakType.meditation,
          )],
        ),
      );
      WatchSyncService.instance.syncMeditation(streak: streak);
    } catch (error) {
      debugPrint('Watch meditation sync failed: $error');
    }
  }

  Future<void> _scheduleMeditationCompletionAlert(
    TimeProvider timeProvider,
  ) async {
    if (timeProvider.remainingTime <= 0) return;

    _completionAlertHandled = false;
    _completionFlowHandled = false;
    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance
        .scheduleMeditationCompleteNotification(
      endsAt: DateTime.now().add(Duration(seconds: timeProvider.remainingTime)),
    );
  }

  Future<void> _cancelMeditationCompletionAlert() async {
    await FastingNotificationService.instance
        .cancelMeditationCompleteNotification();
    await _stopCompletionSpeech();
  }

  Future<void> _handleMeditationCompleteAlert() async {
    if (_completionAlertHandled) return;
    _completionAlertHandled = true;

    await FastingNotificationService.instance
        .cancelMeditationCompleteNotification();
    await FastingNotificationService.instance
        .showMeditationCompleteNotification();
  }

  String get _completionAffirmation {
    final index =
        DateTime.now().millisecondsSinceEpoch % _completionAffirmations.length;
    return _completionAffirmations[index];
  }

  void _playCompletionAlarm() {
    _completionAlarmTimer?.cancel();

    var rings = 0;
    void ring() {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
    }

    ring();
    _completionAlarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      rings += 1;
      if (rings >= 3) {
        timer.cancel();
        if (_completionAlarmTimer == timer) {
          _completionAlarmTimer = null;
        }
        return;
      }
      ring();
    });
  }

  Future<void> _speakCompletionPraise() async {
    try {
      await _feedbackChannel.invokeMethod<void>('speak', {
        'text': 'Meditation done, great job.',
      });
    } catch (error) {
      debugPrint('Meditation completion speech failed: $error');
    }
  }

  Future<void> _stopCompletionSpeech() async {
    try {
      await _feedbackChannel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Meditation completion speech stop failed: $error');
    }
  }

  Future<void> _showMeditationCompleteDialog() async {
    if (_completionDialogVisible || !mounted) return;

    _completionDialogVisible = true;
    final affirmation = _completionAffirmation;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final backgroundColor = colorScheme.surface;
        final borderColor = colorScheme.primary.withValues(alpha: 0.18);
        final titleColor = colorScheme.onSurface;
        final bodyColor = colorScheme.onSurface.withValues(alpha: 0.78);
        final mutedColor = colorScheme.primary;
        final iconCircleColor = colorScheme.primary.withValues(alpha: 0.16);
        final iconColor = colorScheme.primary;
        final primaryButtonColor = colorScheme.primary;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: borderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 28,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 74,
                  width: 74,
                  decoration: BoxDecoration(
                    color: iconCircleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.self_improvement,
                    color: iconColor,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Meditation complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You finished your session. If you want, take a photo and share this calm moment to the community page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  affirmation,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _shareWithMemories,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Take photo & share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: iconColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryButtonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _completionDialogVisible = false;
  }

  Future<void> _showUnlockedRewardDialog(
    MeditationStreakMilestone reward,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.22),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 32,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary,
                      width: 4,
                    ),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: colorScheme.primary,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Reward unlocked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reward.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  reward.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _openStreakRewards();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'View medals',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<ImageSource?> _showMemorySourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final backgroundColor =
            isDark ? const Color(0xFF1B1622) : const Color(0xFFFFFBF7);
        final borderColor =
            isDark ? const Color(0xFF443857) : const Color(0xFFD8C7B9);
        final titleColor =
            isDark ? const Color(0xFFF5EFE9) : const Color(0xFF2B2B2B);
        final iconColor =
            isDark ? const Color(0xFFE1D8D2) : const Color(0xFF6E625B);
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(color: borderColor),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 24,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.photo_camera_rounded, color: iconColor),
                    title: Text(
                      'Take photo',
                      style: TextStyle(color: titleColor),
                    ),
                    onTap: () =>
                        Navigator.pop(sheetContext, ImageSource.camera),
                  ),
                  ListTile(
                    leading:
                        Icon(Icons.photo_library_rounded, color: iconColor),
                    title: Text(
                      'Upload image',
                      style: TextStyle(color: titleColor),
                    ),
                    onTap: () =>
                        Navigator.pop(sheetContext, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareWithMemories() async {
    if (!mounted) return;

    // Close the "Meditation complete" dialog first. Presenting the photo
    // source sheet (and then the native image picker) while this dialog is
    // still on screen can fail to open on iOS, since it isn't dismissed
    // before the next modal tries to present.
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    final source = await _showMemorySourceSheet();
    if (source == null || !mounted) return;

    XFile? image;
    try {
      image = await _memoryPicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );
    } catch (error) {
      debugPrint('Meditation memory picker failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open image picker.')),
      );
      return;
    }

    if (image == null || !mounted) return;

    final memoryNote = Note(
      id: '',
      userId: '',
      username: '',
      title: 'Meditation Moment',
      note: const [
        {
          'type': 'text',
          'value':
              'I completed a meditation session today and wanted to share this calm moment with the community.',
        },
      ],
      createdAt: DateTime.now(),
      category: 'Add Value',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesType(
          note: memoryNote,
          initialImage: image,
          initialCategory: 'Add Value',
          openCommunityAfterPost: true,
        ),
      ),
    );
  }

  Future<void> _handleMeditationFinished(TimeProvider timeProvider) async {
    if (_completionFlowHandled) return;
    _completionFlowHandled = true;
    final completedSeconds = timeProvider.initialTime;

    timeProvider.stopTimer();
    await AudioHelper.stopAudio();
    await _stopSpotifyPlayer();
    _playCompletionAlarm();
    unawaited(_speakCompletionPraise());
    final completionFuture =
        _onMeditationComplete(completedSeconds: completedSeconds);
    await _handleMeditationCompleteAlert();

    if (!mounted) return;
    await _showMeditationCompleteDialog();
    final unlockedRewards = await completionFuture;
    if (unlockedRewards.isNotEmpty) {
      await _showUnlockedRewardDialog(unlockedRewards.last);
    }
  }

  String? _getSongPath(String songTitle) {
    const songMap = {
      "Under the Shining Sun": "audio/Forest_Birds.mp3",
      "Call of the Waves": "audio/Ocean_Waves.mp3",
      "It's Raining Gently": "audio/Rain_Sounds.mp3",
      "Beside the Fireplace": "audio/Night_Firepit.mp3",
    };
    return songMap[songTitle];
  }

  String? _extractSpotifyTrackId(String? spotifyUrl) {
    final uri = Uri.tryParse(spotifyUrl ?? '');
    if (uri == null) return null;

    if (uri.scheme == 'spotify') {
      final parts = uri.path.split(':');
      if (parts.length >= 2 && parts.first == 'track') {
        return parts[1];
      }
    }

    final segments = uri.pathSegments;
    final trackIndex = segments.indexOf('track');
    if (trackIndex == -1 || trackIndex + 1 >= segments.length) {
      return null;
    }

    return segments[trackIndex + 1].split('?').first;
  }

  Future<void> _pauseSpotifyPlayer() async {
    try {
      await SpotifyNativeService.instance.pause();
    } catch (error) {
      debugPrint('Spotify pause failed: $error');
    }
    if (!mounted) return;
    setState(() {
      playingSong = null;
    });
  }

  Future<void> _stopSpotifyPlayer() async {
    try {
      await SpotifyNativeService.instance.stop();
    } catch (error) {
      debugPrint('Spotify stop failed: $error');
    }
    if (!mounted) return;
    setState(() {
      playingSong = null;
    });
  }

  Future<void> _showSpotifyConnectionDialog(Object error) async {
    if (!mounted) return;

    final spotifyError = error is SpotifyNativeException ? error : null;
    final reason = spotifyError?.reason;

    final title = switch (reason) {
      SpotifyNativeFailureReason.appNotInstalled => 'Spotify Required',
      SpotifyNativeFailureReason.notLoggedIn => 'Log In To Spotify',
      SpotifyNativeFailureReason.offlineMode => 'Spotify Is Offline',
      SpotifyNativeFailureReason.unsupportedVersion => 'Update Spotify',
      _ => 'Spotify Permission Needed',
    };

    final message = switch (reason) {
      SpotifyNativeFailureReason.appNotInstalled =>
        'Install the Spotify app, log in, then come back to InnerU.',
      SpotifyNativeFailureReason.notLoggedIn =>
        'Open Spotify and log in. After that, return to InnerU and tap play again.',
      SpotifyNativeFailureReason.offlineMode =>
        'Turn off Offline Mode in Spotify, then come back to InnerU and tap play again.',
      SpotifyNativeFailureReason.unsupportedVersion =>
        'Update Spotify from the Play Store, then come back to InnerU.',
      SpotifyNativeFailureReason.authenticationFailed =>
        'Spotify could not authorize InnerU. Tap play again and approve InnerU if Spotify asks.',
      _ =>
        'Spotify needs permission before InnerU can control playback. Tap play again, approve InnerU in Spotify if asked, then return here.',
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String? _spotifyUriFromTrackId(String? trackId) {
    final trimmed = trackId?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return 'spotify:track:$trimmed';
  }

  Future<void> _handleMeditationPlay(TimeProvider timeProvider) async {
    if (favoriteSongSource == "spotify" &&
        favoriteSong != "No favorite selected") {
      if (timeProvider.isRunning) {
        timeProvider.pauseTimer();
        await _pauseSpotifyPlayer();
        await _cancelMeditationCompletionAlert();
      } else {
        final trackUri = _spotifyUriFromTrackId(favoriteSpotifyTrackId);
        if (trackUri == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This Spotify track is missing a valid track ID. Please choose another Spotify song.',
              ),
            ),
          );
          return;
        }

        if (mounted) {
          setState(() {
            _spotifyConnecting = true;
          });
        }

        try {
          await _scheduleMeditationCompletionAlert(timeProvider);
          await SpotifyNativeService.instance.playTrack(trackUri);
          timeProvider.startTimer(
            onComplete: () => _handleMeditationFinished(timeProvider),
          );
          if (!mounted) return;
          setState(() {
            playingSong = favoriteSong;
          });
        } catch (error) {
          await _cancelMeditationCompletionAlert();
          if (!mounted) return;
          debugPrint('Spotify meditation playback failed: $error');
          setState(() {
            _spotifyConnecting = false;
          });
          await _showSpotifyConnectionDialog(error);
        } finally {
          if (mounted) {
            setState(() {
              _spotifyConnecting = false;
            });
          }
        }
      }
      return;
    }

    if (favoriteSongPath != null) {
      AudioHelper.togglePlayPause(
        favoriteSong,
        favoriteSongPath!,
        (newPlayingSong) {
          if (!mounted) return;
          setState(() {
            playingSong = newPlayingSong;
          });
        },
      );
    }

    if (timeProvider.isRunning) {
      timeProvider.pauseTimer();
      await _cancelMeditationCompletionAlert();
    } else {
      await _scheduleMeditationCompletionAlert(timeProvider);
      timeProvider.startTimer(
        onComplete: () => _handleMeditationFinished(timeProvider),
      );
    }
  }

  Future<void> _openMusicSelector() async {
    final selectedSong = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationSong(),
      ),
    );

    if (selectedSong is! Map) return;

    final selectedTitle = (selectedSong['title'] as String?)?.trim();
    final selectedSource = (selectedSong['source'] as String?)?.trim();
    final selectedSpotifyUrl = (selectedSong['spotifyUrl'] as String?)?.trim();
    if (selectedTitle == null || selectedTitle.isEmpty) {
      return;
    }

    await AudioHelper.stopAudio();
    await _stopSpotifyPlayer();
    if (!mounted) return;

    setState(() {
      favoriteSong = selectedTitle;
      favoriteSongSource = selectedSource == "spotify" ? "spotify" : "default";
      favoriteSpotifyTrackId = _extractSpotifyTrackId(selectedSpotifyUrl);
      favoriteSongPath = _getSongPath(selectedTitle);
      playingSong = null;
    });
  }

  void _openStreakRewards() {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationStreakRewardsScreen(),
      ),
    );
  }

  void _showTimePicker(BuildContext context, TimeProvider timeProvider) {
    final pageTheme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: pageTheme.colorScheme.surface,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return CupertinoTheme(
          data: CupertinoTheme.of(context).copyWith(
            brightness: theme.brightness,
            scaffoldBackgroundColor: colorScheme.surface,
            textTheme: CupertinoTextThemeData(
              pickerTextStyle: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 21,
              ),
            ),
          ),
          child: SizedBox(
            height: 300,
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hms,
              initialTimerDuration:
                  Duration(seconds: timeProvider.remainingTime),
              onTimerDurationChanged: (Duration newDuration) {
                if (newDuration.inSeconds > 0) {
                  timeProvider.setTime(newDuration.inSeconds);
                }
              },
            ),
          ),
        );
      },
    );
  }

  String _formatTime(int totalSecond) {
    final hours = totalSecond ~/ 3600;
    final minutes = (totalSecond % 3600) ~/ 60;
    final seconds = totalSecond % 60;
    return "${hours.toString().padLeft(2, "0")}:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final timeProvider = Provider.of<TimeProvider>(context);
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final colorScheme = theme.colorScheme;
              final isDark = theme.brightness == Brightness.dark;

              return Scaffold(
                backgroundColor: companyTheme.backgroundColor,
                body: SafeArea(
                  child: Stack(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isLandscape =
                              constraints.maxWidth > constraints.maxHeight;
                          final isShort =
                              constraints.maxHeight < 520 || isLandscape;
                          final animationHeight = isShort
                              ? (constraints.maxHeight * 0.28)
                                  .clamp(110.0, 170.0)
                              : 300.0;
                          final timerFontSize = isShort ? 42.0 : 55.0;
                          final topPadding = isShort ? 8.0 : 24.0;

                          return SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              topPadding,
                              20,
                              MediaQuery.paddingOf(context).bottom + 28,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    (constraints.maxHeight - topPadding - 28)
                                        .clamp(0.0, double.infinity),
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 560),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Lottie.asset(
                                        "assets/images/lottie_meditation.json",
                                        height: animationHeight,
                                      ),
                                      SizedBox(height: isShort ? 4 : 10),
                                      Builder(builder: (context) {
                                        // A session is in progress once time
                                        // has been spent from the picked
                                        // duration, whether currently
                                        // counting down or paused -- only a
                                        // full Stop (which resets remaining
                                        // back to initial) or a natural
                                        // finish (which calls stopTimer())
                                        // should re-enable the picker.
                                        final sessionInProgress =
                                            timeProvider.isRunning ||
                                                timeProvider.remainingTime <
                                                    timeProvider.initialTime;
                                        return GestureDetector(
                                          onTap: sessionInProgress
                                              ? null
                                              : () => _showTimePicker(
                                                  context, timeProvider),
                                          child: Opacity(
                                            opacity:
                                                sessionInProgress ? 0.6 : 1,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _formatTime(timeProvider
                                                      .remainingTime),
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: timerFontSize,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFF3EFE9)
                                                        : const Color(
                                                            0xFF2E2A27),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  sessionInProgress
                                                      ? 'Stop meditation to change minutes'
                                                      : 'Tap to set meditation minutes',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFB9B1A7)
                                                        : const Color(
                                                            0xFF8B8179),
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                      SizedBox(height: isShort ? 4 : 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            onPressed: _spotifyConnecting
                                                ? null
                                                : () => _handleMeditationPlay(
                                                    timeProvider),
                                            icon: Icon(
                                              timeProvider.isRunning
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: const Color(0xFFCE8F5A),
                                              size: 40,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              _completionAlarmTimer?.cancel();
                                              _completionFlowHandled = true;
                                              timeProvider.stopTimer();
                                              AudioHelper.stopAudio();
                                              _stopSpotifyPlayer();
                                              _cancelMeditationCompletionAlert();
                                              _stopCompletionSpeech();
                                              setState(() {
                                                playingSong = null;
                                              });
                                            },
                                            icon: const Icon(
                                              Icons.stop,
                                              color: Color(0xFFCE8F5A),
                                              size: 40,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        width: double.infinity,
                                        margin: EdgeInsets.only(
                                            top: isShort ? 2 : 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? colorScheme.surface
                                              : const Color(0xFFFFFBF7),
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: isDark
                                                ? companyTheme.iconColor
                                                    .withValues(alpha: 0.34)
                                                : const Color(0xFFE9DED5),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.music_note,
                                              size: 20,
                                              color: companyTheme.iconColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: _openMusicSelector,
                                                child: Text(
                                                  '$favoriteSong (${favoriteSongSource == "spotify" ? "Spotify" : "Default"})',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.25,
                                                    color:
                                                        companyTheme.inkColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: null,
                                              tooltip: favoriteSongSource ==
                                                      "spotify"
                                                  ? 'Native Spotify playback is active for this track'
                                                  : 'Open on Spotify',
                                              icon: Icon(
                                                Icons.open_in_new,
                                                color:
                                                    companyTheme.mutedInkColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (favoriteSongSource == "spotify" &&
                                          _spotifyConnecting)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(
                                            'Connecting...',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        top: 2,
                        right: 10,
                        child: IconButton(
                          onPressed: _openStreakRewards,
                          icon: const Icon(Icons.workspace_premium_rounded),
                          tooltip: 'Rewards',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
