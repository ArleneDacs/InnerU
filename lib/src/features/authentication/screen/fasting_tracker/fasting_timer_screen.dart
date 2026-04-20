import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FastingTimerScreen extends StatefulWidget {
  const FastingTimerScreen({super.key});

  @override
  State<FastingTimerScreen> createState() => _FastingTimerScreenState();
}

class _FastingTimerScreenState extends State<FastingTimerScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<int> _fastingPlans = const [12, 14, 16, 18, 20];

  Timer? _timer;
  int _selectedHours = 16;
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFastingState();
  }

  String get _userId => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _fastingRef =>
      _firestore.collection('users').doc(_userId).collection('wellness').doc('fasting');

  CollectionReference<Map<String, dynamic>> get _historyRef =>
      _fastingRef.collection('history');

  Future<void> _loadFastingState() async {
    try {
      final snapshot = await _fastingRef.get();
      final data = snapshot.data();

      if (data != null) {
        setState(() {
          _selectedHours = (data['targetHours'] as num?)?.toInt() ?? 16;
          _startTime = (data['startTime'] as Timestamp?)?.toDate();
          _endTime = (data['endTime'] as Timestamp?)?.toDate();
        });

        if (_startTime != null && _endTime != null && DateTime.now().isBefore(_endTime!)) {
          _startTicker();
        }
      }
    } catch (error) {
      debugPrint('Failed to load fasting state: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startFast() async {
    final now = DateTime.now();
    final end = now.add(Duration(hours: _selectedHours));

    try {
      await _fastingRef.set({
        'targetHours': _selectedHours,
        'startTime': Timestamp.fromDate(now),
        'endTime': Timestamp.fromDate(end),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _startTime = now;
        _endTime = end;
      });
      _startTicker();
    } catch (error) {
      _showSnackBar('Failed to start fasting timer.');
    }
  }

  Future<void> _endFast() async {
    final startedAt = _startTime;
    final plannedEnd = _endTime;
    final finishedAt = DateTime.now();

    try {
      if (startedAt != null) {
        final durationHours =
            finishedAt.difference(startedAt).inMinutes / 60.0;
        await _historyRef.add({
          'targetHours': _selectedHours,
          'startTime': Timestamp.fromDate(startedAt),
          'plannedEndTime':
              plannedEnd == null ? null : Timestamp.fromDate(plannedEnd),
          'finishedAt': Timestamp.fromDate(finishedAt),
          'completedHours': double.parse(durationHours.toStringAsFixed(2)),
          'completedTarget':
              plannedEnd != null && !finishedAt.isBefore(plannedEnd),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _fastingRef.set({
        'targetHours': _selectedHours,
        'startTime': null,
        'endTime': null,
        'lastCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _timer?.cancel();
      setState(() {
        _startTime = null;
        _endTime = null;
      });
    } catch (error) {
      _showSnackBar('Failed to end fasting timer.');
    }
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_endTime != null && DateTime.now().isAfter(_endTime!)) {
        _timer?.cancel();
      }

      setState(() {});
    });
  }

  Duration _remainingTime() {
    if (_endTime == null) return Duration.zero;
    final remaining = _endTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double _progress() {
    if (_startTime == null || _endTime == null) return 0;
    final total = _endTime!.difference(_startTime!).inSeconds;
    if (total <= 0) return 0;
    final elapsed = DateTime.now().difference(_startTime!).inSeconds.clamp(0, total);
    return elapsed / total;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatHours(num value) {
    final formatted = value.toStringAsFixed(1);
    return formatted.endsWith('.0')
        ? '${value.toInt()}h'
        : '${formatted}h';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _startTime != null && _endTime != null;
    final progress = _progress();
    final remaining = _remainingTime();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fasting Timer'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF5EA),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Intermittent Fasting',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isActive
                              ? 'Your fasting session is running.'
                              : 'Choose a plan and start your next fasting window.',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 180,
                                height: 180,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 12,
                                  backgroundColor: Colors.white,
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF90A17D),
                                  ),
                                ),
                              ),
                              Column(
                                children: [
                                  Text(
                                    isActive
                                        ? _formatDuration(remaining)
                                        : '${_selectedHours}h',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isActive ? 'remaining' : 'selected plan',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 20),
                          Text(
                            'Started: ${_startTime.toString().substring(0, 16)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            'Ends: ${_endTime.toString().substring(0, 16)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Fasting Plans',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _fastingPlans.map((hours) {
                      return ChoiceChip(
                        label: Text('$hours hours'),
                        selected: _selectedHours == hours,
                        onSelected: isActive
                            ? null
                            : (_) {
                                setState(() {
                                  _selectedHours = hours;
                                });
                              },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isActive ? _endFast : _startFast,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isActive ? const Color(0xFF6D849A) : const Color(0xFFCE8F5A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        isActive ? 'End Fast' : 'Start Fast',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Fasting History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _historyRef
                        .orderBy('finishedAt', descending: true)
                        .limit(10)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final history = snapshot.data?.docs ?? [];

                      if (history.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No fasting history yet.'),
                        );
                      }

                      return Column(
                        children: history.map((doc) {
                          final data = doc.data();
                          final targetHours =
                              (data['targetHours'] as num?)?.toInt() ?? 0;
                          final completedHours =
                              (data['completedHours'] as num?) ?? 0;
                          final completedTarget =
                              (data['completedTarget'] as bool?) ?? false;
                          final finishedAt =
                              (data['finishedAt'] as Timestamp?)?.toDate();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(
                                '${_formatHours(completedHours)} completed',
                              ),
                              subtitle: Text(
                                '${finishedAt == null ? 'Unknown date' : finishedAt.toString().substring(0, 16)} • Goal ${targetHours}h',
                              ),
                              trailing: Text(
                                completedTarget ? 'Goal hit' : 'Ended early',
                                style: TextStyle(
                                  color: completedTarget
                                      ? const Color(0xFF90A17D)
                                      : const Color(0xFFCE8F5A),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
