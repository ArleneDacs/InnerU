import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toExportShape } from './export-auth-users.js';

test('toExportShape maps a password-based UserRecord to the CLI export shape', () => {
  const userRecord = {
    uid: 'uid-1',
    email: 'jane@example.com',
    emailVerified: true,
    displayName: 'Jane',
    photoURL: 'https://x/jane.png',
    passwordHash: 'base64hash',
    passwordSalt: 'base64salt',
    providerData: [
      { providerId: 'password', uid: 'jane@example.com', email: 'jane@example.com', displayName: null, photoURL: null },
    ],
  };

  assert.deepEqual(toExportShape(userRecord), {
    localId: 'uid-1',
    email: 'jane@example.com',
    emailVerified: true,
    displayName: 'Jane',
    photoUrl: 'https://x/jane.png',
    providerUserInfo: [
      { providerId: 'password', rawId: 'jane@example.com', email: 'jane@example.com', displayName: null, photoUrl: null },
    ],
    passwordHash: 'base64hash',
    salt: 'base64salt',
  });
});

test('toExportShape omits passwordHash/salt for a provider-only account (e.g. Google sign-in)', () => {
  const userRecord = {
    uid: 'uid-2',
    email: 'google.user@example.com',
    emailVerified: true,
    displayName: null,
    photoURL: null,
    passwordHash: undefined,
    passwordSalt: undefined,
    providerData: [{ providerId: 'google.com', uid: '10987654321', email: 'google.user@example.com', displayName: null, photoURL: null }],
  };

  const result = toExportShape(userRecord);
  assert.equal('passwordHash' in result, false);
  assert.equal('salt' in result, false);
  assert.equal(result.providerUserInfo[0].providerId, 'google.com');
});

test('toExportShape handles an Apple sign-in account with a rawId', () => {
  const userRecord = {
    uid: 'uid-3',
    email: 'apple.user@example.com',
    emailVerified: true,
    displayName: null,
    photoURL: null,
    providerData: [{ providerId: 'apple.com', uid: 'apple-sub-123', email: 'apple.user@example.com', displayName: null, photoURL: null }],
  };

  const result = toExportShape(userRecord);
  assert.equal(result.providerUserInfo[0].providerId, 'apple.com');
  assert.equal(result.providerUserInfo[0].rawId, 'apple-sub-123');
});
