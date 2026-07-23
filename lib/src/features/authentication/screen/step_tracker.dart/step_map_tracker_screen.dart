import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/admin_user_api_service.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/step_map_api_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';

class _StepMapTrackingController extends ChangeNotifier {
  static const LatLng _defaultCenter = LatLng(1.3521, 103.8198);
  static const int _maxSharedRoutePoints = 500;
  static const double _minMovementMeters = 3;
  static const double _maxReasonableAccuracyMeters = 35;
  static const double _maxJumpDistanceMeters = 120;
  static const double _maxWalkingSpeedMetersPerSecond = 3.2;
  static const double _minStreetSnapDistanceMeters = 8;

  static final _StepMapTrackingController instance =
      _StepMapTrackingController._();

  _StepMapTrackingController._();

  final StepMapApiService _api = StepMapApiService.instance;
  final Distance _distance = const Distance();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<StepCount>? _stepSubscription;
  Timer? _elapsedTimer;
  int _trackingGeneration = 0;

  List<LatLng> routePoints = [];
  Position? currentPosition;
  DateTime? startedAt;
  Duration elapsed = Duration.zero;
  int? stepBaseline;
  int lastRawSessionSteps = 0;
  int sessionSteps = 0;
  double distanceMeters = 0;
  bool isTracking = false;
  bool isPreparing = false;
  String statusText = 'Tap start to track your walk on the map.';
  bool _isProcessingPositionUpdate = false;
  Position? _queuedPositionUpdate;
  int? _queuedPositionUpdateGeneration;
  int _consecutiveSpikeRejections = 0;
  String? currentUserId;
  String currentUsername = 'Walker';
  String? activeSessionId;
  int _lastNotificationElapsedSeconds = -1;

  // iOS exposes motion access as sensors, while Android uses activity recognition.
  Permission get _stepPermission =>
      Platform.isIOS ? Permission.sensors : Permission.activityRecognition;

  LatLng get defaultCenter => _defaultCenter;
  int get elapsedSeconds => elapsed.inSeconds;

  void updateUser({
    required String? userId,
    required String username,
  }) {
    currentUserId = userId;
    currentUsername = username;
  }

  void updateActiveSession(String? sessionId) {
    activeSessionId = sessionId;
  }

  bool _isFiniteCoordinate(double value) => value.isFinite;

  bool _isValidLatitude(double value) =>
      _isFiniteCoordinate(value) && value >= -90 && value <= 90;

  bool _isValidLongitude(double value) =>
      _isFiniteCoordinate(value) && value >= -180 && value <= 180;

  LatLng? safeLatLng(double latitude, double longitude) {
    if (!_isValidLatitude(latitude) || !_isValidLongitude(longitude)) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  LatLng? positionToLatLng(Position position) {
    return safeLatLng(position.latitude, position.longitude);
  }

  List<Map<String, double>> serializeRoutePoints(List<LatLng> points) {
    final start = math.max(0, points.length - _maxSharedRoutePoints);
    return points
        .sublist(start)
        .map((point) => {
              'latitude': point.latitude,
              'longitude': point.longitude,
            })
        .toList();
  }

  double _routeDistance(List<LatLng> points) {
    if (points.length < 2) return 0;

    var total = 0.0;
    for (var index = 1; index < points.length; index++) {
      total += _distance(points[index - 1], points[index]);
    }
    return total;
  }

  List<LatLng> _mergeSegmentIntoRoute(
    List<LatLng> existingRoutePoints,
    List<LatLng> segmentPoints,
  ) {
    if (segmentPoints.isEmpty) return existingRoutePoints;
    if (existingRoutePoints.isEmpty) return List<LatLng>.from(segmentPoints);

    final merged = List<LatLng>.from(existingRoutePoints);
    final shouldSkipFirstPoint =
        _distance(merged.last, segmentPoints.first) < 1.5;

    merged.addAll(
      shouldSkipFirstPoint ? segmentPoints.skip(1) : segmentPoints,
    );
    return merged;
  }

  Future<List<LatLng>> _buildStreetAlignedSegment(
    LatLng startPoint,
    LatLng endPoint,
  ) async {
    final directDistance = _distance(startPoint, endPoint);
    if (directDistance < _minStreetSnapDistanceMeters) {
      return [startPoint, endPoint];
    }

    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/foot/'
          '${startPoint.longitude.toStringAsFixed(6)},${startPoint.latitude.toStringAsFixed(6)};'
          '${endPoint.longitude.toStringAsFixed(6)},${endPoint.latitude.toStringAsFixed(6)}',
      const {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'selfcare_projects_step_map_tracker/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        return [startPoint, endPoint];
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic> || payload['code'] != 'Ok') {
        return [startPoint, endPoint];
      }

      final routes = payload['routes'];
      if (routes is! List || routes.isEmpty) {
        return [startPoint, endPoint];
      }

      final geometry = (routes.first as Map<String, dynamic>)['geometry'];
      final coordinates =
          geometry is Map<String, dynamic> ? geometry['coordinates'] : null;
      if (coordinates is! List || coordinates.length < 2) {
        return [startPoint, endPoint];
      }

      final snappedPoints = <LatLng>[];
      for (final coordinate in coordinates) {
        if (coordinate is List && coordinate.length >= 2) {
          final longitude = (coordinate[0] as num?)?.toDouble();
          final latitude = (coordinate[1] as num?)?.toDouble();
          if (latitude != null && longitude != null) {
            final point = safeLatLng(latitude, longitude);
            if (point != null) {
              snappedPoints.add(point);
            }
          }
        }
      }

      if (snappedPoints.length < 2) {
        return [startPoint, endPoint];
      }

      final snappedDistance = _routeDistance(snappedPoints);
      if (snappedDistance <= 0 || snappedDistance > directDistance * 3.5 + 30) {
        return [startPoint, endPoint];
      }

      return snappedPoints;
    } catch (_) {
      return [startPoint, endPoint];
    }
  }

  bool _isLikelyGpsSpike(
    Position position,
    double segmentDistance,
  ) {
    if (segmentDistance > _maxJumpDistanceMeters) {
      return true;
    }

    final measuredSpeed =
        position.speed.isFinite && position.speed > 0 ? position.speed : null;
    if (measuredSpeed != null &&
        measuredSpeed > _maxWalkingSpeedMetersPerSecond &&
        segmentDistance > 25) {
      return true;
    }

    if (position.accuracy > _maxReasonableAccuracyMeters &&
        segmentDistance > 20) {
      return true;
    }

    return false;
  }

  void _emit() {
    notifyListeners();
  }

  Future<void> loadInitialMapPreview() async {
    if (isTracking || currentPosition != null) return;

    try {
      final hasLocationAccess =
          await _ensureLocationAccess(openSettings: false);
      if (!hasLocationAccess) return;

      final previewPosition = await _getInitialPosition();
      final previewPoint =
          previewPosition == null ? null : positionToLatLng(previewPosition);
      if (previewPosition == null || previewPoint == null) return;

      currentPosition = previewPosition;
      statusText = 'Ready to track. Tap start to begin your walk.';
      _emit();
    } catch (_) {
      // Keep the default map state if preview location is unavailable.
    }
  }

  Future<Position?> _getInitialPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      return Geolocator.getLastKnownPosition();
    } on LocationServiceDisabledException {
      rethrow;
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  Future<bool> _ensureActivityRecognitionAccess() async {
    var status = await _stepPermission.status;
    if (!status.isGranted) {
      status = await _stepPermission.request();
    }

    if (status.isGranted) {
      return true;
    }

    statusText =
        'Activity recognition permission is needed to show live step counts.';
    _emit();

    return false;
  }

  Future<bool> _ensureLocationAccess({bool openSettings = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      statusText = 'Turn on location services to start route tracking.';
      _emit();
      if (openSettings) {
        await Geolocator.openLocationSettings();
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      statusText = 'Location permission is needed to draw your walking route.';
      _emit();
      if (permission == LocationPermission.deniedForever && openSettings) {
        await Geolocator.openAppSettings();
      }
      return false;
    }

    return true;
  }

  /// Tracking must survive screen-off and backgrounding: Android needs a
  /// foreground service, iOS needs background location updates enabled.
  LocationSettings _trackingLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'InnerU walk tracking',
          notificationText: 'Your route is being recorded.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  Future<void> startTracking() async {
    if (isPreparing || isTracking) return;

    isPreparing = true;
    statusText = 'Checking location permissions...';
    _emit();

    try {
      final hasLocationAccess = await _ensureLocationAccess();
      if (!hasLocationAccess) return;

      final hasActivityAccess = await _ensureActivityRecognitionAccess();
      if (!hasActivityAccess) return;

      final latestPosition = await _getInitialPosition();
      if (latestPosition == null) {
        statusText =
            'We could not get your location yet. Step outside or turn on GPS, then try again.';
        _emit();
        return;
      }

      final startPoint = positionToLatLng(latestPosition);
      if (startPoint == null) {
        statusText =
            'Your device returned an invalid location. Please wait a moment and try again.';
        _emit();
        return;
      }

      await _positionSubscription?.cancel();
      await _stepSubscription?.cancel();
      _elapsedTimer?.cancel();
      _queuedPositionUpdate = null;
      _queuedPositionUpdateGeneration = null;
      _isProcessingPositionUpdate = false;

      _trackingGeneration++;
      isTracking = true;
      _consecutiveSpikeRejections = 0;
      currentPosition = latestPosition;
      routePoints = [startPoint];
      distanceMeters = 0;
      sessionSteps = 0;
      stepBaseline = null;
      lastRawSessionSteps = 0;
      startedAt = DateTime.now();
      elapsed = Duration.zero;
      statusText = 'Tracking your route...';
      _emit();
      await FastingNotificationService.instance.ensurePermissions();
      await _updateWalkTrackingNotification(force: true);

      await syncSharedSessionMember();
      await _persistTrackingFlag();

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (startedAt == null) return;
        elapsed = DateTime.now().difference(startedAt!);
        _emit();
        _updateWalkTrackingNotification();
        unawaited(_persistTrackingFlag());
      });

      _stepSubscription = Pedometer.stepCountStream.listen(
        (event) {
          if (!isTracking) return;

          stepBaseline ??= event.steps;
          final rawSessionSteps =
              ((event.steps - (stepBaseline ?? event.steps)).clamp(0, 1000000))
                  .toInt();
          _handleRawSessionStepCount(rawSessionSteps);
        },
        onError: (_) {
          statusText =
              'Route tracking is running, but live step updates are unavailable right now.';
          _emit();
        },
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _trackingLocationSettings(),
      ).listen(
        _queuePositionUpdate,
        onError: (_) {
          statusText = 'Unable to update your location right now.';
          _emit();
        },
      );
    } on LocationServiceDisabledException {
      statusText =
          'Location services are off. Please turn GPS on and try again.';
      _emit();
    } on PermissionDeniedException {
      statusText =
          'Location permission was denied. Please allow it to start map tracking.';
      _emit();
    } on TimeoutException {
      statusText =
          'Getting your first GPS fix took too long. Please try again in an open area.';
      _emit();
    } on MissingPluginException {
      statusText =
          'Map tracking needs a full app rebuild after adding location support. Please stop the app and run it again.';
      _emit();
    } catch (error) {
      debugPrint('Step map tracker start failed: $error');
      statusText = 'Could not start tracking: $error';
      _emit();
    } finally {
      isPreparing = false;
      _emit();
    }
  }

  void _handleRawSessionStepCount(int rawSessionSteps) {
    final delta = rawSessionSteps - lastRawSessionSteps;
    lastRawSessionSteps = rawSessionSteps;

    if (delta <= 0) {
      return;
    }

    sessionSteps = rawSessionSteps;
    _emit();
    syncSharedSessionMember();
  }

  void _queuePositionUpdate(Position position) {
    if (!isTracking) return;

    _queuedPositionUpdate = position;
    _queuedPositionUpdateGeneration = _trackingGeneration;
    if (_isProcessingPositionUpdate) {
      return;
    }

    _drainPositionQueue();
  }

  Future<void> _drainPositionQueue() async {
    _isProcessingPositionUpdate = true;

    try {
      while (_queuedPositionUpdate != null) {
        final nextPosition = _queuedPositionUpdate!;
        final nextGeneration =
            _queuedPositionUpdateGeneration ?? _trackingGeneration;
        _queuedPositionUpdate = null;
        _queuedPositionUpdateGeneration = null;

        try {
          await _handlePositionUpdate(nextPosition, nextGeneration);
        } catch (error) {
          debugPrint('Step map route update failed: $error');
          await _appendDirectPositionUpdate(nextPosition, nextGeneration);
        }
      }
    } finally {
      _isProcessingPositionUpdate = false;
    }
  }

  Future<void> _appendDirectPositionUpdate(
    Position position,
    int trackingGeneration,
  ) async {
    if (!isTracking || trackingGeneration != _trackingGeneration) {
      return;
    }

    final nextPoint = positionToLatLng(position);
    if (nextPoint == null) return;

    final previousPoint = routePoints.isNotEmpty ? routePoints.last : null;
    var segmentDistance = 0.0;

    if (previousPoint != null) {
      segmentDistance = _distance(previousPoint, nextPoint);
      if (segmentDistance < _minMovementMeters) {
        currentPosition = position;
        _emit();
        return;
      }
      if (_isLikelyGpsSpike(position, segmentDistance)) {
        await _registerSpikeAndMaybeRebase(position, nextPoint);
        return;
      }
      _consecutiveSpikeRejections = 0;
    }

    routePoints = previousPoint == null
        ? [nextPoint]
        : _mergeSegmentIntoRoute(routePoints, [previousPoint, nextPoint]);
    currentPosition = position;
    distanceMeters += segmentDistance;
    statusText =
        'Street route was unavailable for one update, so tracking continued with GPS.';
    _emit();

    await syncSharedSessionMember();
  }

  /// After several consecutive rejected jumps the user has genuinely moved
  /// (GPS gap, tunnel, resumed from background), so restart the route from
  /// the new location instead of freezing forever. The gap's distance is
  /// deliberately not counted.
  Future<bool> _registerSpikeAndMaybeRebase(
    Position position,
    LatLng nextPoint,
  ) async {
    _consecutiveSpikeRejections++;
    if (_consecutiveSpikeRejections < 3) {
      currentPosition = position;
      return false;
    }
    _consecutiveSpikeRejections = 0;
    routePoints = _mergeSegmentIntoRoute(routePoints, [nextPoint]);
    currentPosition = position;
    statusText = 'Resumed tracking after a location gap.';
    _emit();
    await syncSharedSessionMember();
    return true;
  }

  Future<void> _handlePositionUpdate(
    Position position,
    int trackingGeneration,
  ) async {
    if (!isTracking || trackingGeneration != _trackingGeneration) {
      return;
    }

    final nextPoint = positionToLatLng(position);
    if (nextPoint == null) {
      statusText =
          'Skipping one invalid location update. Tracking will continue.';
      _emit();
      return;
    }

    final previousPoint = routePoints.isNotEmpty ? routePoints.last : null;
    var routePointsToAdd = <LatLng>[nextPoint];
    var segmentDistance = 0.0;

    if (previousPoint != null) {
      segmentDistance = _distance(previousPoint, nextPoint);

      if (segmentDistance < _minMovementMeters) {
        currentPosition = position;
        _emit();
        return;
      }

      if (_isLikelyGpsSpike(position, segmentDistance)) {
        if (await _registerSpikeAndMaybeRebase(position, nextPoint)) {
          return;
        }
        currentPosition = position;
        statusText =
            'Ignoring one noisy GPS jump to keep your route on the street.';
        _emit();
        return;
      }
      _consecutiveSpikeRejections = 0;

      routePointsToAdd = await _buildStreetAlignedSegment(
        previousPoint,
        nextPoint,
      );
      if (!isTracking || trackingGeneration != _trackingGeneration) {
        return;
      }
      segmentDistance = _routeDistance(routePointsToAdd);
    }

    routePoints = previousPoint == null
        ? [nextPoint]
        : _mergeSegmentIntoRoute(routePoints, routePointsToAdd);
    currentPosition = position;
    distanceMeters += segmentDistance;
    statusText = 'Tracking your route...';
    _emit();

    await syncSharedSessionMember();
  }

  /// The watch mirrors the phone's live track; keep its payload small.
  List<List<double>> _watchTrackPoints() {
    const maxPoints = 120;
    var points = routePoints;
    if (points.length > maxPoints) {
      final stride = (points.length - 1) / (maxPoints - 1);
      points = List<LatLng>.generate(
        maxPoints,
        (index) => routePoints[(index * stride).round()],
      );
    }
    return points
        .map((point) => [point.latitude, point.longitude])
        .toList();
  }

  Future<void> syncSharedSessionMember() async {
    WatchSyncService.instance.syncTrack(
      active: isTracking,
      points: _watchTrackPoints(),
      distanceMeters: distanceMeters,
      startedAt: startedAt,
      steps: sessionSteps,
    );

    final userId = currentUserId;
    final sessionId = activeSessionId;
    if (userId == null || sessionId == null) return;

    final livePosition =
        currentPosition == null ? null : positionToLatLng(currentPosition!);

    try {
      await _api.saveMember(sessionId, {
        'user_id': userId,
        'username': currentUsername,
        'status': 'accepted',
        'is_tracking': isTracking,
        'step_count': sessionSteps,
        'distance_meters': distanceMeters,
        'elapsed_seconds': elapsedSeconds,
        'route_points': serializeRoutePoints(routePoints),
        'current_location_lat': livePosition?.latitude,
        'current_location_lng': livePosition?.longitude,
      });
    } catch (error) {
      debugPrint('Failed to sync shared walk session: $error');
    }
  }

  Future<void> stopTracking({bool syncSharedSession = true}) async {
    final hadRoute = routePoints.length > 1;
    final positionSubscription = _positionSubscription;
    final stepSubscription = _stepSubscription;

    _trackingGeneration++;
    isTracking = false;
    _elapsedTimer?.cancel();
    _positionSubscription = null;
    _stepSubscription = null;
    _queuedPositionUpdate = null;
    _queuedPositionUpdateGeneration = null;
    _isProcessingPositionUpdate = false;

    await positionSubscription?.cancel();
    await stepSubscription?.cancel();

    statusText = hadRoute
        ? 'Session complete. You can review the route on screen or start again.'
        : 'Tracking stopped.';
    _lastNotificationElapsedSeconds = -1;
    _emit();
    await FastingNotificationService.instance.cancelWalkTrackingNotification();
    await _clearTrackingFlag();
    if (syncSharedSession) {
      await syncSharedSessionMember();
    }
  }

  static String _trackingFlagKey(String uid) => 'walk_tracking_state_$uid';

  // Snapshot of the in-progress walk, refreshed every second while tracking.
  // This is the only copy of the route guaranteed to survive a process kill
  // when the server sync never went through (no connectivity for the whole
  // session) — reconcileStaleSession() recovers from this, not the server.
  Future<void> _persistTrackingFlag() async {
    final userId = currentUserId;
    final started = startedAt;
    if (userId == null || started == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _trackingFlagKey(userId),
        jsonEncode({
          'sessionId': activeSessionId,
          'startedAtMs': started.millisecondsSinceEpoch,
          'username': currentUsername,
          'routePoints': serializeRoutePoints(routePoints),
          'stepCount': sessionSteps,
          'distanceMeters': distanceMeters,
          'elapsedSeconds': elapsedSeconds,
        }),
      );
    } catch (error) {
      debugPrint('Failed to persist tracking flag: $error');
    }
  }

  Future<void> _clearTrackingFlag() async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_trackingFlagKey(userId));
    } catch (error) {
      debugPrint('Failed to clear tracking flag: $error');
    }
  }

  List<LatLng> _parseStoredRoutePoints(dynamic rawRoutePoints) {
    if (rawRoutePoints is! List) return const [];
    final points = <LatLng>[];
    for (final rawPoint in rawRoutePoints) {
      if (rawPoint is! Map) continue;
      final latitude = (rawPoint['latitude'] as num?)?.toDouble();
      final longitude = (rawPoint['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) continue;
      if (!latitude.isFinite || !longitude.isFinite) continue;
      points.add(LatLng(latitude, longitude));
    }
    return points;
  }

  /// Finalizes a walk that was interrupted by a process kill: saves the
  /// walk to history and marks the shared-session member as no longer
  /// tracking. Local data (captured every second while tracking, see
  /// _persistTrackingFlag) is the primary source and always complete, even
  /// if the walk had zero connectivity the whole time; the server copy is
  /// only used if it happens to be more complete. The persisted flag is
  /// cleared only once the recovery actually saves — if the app is still
  /// offline right now, the flag stays and this retries on the next launch
  /// instead of losing the walk permanently.
  Future<void> reconcileStaleSession() async {
    final userId = currentUserId;
    if (userId == null || isTracking) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trackingFlagKey(userId));
    if (raw == null) return;

    Map<String, dynamic> flag;
    try {
      flag = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await prefs.remove(_trackingFlagKey(userId));
      return;
    }

    final sessionId = flag['sessionId'] as String?;
    final startedAtMs = flag['startedAtMs'] as int?;
    if (sessionId == null || sessionId.isEmpty || startedAtMs == null) {
      await prefs.remove(_trackingFlagKey(userId));
      return;
    }

    var recoveredRoutePoints = _parseStoredRoutePoints(flag['routePoints']);
    var stepCount = (flag['stepCount'] as num?)?.toInt() ?? 0;
    var distance = (flag['distanceMeters'] as num?)?.toDouble() ?? 0.0;
    var elapsedSecondsValue = (flag['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final recoveredUsername = (flag['username'] as String?) ?? currentUsername;

    try {
      final members = await _api.fetchMembers(sessionId);
      final data = members.firstWhere(
        (member) => member['userId']?.toString() == userId,
        orElse: () => <String, dynamic>{},
      );
      if (data.isNotEmpty && data['isTracking'] == true) {
        final serverRoutePoints = _parseStoredRoutePoints(data['routePoints']);
        if (serverRoutePoints.length > recoveredRoutePoints.length) {
          recoveredRoutePoints = serverRoutePoints;
          stepCount = (data['stepCount'] as num?)?.toInt() ?? stepCount;
          distance = (data['distanceMeters'] as num?)?.toDouble() ?? distance;
          elapsedSecondsValue =
              (data['elapsedSeconds'] as num?)?.toInt() ?? elapsedSecondsValue;
        }
      }
    } catch (error) {
      debugPrint(
        'Could not reach server during walk recovery, using local data: $error',
      );
    }

    if (recoveredRoutePoints.length < 2) {
      await prefs.remove(_trackingFlagKey(userId));
      return;
    }

    try {
      await _api.saveRecordedWalk({
        'id': '$startedAtMs',
        'username': recoveredUsername,
        'started_at': DateTime.fromMillisecondsSinceEpoch(startedAtMs)
            .toIso8601String(),
        'ended_at': DateTime.now().toIso8601String(),
        'step_count': stepCount,
        'distance_meters': distance,
        'elapsed_seconds': elapsedSecondsValue,
        'route_points': serializeRoutePoints(recoveredRoutePoints),
        'interrupted': true,
      });

      await _api.saveMember(sessionId, {
        'user_id': userId,
        'username': recoveredUsername,
        'status': 'accepted',
        'is_tracking': false,
        'step_count': stepCount,
        'distance_meters': distance,
        'elapsed_seconds': elapsedSecondsValue,
        'route_points': serializeRoutePoints(recoveredRoutePoints),
      });

      // Only clear now that recovery actually saved — see method doc.
      await prefs.remove(_trackingFlagKey(userId));
      statusText =
          'Your previous walk ended unexpectedly and was saved to history.';
      _emit();
    } catch (error) {
      debugPrint(
        'Stale walk session recovery could not reach the server yet; '
        'will retry next launch: $error',
      );
    }
  }

  Future<void> resetSession() async {
    await stopTracking(syncSharedSession: false);
    await leaveSharedSession();
    routePoints = [];
    currentPosition = null;
    startedAt = null;
    elapsed = Duration.zero;
    stepBaseline = null;
    lastRawSessionSteps = 0;
    sessionSteps = 0;
    distanceMeters = 0;
    statusText = 'Tap start to track your walk on the map.';
    _lastNotificationElapsedSeconds = -1;
    _emit();
    await syncSharedSessionMember();
  }

  Future<void> leaveSharedSession() async {
    final userId = currentUserId;
    final sessionId = activeSessionId;

    if (userId == null || userId.isEmpty || sessionId == null || sessionId.isEmpty) {
      activeSessionId = null;
      WatchSyncService.instance.syncTrack(
        active: isTracking,
        points: _watchTrackPoints(),
        distanceMeters: distanceMeters,
        startedAt: startedAt,
        steps: sessionSteps,
      );
      _emit();
      return;
    }

    try {
      await _api.deleteMember(sessionId, userId);
    } catch (error) {
      debugPrint('Failed to leave shared walk session: $error');
    } finally {
      activeSessionId = null;
      WatchSyncService.instance.syncTrack(
        active: isTracking,
        points: _watchTrackPoints(),
        distanceMeters: distanceMeters,
        startedAt: startedAt,
        steps: sessionSteps,
      );
      _emit();
    }
  }

  Future<void> clearForAccountBoundary() async {
    await stopTracking(syncSharedSession: false);
    await leaveSharedSession();
    routePoints = [];
    currentPosition = null;
    startedAt = null;
    elapsed = Duration.zero;
    stepBaseline = null;
    lastRawSessionSteps = 0;
    sessionSteps = 0;
    distanceMeters = 0;
    statusText = 'Tap start to track your walk on the map.';
    currentUserId = null;
    currentUsername = 'Walker';
    activeSessionId = null;
    _lastNotificationElapsedSeconds = -1;
    WatchSyncService.instance.syncTrack(active: false);
    _emit();
  }

  Future<void> _updateWalkTrackingNotification({bool force = false}) async {
    if (!isTracking) return;

    final elapsedSecondsNow = elapsed.inSeconds;
    final shouldUpdate = force ||
        _lastNotificationElapsedSeconds == -1 ||
        elapsedSecondsNow - _lastNotificationElapsedSeconds >= 15 ||
        elapsedSecondsNow == 0;

    if (!shouldUpdate) {
      return;
    }

    _lastNotificationElapsedSeconds = elapsedSecondsNow;
    await FastingNotificationService.instance.showWalkTrackingNotification(
      stepCount: sessionSteps,
      distanceMeters: distanceMeters,
      elapsed: elapsed,
    );
  }
}

Future<void> clearStepMapTrackerStateForSignOut() {
  return _StepMapTrackingController.instance.clearForAccountBoundary();
}

class StepMapTrackerScreen extends StatefulWidget {
  const StepMapTrackerScreen({super.key});

  @override
  State<StepMapTrackerScreen> createState() => _StepMapTrackerScreenState();
}

class _StepMapTrackerScreenState extends State<StepMapTrackerScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _shareChannel =
      MethodChannel('inneru/native_share');
  static const LatLng _defaultCenter = LatLng(1.3521, 103.8198);
  static const int _maxSharedRoutePoints = 500;
  static const String _streetTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _satelliteTileUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  final MapController _mapController = MapController();
  final _StepMapTrackingController _trackingController =
      _StepMapTrackingController.instance;
  final StepMapApiService _api = StepMapApiService.instance;

  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _memberSubscription;
  Timer? _routeReplayTimer;

  List<LatLng> _routePoints = [];
  Position? _currentPosition;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  int _sessionSteps = 0;
  double _distanceMeters = 0;
  bool _isTracking = false;
  bool _isPreparing = false;
  bool _isResetting = false;
  bool _isSessionBusy = false;
  bool _isWalkerSessionOverlayVisible = true;
  bool _isTrackerDockVisible = true;
  String? _currentUserId;
  String _currentUsername = 'Walker';
  String? _activeSessionId;
  String? _activeSessionStatus;
  String? _activeSessionCreatedBy;
  String? _selectedMarkerUserId;
  _RecordedWalk? _selectedRecordedWalk;
  List<_WalkSessionMember> _sharedMembers = const [];
  Map<String, String> _sharedMemberStatuses = const {};
  final Map<String, String> _locationLabelCache = {};
  final Map<String, Future<String>> _locationLabelRequests = {};
  String _statusText = 'Tap start to track your walk on the map.';
  bool _useSatelliteTiles = true;
  bool _isReplayingRecordedWalk = false;
  int _replayRouteIndex = 0;
  List<LatLng> _replayRoutePoints = const [];
  LatLng? _replayCurrentPoint;

  bool get _isSessionOwner {
    final currentUserId = _currentUserId;
    final sessionOwner = _activeSessionCreatedBy;
    return currentUserId != null &&
        currentUserId.isNotEmpty &&
        sessionOwner != null &&
        sessionOwner.isNotEmpty &&
        sessionOwner == currentUserId;
  }

  bool get _hasActiveSharedSession {
    return _activeSessionId != null &&
        (_activeSessionStatus == 'pending' || _activeSessionStatus == 'active');
  }

  String? get _sharedSessionActionLabel {
    if (!_hasActiveSharedSession) return null;
    return _isSessionOwner ? 'End Session' : 'Leave Session';
  }

  void _listenToSessionMembers(String? sessionId) {
    _memberSubscription?.cancel();

    if (sessionId == null || sessionId.isEmpty) {
      if (mounted) {
        setState(() {
          _sharedMembers = const [];
          _sharedMemberStatuses = const {};
        });
      }
      return;
    }

    _memberSubscription = _api.watchMembers(sessionId).listen((membersData) {
      final members = membersData
          .map((data) => _WalkSessionMember.fromApi(
                data,
                _deserializeRoutePoints,
              ))
          .toList();
      final previousStatuses = _sharedMemberStatuses;
      final nextStatuses = <String, String>{
        for (final member in members)
          if (member.userId.isNotEmpty)
            member.userId: member.status.trim().toLowerCase(),
      };

      for (final member in members) {
        if (member.userId == _currentUserId) {
          continue;
        }

        final previousStatus = previousStatuses[member.userId];
        final currentStatus = member.status.trim().toLowerCase();
        final hasAcceptedInvite =
            previousStatus != null &&
                previousStatus != currentStatus &&
                previousStatus == 'invited' &&
                currentStatus == 'accepted';

        if (hasAcceptedInvite) {
          unawaited(
            FastingNotificationService.instance
                .showWalkInviteAcceptedNotification(
              walkerName: member.username.isEmpty
                  ? 'A walker'
                  : member.username,
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${member.username.isEmpty ? 'A walker' : member.username} accepted your walk invite.',
                ),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _sharedMembers = members;
        _sharedMemberStatuses = nextStatuses;
      });
    }, onError: (error) {
      debugPrint('Failed to listen to session members: $error');
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = AuthService.instance.currentSession?.id.toString();
    _trackingController.addListener(_handleTrackingControllerChanged);
    _applyTrackingState(notify: false);
    _trackingController.updateUser(
      userId: _currentUserId,
      username: _currentUsername,
    );
    unawaited(_trackingController.reconcileStaleSession());
    _loadCurrentUser();
    _listenToWalkSessions();
    _loadInitialMapPreview();
  }

  // Tracking intentionally continues while the app is backgrounded or the
  // screen is off (Android foreground service / iOS background location),
  // so no lifecycle handling stops it. A session interrupted by a process
  // kill is finalized by reconcileStaleSession on next launch.

  Future<void> _loadInitialMapPreview() async {
    await _trackingController.loadInitialMapPreview();
  }

  void _handleTrackingControllerChanged() {
    if (!mounted) return;
    _applyTrackingState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _trackingController.updateUser(
          userId: _currentUserId,
          username: _currentUsername,
        );
        _trackingController.updateActiveSession(_activeSessionId);
        _listenToWalkSessions();
        if (mounted) {
          _applyTrackingState(notify: true);
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        unawaited(_trackingController.syncSharedSessionMember());
        break;
      case AppLifecycleState.detached:
        unawaited(_trackingController.syncSharedSessionMember());
        break;
    }
  }

  void _applyTrackingState({bool notify = true}) {
    final currentPosition = _trackingController.currentPosition;
    void updateState() {
      _routePoints = List<LatLng>.from(_trackingController.routePoints);
      _currentPosition = currentPosition;
      _startedAt = _trackingController.startedAt;
      _elapsed = _trackingController.elapsed;
      _sessionSteps = _trackingController.sessionSteps;
      _distanceMeters = _trackingController.distanceMeters;
      _isTracking = _trackingController.isTracking;
      _isPreparing = _trackingController.isPreparing;
      _statusText = _trackingController.statusText;
    }

    if (notify && mounted) {
      setState(updateState);
    } else {
      updateState();
    }

    if (currentPosition != null) {
      final point = _positionToLatLng(currentPosition);
      if (point != null) {
        _moveCamera(point, zoom: _isTracking ? 17 : 16);
      }
    }
  }

  bool _isFiniteCoordinate(double value) => value.isFinite;

  bool _isValidLatitude(double value) =>
      _isFiniteCoordinate(value) && value >= -90 && value <= 90;

  bool _isValidLongitude(double value) =>
      _isFiniteCoordinate(value) && value >= -180 && value <= 180;

  LatLng? _safeLatLng(double latitude, double longitude) {
    if (!_isValidLatitude(latitude) || !_isValidLongitude(longitude)) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  LatLng? _positionToLatLng(Position position) {
    return _safeLatLng(position.latitude, position.longitude);
  }

  List<Map<String, double>> _serializeRoutePoints(List<LatLng> points) {
    final start = math.max(0, points.length - _maxSharedRoutePoints);
    return points
        .sublist(start)
        .map((point) => {
              'latitude': point.latitude,
              'longitude': point.longitude,
            })
        .toList();
  }

  List<LatLng> _deserializeRoutePoints(dynamic rawRoutePoints) {
    if (rawRoutePoints is! List) return const [];

    final points = <LatLng>[];
    for (final rawPoint in rawRoutePoints) {
      if (rawPoint is Map) {
        final latitude = (rawPoint['latitude'] as num?)?.toDouble();
        final longitude = (rawPoint['longitude'] as num?)?.toDouble();
        if (latitude != null && longitude != null) {
          final safePoint = _safeLatLng(latitude, longitude);
          if (safePoint != null) {
            points.add(safePoint);
          }
        }
      }
    }
    return points;
  }

  DateTime _timestampToDateTime(dynamic value) {
    if (value is DateTime) return value;
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _elapsedSeconds() => _elapsed.inSeconds;

  Color _memberColor(String userId) {
    if (userId == _currentUserId) {
      return const Color(0xFFCE8F5A);
    }

    const palette = [
      Color(0xFF6D849A),
      Color(0xFF90A17D),
      Color(0xFFB96D40),
      Color(0xFF43766C),
    ];

    return palette[userId.hashCode.abs() % palette.length];
  }

  Future<void> _loadCurrentUser() async {
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final data = await UserService.getUserData();
      final username = (data['username'] as String?)?.trim();

      if (!mounted) return;
      setState(() {
        _currentUsername = (username == null || username.isEmpty)
            ? (AuthService.instance.currentSession?.email.split('@').first ??
                'Walker')
            : username;
      });
      _trackingController.updateUser(
        userId: _currentUserId,
        username: _currentUsername,
      );
    } catch (error) {
      debugPrint('Failed to load current user: $error');
    }
  }

  Map<String, dynamic> _normalizeInviteUser(Map<String, dynamic> user) {
    final id = user['id']?.toString().trim() ?? '';
    final username = (user['username'] ??
            user['name'] ??
            user['fullName'] ??
            user['displayName'])
        ?.toString()
        .trim();
    final email = (user['email'] ?? user['username'])?.toString().trim();

    return {
      ...user,
      'id': id,
      'username': username?.isNotEmpty == true ? username : email ?? '',
      'email': email ?? '',
    };
  }

  Future<List<Map<String, dynamic>>> _fetchInviteUsers() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final candidates = <Map<String, dynamic>>[];

    try {
      final coachUsers = await CoachApiService.instance.fetchUsers();
      candidates.addAll(coachUsers.map(_normalizeInviteUser));
    } catch (error) {
      debugPrint('Failed to load invite users from coach endpoint: $error');
    }

    try {
      final adminUsers = await AdminUserApiService.instance.fetchUsers();
      candidates.addAll(
        adminUsers.map(
          (user) => _normalizeInviteUser({
            'id': user.id,
            'username': user.name,
            'email': user.email,
            'profilePic': user.profilePic,
            'companyName': user.companyName,
            'companyCode': user.companyCode,
          }),
        ),
      );
    } catch (error) {
      debugPrint('Failed to load invite users from admin endpoint: $error');
    }

    final seenIds = <String>{};
    final filteredUsers = <Map<String, dynamic>>[];
    for (final user in candidates) {
      final id = user['id']?.toString().trim() ?? '';
      if (id.isEmpty || id == currentUserId || !seenIds.add(id)) {
        continue;
      }
      filteredUsers.add(user);
    }

    filteredUsers.sort((a, b) {
      final aName = ((a['username']?.toString().trim().isNotEmpty == true
                  ? a['username']
                  : a['email'])
              ?.toString()
              .toLowerCase()) ??
          '';
      final bName = ((b['username']?.toString().trim().isNotEmpty == true
                  ? b['username']
                  : b['email'])
              ?.toString()
              .toLowerCase()) ??
          '';
      return aName.compareTo(bName);
    });

    return filteredUsers;
  }

  void _listenToWalkSessions() {
    final userId = _currentUserId;
    if (userId == null) return;

    _sessionSubscription?.cancel();
    _sessionSubscription = _api.watchSessions(userId).listen((sessions) {
      final docs = sessions.where((doc) {
        final status = doc['status'] as String? ?? 'pending';
        return status == 'pending' || status == 'active';
      }).toList()
        ..sort((a, b) {
          final aDate = _timestampToDateTime(a['updatedAt'] ?? a['createdAt']);
          final bDate = _timestampToDateTime(b['updatedAt'] ?? b['createdAt']);
          return bDate.compareTo(aDate);
        });

      if (!mounted) return;

      if (docs.isEmpty) {
        setState(() {
          _activeSessionId = null;
          _activeSessionStatus = null;
          _activeSessionCreatedBy = null;
          _sharedMembers = const [];
        });
        _trackingController.updateActiveSession(null);
        _listenToSessionMembers(null);
        return;
      }

      final activeDoc = docs.first;
      final nextSessionId = activeDoc['id'] as String? ?? '';
      final nextStatus = activeDoc['status'] as String? ?? 'pending';
      final nextCreatedBy = activeDoc['createdBy'] as String? ?? '';

      if (_activeSessionId != nextSessionId) {
        _listenToSessionMembers(nextSessionId);
      }

      setState(() {
        _activeSessionId = nextSessionId;
        _activeSessionStatus = nextStatus;
        _activeSessionCreatedBy = nextCreatedBy;
      });
      _trackingController.updateActiveSession(nextSessionId);
    }, onError: (error) {
      debugPrint('Failed to listen to walk sessions: $error');
    });
  }

  Future<bool> _createWalkInvite(Map<String, dynamic> invitedUser) async {
    final userId = _currentUserId;
    final invitedUserId = invitedUser['id'] as String?;
    final invitedUsername =
        (invitedUser['username'] as String?)?.trim() ??
            (invitedUser['name'] as String?)?.trim();

    if (userId == null ||
        invitedUserId == null ||
        invitedUserId.isEmpty ||
        invitedUsername == null ||
        invitedUsername.isEmpty) {
      return false;
    }

    setState(() {
      _isSessionBusy = true;
    });

    try {
      final hasReusableSession = _activeSessionId != null &&
          (_activeSessionStatus == 'pending' ||
              _activeSessionStatus == 'active');
      final sessionId = hasReusableSession
          ? _activeSessionId!
          : DateTime.now().millisecondsSinceEpoch.toString();
      final inviteId = '$sessionId:$invitedUserId';
      final safeCurrentLocation = _currentPosition == null
          ? null
          : _positionToLatLng(_currentPosition!);
      final participantIds = <String>{
        ..._sharedMembers.map((member) => member.userId),
        userId,
        invitedUserId,
      }.toList();

      await _api.saveSession({
        'id': sessionId,
        'status': hasReusableSession
            ? (_activeSessionStatus ?? 'pending')
            : 'pending',
        'participant_ids': participantIds,
        'created_by': userId,
        'created_by_name': _currentUsername,
      });

      await _api.saveMember(sessionId, {
        'user_id': userId,
        'username': _currentUsername,
        'status': 'accepted',
        'is_tracking': _isTracking,
        'step_count': _sessionSteps,
        'distance_meters': _distanceMeters,
        'elapsed_seconds': _elapsedSeconds(),
        'route_points': _serializeRoutePoints(_routePoints),
        if (safeCurrentLocation != null)
          'current_location_lat': safeCurrentLocation.latitude,
        if (safeCurrentLocation != null)
          'current_location_lng': safeCurrentLocation.longitude,
      });

      await _api.saveMember(sessionId, {
        'user_id': invitedUserId,
        'username': invitedUsername,
        'status': 'invited',
        'is_tracking': false,
        'step_count': 0,
        'distance_meters': 0,
        'elapsed_seconds': 0,
        'route_points': const [],
      });

      await _api.saveInvite({
        'id': inviteId,
        'walk_session_id': sessionId,
        'from_user_id': userId,
        'from_username': _currentUsername,
        'to_user_id': invitedUserId,
        'to_username': invitedUsername,
      });

      if (!mounted) return false;
      setState(() {
        _activeSessionId = sessionId;
        _activeSessionStatus = hasReusableSession
            ? (_activeSessionStatus ?? 'pending')
            : 'pending';
        _activeSessionCreatedBy = userId;
      });
      _trackingController.updateActiveSession(sessionId);
      _listenToSessionMembers(sessionId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Walk invite sent to $invitedUsername.'),
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send walk invite: $error'),
        ),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSessionBusy = false;
        });
      }
    }
  }

  Future<void> _acceptWalkInvite(Map<String, dynamic> inviteData) async {
    final userId = _currentUserId;
    final sessionId = inviteData['sessionId'] as String?;
    final inviteId = inviteData['id'] as String?;
    if (userId == null ||
        sessionId == null ||
        sessionId.isEmpty ||
        inviteId == null ||
        inviteId.isEmpty) {
      return;
    }

    setState(() {
      _isSessionBusy = true;
    });

    try {
      await _api.updateInvite(inviteId, 'accepted');
      if (!mounted) return;
      setState(() {
        _activeSessionId = sessionId;
        _activeSessionStatus = 'active';
        _activeSessionCreatedBy =
            (inviteData['fromUserId'] as String?)?.trim().isNotEmpty == true
                ? inviteData['fromUserId'] as String?
                : null;
      });
      _trackingController.updateActiveSession(sessionId);
      _listenToSessionMembers(sessionId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept walk invite: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSessionBusy = false;
        });
      }
    }
  }

  Future<void> _declineWalkInvite(Map<String, dynamic> inviteData) async {
    final inviteId = inviteData['id'] as String?;
    if (inviteId == null || inviteId.isEmpty) return;

    try {
      await _api.updateInvite(inviteId, 'declined');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to decline walk invite: $error'),
        ),
      );
    }
  }

  Future<void> _startTracking() async {
    _trackingController.updateUser(
      userId: _currentUserId,
      username: _currentUsername,
    );
    _trackingController.updateActiveSession(_activeSessionId);
    await _trackingController.startTracking();
  }

  void _moveCamera(LatLng point, {double zoom = 16}) {
    if (!_isValidLatitude(point.latitude) ||
        !_isValidLongitude(point.longitude)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(point, zoom);
    });
  }

  LatLng _routeCenter(List<LatLng> points) {
    if (points.isEmpty) return _defaultCenter;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  double _routeOverviewZoom(List<LatLng> points) {
    if (points.length < 2) return 16.8;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    final span = math.max(latSpan, lngSpan);

    if (span < 0.0012) return 17.8;
    if (span < 0.0025) return 17.0;
    if (span < 0.005) return 16.2;
    if (span < 0.012) return 15.4;
    return 14.6;
  }

  double _replayZoomForProgress(double progress) {
    final eased = math.sin(progress * math.pi);
    return 19.0 + (eased * 0.25);
  }

  List<LatLng> _buildSmoothedReplayRoute(List<LatLng> points) {
    if (points.length < 2) return points;

    final smoothed = <LatLng>[points.first];
    for (var index = 1; index < points.length; index++) {
      final from = points[index - 1];
      final to = points[index];
      final segmentDistance = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );
      final steps = segmentDistance < 8
          ? 2
          : segmentDistance < 20
              ? 3
              : segmentDistance < 40
                  ? 4
                  : 5;

      for (var step = 1; step <= steps; step++) {
        final t = step / steps;
        smoothed.add(
          LatLng(
            from.latitude + ((to.latitude - from.latitude) * t),
            from.longitude + ((to.longitude - from.longitude) * t),
          ),
        );
      }
    }

    return smoothed;
  }

  void _moveReplayCamera(LatLng point, double progress) {
    _moveCamera(point, zoom: _replayZoomForProgress(progress));
  }

  Future<void> _shareRecordedWalk(_RecordedWalk walk) async {
    try {
      final imageBytes = await _buildRecordedWalkShareImage(walk);
      final tempDir = await getTemporaryDirectory();
      final safeFileName =
          'inneru_walk_${walk.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$safeFileName');
      await file.writeAsBytes(imageBytes, flush: true);

      if (!mounted) return;
      await _shareChannel.invokeMethod<void>(
        'shareImage',
        <String, dynamic>{
          'filePath': file.path,
          'text':
              'InnerU recorded walk • ${_formatDistance(walk.distanceMeters)} • ${walk.stepCount} steps • ${_formatDuration(Duration(seconds: walk.elapsedSeconds))}',
        },
      );
    } catch (error) {
      debugPrint('Failed to share recorded walk: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share recorded walk: $error'),
        ),
      );
    }
  }

  Future<Uint8List> _buildRecordedWalkShareImage(_RecordedWalk walk) async {
    const width = 1080.0;
    const height = 1350.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(width, height);

    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF8F3EA), Color(0xFFECD7BC)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    canvas.drawCircle(
      const Offset(930, 200),
      260,
      Paint()..color = const Color(0x20FFFFFF),
    );
    canvas.drawCircle(
      const Offset(170, 1140),
      200,
      Paint()..color = const Color(0x14B96D40),
    );

    _paintShareText(
      canvas,
      'InnerU',
      const Offset(72, 64),
      const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: Color(0xFF2A3B36),
        letterSpacing: 0.4,
      ),
    );
    _paintShareText(
      canvas,
      'Recorded Walk',
      const Offset(72, 112),
      const TextStyle(
        fontSize: 56,
        fontWeight: FontWeight.w900,
        color: Color(0xFF1F2A2E),
      ),
    );
    _paintShareText(
      canvas,
      _formatRecordedWalkDate(walk.endedAt),
      const Offset(74, 182),
      const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Color(0xFF5C5C5C),
      ),
    );

    final routeCard = RRect.fromRectAndRadius(
      const Rect.fromLTWH(72, 252, 936, 760),
      const Radius.circular(42),
    );
    final routePath = ui.Path()..addRRect(routeCard);
    canvas.drawShadow(routePath, Colors.black26, 18, true);
    canvas.drawRRect(
      routeCard,
      Paint()..color = const Color(0xFFFDFBF7),
    );

    final routeBounds = walk.routePoints.fold<_RouteBounds?>(
      null,
      (previous, point) {
        if (previous == null) {
          return _RouteBounds(
            minLat: point.latitude,
            maxLat: point.latitude,
            minLng: point.longitude,
            maxLng: point.longitude,
          );
        }
        return _RouteBounds(
          minLat: math.min(previous.minLat, point.latitude),
          maxLat: math.max(previous.maxLat, point.latitude),
          minLng: math.min(previous.minLng, point.longitude),
          maxLng: math.max(previous.maxLng, point.longitude),
        );
      },
    );
    if (routeBounds == null) {
      final bytes = await recorder.endRecording().toImage(width.toInt(), height.toInt());
      final data = await bytes.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    final plotRect = const Rect.fromLTWH(72, 252, 936, 760).deflate(56);
    final latSpan = (routeBounds.maxLat - routeBounds.minLat).abs().clamp(0.000001, double.infinity);
    final lngSpan = (routeBounds.maxLng - routeBounds.minLng).abs().clamp(0.000001, double.infinity);

    Offset toCanvasPoint(LatLng point) {
      final xRatio = ((point.longitude - routeBounds.minLng) / lngSpan).clamp(0.0, 1.0);
      final yRatio = ((point.latitude - routeBounds.minLat) / latSpan).clamp(0.0, 1.0);
      return Offset(
        plotRect.left + (xRatio * plotRect.width),
        plotRect.bottom - (yRatio * plotRect.height),
      );
    }

    final gridPaint = Paint()
      ..color = const Color(0x11000000)
      ..strokeWidth = 2;
    for (double x = plotRect.left; x <= plotRect.right; x += 120) {
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
    }
    for (double y = plotRect.top; y <= plotRect.bottom; y += 120) {
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }

    final routePoints = walk.routePoints.map(toCanvasPoint).toList();
    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 22
      ..color = const Color(0x332E5BFF);
    final routePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 14
      ..color = const Color(0xFF2E5BFF);

    final path = ui.Path()..moveTo(routePoints.first.dx, routePoints.first.dy);
    for (final point in routePoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, routePaint);

    void drawEndpoint(Offset point, Color color) {
      canvas.drawCircle(point, 22, Paint()..color = Colors.white);
      canvas.drawCircle(point, 15, Paint()..color = color);
    }

    drawEndpoint(routePoints.first, const Color(0xFF2E8B57));
    drawEndpoint(routePoints.last, const Color(0xFFB96D40));

    final statsTop = 1060.0;
    final statsCard = RRect.fromRectAndRadius(
      Rect.fromLTWH(72, statsTop, 936, 196),
      const Radius.circular(36),
    );
    canvas.drawShadow(ui.Path()..addRRect(statsCard), Colors.black26, 14, true);
    canvas.drawRRect(
      statsCard,
      Paint()..color = const Color(0xFFFDFBF7),
    );

    _drawMetricCard(
      canvas,
      Rect.fromLTWH(96, statsTop + 28, 276, 120),
      'Distance',
      _formatDistance(walk.distanceMeters),
    );
    _drawMetricCard(
      canvas,
      Rect.fromLTWH(402, statsTop + 28, 276, 120),
      'Steps',
      walk.stepCount.toString(),
    );
    _drawMetricCard(
      canvas,
      Rect.fromLTWH(708, statsTop + 28, 276, 120),
      'Time',
      _formatDuration(Duration(seconds: walk.elapsedSeconds)),
    );

    _paintShareText(
      canvas,
      'Shared from InnerU',
      const Offset(72, 1280),
      const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6A655D),
      ),
    );

    final image = await recorder
        .endRecording()
        .toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void _paintShareText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    double maxWidth = 900,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  void _drawMetricCard(
    Canvas canvas,
    Rect rect,
    String label,
    String value,
  ) {
    final cardPath = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    canvas.drawRRect(cardPath, Paint()..color = const Color(0xFFF6F0E8));

    _paintShareText(
      canvas,
      value,
      Offset(rect.left + 18, rect.top + 18),
      const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        color: Color(0xFF1F2A2E),
      ),
    );
    _paintShareText(
      canvas,
      label,
      Offset(rect.left + 18, rect.top + 72),
      const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6A655D),
      ),
    );
  }

  Future<void> _stopTracking() async {
    final shouldSave = _isTracking && _routePoints.length > 1;
    await _trackingController.stopTracking();
    if (shouldSave) {
      await _saveRecordedWalk();
    }
  }

  Future<void> _leaveSharedSessionAction() async {
    if (_isSessionBusy || !_hasActiveSharedSession) return;

    setState(() {
      _isSessionBusy = true;
    });

    try {
      await _trackingController.stopTracking(syncSharedSession: false);
      await _trackingController.leaveSharedSession();
      if (!mounted) return;
      setState(() {
        _activeSessionId = null;
        _activeSessionStatus = null;
        _activeSessionCreatedBy = null;
        _sharedMembers = const [];
        _sharedMemberStatuses = const {};
        _selectedMarkerUserId = null;
      });
      _trackingController.updateActiveSession(null);
      _listenToWalkSessions();
    } finally {
      if (mounted) {
        setState(() {
          _isSessionBusy = false;
        });
      }
    }
  }

  Future<void> _endSharedSessionAction() async {
    if (_isSessionBusy || !_hasActiveSharedSession) return;

    final sessionId = _activeSessionId;
    final currentUserId = _currentUserId;
    if (sessionId == null || currentUserId == null) return;

    setState(() {
      _isSessionBusy = true;
    });

    try {
      await _trackingController.stopTracking(syncSharedSession: false);

      await _api.saveSession({
        'id': sessionId,
        'status': 'ended',
        'participant_ids': _sharedMembers
            .map((member) => member.userId)
            .where((value) => value.isNotEmpty)
            .toList(),
        'created_by': _activeSessionCreatedBy ?? currentUserId,
        'created_by_name': _currentUsername,
      });

      await _trackingController.leaveSharedSession();

      if (!mounted) return;
      setState(() {
        _activeSessionId = null;
        _activeSessionStatus = null;
        _activeSessionCreatedBy = null;
        _sharedMembers = const [];
        _sharedMemberStatuses = const {};
        _selectedMarkerUserId = null;
      });
      _trackingController.updateActiveSession(null);
      _listenToWalkSessions();
    } finally {
      if (mounted) {
        setState(() {
          _isSessionBusy = false;
        });
      }
    }
  }

  Future<void> _resetSession() async {
    if (_isResetting) return;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          title: const Text('Reset tracking?'),
          content: const Text(
            'This will stop the current walk and clear the live steps, distance, time, and route. You will need to tap Start Tracking again to record a new walk.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCE8F5A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldReset != true) return;

    setState(() {
      _isResetting = true;
    });

    try {
      await _trackingController.resetSession();
      if (!mounted) return;
      setState(() {
        _activeSessionId = null;
        _activeSessionStatus = null;
        _sharedMembers = const [];
        _sharedMemberStatuses = const {};
        _selectedMarkerUserId = null;
        _isWalkerSessionOverlayVisible = true;
      });
      _trackingController.updateActiveSession(null);
      _listenToWalkSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tracking session reset.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResetting = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _formatRecordedWalkDate(DateTime dateTime) {
    final month = _monthLabel(dateTime.month);
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$month $day, ${dateTime.year} at $hour:$minute';
  }

  String _monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  void _resetRecordedWalkReplay({bool clearSelection = false}) {
    _routeReplayTimer?.cancel();
    _routeReplayTimer = null;

    if (!mounted) return;
    setState(() {
      _isReplayingRecordedWalk = false;
      _replayRouteIndex = 0;
      _replayRoutePoints = const [];
      _replayCurrentPoint = null;
      if (clearSelection) {
        _selectedRecordedWalk = null;
        _isTrackerDockVisible = true;
      }
    });
  }

  void _startRecordedWalkReplay() {
    final walk = _selectedRecordedWalk;
    if (walk == null || walk.routePoints.length < 2) {
      return;
    }

    _routeReplayTimer?.cancel();
    final replayPoints = _buildSmoothedReplayRoute(walk.routePoints);

    final totalPoints = replayPoints.length;
    final intervalMs = (22000 / totalPoints).round().clamp(120, 520);

    setState(() {
      _isReplayingRecordedWalk = true;
      _replayRouteIndex = 1;
      _replayRoutePoints = replayPoints.take(1).toList();
      _replayCurrentPoint = replayPoints.first;
    });
    _moveReplayCamera(replayPoints.first, 0);

    _routeReplayTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_selectedRecordedWalk == null ||
            _replayRouteIndex >= replayPoints.length) {
          timer.cancel();
          setState(() {
            _isReplayingRecordedWalk = false;
            _replayRoutePoints = List<LatLng>.from(replayPoints);
            _replayCurrentPoint = replayPoints.last;
          });
          return;
        }

        final nextPoint = replayPoints[_replayRouteIndex];
        final nextIndex = _replayRouteIndex + 1;
        final progress = (nextIndex / replayPoints.length).clamp(0.0, 1.0);
        setState(() {
          _replayRouteIndex = nextIndex;
          _replayRoutePoints =
              replayPoints.take(_replayRouteIndex).toList();
          _replayCurrentPoint = nextPoint;
        });
        _moveReplayCamera(nextPoint, progress);
      },
    );
  }

  Future<void> _saveRecordedWalk() async {
    final userId = _currentUserId;
    final startedAt = _startedAt;
    if (userId == null || startedAt == null || _routePoints.length < 2) {
      return;
    }

    final endedAt = DateTime.now();
    final docId = '${startedAt.millisecondsSinceEpoch}';

    try {
      await _api.saveRecordedWalk({
        'id': docId,
        'username': _currentUsername,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'step_count': _sessionSteps,
        'distance_meters': _distanceMeters,
        'elapsed_seconds': _elapsedSeconds(),
        'route_points': _serializeRoutePoints(_routePoints),
        'interrupted': false,
      });
    } catch (error) {
      debugPrint('Failed to save recorded walk: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save this walk recording: $error'),
        ),
      );
    }
  }

  void _openRecordedWalk(_RecordedWalk walk) {
    _routeReplayTimer?.cancel();
    setState(() {
      _selectedRecordedWalk = walk;
      _isReplayingRecordedWalk = false;
      _isTrackerDockVisible = false;
      _replayRouteIndex = 0;
      _replayRoutePoints = const [];
      _replayCurrentPoint = null;
    });

    if (walk.routePoints.isNotEmpty) {
      _moveCamera(
        _routeCenter(walk.routePoints),
        zoom: _routeOverviewZoom(walk.routePoints),
      );
    }
  }

  void _showRecordedWalksSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.86,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _api.watchRecordedWalks(),
                builder: (context, snapshot) {
                  final walks = (snapshot.data ?? [])
                      .map((data) => _RecordedWalk.fromApi(
                            id: (data['id'] as String?) ?? '',
                            data: data,
                            routeParser: _deserializeRoutePoints,
                            timestampParser: _timestampToDateTime,
                          ))
                      .where((walk) => walk.routePoints.length > 1)
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recorded Walks',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Open any saved walk to preview its route on the map.',
                        style: TextStyle(fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: walks.isEmpty
                            ? const Center(
                                child: Text('No recorded walks yet.'),
                              )
                            : ListView.separated(
                                itemCount: walks.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final walk = walks[index];
                                  final isSelected =
                                      _selectedRecordedWalk?.id == walk.id;

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF6D849A),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    title:
                                        Text(_formatRecordedWalkDate(walk.endedAt)),
                                    subtitle: Text(
                                      '${_formatDistance(walk.distanceMeters)} | ${walk.stepCount} steps | ${_formatDuration(Duration(seconds: walk.elapsedSeconds))}',
                                    ),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          onPressed: () async {
                                            Navigator.of(context).pop();
                                            await _shareRecordedWalk(walk);
                                          },
                                          icon: const Icon(
                                            Icons.share_outlined,
                                            color: Color(0xFF6D849A),
                                          ),
                                          tooltip: 'Share walk image',
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            _openRecordedWalk(walk);
                                          },
                                          child: Text(
                                            isSelected ? 'Opened' : 'Open',
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _deleteRecordedWalk(walk),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFFB96D40),
                                          ),
                                          tooltip: 'Delete replay',
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteRecordedWalk(_RecordedWalk walk) async {
    final userId = _currentUserId;
    if (userId == null) return;

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete Walk Replay'),
              content: const Text(
                'Do you want to permanently delete this recorded walk replay?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) return;

    try {
      await _api.deleteRecordedWalk(walk.id);

      if (!mounted) return;
      if (_selectedRecordedWalk?.id == walk.id) {
        _resetRecordedWalkReplay(clearSelection: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recorded walk deleted.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete recorded walk: $error'),
        ),
      );
    }
  }

  List<_WalkSessionMember> _displayMembers() {
    if (_sharedMembers.isNotEmpty) {
      return _sharedMembers;
    }

    final userId = _currentUserId;
    if (userId == null) return const [];

    final currentPoint =
        _currentPosition == null ? null : _positionToLatLng(_currentPosition!);

    return [
      _WalkSessionMember(
        userId: userId,
        username: _currentUsername,
        status: 'accepted',
        isTracking: _isTracking,
        stepCount: _sessionSteps,
        distanceMeters: _distanceMeters,
        elapsedSeconds: _elapsedSeconds(),
        currentLocation: currentPoint,
        routePoints: _routePoints,
      ),
    ];
  }

  LatLng? _memberFocusPoint(_WalkSessionMember member) {
    return member.currentLocation ??
        (member.routePoints.isNotEmpty ? member.routePoints.last : null);
  }

  _WalkSessionMember? _memberById(
    List<_WalkSessionMember> members,
    String? userId,
  ) {
    if (userId == null || userId.isEmpty) return null;

    for (final member in members) {
      if (member.userId == userId) {
        return member;
      }
    }
    return null;
  }

  String _locationKey(LatLng point) {
    return '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
  }

  String _buildLocationLabel(
    Map<String, dynamic>? address,
    String displayName,
  ) {
    final parts = <String>[];
    final fields = [
      'road',
      'neighbourhood',
      'suburb',
      'city_district',
      'city',
      'town',
      'village',
      'municipality',
      'county',
      'state',
      'country',
    ];

    for (final field in fields) {
      final value = (address?[field] as String?)?.trim();
      if (value != null && value.isNotEmpty && !parts.contains(value)) {
        parts.add(value);
      }
      if (parts.length >= 3) break;
    }

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    final trimmedDisplayName = displayName.trim();
    if (trimmedDisplayName.isNotEmpty) {
      final displayParts = trimmedDisplayName
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (displayParts.isNotEmpty) {
        return displayParts.take(3).join(', ');
      }
      return trimmedDisplayName;
    }

    return '';
  }

  Future<String> _resolveLocationLabel(LatLng point) {
    final key = _locationKey(point);
    final cached = _locationLabelCache[key];
    if (cached != null) return Future.value(cached);

    final inFlight = _locationLabelRequests[key];
    if (inFlight != null) return inFlight;

    final future = _fetchLocationLabel(point).then((label) {
      _locationLabelCache[key] = label;
      _locationLabelRequests.remove(key);
      return label;
    }).catchError((error) {
      debugPrint('Failed to reverse geocode walker location: $error');
      _locationLabelRequests.remove(key);
      return '';
    });

    _locationLabelRequests[key] = future;
    return future;
  }

  Future<String> _fetchLocationLabel(LatLng point) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      {
        'format': 'jsonv2',
        'lat': point.latitude.toStringAsFixed(6),
        'lon': point.longitude.toStringAsFixed(6),
        'zoom': '18',
        'addressdetails': '1',
      },
    );

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'selfcare_projects_step_map_tracker/1.0',
      },
    ).timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) return '';

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) return '';

    final address = payload['address'];
    final displayName = (payload['display_name'] as String?) ?? '';
    final placeLabel = _buildLocationLabel(
      address is Map<String, dynamic> ? address : null,
      displayName,
    );
    return placeLabel;
  }

  Widget _buildSharedSessionOverlay(_WalkSessionMember? selectedMember) {
    if (_sharedMembers.isEmpty) return const SizedBox.shrink();

    final visibleMembers = _sharedMembers
        .where((member) => member.userId.isNotEmpty)
        .toList();

    if (visibleMembers.isEmpty) return const SizedBox.shrink();

    Widget statusChip(String status) {
      final normalized = status.trim().toLowerCase();
      final label = switch (normalized) {
        'accepted' || 'active' => 'Joined',
        'invited' || 'pending' => 'Pending',
        'declined' => 'Declined',
        _ => 'Invite',
      };
      final color = switch (normalized) {
        'accepted' || 'active' => const Color(0xFF90A17D),
        'invited' || 'pending' => const Color(0xFFD48B4A),
        'declined' => const Color(0xFFB96D40),
        _ => const Color(0xFF7C7C7C),
      };

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    Widget liveChip() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF7BB26B).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
            color: Color(0xFF4E8A42),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    final focusMember = selectedMember != null &&
            visibleMembers.any((member) => member.userId == selectedMember.userId)
        ? selectedMember
        : null;

    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Walkers in this session',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
              Text(
                '${visibleMembers.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isWalkerSessionOverlayVisible = false;
                  });
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.visibility_off_rounded, size: 16),
                label: const Text('Hide'),
              ),
            ],
          ),
          if (_sharedSessionActionLabel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSessionBusy
                    ? null
                    : (_isSessionOwner
                        ? _endSharedSessionAction
                        : _leaveSharedSessionAction),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isSessionOwner
                      ? const Color(0xFFB96D40)
                      : const Color(0xFF90A17D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                icon: Icon(
                  _isSessionOwner
                      ? Icons.stop_circle_outlined
                      : Icons.logout_rounded,
                  size: 18,
                ),
                label: Text(_sharedSessionActionLabel!),
              ),
            ),
          ],
          if (focusMember != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: _memberColor(focusMember.userId),
                        child: Text(
                          (focusMember.username.isEmpty
                                  ? 'W'
                                  : focusMember.username[0])
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live walker preview',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface.withValues(alpha: 0.68),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              focusMember.username.isEmpty
                                  ? 'Walker'
                                  : focusMember.username,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (focusMember.isTracking) liveChip(),
                                statusChip(focusMember.status),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    focusMember.routePoints.length > 1
                        ? 'Route distance: ${_formatDistance(focusMember.distanceMeters)}'
                        : 'Route distance: not available yet',
                    style: TextStyle(fontSize: 13, color: colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Steps: ${focusMember.stepCount}',
                    style: TextStyle(fontSize: 13, color: colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  if (_memberFocusPoint(focusMember) == null)
                    Text(
                      'Location: Waiting for live location',
                      style: TextStyle(fontSize: 13, color: colors.onSurface),
                    )
                  else
                    FutureBuilder<String>(
                      future: _resolveLocationLabel(
                        _memberFocusPoint(focusMember)!,
                      ),
                      builder: (context, snapshot) {
                        final placeName =
                            snapshot.data?.trim().isNotEmpty == true
                                ? snapshot.data!.trim()
                                : 'Locating live area...';
                        return Text(
                          'Location: $placeName',
                          style: TextStyle(fontSize: 13, color: colors.onSurface),
                        );
                      },
                    ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        final point = _memberFocusPoint(focusMember);
                        if (point == null) return;
                        setState(() {
                          _isWalkerSessionOverlayVisible = false;
                          _selectedMarkerUserId = focusMember.userId;
                        });
                        _moveCamera(point, zoom: 17);
                      },
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Center map'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: visibleMembers.map((member) {
              final displayName =
                  member.username.isEmpty ? 'Walker' : member.username;
              final isSelected = selectedMember?.userId == member.userId;
              final memberPoint = _memberFocusPoint(member);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _selectedMarkerUserId =
                        isSelected ? null : member.userId;
                  });
                  if (!isSelected && memberPoint != null) {
                    _moveCamera(memberPoint, zoom: 17);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primary.withValues(alpha: 0.22)
                        : colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFB96D40)
                          : colors.primary.withValues(alpha: 0.24),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: _memberColor(member.userId),
                        child: Text(
                          displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 132,
                            child: Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (member.isTracking)
                            liveChip()
                          else
                            statusChip(member.status),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedWalkerSessionToggle() {
    final walkerCount =
        _sharedMembers.where((member) => member.userId.isNotEmpty).length;
    final colors = Theme.of(context).colorScheme;
    final labelColor = colors.onSurface.withValues(alpha: 0.72);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: colors.surface.withValues(alpha: 0.96),
        elevation: 3,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () {
            setState(() {
              _isWalkerSessionOverlayVisible = true;
            });
          },
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 18,
                  color: labelColor,
                ),
                const SizedBox(width: 8),
                Text(
                  walkerCount == 1
                      ? '1 walker hidden'
                      : '$walkerCount walkers hidden',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.visibility_rounded,
                  size: 18,
                  color: labelColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingInvitesOverlay() {
    final userId = _currentUserId;
    if (userId == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _api.watchInvites(),
      builder: (context, snapshot) {
        final pendingInvites = (snapshot.data ?? [])
            .where((invite) => (invite['status'] as String?) == 'pending')
            .toList();

        if (pendingInvites.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          children: pendingInvites.map((invite) {
            final fromUsername =
                (invite['fromUsername'] as String?)?.trim().isNotEmpty == true
                    ? invite['fromUsername'] as String
                    : 'Another walker';

            final colors = Theme.of(context).colorScheme;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$fromUsername invited you to a shared walk.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSessionBusy
                              ? null
                              : () => _acceptWalkInvite(invite),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF90A17D),
                          ),
                          child: const Text(
                            'Accept',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSessionBusy
                              ? null
                              : () => _declineWalkInvite(invite),
                          child: const Text('Decline'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _openInviteSheet() async {
    if (_currentUserId == null) return;
    final activeSessionId = _activeSessionId;
    final activeSessionStatus = _activeSessionStatus;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';
        final localInviteStatuses = <String, String>{};

        String statusLabelForUser({
          required String invitedUserId,
          required Map<String, dynamic>? sessionMember,
        }) {
          final status = (localInviteStatuses[invitedUserId] ??
                  (sessionMember?['status'] as String?))
              ?.trim()
              .toLowerCase();

          switch (status) {
            case 'accepted':
            case 'active':
              return 'Joined';
            case 'invited':
            case 'pending':
              return 'Pending';
            default:
              return 'Invite';
          }
        }

        bool canInviteUser({
          required String invitedUserId,
          required Map<String, dynamic>? sessionMember,
        }) {
          final status = (localInviteStatuses[invitedUserId] ??
                  (sessionMember?['status'] as String?))
              ?.trim()
              .toLowerCase();
          return status == null ||
              status.isEmpty ||
              status == 'declined';
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invite a Walker',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Search users and invite one to join your walk in real time.',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) {
                        setModalState(() {
                          searchQuery = value.trim().toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by username or email',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: const Color(0xFFFCF5EA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 360,
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: _fetchInviteUsers(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              snapshot.data == null) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('Unable to load users right now.'),
                              ),
                            );
                          }

                          final users = (snapshot.data ?? [])
                              .where((user) {
                                if (searchQuery.isEmpty) return true;
                                final username =
                                    (user['username'] as String).toLowerCase();
                                final email =
                                    (user['email'] as String).toLowerCase();
                                return username.contains(searchQuery) ||
                                    email.contains(searchQuery);
                              })
                              .toList();

                          if (users.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text('No users found.'),
                              ),
                            );
                          }

                          final sessionId = activeSessionId;
                          return FutureBuilder<List<Map<String, dynamic>>>(
                            future: sessionId == null ||
                                    !(activeSessionStatus == 'pending' ||
                                        activeSessionStatus == 'active')
                                ? Future.value(const <Map<String, dynamic>>[])
                                : _api.fetchMembers(sessionId),
                            builder: (context, membersSnapshot) {
                              final sessionMembers = {
                                for (final member in membersSnapshot.data ?? [])
                                  (member['userId'] as String?) ?? '':
                                      member,
                              };

                              return ListView.separated(
                                shrinkWrap: true,
                                itemCount: users.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  final username =
                                      (user['username'] as String).trim();
                                  final email = (user['email'] as String).trim();
                                  final invitedUserId = user['id'] as String;
                                  final sessionMember =
                                      sessionMembers[invitedUserId];
                                  final label = statusLabelForUser(
                                    invitedUserId: invitedUserId,
                                    sessionMember: sessionMember,
                                  );

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF90A17D),
                                      child: Text(
                                        (username.isNotEmpty
                                                ? username
                                                : email.isNotEmpty
                                                    ? email
                                                    : 'W')[0]
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      username.isEmpty
                                          ? 'Unnamed user'
                                          : username,
                                    ),
                                    subtitle:
                                        email.isEmpty ? null : Text(email),
                                    trailing: TextButton(
                                      onPressed:
                                          _isSessionBusy || !canInviteUser(
                                                  invitedUserId: invitedUserId,
                                                  sessionMember: sessionMember)
                                              ? null
                                              : () async {
                                                  final success =
                                                      await _createWalkInvite(
                                                          user);
                                                  if (!success || !mounted) {
                                                    return;
                                                  }
                                                  setModalState(() {
                                                    localInviteStatuses[
                                                        invitedUserId] =
                                                        'invited';
                                                  });
                                                },
                                      child: Text(label),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeReplayTimer?.cancel();
    _trackingController.removeListener(_handleTrackingControllerChanged);
    _sessionSubscription?.cancel();
    _memberSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialCenter = _currentPosition == null
        ? _defaultCenter
        : (_positionToLatLng(_currentPosition!) ?? _defaultCenter);
    final membersToDisplay = _displayMembers();
    final selectedMember =
        _memberById(membersToDisplay, _selectedMarkerUserId);
    final selectedMemberId = selectedMember?.userId;
    final polylines = membersToDisplay
        .where((member) => member.routePoints.length > 1)
        .map(
          (member) {
            final isSelected = selectedMemberId == member.userId;
            final isDimmed = selectedMemberId != null && !isSelected;
            final baseColor = _memberColor(member.userId);

            return Polyline(
              points: member.routePoints,
              strokeWidth: isSelected
                  ? 7
                  : member.userId == _currentUserId
                      ? 6
                      : 5,
              color: isDimmed
                  ? baseColor.withValues(alpha: 0.35)
                  : baseColor,
            );
          },
        )
        .toList();
    final markers = membersToDisplay
        .map((member) {
          final markerPoint = member.currentLocation ??
              (member.routePoints.isNotEmpty ? member.routePoints.last : null);
          final isSelected = _selectedMarkerUserId == member.userId;

          if (markerPoint == null) return null;

          return Marker(
            point: markerPoint,
            width: 180,
            height: isSelected ? 168 : 72,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedMarkerUserId = isSelected ? null : member.userId;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    Container(
                      width: 168,
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.username,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedMarkerUserId = null;
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.close, size: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Steps: ${member.stepCount}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Distance: ${_formatDistance(member.distanceMeters)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Time: ${_formatDuration(Duration(seconds: member.elapsedSeconds))}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          FutureBuilder<String>(
                            future: _resolveLocationLabel(markerPoint),
                            builder: (context, snapshot) {
                              final placeName =
                                  snapshot.data?.trim().isNotEmpty == true
                                      ? snapshot.data!.trim()
                                      : 'Locating live area...';
                              return Text(
                                'Location: $placeName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: const TextStyle(fontSize: 11),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  if (isSelected) const SizedBox(height: 6),
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _memberColor(member.userId),
                    child: Text(
                      member.username.isEmpty
                          ? 'W'
                          : member.username[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
    final replayRoutePoints =
        _isReplayingRecordedWalk && _replayRoutePoints.length > 1
            ? _replayRoutePoints
            : _selectedRecordedWalk?.routePoints ?? const <LatLng>[];
    final recordedWalkGuidePolyline = _selectedRecordedWalk != null &&
            _selectedRecordedWalk!.routePoints.length > 1
        ? Polyline(
            points: _selectedRecordedWalk!.routePoints,
            strokeWidth: 8,
            color: const Color(0x552E5BFF),
          )
        : null;
    final recordedWalkPolylineShadow = replayRoutePoints.length > 1
        ? Polyline(
            points: replayRoutePoints,
            strokeWidth: 9,
            color: const Color(0x663B2A1F),
          )
        : null;
    final recordedWalkPolyline = replayRoutePoints.length > 1
        ? Polyline(
            points: replayRoutePoints,
            strokeWidth: 5.5,
            color: const Color(0xFF2E5BFF),
          )
        : null;
    final recordedWalkMarkers = _selectedRecordedWalk == null
        ? const <Marker>[]
        : [
            if (_selectedRecordedWalk!.routePoints.isNotEmpty &&
                !_isReplayingRecordedWalk)
              Marker(
                point: _selectedRecordedWalk!.routePoints.first,
                width: 96,
                height: 48,
                child: _RouteBadge(
                  label: 'Start',
                  color: const Color(0xFF2E8B57),
                ),
              ),
            if (_selectedRecordedWalk!.routePoints.isNotEmpty &&
                !_isReplayingRecordedWalk)
              Marker(
                point: _selectedRecordedWalk!.routePoints.last,
                width: 96,
                height: 48,
                child: _RouteBadge(
                  label: 'End',
                  color: const Color(0xFFB96D40),
                ),
              ),
            if (_replayCurrentPoint != null)
              Marker(
                point: _replayCurrentPoint!,
                width: 52,
                height: 52,
                child: const _ReplayMarkerBadge(
                  color: Color(0xFF2E5BFF),
                ),
              ),
          ];
    final pendingInvitesOverlay = _buildPendingInvitesOverlay();
    final sharedSessionOverlay = _buildSharedSessionOverlay(selectedMember);
    final sharedSessionActionLabel = _sharedSessionActionLabel;
    final dockStatusText = _selectedRecordedWalk == null
        ? _statusText
        : (_isReplayingRecordedWalk
            ? 'Replaying the street route with follow zoom.'
            : 'Recorded walk ready. Replay to follow the route with cinematic zoom.');

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              iconTheme: IconThemeData(color: companyTheme.inkColor),
              centerTitle: false,
              titleSpacing: 0,
              title: LayoutBuilder(
                builder: (context, constraints) {
                  final useCompactTitle = constraints.maxWidth < 210;
                  return Text(
                    'Step Map',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: companyTheme.inkColor,
                      fontSize: useCompactTitle ? 18 : 20,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
              actions: [
                IconButton(
                  onPressed: _showRecordedWalksSheet,
                  icon: const Icon(Icons.history_rounded),
                  tooltip: 'Recorded walks',
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _useSatelliteTiles = !_useSatelliteTiles;
                    });
                  },
                  icon: Icon(
                    _useSatelliteTiles
                        ? Icons.layers_clear_rounded
                        : Icons.satellite_alt_rounded,
                  ),
                  tooltip: _useSatelliteTiles
                      ? 'Switch to street map'
                      : 'Switch to satellite map',
                ),
                IconButton(
                  onPressed: _isSessionBusy ? null : _openInviteSheet,
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: _currentPosition == null ? 11 : 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _useSatelliteTiles
                            ? _satelliteTileUrl
                            : _streetTileUrl,
                        userAgentPackageName: 'com.valenin.inneru',
                      ),
                      if (recordedWalkGuidePolyline != null)
                        PolylineLayer(
                          polylines: [recordedWalkGuidePolyline],
                        ),
                      if (recordedWalkPolylineShadow != null)
                        PolylineLayer(
                          polylines: [recordedWalkPolylineShadow],
                        ),
                      if (recordedWalkPolyline != null)
                        PolylineLayer(
                          polylines: [recordedWalkPolyline],
                        ),
                      if (polylines.isNotEmpty)
                        PolylineLayer(
                          polylines: polylines,
                        ),
                      if (recordedWalkMarkers.isNotEmpty)
                        MarkerLayer(
                          markers: recordedWalkMarkers,
                        ),
                      if (markers.isNotEmpty)
                        MarkerLayer(
                          markers: markers,
                        ),
                    ],
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pendingInvitesOverlay,
                      if (pendingInvitesOverlay is! SizedBox)
                        const SizedBox(height: 8),
                      if (_sharedMembers.isNotEmpty)
                        (_isWalkerSessionOverlayVisible
                            ? sharedSessionOverlay
                            : _buildCollapsedWalkerSessionToggle()),
                      if ((_sharedMembers.isNotEmpty &&
                              _isWalkerSessionOverlayVisible) ||
                          _useSatelliteTiles ||
                          _selectedRecordedWalk != null)
                        const SizedBox(height: 8),
                      if (_useSatelliteTiles)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _MapPill(
                            icon: Icons.satellite_alt_rounded,
                            label: 'Satellite view',
                            dark: true,
                          ),
                        ),
                      if (_selectedRecordedWalk != null) ...[
                        if (_useSatelliteTiles) const SizedBox(height: 8),
                        _ReplaySummaryCard(
                          title: 'Recorded Walk',
                          subtitle:
                              '${_formatRecordedWalkDate(_selectedRecordedWalk!.endedAt)} | ${_formatDistance(_selectedRecordedWalk!.distanceMeters)} | street replay',
                          isReplaying: _isReplayingRecordedWalk,
                          onClose: () =>
                              _resetRecordedWalkReplay(clearSelection: true),
                          onReplay: _isReplayingRecordedWalk
                              ? () => _resetRecordedWalkReplay()
                              : _startRecordedWalkReplay,
                          onShare: () =>
                              _shareRecordedWalk(_selectedRecordedWalk!),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isTrackerDockVisible)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: SafeArea(
                      top: false,
                      child: _BottomTrackerDock(
                        liveWalkerCount: _sharedMembers
                            .where((member) => member.isTracking)
                            .length,
                        steps: '$_sessionSteps',
                        distance: _formatDistance(_distanceMeters),
                        time: _formatDuration(_elapsed),
                        statusText: dockStatusText,
                        viewingRecordedWalk: _selectedRecordedWalk != null,
                        replayEnabled: _selectedRecordedWalk != null,
                        isReplaying: _isReplayingRecordedWalk,
                        sessionActionLabel: sharedSessionActionLabel,
                        onSessionAction: sharedSessionActionLabel == null
                            ? null
                            : (_isSessionOwner
                                ? _endSharedSessionAction
                                : _leaveSharedSessionAction),
                        isSessionOwner: _isSessionOwner,
                        onReplay: _selectedRecordedWalk == null
                            ? null
                            : (_isReplayingRecordedWalk
                                ? () => _resetRecordedWalkReplay()
                                : _startRecordedWalkReplay),
                        onCenterMap: selectedMember == null
                            ? (markers.isEmpty
                                ? null
                                : () {
                                    final point = markers.last.point;
                                    setState(() {
                                      _isWalkerSessionOverlayVisible = false;
                                      _selectedMarkerUserId = null;
                                    });
                                    _moveCamera(point, zoom: 17);
                                  })
                            : (_memberFocusPoint(selectedMember) == null
                                ? null
                                : () {
                                    final point =
                                        _memberFocusPoint(selectedMember)!;
                                    setState(() {
                                      _isWalkerSessionOverlayVisible = false;
                                      _selectedMarkerUserId =
                                          selectedMember.userId;
                                    });
                                    _moveCamera(point, zoom: 17);
                                  }),
                        onToggleVisibility: () {
                          setState(() {
                            _isTrackerDockVisible = false;
                          });
                        },
                        onStartStop:
                            _selectedRecordedWalk != null || _isResetting
                                ? null
                                : (_isTracking ? _stopTracking : _startTracking),
                        startStopLabel: _isResetting
                            ? 'Resetting...'
                            : _isPreparing
                                ? 'Preparing...'
                                : _isTracking
                                    ? 'Stop Tracking'
                                    : 'Start Tracking',
                        isTracking: _isTracking,
                        onReset: _selectedRecordedWalk != null ||
                                _isPreparing ||
                                _isResetting
                            ? null
                            : _resetSession,
                      ),
                    ),
                  )
                else
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: SafeArea(
                      top: false,
                      child: _CollapsedTrackerDockToggle(
                        onPressed: () {
                          setState(() {
                            _isTrackerDockVisible = true;
                          });
                        },
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
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.isTracking,
  });

  final String label;
  final String value;
  final bool isTracking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isTracking
                  ? (theme.brightness == Brightness.dark ? 0.24 : 0.42)
                  : (theme.brightness == Brightness.dark ? 0.42 : 1)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPill extends StatelessWidget {
  const _MapPill({
    required this.icon,
    required this.label,
    this.dark = false,
  });

  final IconData icon;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = dark
        ? Colors.black.withValues(alpha: 0.58)
        : theme.colorScheme.surface.withValues(alpha: 0.94);
    final foregroundColor = dark ? Colors.white : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteBounds {
  const _RouteBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}

class _ReplaySummaryCard extends StatelessWidget {
  const _ReplaySummaryCard({
    required this.title,
    required this.subtitle,
    required this.isReplaying,
    required this.onClose,
    required this.onReplay,
    required this.onShare,
  });

  final String title;
  final String subtitle;
  final bool isReplaying;
  final VoidCallback onClose;
  final VoidCallback onReplay;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onReplay,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.9),
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(
              isReplaying
                  ? Icons.pause_circle_outline_rounded
                  : Icons.directions_walk_rounded,
              size: 18,
            ),
            color: theme.colorScheme.onSurface,
            tooltip: isReplaying ? 'Stop replay' : 'Replay recorded walk',
          ),
          IconButton(
            onPressed: onShare,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.9),
              minimumSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(
              Icons.ios_share_rounded,
              size: 18,
            ),
            color: theme.colorScheme.onSurface,
            tooltip: 'Share walk image',
          ),
          TextButton(
            onPressed: onClose,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ReplayMarkerBadge extends StatelessWidget {
  const _ReplayMarkerBadge({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.directions_walk_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

class _BottomTrackerDock extends StatelessWidget {
  const _BottomTrackerDock({
    required this.liveWalkerCount,
    required this.steps,
    required this.distance,
    required this.time,
    required this.statusText,
    required this.viewingRecordedWalk,
    required this.replayEnabled,
    required this.isReplaying,
    required this.onReplay,
    required this.onCenterMap,
    required this.onToggleVisibility,
    required this.onStartStop,
    required this.startStopLabel,
    required this.isTracking,
    required this.onReset,
    required this.sessionActionLabel,
    required this.onSessionAction,
    required this.isSessionOwner,
  });

  final int liveWalkerCount;
  final String steps;
  final String distance;
  final String time;
  final String statusText;
  final bool viewingRecordedWalk;
  final bool replayEnabled;
  final bool isReplaying;
  final VoidCallback? onReplay;
  final VoidCallback? onCenterMap;
  final VoidCallback? onToggleVisibility;
  final VoidCallback? onStartStop;
  final String startStopLabel;
  final bool isTracking;
  final VoidCallback? onReset;
  final String? sessionActionLabel;
  final VoidCallback? onSessionAction;
  final bool isSessionOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveLabel = liveWalkerCount == 1
        ? '1 walker live'
        : '$liveWalkerCount walkers live';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: isTracking ? 0.58 : 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black26.withValues(alpha: isTracking ? 0.14 : 0.22),
            blurRadius: isTracking ? 12 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sessionActionLabel != null && onSessionAction != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSessionAction,
                icon: Icon(
                  isSessionOwner
                      ? Icons.stop_circle_rounded
                      : Icons.logout_rounded,
                ),
                label: Text(sessionActionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (liveWalkerCount > 0 || onCenterMap != null || onToggleVisibility != null) ...[
            Row(
              children: [
                if (liveWalkerCount > 0)
                  _MapPill(
                    icon: Icons.groups_rounded,
                    label: liveLabel,
                  ),
                if ((liveWalkerCount > 0 && (onCenterMap != null || onToggleVisibility != null)) ||
                    (onCenterMap != null && onToggleVisibility != null))
                  const Spacer(),
                if (onCenterMap != null)
                  IconButton(
                    onPressed: onCenterMap,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          theme.colorScheme.surface.withValues(alpha: 0.92),
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    color: theme.colorScheme.onSurface,
                    tooltip: 'Center map',
                  ),
                if (onToggleVisibility != null)
                  IconButton(
                    onPressed: onToggleVisibility,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          theme.colorScheme.surface.withValues(alpha: 0.92),
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.visibility_off_rounded, size: 18),
                    color: theme.colorScheme.onSurface,
                    tooltip: 'Hide tracker',
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              _StatTile(label: 'Steps', value: steps, isTracking: isTracking),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Distance',
                value: distance,
                isTracking: isTracking,
              ),
              const SizedBox(width: 8),
              _StatTile(label: 'Time', value: time, isTracking: isTracking),
            ],
          ),
          const SizedBox(height: 12),
          if (viewingRecordedWalk) ...[
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onReplay,
                style: IconButton.styleFrom(
                  backgroundColor:
                      theme.colorScheme.surface.withValues(alpha: 0.92),
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  isReplaying
                      ? Icons.pause_circle_outline_rounded
                      : Icons.directions_walk_rounded,
                  size: 18,
                ),
                color: theme.colorScheme.onSurface,
                tooltip: isReplaying ? 'Stop replay' : 'Replay recorded walk',
              ),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
              child: ElevatedButton(
                onPressed: onStartStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTracking
                      ? const Color(0xFF6D849A).withValues(alpha: 0.72)
                      : const Color(0xFFCE8F5A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                  child: Text(
                    startStopLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: onReset,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollapsedTrackerDockToggle extends StatelessWidget {
  const _CollapsedTrackerDockToggle({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      elevation: 4,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_rounded,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Show tracker',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _WalkSessionMember {
  const _WalkSessionMember({
    required this.userId,
    required this.username,
    required this.status,
    required this.isTracking,
    required this.stepCount,
    required this.distanceMeters,
    required this.elapsedSeconds,
    required this.currentLocation,
    required this.routePoints,
  });

  final String userId;
  final String username;
  final String status;
  final bool isTracking;
  final int stepCount;
  final double distanceMeters;
  final int elapsedSeconds;
  final LatLng? currentLocation;
  final List<LatLng> routePoints;

  factory _WalkSessionMember.fromApi(
    Map<String, dynamic> data,
    List<LatLng> Function(dynamic rawRoutePoints) routeParser,
  ) {
    final currentLocation = data['currentLocation'];
    LatLng? location;
    if (currentLocation is Map) {
      final lat = (currentLocation['latitude'] as num?)?.toDouble();
      final lng = (currentLocation['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        location = LatLng(lat, lng);
      }
    }

    return _WalkSessionMember(
      userId: (data['userId'] as String?) ?? '',
      username: (data['username'] as String?) ?? 'Walker',
      status: (data['status'] as String?) ?? 'accepted',
      isTracking: (data['isTracking'] as bool?) ?? false,
      stepCount: (data['stepCount'] as num?)?.toInt() ?? 0,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
      elapsedSeconds: (data['elapsedSeconds'] as num?)?.toInt() ?? 0,
      currentLocation: location,
      routePoints: routeParser(data['routePoints']),
    );
  }

}

class _RecordedWalk {
  const _RecordedWalk({
    required this.id,
    required this.endedAt,
    required this.stepCount,
    required this.distanceMeters,
    required this.elapsedSeconds,
    required this.routePoints,
  });

  final String id;
  final DateTime endedAt;
  final int stepCount;
  final double distanceMeters;
  final int elapsedSeconds;
  final List<LatLng> routePoints;

  factory _RecordedWalk.fromApi({
    required String id,
    required Map<String, dynamic> data,
    required List<LatLng> Function(dynamic rawRoutePoints) routeParser,
    required DateTime Function(dynamic value) timestampParser,
  }) {
    return _RecordedWalk(
      id: id,
      endedAt: timestampParser(data['endedAt']),
      stepCount: (data['stepCount'] as num?)?.toInt() ?? 0,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
      elapsedSeconds: (data['elapsedSeconds'] as num?)?.toInt() ?? 0,
      routePoints: routeParser(data['routePoints']),
    );
  }

}
