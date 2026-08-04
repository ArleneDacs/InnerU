import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/api_client.dart';

void main() {
  group('ApiTimeoutException', () {
    test('carries a user-facing message by default', () {
      const exception = ApiTimeoutException();
      expect(exception.message, isNotEmpty);
      expect(exception.toString(), contains(exception.message));
    });

    test('accepts a custom message', () {
      const exception = ApiTimeoutException('custom timeout message');
      expect(exception.message, 'custom timeout message');
      expect(exception.toString(), contains('custom timeout message'));
    });
  });

  group('ApiException', () {
    test('formats status code and message', () {
      final exception = ApiException(404, 'Not found.');
      expect(exception.toString(), 'ApiException(404): Not found.');
    });
  });
}
