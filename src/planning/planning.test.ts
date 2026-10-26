import assert from 'node:assert/strict';
import test from 'node:test';
import { isValidTimezone, isWithinWorkWindows, parseCostCsv } from './planning.ts';

test('work windows honour the timezone', () => {
  const windows = [{ day: 1, start: '09:00', end: '17:00' }];
  const monday = new Date('2026-10-26T10:00:00Z');
  assert.equal(isWithinWorkWindows(monday, 'UTC', windows), true);
  assert.equal(isWithinWorkWindows(monday, 'Asia/Tokyo', windows), false);
  assert.equal(isWithinWorkWindows(new Date('2026-10-26T17:00:00Z'), 'UTC', windows), false);
  assert.equal(isValidTimezone('Europe/Warsaw'), true);
  assert.equal(isValidTimezone('Nope/Zone'), false);
});

test('cost CSV rejects bad rows and keeps categories separate', () => {
  const ok = parseCostCsv('date,category,amount,currency,description\n2026-10-01,usage,12.50,usd,"API, calls"\n2026-10-02,SUBSCRIPTION,10,USD,Plan');
  assert.deepEqual(ok.errors, []);
  assert.equal(ok.rows[0].amountMinor, 1250);
  assert.equal(ok.rows[0].description, 'API, calls');
  assert.equal(ok.rows[1].category, 'SUBSCRIPTION');
  assert.equal(parseCostCsv('a,b\n').errors.length, 1);
  assert.equal(parseCostCsv('date,category,amount,currency,description\n2026-13-99,USAGE,1,USD,x').errors.length, 1);
});
