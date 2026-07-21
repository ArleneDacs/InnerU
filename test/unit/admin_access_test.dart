import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/admin_access.dart';

void main() {
  group('AdminAccess.hasAdminRole', () {
    test('returns true when role is admin', () {
      expect(AdminAccess.hasAdminRole({'role': 'admin'}), isTrue);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(AdminAccess.hasAdminRole({'role': ' ADMIN '}), isTrue);
      expect(AdminAccess.hasAdminRole({'role': 'Admin'}), isTrue);
    });

    test('returns true when isAdmin flag is set', () {
      expect(AdminAccess.hasAdminRole({'isAdmin': true}), isTrue);
    });

    test('returns false for user and coach roles', () {
      expect(AdminAccess.hasAdminRole({'role': 'user'}), isFalse);
      expect(AdminAccess.hasAdminRole({'role': 'coach'}), isFalse);
    });

    test('returns false for null or empty data', () {
      expect(AdminAccess.hasAdminRole(null), isFalse);
      expect(AdminAccess.hasAdminRole({}), isFalse);
    });

    test('returns false when isAdmin is falsy or non-bool', () {
      expect(AdminAccess.hasAdminRole({'isAdmin': false}), isFalse);
      expect(AdminAccess.hasAdminRole({'isAdmin': 'true'}), isFalse);
    });
  });
}
