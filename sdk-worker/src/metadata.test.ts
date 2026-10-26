import assert from 'node:assert/strict';
import test from 'node:test';
import { metadataJson, quotaSchema } from './metadata.ts';

test('quota metadata keeps real entitlements, overage flags and unknown quota types', () => {
  const snapshot = {
    isUnlimitedEntitlement: false, entitlementRequests: 300, usedRequests: 100,
    usageAllowedWithExhaustedQuota: false, remainingPercentage: 66.666,
    overage: 0, overageAllowedWithExhaustedQuota: false, resetDate: '2026-11-01',
  };
  const parsed = quotaSchema.parse({ quotaSnapshots: { ai_credits: snapshot } });
  assert.deepEqual(parsed.quotaSnapshots.ai_credits, snapshot);
  assert.deepEqual(quotaSchema.parse({ quotaSnapshots: {} }).quotaSnapshots, {});
  assert.equal(quotaSchema.safeParse({ quotaSnapshots: { ai_credits: { ...snapshot, usedRequests: -1 } } }).success, false);
  assert.equal(quotaSchema.safeParse({ quotaSnapshots: { ai_credits: { ...snapshot, overageAllowedWithExhaustedQuota: null } } }).success, false);
  assert.equal(quotaSchema.safeParse({ quotaSnapshots: { ai_credits: { entitlementRequests: 300 } } }).success, false);
  assert.equal(quotaSchema.safeParse({}).success, false);
});

test('SDK metadata JSON preserves missing prices instead of inventing free usage', () => {
  assert.deepEqual(metadataJson({ models: [{ id: 'auto', tokenPrices: null }], priceUnits: { units: [] } }), {
    models: [{ id: 'auto', tokenPrices: null }], priceUnits: { units: [] },
  });
  assert.throws(() => metadataJson({ data: 'x'.repeat(1024 * 1024) }), /safety limit/);
  assert.throws(() => metadataJson(null));
  assert.throws(() => metadataJson({ invalid: Number.NaN }));
  assert.throws(() => metadataJson({ models: undefined }));
});
