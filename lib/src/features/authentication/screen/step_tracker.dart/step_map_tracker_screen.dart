import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';

class StepMapTrackerScreen extends StatefulWidget {
  const StepMapTrackerScreen({super.key});

  @override
  State<StepMapTrackerScreen> createState() => _StepMapTrackerScreenState();
}

class _StepMapTrackerScreenState extends State<StepMapTrackerScreen> {
  static const LatLng _defaultCenter = LatLng(1.3521, 103.8198);
  static const int _minimumStepBurst = 3;
  static const Duration _stepBurstWindow = Duration(seconds: 6);
  static const int _maxSharedRoutePoints = 250;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _memberSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<StepCount>? _stepSubscription;
  Timer? _elapsedTimer;

  List<LatLng> _routePoints = [];
  Position? _currentPosition;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  int? _stepBaseline;
  int _lastRawSessionSteps = 0;
  int _pendingStepBurst = 0;
  int _sessionSteps = 0;
  double _distanceMeters = 0;
  bool _isTracking = false;
  bool _isPreparing = false;
  bool _isSessionBusy = false;
  String? _currentUserId;
  String _currentUsername = 'Walker';
  String? _activeSessionId;
  String? _activeSessionStatus;
  List<_WalkSessionMember> _sharedMembers = const [];
  String _statusText = 'Tap start to track your walk on the map.';
  Timer? _pendingStepTimer;

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
    _loadCurrentUser();
    _listenToWalkSessions();
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
    }, onError: (error) {
      debugPrint('Failed to listen to walk sessions: $error');
    });
  }

  Future<void> _syncSharedSessionMember() async {
    final userId = _currentUserId;
    final sessionId = _activeSessionId;
    if (userId == null || sessionId == null) return;

    final currentLocation = _currentPosition == null
        ? null
        : _positionToLatLng(_currentPosition!);

    try {
      await _firestore
          .collection('walk_sessions')
          .doc(sessionId)
          .collection('members')
          .doc(userId)
          .set({
        'userId': userId,
        'username': _currentUsername,
        'status': 'accepted',
        'isTracking': _isTracking,
        'stepCount': _sessionSteps,
        'routePoints': _serializeRoutePoints(_routePoints),
        'currentLocation': currentLocation == null
            ? null
            : GeoPoint(currentLocation.latitude, currentLocation.longitude),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore.collection('walk_sessions').doc(sessionId).set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Failed to sync shared walk session: $error');
    }
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

    if (_activeSessionId != null &&
        (_activeSessionStatus == 'pending' || _activeSessionStatus == 'active')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finish your current shared walk before inviting another user.'),
        ),
      );
      return;
    }

    setState(() {
      _isSessionBusy = true;
    });

    try {
      final sessionRef = _firestore.collection('walk_sessions').doc();
      final inviteRef = _firestore
          .collection('users')
          .doc(invitedUserId)
          .collection('walkInvites')
          .doc(sessionRef.id);
      final safeCurrentLocation = _currentPosition == null
          ? null
          : _positionToLatLng(_currentPosition!);

      final batch = _firestore.batch();

      batch.set(sessionRef, {
        'createdBy': userId,
        'createdByName': _currentUsername,
        'participantIds': [userId, invitedUserId],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(sessionRef.collection('members').doc(userId), {
        'userId': userId,
        'username': _currentUsername,
        'status': 'accepted',
        'isTracking': _isTracking,
        'stepCount': _sessionSteps,
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
        _activeSessionStatus = 'pending';
      });
      _listenToSessionMembers(sessionRef.id);
      Navigator.pop(context);
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

  Future<void> _startTracking() async {
    if (_isPreparing || _isTracking) return;

    setState(() {
      _isPreparing = true;
      _statusText = 'Checking location permissions...';
    });

    try {
      final hasAccess = await _ensureLocationAccess();
      if (!hasAccess) return;

      final currentPosition = await _getInitialPosition();
      if (currentPosition == null) {
        if (!mounted) return;
        setState(() {
          _statusText =
              'We could not get your location yet. Step outside or turn on GPS, then try again.';
        });
        return;
      }

      final startPoint = _positionToLatLng(currentPosition);
      if (startPoint == null) {
        if (!mounted) return;
        setState(() {
          _statusText =
              'Your device returned an invalid location. Please wait a moment and try again.';
        });
        return;
      }

      _positionSubscription?.cancel();
      _stepSubscription?.cancel();
      _elapsedTimer?.cancel();

      setState(() {
        _isTracking = true;
        _currentPosition = currentPosition;
        _routePoints = [startPoint];
        _distanceMeters = 0;
        _sessionSteps = 0;
        _stepBaseline = null;
        _lastRawSessionSteps = 0;
        _pendingStepBurst = 0;
        _startedAt = DateTime.now();
        _elapsed = Duration.zero;
        _statusText = 'Tracking your route...';
      });

      await _syncSharedSessionMember();
      _moveCamera(startPoint, zoom: 17);

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _startedAt == null) return;
        setState(() {
          _elapsed = DateTime.now().difference(_startedAt!);
        });
      });

      _stepSubscription = Pedometer.stepCountStream.listen(
        (event) {
          if (!mounted || !_isTracking) return;

          _stepBaseline ??= event.steps;
          final rawSessionSteps =
              ((event.steps - (_stepBaseline ?? event.steps)).clamp(0, 1000000))
                  .toInt();
          _handleRawSessionStepCount(rawSessionSteps);
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _statusText =
                'Route tracking is running, but live step updates are unavailable right now.';
          });
        },
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        _handlePositionUpdate,
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _statusText = 'Unable to update your location right now.';
          });
        },
      );
    } on LocationServiceDisabledException {
      if (!mounted) return;
      setState(() {
        _statusText = 'Location services are off. Please turn GPS on and try again.';
      });
    } on PermissionDeniedException {
      if (!mounted) return;
      setState(() {
        _statusText =
            'Location permission was denied. Please allow it to start map tracking.';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _statusText =
            'Getting your first GPS fix took too long. Please try again in an open area.';
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _statusText =
            'Map tracking needs a full app rebuild after adding location support. Please stop the app and run it again.';
      });
    } catch (error) {
      debugPrint('Step map tracker start failed: $error');
      if (!mounted) return;
      setState(() {
        _statusText = 'Could not start tracking: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPreparing = false;
        });
      }
    }
  }

  void _handleRawSessionStepCount(int rawSessionSteps) {
    final delta = rawSessionSteps - _lastRawSessionSteps;
    _lastRawSessionSteps = rawSessionSteps;

    if (delta <= 0) {
      return;
    }

    _pendingStepBurst += delta;
    _pendingStepTimer?.cancel();
    _pendingStepTimer = Timer(_stepBurstWindow, () {
      _pendingStepBurst = 0;
    });

    if (_pendingStepBurst >= _minimumStepBurst) {
      if (!mounted) return;
      setState(() {
        _sessionSteps += _pendingStepBurst;
      });
      _pendingStepBurst = 0;
      _pendingStepTimer?.cancel();
      _syncSharedSessionMember();
    }
  }

  void _handlePositionUpdate(Position position) {
    final nextPoint = _positionToLatLng(position);
    if (nextPoint == null) {
      if (!mounted) return;
      setState(() {
        _statusText =
            'Skipping one invalid location update. Tracking will continue.';
      });
      return;
    }

    final previousPoint = _routePoints.isNotEmpty ? _routePoints.last : null;

    if (previousPoint != null) {
      final segmentDistance = _distance(previousPoint, nextPoint);

      // Ignore tiny GPS jitter to keep the route cleaner.
      if (segmentDistance < 3) {
        setState(() {
          _currentPosition = position;
        });
        return;
      }

      _distanceMeters += segmentDistance;
    }

    setState(() {
      _currentPosition = position;
      _routePoints = [..._routePoints, nextPoint];
      _statusText = 'Tracking your route...';
    });

    _syncSharedSessionMember();
    _moveCamera(nextPoint);
  }

  Future<bool> _ensureLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _statusText = 'Turn on location services to start route tracking.';
        });
      }
      await Geolocator.openLocationSettings();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _statusText =
              'Location permission is needed to draw your walking route.';
        });
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }
      return false;
    }

    return true;
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

  void _stopTracking() {
    _positionSubscription?.cancel();
    _stepSubscription?.cancel();
    _elapsedTimer?.cancel();
    _pendingStepTimer?.cancel();
    _pendingStepBurst = 0;

    setState(() {
      _isTracking = false;
      _statusText = _routePoints.length > 1
          ? 'Session complete. You can review the route on screen or start again.'
          : 'Tracking stopped.';
    });
    _syncSharedSessionMember();
  }

  void _resetSession() {
    _positionSubscription?.cancel();
    _stepSubscription?.cancel();
    _elapsedTimer?.cancel();
    _pendingStepTimer?.cancel();

    setState(() {
      _isTracking = false;
      _routePoints = [];
      _currentPosition = null;
      _startedAt = null;
      _elapsed = Duration.zero;
      _stepBaseline = null;
      _lastRawSessionSteps = 0;
      _pendingStepBurst = 0;
      _sessionSteps = 0;
      _distanceMeters = 0;
      _statusText = 'Tap start to track your walk on the map.';
    });
    _syncSharedSessionMember();
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
        currentLocation: currentPoint,
        routePoints: _routePoints,
      ),
    ];
  }

  Widget _buildSharedSessionOverlay() {
    final memberNames = _sharedMembers
        .map((member) => member.username)
        .where((name) => name.trim().isNotEmpty)
        .join(', ');

    if (_activeSessionId == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Walk Together',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Invite another user and share your walk map in real time.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isSessionBusy ? null : _openInviteSheet,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Invite'),
            ),
          ],
        ),
      );
    }

    final isPending = _activeSessionStatus == 'pending';
    final isActive = _activeSessionStatus == 'active';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive ? Icons.groups_rounded : Icons.schedule_rounded,
                color: const Color(0xFFCE8F5A),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isActive ? 'Shared Walk Live' : 'Walk Invite Pending',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isActive || isPending)
                TextButton(
                  onPressed: _endSharedWalk,
                  child: const Text('End'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            memberNames.isEmpty
                ? (isPending
                    ? 'Waiting for the other walker to join.'
                    : 'Your shared walk is connected.')
                : 'Walkers: $memberNames',
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
          if (isPending) ...[
            const SizedBox(height: 8),
            const Text(
              'The session will become live as soon as the invited user accepts.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
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
    _sessionSubscription?.cancel();
    _memberSubscription?.cancel();
    _positionSubscription?.cancel();
    _stepSubscription?.cancel();
    _elapsedTimer?.cancel();
    _pendingStepTimer?.cancel();
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

          if (markerPoint == null) return null;

          return Marker(
            point: markerPoint,
            width: 70,
            height: 70,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    member.username,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
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
          );
        })
        .whereType<Marker>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Step Map Tracker'),
        actions: [
          IconButton(
            onPressed: _isSessionBusy ? null : _openInviteSheet,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: _currentPosition == null ? 11 : 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.selfcare_projects',
                    ),
                    if (polylines.isNotEmpty)
                      PolylineLayer(
                        polylines: polylines,
                      ),
                    if (markers.isNotEmpty)
                      MarkerLayer(
                        markers: markers,
                      ),
                  ],
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      _buildPendingInvitesOverlay(),
                      const SizedBox(height: 10),
                      _buildSharedSessionOverlay(),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.94),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                _StatTile(
                                  label: 'Steps',
                                  value: '$_sessionSteps',
                                ),
                                const SizedBox(width: 10),
                                _StatTile(
                                  label: 'Distance',
                                  value: _formatDistance(_distanceMeters),
                                ),
                                const SizedBox(width: 10),
                                _StatTile(
                                  label: 'Time',
                                  value: _formatDuration(_elapsed),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _statusText,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_sharedMembers.isNotEmpty)
                  Positioned(
                    bottom: 86,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_sharedMembers.where((member) => member.isTracking).length} walkers live',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 16,
                  right: 16,
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
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isTracking ? _stopTracking : _startTracking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isTracking
                            ? const Color(0xFF6D849A)
                            : const Color(0xFFCE8F5A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        _isPreparing
                            ? 'Preparing...'
                            : _isTracking
                                ? 'Stop Tracking'
                                : 'Start Tracking',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _resetSession,
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

class _WalkSessionMember {
  const _WalkSessionMember({
    required this.userId,
    required this.username,
    required this.status,
    required this.isTracking,
    required this.stepCount,
    required this.currentLocation,
    required this.routePoints,
  });

  final String userId;
  final String username;
  final String status;
  final bool isTracking;
  final int stepCount;
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
      currentLocation: currentLocation,
      routePoints: routeParser(data['routePoints']),
    );
  }
}
