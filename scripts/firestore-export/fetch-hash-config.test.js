import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extractHashConfig } from './fetch-hash-config.js';

test('extractHashConfig maps a real-shaped Identity Toolkit response, including memoryCost -> memCost', () => {
  const body = {
    signIn: {
      hashConfig: {
        algorithm: 'SCRYPT',
        signerKey: 'signer-key-base64',
        saltSeparator: 'salt-separator-base64',
        rounds: 8,
        memoryCost: 14,
      },
    },
  };

  assert.deepEqual(extractHashConfig(body), {
    signerKey: 'signer-key-base64',
    saltSeparator: 'salt-separator-base64',
    rounds: 8,
    memCost: 14,
  });
});

test('extractHashConfig throws when hashConfig is missing', () => {
  assert.throws(() => extractHashConfig({ signIn: {} }), /SCRYPT/);
});

test('extractHashConfig throws when algorithm is not SCRYPT', () => {
  const body = { signIn: { hashConfig: { algorithm: 'STANDARD_SCRYPT' } } };
  assert.throws(() => extractHashConfig(body), /SCRYPT/);
});
