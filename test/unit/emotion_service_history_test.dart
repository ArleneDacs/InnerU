import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';

void main() {
  group('EmotionService history', () {
    test('loads persisted local mood changes for the selected month', () async {
      SharedPreferences.setMockInitialValues({
        'emotion_history_user-1': [
          jsonEncode({
            'date': '2026-07-23',
            'emotion': 'happy',
            'loggedAt': '2026-07-23T08:15:00.000',
          }),
          jsonEncode({
            'date': '2026-07-23',
            'emotion': 'sad',
            'loggedAt': '2026-07-23T13:42:00.000',
          }),
          jsonEncode({
            'date': '2026-06-21',
            'emotion': 'angry',
            'loggedAt': '2026-06-21T11:00:00.000',
          }),
        ],
      });

      final service = EmotionService();
      final julyLogs = await service.loadLocalEmotionHistory(
        userId: 'user-1',
        month: '2026-07',
      );

      expect(julyLogs, hasLength(2));
      expect(julyLogs[0]['emotion'], 'happy');
      expect(julyLogs[1]['emotion'], 'sad');
      expect(julyLogs[1]['loggedAt'], '2026-07-23T13:42:00.000');
    });
  });
}
