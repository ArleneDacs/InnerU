import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/utils/grapheme_text.dart';

void main() {
  group('truncateToGraphemeClusters', () {
    test('does not split a standalone emoji at the preview boundary', () {
      final prefix = List<String>.filled(149, 'a').join();
      final text = '$prefix🎂🎉';

      expect(
        truncateToGraphemeClusters(text, 150),
        '$prefix🎂',
      );
    });

    test('does not split a composed emoji sequence at the preview boundary',
        () {
      final prefix = List<String>.filled(149, 'a').join();
      const family = '👨‍👩‍👧‍👦';
      final text = '$prefix${family}x';

      expect(
        truncateToGraphemeClusters(text, 150),
        '$prefix$family',
      );
    });

    test('leaves text within the limit unchanged', () {
      const text = 'Mom’s Birthday 🎂🎉';

      expect(truncateToGraphemeClusters(text, 150), text);
    });
  });
}
