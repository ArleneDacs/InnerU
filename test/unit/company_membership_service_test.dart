import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';

void main() {
  group('CompanyMembershipService', () {
    test('prefers active company fields when resolving memberships', () {
      final data = {
        'companyMemberships': [
          {
            'companyId': 'legacy-id',
            'companyCode': 'LEGACY',
            'companyName': 'Legacy Company',
            'scoreMode': 'merged',
          },
          {
            'companyId': 'active-id',
            'companyCode': 'ACTIVE',
            'companyName': 'Active Company',
            'scoreMode': 'separate',
          },
        ],
        'companyId': 'legacy-id',
        'companyCode': 'LEGACY',
        'companyName': 'Legacy Company',
        'activeCompanyId': 'active-id',
        'activeCompanyCode': 'ACTIVE',
        'activeCompanyName': 'Active Company',
        'activeCompanyScoreMode': 'separate',
      };

      final membershipData = CompanyMembershipService.fromUserData(data);

      expect(membershipData.memberships, hasLength(2));
      expect(membershipData.activeMembership, isNotNull);
      expect(membershipData.activeMembership!.id, 'active-id');
      expect(membershipData.activeMembership!.code, 'ACTIVE');
      expect(membershipData.activeMembership!.scoreMode.id, 'separate');
    });

    test('lookup keys include active company identifiers first', () {
      final keys = CompanyMembershipService.lookupKeysFromUserData({
        'activeCompanyId': 'active-id',
        'activeCompanyCode': 'ACTIVE',
        'companyId': 'legacy-id',
        'companyCode': 'LEGACY',
        'companyIds': ['legacy-id', 'extra-id'],
        'companyCodes': ['LEGACY', 'EXTRA'],
      });

      expect(keys, containsAll([
        'active-id',
        'ACTIVE',
        'legacy-id',
        'LEGACY',
        'extra-id',
        'EXTRA',
      ]));
      expect(keys.first, 'active-id');
    });
  });
}
