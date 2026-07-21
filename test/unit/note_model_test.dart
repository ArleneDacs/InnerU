import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

void main() {
  group('Note.fromMap', () {
    Map<String, dynamic> baseData() => {
          'id': 'note-1',
          'userId': 'uid-1',
          'username': 'karina',
          'title': 'My note',
          'note': [
            {'type': 'text', 'value': 'hello'},
          ],
          'color': 0xFF80C8BC,
          'createdAt': Timestamp.fromDate(DateTime(2026, 7, 1, 12)),
          'category': 'personal',
          'saved': true,
        };

    test('parses a complete document', () {
      final note = Note.fromMap(baseData());

      expect(note.id, 'note-1');
      expect(note.userId, 'uid-1');
      expect(note.username, 'karina');
      expect(note.title, 'My note');
      expect(note.note, [
        {'type': 'text', 'value': 'hello'},
      ]);
      expect(note.color, 0xFF80C8BC);
      expect(note.createdAt, DateTime(2026, 7, 1, 12));
      expect(note.category, 'personal');
      expect(note.saved, isTrue);
    });

    test('defaults missing optional fields', () {
      final data = baseData()
        ..remove('id')
        ..remove('username')
        ..remove('title')
        ..remove('category')
        ..remove('saved');

      final note = Note.fromMap(data);

      expect(note.id, '');
      expect(note.username, '');
      expect(note.title, '');
      expect(note.category, '');
      expect(note.saved, isFalse);
    });

    test('parses color stored as string and falls back to white', () {
      final asString = baseData()..['color'] = '4286695612';
      expect(Note.fromMap(asString).color, 4286695612);

      final invalid = baseData()..['color'] = 'not-a-number';
      expect(Note.fromMap(invalid).color, 0xFFFFFFFF);
    });
  });

  group('Note.toJson', () {
    test('round-trips the persisted fields', () {
      final note = Note(
        id: 'note-2',
        userId: 'uid-2',
        username: 'coach-anna',
        title: 'Plan',
        note: [
          {'type': 'text', 'value': 'session notes'},
        ],
        color: 0xFFEFD199,
        createdAt: DateTime(2026, 7, 13),
        category: 'work',
        saved: true,
      );

      final json = note.toJson();

      expect(json['username'], 'coach-anna');
      expect(json['title'], 'Plan');
      expect(json['note'], note.note);
      expect(json['color'], 0xFFEFD199);
      expect(json['createdAt'], DateTime(2026, 7, 13));
      expect(json['category'], 'work');
      expect(json['userId'], 'uid-2');
      expect(json['saved'], isTrue);
    });
  });

  group('generateRandomLightShade', () {
    test('always produces an opaque light color', () {
      for (var i = 0; i < 200; i++) {
        final color = generateRandomLightShade();
        expect((color >> 24) & 0xFF, 0xFF, reason: 'alpha must be opaque');

        final red = (color >> 16) & 0xFF;
        final green = (color >> 8) & 0xFF;
        final blue = color & 0xFF;
        for (final channel in [red, green, blue]) {
          expect(channel, inInclusiveRange(0, 255));
        }
        // Lightened by at least 30%, so channels stay comfortably bright.
        expect((red + green + blue) / 3, greaterThan(100));
      }
    });
  });
}
