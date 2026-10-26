import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../../src/generated/prisma/client.ts';
import { createApp } from '../../src/app.ts';
import { parseConfig } from '../../src/config.ts';
import { encryptSecret } from '../../src/security/secrets.ts';
import { processMetadataJob } from './metadata-jobs.ts';
import { metadataJson } from './metadata.ts';

test('cost policy and SDK quotas persist with strict ownership, fencing and explicit failures', async (context) => {
  const databaseUrl = process.env.WORKSPACE_TEST_DATABASE_URL;
  if (!databaseUrl) throw new Error('A disposable integration database is required.');
  const url = new URL(databaseUrl);
  if (url.hostname !== 'workspace-db' || url.pathname !== '/workspace_integration') throw new Error('Unsafe metadata integration database.');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  const encryptionKey = Buffer.alloc(32, 11).toString('base64url');
  const config = parseConfig({
    NODE_ENV: 'test', DATABASE_URL: databaseUrl, APP_ORIGIN: 'http://workspace.example.test',
    APP_ENCRYPTION_KEY: encryptionKey, SDK_METADATA_ENABLED: 'true',
  });
  let app = createApp({ prisma, config });
  context.after(() => app.close());
  const register = async () => {
    const response = await app.inject({
      method: 'POST', url: '/api/auth/register',
      payload: { email: `metadata+${randomUUID()}@workspace.example.test`, password: 'Synthetic-password-12345' },
    });
    assert.equal(response.statusCode, 201, response.body);
    const body = response.json();
    return { userId: body.user.id as string, headers: { authorization: `Bearer ${body.sessionToken}`, 'x-csrf-token': body.csrfToken as string } };
  };
  const alice = await register();
  const bob = await register();
  const account = await prisma.gitHubAccount.create({
    data: {
      userId: alice.userId, githubUserId: 'synthetic-metadata', login: 'synthetic-metadata',
      encryptedAccessToken: encryptSecret('synthetic-metadata-token', encryptionKey), scopes: ['repo'],
    },
  });
  assert.equal((await app.inject({ method: 'GET', url: '/api/workspace/costs' })).statusCode, 401);
  const load = async (headers = alice.headers) => {
    const response = await app.inject({ method: 'GET', url: '/api/workspace/costs', headers });
    assert.equal(response.statusCode, 200, response.body);
    return response.json();
  };
  const initial = await load();
  assert.equal(initial.sdk.model, 'auto');
  assert.equal(initial.sdk.policy, null);
  assert.equal(initial.sdk.executionAvailable, false);
  assert.equal(initial.sdk.providerBudgetManagedByApplication, false);
  assert.equal(initial.sdk.accounts[0].metadata, null);
  assert.equal(initial.openai.spentMicros, 0);
  assert.equal(initial.openai.reservedMicros, 0);
  assert.deepEqual((await load(bob.headers)).sdk.accounts, []);
  const savePolicy = (value: { monthlyExtraLimitMinor: number; updatedAt: string | null }) => app.inject({
    method: 'POST', url: '/api/workspace/costs/sdk-policy', headers: alice.headers, payload: value,
  });
  for (const invalid of [-1, 1.5, 1_000_001]) {
    assert.equal((await savePolicy({ monthlyExtraLimitMinor: invalid, updatedAt: null })).statusCode, 400);
  }
  const saved = await savePolicy({ monthlyExtraLimitMinor: 1234, updatedAt: null });
  assert.equal(saved.statusCode, 200, saved.body);
  const version = saved.json().policy.updatedAt;
  assert.equal(saved.json().policy.monthlyExtraLimitMinor, 1234);
  assert.equal((await load(bob.headers)).sdk.policy, null);
  const stale = await savePolicy({ monthlyExtraLimitMinor: 5000, updatedAt: null });
  assert.equal(stale.statusCode, 409);
  assert.equal(stale.json().error.code, 'SDK_COST_POLICY_CHANGED');
  const updated = await savePolicy({ monthlyExtraLimitMinor: 0, updatedAt: version });
  assert.equal(updated.statusCode, 200);
  assert.notEqual(updated.json().policy.updatedAt, version);

  const path = `/api/workspace/github-accounts/${account.id}/sdk-metadata`;
  assert.equal((await app.inject({ method: 'POST', url: path, headers: bob.headers })).statusCode, 404);
  assert.equal((await app.inject({ method: 'POST', url: path, headers: { authorization: alice.headers.authorization } })).statusCode, 403);
  const enqueue = async () => {
    const response = await app.inject({ method: 'POST', url: path, headers: alice.headers });
    assert.equal(response.statusCode, 202, response.body);
    return response.json();
  };
  const first = await enqueue();
  const repeated = await enqueue();
  assert.equal(repeated.requestedAt, first.requestedAt);
  let calls = 0;
  const catalog = metadataJson({
    readOnly: true, sessionsCreated: 0, models: [{ id: 'auto', name: 'Auto', tokenPrices: null }],
    priceUnits: { units: [] },
  });
  const quota = metadataJson({
    quotaSnapshots: {
      ai_credits: {
        isUnlimitedEntitlement: false, entitlementRequests: 1000, usedRequests: 123.5,
        remainingPercentage: 87.65, overage: 0, usageAllowedWithExhaustedQuota: false,
        overageAllowedWithExhaustedQuota: false, resetDate: '2026-11-01',
      },
    },
  });
  const errors: string[] = [];
  const discover = async (token: string) => {
    assert.equal(token, 'synthetic-metadata-token');
    calls++;
    return { catalog, quota };
  };
  assert.equal(await processMetadataJob({ prisma, encryptionKey, discover, logError: (code) => errors.push(code) }), true);
  const ready = await load();
  assert.equal(calls, 1);
  assert.equal(ready.sdk.accounts[0].metadata.status, 'READY');
  assert.equal(ready.sdk.accounts[0].metadata.autoAvailable, true);
  assert.equal(ready.sdk.accounts[0].metadata.quota.quotaSnapshots.ai_credits.usedRequests, 123.5);
  assert.equal('encryptedAccessToken' in ready.sdk.accounts[0], false);
  assert.equal('leaseToken' in ready.sdk.accounts[0].metadata, false);
  assert.equal(await processMetadataJob({ prisma, encryptionKey, discover, logError: (code) => errors.push(code) }), false);
  const bobAccount = await prisma.gitHubAccount.create({
    data: {
      userId: bob.userId, githubUserId: 'synthetic-metadata-bob', login: 'synthetic-metadata-bob',
      encryptedAccessToken: encryptSecret('synthetic-metadata-bob-token', encryptionKey), scopes: ['repo'],
    },
  });
  assert.equal((await app.inject({
    method: 'POST', url: `/api/workspace/github-accounts/${bobAccount.id}/sdk-metadata`, headers: bob.headers,
  })).statusCode, 202);
  let enter!: () => void;
  let release!: () => void;
  const entered = new Promise<void>((resolve) => { enter = resolve; });
  const blocked = new Promise<void>((resolve) => { release = resolve; });
  const working = processMetadataJob({
    prisma, encryptionKey, logError: (code) => errors.push(code),
    discover: async (token) => {
      assert.equal(token, 'synthetic-metadata-bob-token');
      enter();
      await blocked;
      return { catalog, quota };
    },
  });
  await entered;
  try {
    assert.equal(await processMetadataJob({
      prisma, encryptionKey, logError: (code) => errors.push(code),
      discover: async () => { throw new Error('Concurrent provider discovery must not run.'); },
    }), false);
  } finally {
    release();
    await working;
  }
  assert.deepEqual((await load()).sdk.accounts.map((entry: { id: string }) => entry.id), [account.id]);
  assert.deepEqual((await load(bob.headers)).sdk.accounts.map((entry: { id: string }) => entry.id), [bobAccount.id]);
  await enqueue();
  await processMetadataJob({
    prisma, encryptionKey,
    discover: async () => { throw new Error('Synthetic provider failure synthetic-metadata-token'); },
    logError: (code) => errors.push(code),
  });
  const failed = await load();
  assert.equal(failed.sdk.accounts[0].metadata.status, 'FAILED');
  assert.equal(failed.sdk.accounts[0].metadata.quota.quotaSnapshots.ai_credits.usedRequests, 123.5);
  assert.equal(failed.sdk.accounts[0].metadata.errorMessage.includes('synthetic-metadata-token'), false);
  assert.ok(failed.sdk.accounts[0].metadata.errorMessage.includes('[REDACTED]'));
  assert.deepEqual(errors, ['SDK_METADATA_FAILED']);

  await enqueue();
  const takeover = randomUUID();
  await processMetadataJob({
    prisma, encryptionKey,
    discover: async () => {
      await prisma.sdkAccountMetadata.update({ where: { githubAccountId: account.id }, data: { leaseToken: takeover } });
      return { catalog, quota };
    },
    logError: (code) => errors.push(code),
  }).then(() => assert.fail('A superseded worker must not record success or failure'), (error: Error) => {
    assert.match(error.message, /lease lost/);
  });
  assert.equal((await prisma.sdkAccountMetadata.findUniqueOrThrow({ where: { githubAccountId: account.id } })).leaseToken, takeover);
  await prisma.sdkAccountMetadata.update({ where: { githubAccountId: account.id }, data: { leaseExpiresAt: new Date(0) } });
  assert.equal(await processMetadataJob({ prisma, encryptionKey, discover, logError: (code) => errors.push(code) }), false);
  assert.equal((await load()).sdk.accounts[0].metadata.errorCode, 'SDK_METADATA_INTERRUPTED');

  await app.close();
  const restartedPrisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  app = createApp({ prisma: restartedPrisma, config });
  const persisted = await load();
  assert.equal(persisted.sdk.policy.monthlyExtraLimitMinor, 0);
  assert.equal(persisted.sdk.accounts[0].metadata.quota.quotaSnapshots.ai_credits.usedRequests, 123.5);
  assert.equal(persisted.sdk.accounts[0].metadata.status, 'FAILED');
  await app.close();
  app = createApp({
    prisma: new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) }),
    config: { ...config, SDK_METADATA_ENABLED: false },
  });
  assert.equal((await app.inject({ method: 'POST', url: path, headers: alice.headers })).statusCode, 503);
  assert.equal((await load()).sdk.metadataEnabled, false);
});
