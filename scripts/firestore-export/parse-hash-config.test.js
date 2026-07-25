import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseHashConfig } from './parse-hash-config.js';

test('parseHashConfig extracts all four SCRYPT parameters from CLI log output', () => {
  const log = `
Exporting accounts to snapshot/auth-users.json
Exported 42 account(s) successfully.
IMPORTANT: The following hash parameters are required to migrate these accounts:
base64_signer_key: ABCDefgh1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP==
base64_salt_separator: Bw==
rounds: 8
mem_cost: 14
`;
  assert.deepEqual(parseHashConfig(log), {
    signerKey: 'ABCDefgh1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP==',
    saltSeparator: 'Bw==',
    rounds: 8,
    memCost: 14,
  });
});

test('parseHashConfig throws a clear error when a parameter is missing', () => {
  assert.throws(() => parseHashConfig('no hash config here'), /could not find/i);
});
