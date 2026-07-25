import { test } from 'node:test';
import assert from 'node:assert/strict';
import { serializeValue } from './export-firestore.js';

test('serializeValue converts a Firestore-Timestamp-like object to an ISO string', () => {
  const fakeTimestamp = { toDate: () => new Date('2025-01-15T10:00:00.000Z') };
  assert.equal(serializeValue(fakeTimestamp), '2025-01-15T10:00:00.000Z');
});

test('serializeValue passes through plain scalars unchanged', () => {
  assert.equal(serializeValue('hello'), 'hello');
  assert.equal(serializeValue(42), 42);
  assert.equal(serializeValue(true), true);
  assert.equal(serializeValue(null), null);
});

test('serializeValue recurses into arrays and plain objects', () => {
  const fakeTimestamp = { toDate: () => new Date('2025-01-15T10:00:00.000Z') };
  const result = serializeValue({
    items: [1, fakeTimestamp],
    nested: { createdAt: fakeTimestamp },
  });
  assert.deepEqual(result, {
    items: [1, '2025-01-15T10:00:00.000Z'],
    nested: { createdAt: '2025-01-15T10:00:00.000Z' },
  });
});
