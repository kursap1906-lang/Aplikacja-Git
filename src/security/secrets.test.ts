import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createRandomToken,
  decryptSecret,
  encryptSecret,
  hashToken,
} from './secrets.ts';

const testKey = Buffer.alloc(32, 7).toString('base64url');

test('encrypts GitHub credentials and decrypts them only with the matching key', () => {
  const encrypted = encryptSecret('github-access-token', testKey);

  assert.notEqual(encrypted, 'github-access-token');
  assert.equal(decryptSecret(encrypted, testKey), 'github-access-token');
  assert.throws(() => decryptSecret(encrypted, Buffer.alloc(32, 9).toString('base64url')));
});

test('rejects incorrectly sized encryption keys', () => {
  assert.throws(() => encryptSecret('secret', 'not-a-32-byte-key'));
});

test('generates unique, hashable OAuth state tokens', () => {
  const first = createRandomToken();
  const second = createRandomToken();

  assert.notEqual(first, second);
  assert.notEqual(hashToken(first), first);
  assert.equal(hashToken(first).length, 64);
});