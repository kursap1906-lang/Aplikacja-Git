import assert from 'node:assert/strict';
import test from 'node:test';
import { dummyPasswordHash, hashPassword, verifyPassword } from './passwords.ts';

test('stores only a salted scrypt hash and verifies the original password', async () => {
  const password = 'correct horse battery staple';
  const passwordHash = await hashPassword(password);

  assert.match(passwordHash, /^\$scrypt\$v1\$/);
  assert.notEqual(passwordHash, await hashPassword(password));
  assert.equal(await verifyPassword(password, passwordHash), true);
  assert.equal(await verifyPassword('incorrect password', passwordHash), false);
});

test('provides a valid fixed-cost dummy hash for unknown-user login checks', async () => {
  assert.equal(await verifyPassword('any user supplied password', dummyPasswordHash), false);
  assert.equal(await verifyPassword('password', 'invalid'), false);
});