import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';

void main() {
  group('AbundanceCompany.matches', () {
    test('matches the exact code, case-insensitively and trimmed', () {
      expect(AbundanceCompany.matches('ABU15DN', 'Some Other Name'), isTrue);
      expect(AbundanceCompany.matches('abu15dn', 'Some Other Name'), isTrue);
      expect(AbundanceCompany.matches('  ABU15DN  ', 'Some Other Name'), isTrue);
    });

    test('matches the exact name, case-insensitively and trimmed', () {
      expect(AbundanceCompany.matches('OTHERCODE', 'Abundance'), isTrue);
      expect(AbundanceCompany.matches('OTHERCODE', 'abundance'), isTrue);
      expect(AbundanceCompany.matches('OTHERCODE', '  ABUNDANCE  '), isTrue);
    });

    test('does not match near-miss codes or names', () {
      expect(AbundanceCompany.matches('A12', 'Abundance 12'), isFalse);
      expect(AbundanceCompany.matches('AB12X', 'Abundance 12'), isFalse);
      expect(AbundanceCompany.matches('ABU15DNX', 'Not Abundance'), isFalse);
      expect(AbundanceCompany.matches(null, null), isFalse);
      expect(AbundanceCompany.matches('', ''), isFalse);
    });
  });
}
