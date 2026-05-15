import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';

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

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Distance _distance = const Distance();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<StepCount>? _stepSubscription;
  Timer? _elapsedTimer;

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
  String? currentUserId;
  String currentUsername = 'Walker';
  String? activeSessionId;
  int _lastNotificationElapsedSeconds = -1;

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
      final coordinates = geometry is Map<String, dynamic>
          ? geometry['coordinates']
          : null;
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
      if (snappedDistance <= 0 ||
          snappedDistance > directDistance * 3.5 + 30) {
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

    final measuredSpeed = position.speed.isFinite && position.speed > 0
        ? position.speed
        : null;
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
    final status = await Permission.activityRecognition.request();
    if (status.isGranted) {
      return true;
    }

    statusText =
        'Activity recognition permission is needed to show live step counts.';
    _emit();

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
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
      statusText =
          'Location permission is needed to draw your walking route.';
      _emit();
      if (permission == LocationPermission.deniedForever && openSettings) {
        await Geolocator.openAppSettings();
      }
      return false;
    }

    return true;
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
      _isProcessingPositionUpdate = false;

      isTracking = true;
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

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (startedAt == null) return;
        elapsed = DateTime.now().difference(startedAt!);
        _emit();
        _updateWalkTrackingNotification();
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        _queuePositionUpdate,
        onError: (_) {
          statusText = 'Unable to update your location right now.';
          _emit();
        },
      );
    } on LocationServiceDisabledException {
      statusText = 'Location services are off. Please turn GPS on and try again.';
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
    _queuedPositionUpdate = position;
    if (_isProcessingPositionUpdate) {
      return;
    }

    _drainPositionQueue();
  }

  Future<void> _drainPositionQueue() async {
    _isProcessingPositionUpdate = true;

    while (_queuedPositionUpdate != null) {
      final nextPosition = _queuedPositionUpdate!;
      _queuedPositionUpdate = null;
      await _handlePositionUpdate(nextPosition);
    }

    _isProcessingPositionUpdate = false;
  }

  Future<void> _handlePositionUpdate(Position position) async {
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
        currentPosition = position;
        statusText =
            'Ignoring one noisy GPS jump to keep your route on the street.';
        _emit();
        return;
      }

      routePointsToAdd = await _buildStreetAlignedSegment(
        previousPoint,
        nextPoint,
      );
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

  Future<void> syncSharedSessionMember() async {
    final userId = currentUserId;
    final sessionId = activeSessionId;
    if (userId == null || sessionId == null) return;

    final livePosition = currentPosition == null
        ? null
        : positionToLatLng(currentPosition!);

    try {
      await _firestore
          .collection('walk_sessions')
          .doc(sessionId)
          .collection('members')
          .doc(userId)
          .set({
        'userId': userId,
        'username': currentUsername,
        'status': 'accepted',
        'isTracking': isTracking,
        'stepCount': sessionSteps,
        'distanceMeters': distanceMeters,
        'elapsedSeconds': elapsedSeconds,
        'routePoints': serializeRoutePoints(routePoints),
        'currentLocation': livePosition == null
            ? null
            : GeoPoint(livePosition.latitude, livePosition.longitude),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore.collection('walk_sessions').doc(sessionId).set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to sync shared walk session: $error');
    }
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    await _stepSubscription?.cancel();
    _elapsedTimer?.cancel();
    _positionSubscription = null;
    _stepSubscription = null;
    _queuedPositionUpdate = null;
    _isProcessingPositionUpdate = false;

    isTracking = false;
    statusText = routePoints.length > 1
        ? 'Session complete. You can review the route on screen or start again.'
        : 'Tracking stopped.';
    _lastNotificationElapsedSeconds = -1;
    _emit();
    await FastingNotificationService.instance.cancelWalkTrackingNotification();
    await syncSharedSessionMember();
  }

  Future<void> resetSession() async {
    await stopTracking();
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

class StepMapTrackerScreen extends StatefulWidget {
  const StepMapTrackerScreen({super.key});

  @override
  State<StepMapTrackerScreen> createState() => _StepMapTrackerScreenState();
}

class _StepMapTrackerScreenState extends State<StepMapTrackerScreen> {
  static const LatLng _defaultCenter = LatLng(1.3521, 103.8198);
  static const int _maxSharedRoutePoints = 500;
  static const String _streetTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _satelliteTileUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MapController _mapController = MapController();
  final _StepMapTrackingController _trackingController =
      _StepMapTrackingController.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _memberSubscription;
  Timer? _routeReplayTimer;

  List<LatLng> _routePoints = [];
  Position? _currentPosition;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  int _sessionSteps = 0;
  double _distanceMeters = 0;
  bool _isTracking = false;
  bool _isPreparing = false;
  bool _isSessionBusy = false;
  String? _currentUserId;
  String _currentUsername = 'Walker';
  String? _activeSessionId;
  String? _activeSessionStatus;
  String? _selectedMarkerUserId;
  _RecordedWalk? _selectedRecordedWalk;
  List<_WalkSessionMember> _sharedMembers = const [];
  String _statusText = 'Tap start to track your walk on the map.';
  bool _useSatelliteTiles = true;
  bool _isReplayingRecordedWalk = false;
  int _replayRouteIndex = 0;
  List<LatLng> _replayRoutePoints = const [];
  LatLng? _replayCurrentPoint;

  void _listenToSessionMembers(String? sessionId) {
    _memberSubscription?.cancel();

    if (sessionId == null || sessionId.isEmpty) {
      if (mounted) {
        setState(() {
          _sharedMembers = const [];
        });
      }
      return;
    }

    _memberSubscription = _firestore
        .collection('walk_sessions')
        .doc(sessionId)
        .collection('members')
        .snapshots()
        .listen((snapshot) {
      final members = snapshot.docs
          .map((doc) => _WalkSessionMember.fromFirestore(
                doc.data(),
                _deserializeRoutePoints,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _sharedMembers = members;
      });
    }, onError: (error) {
      debugPrint('Failed to listen to session members: $error');
    });
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _trackingController.addListener(_handleTrackingControllerChanged);
    _applyTrackingState(notify: false);
    _trackingController.updateUser(
      userId: _currentUserId,
      username: _currentUsername,
    );
    _loadCurrentUser();
    _listenToWalkSessions();
    _loadInitialMapPreview();
  }

  Future<void> _loadInitialMapPreview() async {
    await _trackingController.loadInitialMapPreview();
  }

  void _handleTrackingControllerChanged() {
    if (!mounted) return;
    _applyTrackingState();
  }

  void _applyTrackingState({bool notify = true}) {
    final currentPosition = _trackingController.currentPosition;
    final shouldMoveCamera = currentPosition != null;

    final updateState = () {
      _routePoints = List<LatLng>.from(_trackingController.routePoints);
      _currentPosition = currentPosition;
      _startedAt = _trackingController.startedAt;
      _elapsed = _trackingController.elapsed;
      _sessionSteps = _trackingController.sessionSteps;
      _distanceMeters = _trackingController.distanceMeters;
      _isTracking = _trackingController.isTracking;
      _isPreparing = _trackingController.isPreparing;
      _statusText = _trackingController.statusText;
    };

    if (notify && mounted) {
      setState(updateState);
    } else {
      updateState();
    }

    if (shouldMoveCamera) {
      final point = _positionToLatLng(currentPosition!);
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
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
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
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final data = userDoc.data() ?? {};
      final username = (data['username'] as String?)?.trim();

      if (!mounted) return;
      setState(() {
        _currentUsername = (username == null || username.isEmpty)
            ? (_auth.currentUser?.email?.split('@').first ?? 'Walker')
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

  void _listenToWalkSessions() {
    final userId = _currentUserId;
    if (userId == null) return;

    _sessionSubscription?.cancel();
    _sessionSubscription = _firestore
        .collection('walk_sessions')
        .where('participantIds', arrayContains: userId)
        .snapshots()
        .listen((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final status = doc.data()['status'] as String? ?? 'pending';
        return status == 'pending' || status == 'active';
      }).toList()
        ..sort((a, b) {
          final aDate = _timestampToDateTime(
              a.data()['updatedAt'] ?? a.data()['createdAt']);
          final bDate = _timestampToDateTime(
              b.data()['updatedAt'] ?? b.data()['createdAt']);
          return bDate.compareTo(aDate);
        });

      if (!mounted) return;

      if (docs.isEmpty) {
        setState(() {
          _activeSessionId = null;
          _activeSessionStatus = null;
          _sharedMembers = const [];
        });
        _trackingController.updateActiveSession(null);
        _listenToSessionMembers(null);
        return;
      }

      final activeDoc = docs.first;
      final nextSessionId = activeDoc.id;
      final nextStatus = activeDoc.data()['status'] as String? ?? 'pending';

      if (_activeSessionId != nextSessionId) {
        _listenToSessionMembers(nextSessionId);
      }

      setState(() {
        _activeSessionId = nextSessionId;
        _activeSessionStatus = nextStatus;
      });
      _trackingController.updateActiveSession(nextSessionId);
    }, onError: (error) {
      debugPrint('Failed to listen to walk sessions: $error');
    });
  }

  Future<void> _syncSharedSessionMember() async {
    _trackingController.updateUser(
      userId: _currentUserId,
      username: _currentUsername,
    );
    _trackingController.updateActiveSession(_activeSessionId);
    await _trackingController.syncSharedSessionMember();
  }

  Future<void> _createWalkInvite(Map<String, dynamic> invitedUser) async {
    final userId = _currentUserId;
    final invitedUserId = invitedUser['id'] as String?;
    final invitedUsername = (invitedUser['username'] as String?)?.trim();

    if (userId == null ||
        invitedUserId == null ||
        invitedUserId.isEmpty ||
        invitedUsername == null ||
        invitedUsername.isEmpty) {
      return;
    }

    setState(() {
      _isSessionBusy = true;
    });

    try {
      final hasReusableSession = _activeSessionId != null &&
          (_activeSessionStatus == 'pending' ||
              _activeSessionStatus == 'active');
      final sessionRef = hasReusableSession
          ? _firestore.collection('walk_sessions').doc(_activeSessionId)
          : _firestore.collection('walk_sessions').doc();
      final inviteRef = _firestore
          .collection('users')
          .doc(invitedUserId)
          .collection('walkInvites')
          .doc(sessionRef.id);
      final safeCurrentLocation = _currentPosition == null
          ? null
          : _positionToLatLng(_currentPosition!);

      final batch = _firestore.batch();

      final existingInvite = await inviteRef.get();
      final existingMember = await sessionRef
          .collection('members')
          .doc(invitedUserId)
          .get();

      if (existingInvite.exists || existingMember.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$invitedUsername is already in this walk session.'),
          ),
        );
        return;
      }

      batch.set(
        sessionRef,
        {
          'createdBy': userId,
          'createdByName': _currentUsername,
          'participantIds': FieldValue.arrayUnion([userId, invitedUserId]),
          'status': hasReusableSession
              ? (_activeSessionStatus ?? 'pending')
              : 'pending',
          if (!hasReusableSession) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      batch.set(sessionRef.collection('members').doc(userId), {
        'userId': userId,
        'username': _currentUsername,
        'status': 'accepted',
        'isTracking': _isTracking,
        'stepCount': _sessionSteps,
        'distanceMeters': _distanceMeters,
        'elapsedSeconds': _elapsedSeconds(),
        'routePoints': _serializeRoutePoints(_routePoints),
        'currentLocation': safeCurrentLocation == null
            ? null
            : GeoPoint(
                safeCurrentLocation.latitude,
                safeCurrentLocation.longitude,
              ),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(sessionRef.collection('members').doc(invitedUserId), {
        'userId': invitedUserId,
        'username': invitedUsername,
        'status': 'invited',
        'isTracking': false,
        'stepCount': 0,
        'distanceMeters': 0,
        'elapsedSeconds': 0,
        'routePoints': const [],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(inviteRef, {
        'sessionId': sessionRef.id,
        'fromUserId': userId,
        'fromUsername': _currentUsername,
        'toUserId': invitedUserId,
        'toUsername': invitedUsername,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;
      setState(() {
        _activeSessionId = sessionRef.id;
        _activeSessionStatus =
            hasReusableSession ? (_activeSessionStatus ?? 'pending') : 'pending';
      });
      _trackingController.updateActiveSession(sessionRef.id);
      _listenToSessionMembers(sessionRef.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Walk invite sent to $invitedUsername.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send walk invite: $error'),
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

  Future<void> _acceptWalkInvite(Map<String, dynamic> inviteData) async {
    final userId = _currentUserId;
    final sessionId = inviteData['sessionId'] as String?;
    if (userId == null || sessionId == null || sessionId.isEmpty) return;

    setState(() {
      _isSessionBusy = true;
    });

    try {
      final batch = _firestore.batch();
      final sessionRef = _firestore.collection('walk_sessions').doc(sessionId);
      final inviteRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('walkInvites')
          .doc(sessionId);
      final safeCurrentLocation = _currentPosition == null
          ? null
          : _positionToLatLng(_currentPosition!);

      batch.set(sessionRef, {
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(sessionRef.collection('members').doc(userId), {
        'userId': userId,
        'username': _currentUsername,
        'status': 'accepted',
        'isTracking': _isTracking,
        'stepCount': _sessionSteps,
        'distanceMeters': _distanceMeters,
        'elapsedSeconds': _elapsedSeconds(),
        'routePoints': _serializeRoutePoints(_routePoints),
        'currentLocation': safeCurrentLocation == null
            ? null
            : GeoPoint(
                safeCurrentLocation.latitude,
                safeCurrentLocation.longitude,
              ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(inviteRef, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      if (!mounted) return;
      setState(() {
        _activeSessionId = sessionId;
        _activeSessionStatus = 'active';
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
    final userId = _currentUserId;
    final sessionId = inviteData['sessionId'] as String?;
    if (userId == null || sessionId == null || sessionId.isEmpty) return;

    try {
      final batch = _firestore.batch();
      final sessionRef = _firestore.collection('walk_sessions').doc(sessionId);
      final inviteRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('walkInvites')
          .doc(sessionId);

      batch.set(sessionRef, {
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(sessionRef.collection('members').doc(userId), {
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(inviteRef, {
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to decline walk invite: $error'),
        ),
      );
    }
  }

  Future<void> _endSharedWalk() async {
    final sessionId = _activeSessionId;
    if (sessionId == null) return;

    try {
      await _firestore.collection('walk_sessions').doc(sessionId).set({
        'status': 'ended',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to end shared walk: $error'),
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
    if (!_isValidLatitude(point.latitude) || !_isValidLongitude(point.longitude)) {
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
    return 16.2 + (eased * 1.2);
  }

  void _moveReplayCamera(LatLng point, double progress) {
    _moveCamera(point, zoom: _replayZoomForProgress(progress));
  }

  Future<void> _stopTracking() async {
    final shouldSave = _isTracking && _routePoints.length > 1;
    await _trackingController.stopTracking();
    if (shouldSave) {
      await _saveRecordedWalk();
    }
  }

  Future<void> _resetSession() async {
    await _trackingController.resetSession();
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
      }
    });
  }

  void _startRecordedWalkReplay() {
    final walk = _selectedRecordedWalk;
    if (walk == null || walk.routePoints.length < 2) {
      return;
    }

    _routeReplayTimer?.cancel();

    final totalPoints = walk.routePoints.length;
    final intervalMs = (18000 / totalPoints).round().clamp(90, 450);

    setState(() {
      _isReplayingRecordedWalk = true;
      _replayRouteIndex = 1;
      _replayRoutePoints = walk.routePoints.take(1).toList();
      _replayCurrentPoint = walk.routePoints.first;
    });
    _moveReplayCamera(walk.routePoints.first, 0);

    _routeReplayTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_selectedRecordedWalk == null ||
            _replayRouteIndex >= walk.routePoints.length) {
          timer.cancel();
          setState(() {
            _isReplayingRecordedWalk = false;
            _replayRoutePoints = List<LatLng>.from(walk.routePoints);
            _replayCurrentPoint = walk.routePoints.last;
          });
          return;
        }

        final nextPoint = walk.routePoints[_replayRouteIndex];
        final nextIndex = _replayRouteIndex + 1;
        final progress = (nextIndex / walk.routePoints.length).clamp(0.0, 1.0);
        setState(() {
          _replayRouteIndex = nextIndex;
          _replayRoutePoints =
              walk.routePoints.take(_replayRouteIndex).toList();
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
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('recorded_walks')
          .doc(docId)
          .set({
        'userId': userId,
        'username': _currentUsername,
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': Timestamp.fromDate(endedAt),
        'stepCount': _sessionSteps,
        'distanceMeters': _distanceMeters,
        'elapsedSeconds': _elapsedSeconds(),
        'routePoints': _serializeRoutePoints(_routePoints),
      }, SetOptions(merge: true));
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
    final userId = _currentUserId;
    if (userId == null) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('recorded_walks')
                  .orderBy('endedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                final walks = (snapshot.data?.docs ?? [])
                    .map((doc) => _RecordedWalk.fromFirestore(
                          id: doc.id,
                          data: doc.data(),
                          routeParser: _deserializeRoutePoints,
                          timestampParser: _timestampToDateTime,
                        ))
                    .where((walk) => walk.routePoints.length > 1)
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    if (walks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text('No recorded walks yet.'),
                      )
                    else
                      SizedBox(
                        height: 360,
                        child: ListView.separated(
                          shrinkWrap: true,
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
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(_formatRecordedWalkDate(walk.endedAt)),
                              subtitle: Text(
                                '${_formatDistance(walk.distanceMeters)} | ${walk.stepCount} steps | ${_formatDuration(Duration(seconds: walk.elapsedSeconds))}',
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _openRecordedWalk(walk);
                                    },
                                    child: Text(isSelected ? 'Opened' : 'Open'),
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteRecordedWalk(walk),
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
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('recorded_walks')
          .doc(walk.id)
          .delete();

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

    final currentPoint = _currentPosition == null
        ? null
        : _positionToLatLng(_currentPosition!);

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

  Widget _buildSharedSessionOverlay() {
    return const SizedBox.shrink();
  }

  Widget _buildPendingInvitesOverlay() {
    final userId = _currentUserId;
    if (userId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('users')
          .doc(userId)
          .collection('walkInvites')
          .snapshots(),
      builder: (context, snapshot) {
        final pendingInvites = (snapshot.data?.docs ?? [])
            .map((doc) => doc.data())
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

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7EA),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$fromUsername invited you to a shared walk.',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
    final userId = _currentUserId;
    if (userId == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';

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
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _firestore.collection('users').snapshots(),
                        builder: (context, snapshot) {
                          final users = (snapshot.data?.docs ?? [])
                              .map((doc) => {
                                    'id': doc.id,
                                    'username':
                                        (doc.data()['username'] as String?) ??
                                            '',
                                    'email':
                                        (doc.data()['email'] as String?) ?? '',
                                  })
                              .where((user) => user['id'] != userId)
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

                          return ListView.separated(
                            shrinkWrap: true,
                            itemCount: users.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final user = users[index];
                              final username = (user['username'] as String).trim();
                              final email = (user['email'] as String).trim();

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
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  username.isEmpty ? 'Unnamed user' : username,
                                ),
                                subtitle:
                                    email.isEmpty ? null : Text(email),
                                trailing: TextButton(
                                  onPressed: _isSessionBusy
                                      ? null
                                      : () => _createWalkInvite(user),
                                  child: const Text('Invite'),
                                ),
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
    final polylines = membersToDisplay
        .where((member) => member.routePoints.length > 1)
        .map(
          (member) => Polyline(
            points: member.routePoints,
            strokeWidth: member.userId == _currentUserId ? 6 : 5,
            color: _memberColor(member.userId),
          ),
        )
        .toList();
    final markers = membersToDisplay
        .map((member) {
          final markerPoint =
              member.currentLocation ?? (member.routePoints.isNotEmpty
                  ? member.routePoints.last
                  : null);
          final isSelected = _selectedMarkerUserId == member.userId;

          if (markerPoint == null) return null;

          return Marker(
            point: markerPoint,
            width: 180,
            height: isSelected ? 132 : 72,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedMarkerUserId = isSelected ? null : member.userId;
                });
              },
              child: Column(
                children: [
                  if (isSelected)
                    Container(
                      width: 168,
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
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
    final replayRoutePoints = _isReplayingRecordedWalk &&
            _replayRoutePoints.length > 1
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
                width: 110,
                height: 52,
                child: const _RouteBadge(
                  label: 'Replay',
                  color: Color(0xFF2E5BFF),
                ),
              ),
          ];
    final pendingInvitesOverlay = _buildPendingInvitesOverlay();
    final sharedSessionOverlay = _buildSharedSessionOverlay();
    final dockStatusText = _selectedRecordedWalk == null
        ? _statusText
        : (_isReplayingRecordedWalk
            ? 'Replaying the street route with follow zoom.'
            : 'Recorded walk ready. Replay to follow the route with cinematic zoom.');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Step Map Tracker'),
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
                  urlTemplate:
                      _useSatelliteTiles ? _satelliteTileUrl : _streetTileUrl,
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
                sharedSessionOverlay,
                if (_useSatelliteTiles || _selectedRecordedWalk != null)
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
                  ),
                ],
              ],
            ),
          ),
          if (_sharedMembers.isNotEmpty)
            Positioned(
              left: 16,
              bottom: 206,
              child: _MapPill(
                icon: Icons.groups_rounded,
                label:
                    '${_sharedMembers.where((member) => member.isTracking).length} walkers live',
              ),
            ),
          Positioned(
            right: 16,
            bottom: 206,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              onPressed: markers.isEmpty
                  ? null
                  : () => _moveCamera(markers.last.point, zoom: 17),
              child: const Icon(
                Icons.my_location,
                color: Color(0xFFCE8F5A),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: _BottomTrackerDock(
                steps: '$_sessionSteps',
                distance: _formatDistance(_distanceMeters),
                time: _formatDuration(_elapsed),
                statusText: dockStatusText,
                viewingRecordedWalk: _selectedRecordedWalk != null,
                replayEnabled: _selectedRecordedWalk != null,
                isReplaying: _isReplayingRecordedWalk,
                onReplay: _selectedRecordedWalk == null
                    ? null
                    : (_isReplayingRecordedWalk
                        ? () => _resetRecordedWalkReplay()
                        : _startRecordedWalkReplay),
                onStartStop: _selectedRecordedWalk != null
                    ? null
                    : (_isTracking ? _stopTracking : _startTracking),
                startStopLabel: _isPreparing
                    ? 'Preparing...'
                    : _isTracking
                        ? 'Stop Tracking'
                        : 'Start Tracking',
                isTracking: _isTracking,
                onReset: _selectedRecordedWalk != null ? null : _resetSession,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFCF5EA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
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
    final backgroundColor =
        dark ? Colors.black.withOpacity(0.58) : Colors.white.withOpacity(0.94);
    final foregroundColor = dark ? Colors.white : Colors.black87;

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

class _ReplaySummaryCard extends StatelessWidget {
  const _ReplaySummaryCard({
    required this.title,
    required this.subtitle,
    required this.isReplaying,
    required this.onClose,
    required this.onReplay,
  });

  final String title;
  final String subtitle;
  final bool isReplaying;
  final VoidCallback onClose;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onReplay,
            child: Text(isReplaying ? 'Stop Replay' : 'Replay'),
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

class _BottomTrackerDock extends StatelessWidget {
  const _BottomTrackerDock({
    required this.steps,
    required this.distance,
    required this.time,
    required this.statusText,
    required this.viewingRecordedWalk,
    required this.replayEnabled,
    required this.isReplaying,
    required this.onReplay,
    required this.onStartStop,
    required this.startStopLabel,
    required this.isTracking,
    required this.onReset,
  });

  final String steps;
  final String distance;
  final String time;
  final String statusText;
  final bool viewingRecordedWalk;
  final bool replayEnabled;
  final bool isReplaying;
  final VoidCallback? onReplay;
  final VoidCallback? onStartStop;
  final String startStopLabel;
  final bool isTracking;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StatTile(label: 'Steps', value: steps),
              const SizedBox(width: 8),
              _StatTile(label: 'Distance', value: distance),
              const SizedBox(width: 8),
              _StatTile(label: 'Time', value: time),
            ],
          ),
          const SizedBox(height: 12),
          if (viewingRecordedWalk) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReplay,
                    icon: Icon(
                      isReplaying
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(
                      isReplaying
                          ? 'Stop Route Replay'
                          : 'Replay Recorded Walk',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              statusText,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
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
                        ? const Color(0xFF6D849A)
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

  factory _WalkSessionMember.fromFirestore(
    Map<String, dynamic> data,
    List<LatLng> Function(dynamic rawRoutePoints) routeParser,
  ) {
    final rawPoint = data['currentLocation'];
    LatLng? currentLocation;

    if (rawPoint is GeoPoint) {
      currentLocation = LatLng(rawPoint.latitude, rawPoint.longitude);
    }

    return _WalkSessionMember(
      userId: (data['userId'] as String?) ?? '',
      username: (data['username'] as String?) ?? 'Walker',
      status: (data['status'] as String?) ?? 'accepted',
      isTracking: (data['isTracking'] as bool?) ?? false,
      stepCount: (data['stepCount'] as num?)?.toInt() ?? 0,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
      elapsedSeconds: (data['elapsedSeconds'] as num?)?.toInt() ?? 0,
      currentLocation: currentLocation,
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

  factory _RecordedWalk.fromFirestore({
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
