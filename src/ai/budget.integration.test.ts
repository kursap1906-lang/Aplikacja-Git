import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client.ts';
import { ApiError } from '../http/errors.ts';
import { createApp } from '../app.ts';
import { parseConfig } from '../config.ts';
import { analysisModel } from './openai.ts';
import { encryptSecret } from '../security/secrets.ts';
import {
  claimAiAnalysis, heartbeatAiAnalysis, markAiGenerationStarted, reserveAiAnalysis, settleAiAnalysis,
  type AnalysisReservation,
} from './budget.ts';

test('real database enforces global AI limits, leases, idempotency and uncertain charges', async (context) => {
  const databaseUrl = process.env.WORKSPACE_TEST_DATABASE_URL;
  if (!databaseUrl) throw new Error('Set WORKSPACE_TEST_DATABASE_URL to the disposable integration database.');
  const url = new URL(databaseUrl);
  if (url.hostname !== 'workspace-db' || url.pathname !== '/workspace_integration') {
    throw new Error('Refusing to run AI integration tests outside workspace-db/workspace_integration.');
  }
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  context.after(() => prisma.$disconnect());
  const now = new Date('2031-01-31T23:00:00Z');
  const users = await Promise.all(Array.from({ length: 13 }, () => prisma.user.create({ data: {} })));
  const input = (index: number): AnalysisReservation => ({
    userId: users[index]!.id, projectId: null, teamId: null, kind: 'DIAGNOSTIC',
    requestKey: randomUUID(), inputFingerprint: 'a'.repeat(64),
  });
  const requests = users.slice(0, 11).map((_, index) => input(index));
  const reservations = await Promise.allSettled(requests.map((request) => reserveAiAnalysis(prisma, request, now)));
  assert.equal(reservations.filter((entry) => entry.status === 'fulfilled').length, 10);
  const rejected = reservations.filter((entry) => entry.status === 'rejected');
  assert.equal(rejected.length, 1);
  assert.ok(rejected[0]!.reason instanceof ApiError);
  assert.equal(rejected[0]!.reason.code, 'AI_MONTHLY_BUDGET_EXCEEDED');
  let budget = await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } });
  assert.equal(budget.reservedMicros, 10_000_000);
  assert.equal(budget.spentMicros, 0);

  const firstIndex = reservations.findIndex((entry) => entry.status === 'fulfilled');
  const firstRequest = requests[firstIndex]!;
  const repeated = await reserveAiAnalysis(prisma, firstRequest, now);
  const original = reservations[firstIndex]!;
  assert.ok(original.status === 'fulfilled');
  assert.equal(repeated.id, original.value.id);
  assert.equal((await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } })).reservedMicros, 10_000_000);
  await assert.rejects(
    reserveAiAnalysis(prisma, { ...firstRequest, inputFingerprint: 'b'.repeat(64) }, now),
    (error: unknown) => error instanceof ApiError && error.code === 'AI_REQUEST_KEY_CONFLICT',
  );
  await assert.rejects(
    reserveAiAnalysis(prisma, { ...firstRequest, requestKey: randomUUID() }, now),
    (error: unknown) => error instanceof ApiError && error.code === 'AI_ANALYSIS_ACTIVE',
  );

  const owner = users[11]!;
  const outsider = users[12]!;
  const project = await prisma.project.create({ data: { userId: owner.id, name: 'Owned synthetic project' } });
  const team = await prisma.team.create({ data: { userId: owner.id, projectId: project.id, name: `AI fixture ${randomUUID()}` } });
  await assert.rejects(reserveAiAnalysis(prisma, {
    ...input(12), kind: 'TEAM_TASKS', projectId: project.id, teamId: team.id,
  }, now), (error: unknown) => error instanceof ApiError && error.code === 'PROJECT_NOT_FOUND');
  const unrelated = await prisma.project.create({ data: { userId: outsider.id, name: 'Another synthetic project' } });
  await assert.rejects(reserveAiAnalysis(prisma, {
    ...input(12), kind: 'TEAM_TASKS', projectId: unrelated.id, teamId: team.id,
  }, now), (error: unknown) => error instanceof ApiError && error.code === 'TEAM_NOT_FOUND');

  const claimed = await claimAiAnalysis(prisma, now);
  assert.ok(claimed?.leaseToken);
  assert.equal(await claimAiAnalysis(prisma, now), null);
  await assert.rejects(
    markAiGenerationStarted(prisma, claimed.id, randomUUID(), now),
    (error: unknown) => error instanceof ApiError && error.code === 'AI_LEASE_LOST',
  );
  await markAiGenerationStarted(prisma, claimed.id, claimed.leaseToken, now);
  await assert.rejects(
    markAiGenerationStarted(prisma, claimed.id, claimed.leaseToken, now),
    (error: unknown) => error instanceof ApiError && error.code === 'AI_ALREADY_SUBMITTED',
  );
  await settleAiAnalysis(prisma, claimed.id, claimed.leaseToken, {
    status: 'UNKNOWN', errorCode: 'SYNTHETIC_TIMEOUT', errorMessage: 'Synthetic uncertain response; no network request was made.',
  }, now);
  budget = await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } });
  assert.equal(budget.reservedMicros, 10_000_000);
  assert.equal(budget.spentMicros, 0);

  const unpaid = await claimAiAnalysis(prisma, now);
  assert.ok(unpaid?.leaseToken);
  await settleAiAnalysis(prisma, unpaid.id, unpaid.leaseToken, {
    status: 'FAILED', billing: { kind: 'not_charged' }, errorCode: 'SYNTHETIC_PREFLIGHT', errorMessage: 'Synthetic preflight rejection.',
  }, now);
  assert.equal((await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } })).reservedMicros, 9_000_000);

  const paid = await claimAiAnalysis(prisma, now);
  assert.ok(paid?.leaseToken);
  await markAiGenerationStarted(prisma, paid.id, paid.leaseToken, now);
  const usage = { inputTokens: 1000, cachedTokens: 100, outputTokens: 200, costMicros: 1583 };
  await assert.rejects(settleAiAnalysis(prisma, paid.id, paid.leaseToken, {
    status: 'COMPLETED', usage, providerResponseId: 'synthetic-response',
    apply: async (tx) => {
      await tx.project.update({ where: { id: project.id }, data: { repositoryContext: 'Must roll back' } });
      throw new Error('Synthetic application conflict');
    },
  }, now), /Synthetic application conflict/);
  const afterConflict = await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } });
  assert.equal(afterConflict.reservedMicros, 9_000_000);
  assert.equal(afterConflict.spentMicros, 0);
  assert.equal((await prisma.project.findUniqueOrThrow({ where: { id: project.id } })).repositoryContext, '');
  await settleAiAnalysis(prisma, paid.id, paid.leaseToken, {
    status: 'FAILED', billing: { kind: 'usage', usage }, providerResponseId: 'synthetic-response',
    errorCode: 'SYNTHETIC_CONFLICT', errorMessage: 'Output was rejected but its known usage must be charged.',
  }, now);
  budget = await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } });
  assert.equal(budget.reservedMicros, 8_000_000);
  assert.equal(budget.spentMicros, 1583);
  await assert.rejects(settleAiAnalysis(prisma, paid.id, paid.leaseToken, {
    status: 'FAILED', billing: { kind: 'usage', usage }, errorCode: 'DUPLICATE', errorMessage: 'Duplicate settlement.',
  }, now), (error: unknown) => error instanceof ApiError && error.code === 'AI_LEASE_LOST');

  const expiredUnpaid = await claimAiAnalysis(prisma, now);
  assert.ok(expiredUnpaid?.leaseToken);
  const afterExpiry = new Date(now.getTime() + 301_000);
  const resumed = await claimAiAnalysis(prisma, afterExpiry);
  assert.ok(resumed?.leaseToken);
  assert.notEqual(resumed.id, expiredUnpaid.id);
  assert.equal((await prisma.aiAnalysis.findUniqueOrThrow({ where: { id: expiredUnpaid.id } })).status, 'FAILED');
  assert.equal((await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } })).reservedMicros, 7_000_000);
  await assert.rejects(heartbeatAiAnalysis(prisma, expiredUnpaid.id, expiredUnpaid.leaseToken, afterExpiry),
    (error: unknown) => error instanceof ApiError && error.code === 'AI_LEASE_LOST');
  await markAiGenerationStarted(prisma, resumed.id, resumed.leaseToken, afterExpiry);
  await heartbeatAiAnalysis(prisma, resumed.id, resumed.leaseToken, afterExpiry);
  const later = new Date(afterExpiry.getTime() + 301_000);
  const next = await claimAiAnalysis(prisma, later);
  assert.ok(next?.leaseToken);
  assert.equal((await prisma.aiAnalysis.findUniqueOrThrow({ where: { id: resumed.id } })).status, 'UNKNOWN');
  assert.equal((await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-01' } })).reservedMicros, 7_000_000);
  await settleAiAnalysis(prisma, next.id, next.leaseToken, {
    status: 'FAILED', billing: { kind: 'not_charged' }, errorCode: 'SYNTHETIC_STOP', errorMessage: 'Synthetic stop.',
  }, later);

  const february = new Date('2031-02-01T00:00:01Z');
  const transferred = await claimAiAnalysis(prisma, february);
  assert.ok(transferred?.leaseToken);
  assert.equal(transferred.budgetMonth, '2031-02');
  assert.equal((await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-02' } })).reservedMicros, 1_000_000);
  await markAiGenerationStarted(prisma, transferred.id, transferred.leaseToken, february);
  const completed = await settleAiAnalysis(prisma, transferred.id, transferred.leaseToken, {
    status: 'COMPLETED', usage, providerResponseId: 'synthetic-success',
    apply: async (tx) => {
      await tx.project.update({ where: { id: project.id }, data: { repositoryContext: 'Synthetic persisted result' } });
      return { summary: 'Synthetic persisted result' };
    },
  }, february);
  assert.equal(completed.status, 'COMPLETED');
  assert.equal(completed.estimatedCostMicros, 1583);
  assert.equal((await prisma.project.findUniqueOrThrow({ where: { id: project.id } })).repositoryContext, 'Synthetic persisted result');
  budget = await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-02' } });
  assert.equal(budget.reservedMicros, 0);
  assert.equal(budget.spentMicros, 1583);

  const march = new Date('2031-03-01T00:00:01Z');
  const boundary = await claimAiAnalysis(prisma, new Date('2031-02-28T23:59:59Z'));
  assert.ok(boundary?.leaseToken);
  assert.equal(boundary.budgetMonth, '2031-02');
  const movedBeforePayment = await markAiGenerationStarted(prisma, boundary.id, boundary.leaseToken, march);
  assert.equal(movedBeforePayment.budgetMonth, '2031-03');
  assert.equal((await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month: '2031-02' } })).reservedMicros, 0);

  await assert.rejects(prisma.aiBudgetPeriod.update({
    where: { month: '2031-03' }, data: { reservedMicros: 10_000_001 },
  }), /AiBudgetPeriod_limits_check/);
  await assert.rejects(prisma.aiBudgetPeriod.update({
    where: { month: '2031-03' }, data: { reservedMicros: -1 },
  }), /AiBudgetPeriod_limits_check/);
  await settleAiAnalysis(prisma, boundary.id, boundary.leaseToken, {
    status: 'UNKNOWN', errorCode: 'SYNTHETIC_FINAL', errorMessage: 'Synthetic uncertain final result.',
  }, march);
  while (true) {
    const remaining = await claimAiAnalysis(prisma, march);
    if (!remaining) break;
    assert.ok(remaining.leaseToken);
    await settleAiAnalysis(prisma, remaining.id, remaining.leaseToken, {
      status: 'FAILED', billing: { kind: 'not_charged' }, errorCode: 'SYNTHETIC_FINAL', errorMessage: 'Synthetic queue cleanup.',
    }, march);
  }
  const privateJob = await reserveAiAnalysis(prisma, {
    ...input(11), kind: 'TEAM_TASKS', projectId: project.id, teamId: team.id,
  }, march);
  const diagnostic = await reserveAiAnalysis(prisma, input(12), march);
  assert.equal(await claimAiAnalysis(prisma, march, privateJob.id), null);
  const onlyDiagnostic = await claimAiAnalysis(prisma, march, diagnostic.id);
  assert.ok(onlyDiagnostic?.leaseToken);
  assert.equal(onlyDiagnostic.id, diagnostic.id);
  assert.equal((await prisma.aiAnalysis.findUniqueOrThrow({ where: { id: privateJob.id } })).status, 'QUEUED');
  await settleAiAnalysis(prisma, onlyDiagnostic.id, onlyDiagnostic.leaseToken, {
    status: 'FAILED', billing: { kind: 'not_charged' }, errorCode: 'SYNTHETIC_DIAGNOSTIC_ONLY', errorMessage: 'Synthetic restricted diagnostic.',
  }, march);
  const finalPrivate = await claimAiAnalysis(prisma, march);
  assert.ok(finalPrivate?.leaseToken);
  assert.equal(finalPrivate.id, privateJob.id);
  await settleAiAnalysis(prisma, finalPrivate.id, finalPrivate.leaseToken, {
    status: 'FAILED', billing: { kind: 'not_charged' }, errorCode: 'SYNTHETIC_FINAL', errorMessage: 'Synthetic queue cleanup.',
  }, march);
});

test('authenticated async AI tasks persist results and charge rejected output without retrying', async (context) => {
  const databaseUrl = process.env.WORKSPACE_TEST_DATABASE_URL;
  if (!databaseUrl) throw new Error('Disposable integration database required.');
  const url = new URL(databaseUrl);
  if (url.hostname !== 'workspace-db' || url.pathname !== '/workspace_integration') throw new Error('Unsafe integration database.');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  const encryptionKey = Buffer.alloc(32, 9).toString('base64url');
  let mode: 'success' | 'invalid-assignee' | 'changed' | 'duplicate' | 'uncertain' | 'rejected' | 'changed-before-generation' = 'success';
  let botId = '';
  let projectId = '';
  let generationCalls = 0;
  let countCalls = 0;
  const fetcher: typeof fetch = async (value, options) => {
    const address = String(value);
    assert.ok(address.startsWith('https://api.openai.com/v1/'));
    assert.equal(new Headers(options?.headers).get('authorization'), 'Bearer synthetic-openai-key');
    const body = JSON.parse(String(options?.body));
    assert.equal(body.model, analysisModel);
    assert.equal(JSON.stringify(body).includes('fixture-token-never-send'), false);
    if (address.endsWith('/input_tokens')) {
      countCalls++;
      if (mode === 'changed-before-generation') await prisma.project.update({ where: { id: projectId }, data: { brief: `Changed before payment ${countCalls}` } });
      return Response.json({ object: 'response.input_tokens', input_tokens: 2048 });
    }
    generationCalls++;
    assert.equal(body.store, false);
    assert.equal(body.truncation, 'disabled');
    assert.equal(body.max_output_tokens, 16384);
    assert.ok(body.input[0].content.some((part: { text?: string }) => part.text === 'Synthetic UTF-8 attachment: zażółć'));
    if (mode === 'uncertain') throw new TypeError('Synthetic lost connection');
    if (mode === 'rejected') return Response.json({ error: { message: 'Do not expose this provider body' } }, { status: 429 });
    if (mode === 'changed') await prisma.project.update({ where: { id: projectId }, data: { brief: 'Changed while the provider was generating' } });
    return Response.json({
      id: `synthetic-${generationCalls}`, model: analysisModel, status: 'completed',
      usage: { input_tokens: 1000, input_tokens_details: { cached_tokens: 100 }, output_tokens: 200 },
      output: [{
        type: 'message', role: 'assistant', status: 'completed',
        content: [{
          type: 'output_text', text: JSON.stringify({
            summary: 'Synthetic analysis result',
            tasks: [{
              botId: mode === 'invalid-assignee' ? 'another-team-bot' : botId,
              title: mode === 'duplicate' ? 'Manual completed task' : `Generated task ${generationCalls}`,
              description: 'Implement the synthetic feature and verify acceptance tests.', priority: 'HIGH',
            }],
          }),
        }],
      }],
    });
  };
  const app = createApp({
    prisma, fetcher,
    config: parseConfig({
      NODE_ENV: 'test', DATABASE_URL: databaseUrl, APP_ORIGIN: 'http://workspace.example.test',
      APP_ENCRYPTION_KEY: encryptionKey, OPENAI_API_KEY: 'synthetic-openai-key', OPENAI_ANALYSIS_ENABLED: 'true',
    }),
  });
  context.after(() => app.close());
  const register = async () => {
    const response = await app.inject({
      method: 'POST', url: '/api/auth/register',
      payload: { email: `ai+${randomUUID()}@workspace.example.test`, password: 'Synthetic-password-12345' },
    });
    assert.equal(response.statusCode, 201, response.body);
    const result = response.json();
    return { userId: result.user.id as string, headers: { authorization: `Bearer ${result.sessionToken}`, 'x-csrf-token': result.csrfToken as string } };
  };
  const alice = await register();
  const bob = await register();
  const account = await prisma.gitHubAccount.create({
    data: {
      userId: alice.userId, githubUserId: 'synthetic-ai', login: 'synthetic-ai',
      encryptedAccessToken: encryptSecret('fixture-token-never-send', encryptionKey), scopes: ['repo'],
    },
  });
  const project = await prisma.project.create({ data: { userId: alice.userId, name: 'Synthetic analysis project', brief: 'Synthetic feature brief' } });
  projectId = project.id;
  const bot = await prisma.bot.create({
    data: {
      userId: alice.userId, githubAccountId: account.id, name: 'Synthetic bot', repositoryId: '123',
      repository: 'synthetic/repository', defaultBranch: 'main', systemPrompt: 'Implement synthetic features with tests.',
    },
  });
  botId = bot.id;
  const team = await prisma.team.create({
    data: { userId: alice.userId, projectId: project.id, name: `Synthetic AI team ${randomUUID()}`, bots: { create: { botId } } },
  });
  const manual = await prisma.projectTask.create({
    data: {
      userId: alice.userId, projectId: project.id, teamId: team.id, botId,
      title: 'Manual completed task', status: 'COMPLETED', priority: 'LOW',
    },
  });
  const bytes = Buffer.from('Synthetic UTF-8 attachment: zażółć');
  await prisma.workspaceFile.create({
    data: {
      userId: alice.userId, projectId: project.id, filename: 'synthetic.md', sizeBytes: bytes.length,
      contentHash: createHash('sha256').update(bytes).digest('hex'), encryptedContent: encryptSecret(bytes.toString('base64'), encryptionKey),
    },
  });
  const path = `/api/workspace/teams/${team.id}/analyses`;
  assert.equal((await app.inject({ method: 'GET', url: path })).statusCode, 401);
  assert.equal((await app.inject({ method: 'GET', url: path, headers: bob.headers })).statusCode, 404);
  assert.equal((await app.inject({ method: 'POST', url: path, headers: bob.headers, payload: { requestKey: randomUUID() } })).statusCode, 404);
  assert.equal((await app.inject({
    method: 'POST', url: path, headers: { authorization: alice.headers.authorization }, payload: { requestKey: randomUUID() },
  })).statusCode, 403);
  const history = await app.inject({ method: 'GET', url: path, headers: alice.headers });
  assert.equal(history.statusCode, 200, history.body);
  assert.equal(history.json().enabled, true);
  assert.deepEqual(history.json().analyses, []);
  const wait = async (id: string) => {
    for (let attempt = 0; attempt < 100; attempt++) {
      const job = await prisma.aiAnalysis.findUniqueOrThrow({ where: { id } });
      if (!['QUEUED', 'RUNNING'].includes(job.status)) return job;
      await delay(100);
    }
    throw new Error('Synthetic worker did not finish in time.');
  };
  const enqueue = async () => {
    const requestKey = randomUUID();
    const response = await app.inject({ method: 'POST', url: path, headers: alice.headers, payload: { requestKey } });
    assert.equal(response.statusCode, 202, response.body);
    const result = response.json().analysis;
    assert.equal(result.reservationHeldMicros, 1_000_000);
    assert.equal('leaseToken' in result, false);
    assert.equal('inputFingerprint' in result, false);
    return { id: result.id as string, requestKey };
  };
  const first = await enqueue();
  const duplicate = await app.inject({ method: 'POST', url: path, headers: alice.headers, payload: { requestKey: first.requestKey } });
  assert.equal(duplicate.statusCode, 200);
  assert.equal(duplicate.json().analysis.id, first.id);
  const completed = await wait(first.id);
  assert.equal(completed.status, 'COMPLETED');
  assert.equal(completed.estimatedCostMicros, 1583);
  assert.equal(generationCalls, 1);
  const tasks = await prisma.projectTask.findMany({ where: { teamId: team.id } });
  assert.equal(tasks.length, 2);
  assert.equal(tasks.find((task) => task.id === manual.id)?.status, 'COMPLETED');
  assert.equal(tasks.find((task) => task.id !== manual.id)?.botId, botId);
  assert.equal((await prisma.bot.findUniqueOrThrow({ where: { id: botId } })).status, 'IDLE');
  const replay = await app.inject({ method: 'POST', url: path, headers: alice.headers, payload: { requestKey: first.requestKey } });
  assert.equal(replay.statusCode, 200);
  assert.equal(replay.json().analysis.status, 'COMPLETED');
  assert.equal(generationCalls, 1);
  assert.equal((await app.inject({ method: 'GET', url: `/api/workspace/analyses/${first.id}`, headers: bob.headers })).statusCode, 404);

  for (const [failureMode, expectedCode] of [
    ['invalid-assignee', 'OPENAI_RESULT_INVALID'], ['changed', 'AI_SOURCE_CHANGED'], ['duplicate', 'AI_DUPLICATE_TASK'],
  ] as const) {
    mode = failureMode;
    const job = await wait((await enqueue()).id);
    assert.equal(job.status, 'FAILED');
    assert.equal(job.errorCode, expectedCode);
    assert.equal(job.estimatedCostMicros, 1583);
    assert.equal(await prisma.projectTask.count({ where: { teamId: team.id } }), 2);
  }
  mode = 'changed-before-generation';
  const before = generationCalls;
  const changedBefore = await wait((await enqueue()).id);
  assert.equal(changedBefore.status, 'FAILED');
  assert.equal(changedBefore.errorCode, 'AI_SOURCE_CHANGED');
  assert.equal(changedBefore.estimatedCostMicros, 0);
  assert.equal(generationCalls, before);
  mode = 'rejected';
  const rejectedJob = await wait((await enqueue()).id);
  assert.equal(rejectedJob.status, 'FAILED');
  assert.equal(rejectedJob.estimatedCostMicros, 0);
  assert.equal(rejectedJob.errorCode, 'OPENAI_RATE_LIMITED');
  mode = 'uncertain';
  const unknown = await wait((await enqueue()).id);
  assert.equal(unknown.status, 'UNKNOWN');
  assert.equal(unknown.estimatedCostMicros, null);
  const callCount = generationCalls;
  await delay(1200);
  assert.equal(generationCalls, callCount);
  const month = unknown.budgetMonth;
  const budget = await prisma.aiBudgetPeriod.findUniqueOrThrow({ where: { month } });
  assert.equal(budget.spentMicros, 4 * 1583);
  assert.equal(budget.reservedMicros, 1_000_000);
  const status = await app.inject({ method: 'GET', url: `/api/workspace/analyses/${unknown.id}`, headers: alice.headers });
  assert.equal(status.statusCode, 200);
  assert.equal(status.json().analysis.reservationHeldMicros, 1_000_000);
  assert.equal(status.json().analysis.estimatedCostMicros, null);
});
