import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  test('CoachMenteeGoals.fromJson parses a roster entry', () {
    final entry = CoachMenteeGoals.fromJson({
      'menteeId': '42',
      'menteeName': 'Maychell Alcorin',
      'goals': [
        {
          'id': 'g1',
          'userId': '42',
          'companyId': 'c1',
          'title': 'Run 100 km',
          'description': null,
          'notes': null,
          'status': 'IN_PROGRESS',
          'progress': 40,
          'category': 'PERSONAL',
          'goalType': 'MERIT',
          'targetPeriod': 'NONE',
          'direction': 'GAIN',
          'targetValue': 100,
          'currentValue': 40,
          'unit': 'km',
          'startDate': '2026-07-01T00:00:00.000Z',
          'targetDate': '2026-09-01T00:00:00.000Z',
          'completedAt': null,
        },
      ],
    });

    expect(entry.menteeId, '42');
    expect(entry.menteeName, 'Maychell Alcorin');
    expect(entry.goals, hasLength(1));
    expect(entry.goals.single.title, 'Run 100 km');
  });

  test('CoachMenteeGoals.fromJson tolerates a missing goals list', () {
    final entry = CoachMenteeGoals.fromJson({
      'menteeId': '7',
      'menteeName': 'No Goals Yet',
    });

    expect(entry.goals, isEmpty);
  });
}
