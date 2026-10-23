import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createApp } from './app.ts';
import { parseConfig } from './config.ts';
import type { PrismaClient } from './generated/prisma/client.ts';
import { copilotCapabilities, type CopilotTaskRequest } from './github/copilot-provider.ts';
import { hashPassword } from './security/passwords.ts';
import { encryptSecret, hashToken } from './security/secrets.ts';

function testConfig() {
  return parseConfig({
    NODE_ENV: 'test',
    DATABASE_URL: 'postgresql://127.0.0.1:5432/control_center_test',
    APP_ORIGIN: 'http://127.0.0.1:4173',
    PUBLIC_API_URL: 'http://127.0.0.1:3000',
    APP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64url'),
  });
}

function makePrisma(sessionCsrfToken?: string, overrides: Record<string, unknown> = {}) {
  const prisma = {
    authSession: {
      findFirst: async () => sessionCsrfToken
        ? { id: 'session-id', userId: 'user-id', csrfTokenHash: hashToken(sessionCsrfToken) }
        : null,
    },
    $disconnect: async () => undefined,
    ...overrides,
  };

  return prisma as unknown as PrismaClient;
}

test('reports service liveness without a database connection', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({ method: 'GET', url: '/health/live' });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), { status: 'ok' });
});

test('redirects the API root to the configured Control Center UI', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({ method: 'GET', url: '/' });

  assert.equal(response.statusCode, 302);
  assert.equal(response.headers.location, 'http://127.0.0.1:4173');
});

test('serves the production Flutter Web bundle and SPA routes without masking API 404s', async (context) => {
  const webRoot = mkdtempSync(join(tmpdir(), 'ccc-web-test-'));
  writeFileSync(join(webRoot, 'index.html'), '<!doctype html><title>Control Center UI</title>');
  context.after(() => rmSync(webRoot, { recursive: true, force: true }));
  const config = parseConfig({
    NODE_ENV: 'production',
    DATABASE_URL: 'postgresql://127.0.0.1:5432/control_center_test',
    APP_ORIGIN: 'https://control.example.test',
    PUBLIC_API_URL: 'https://control.example.test',
    APP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64url'),
  });
  const app = createApp({ prisma: makePrisma(), config, webRoot });
  context.after(() => app.close());

  const home = await app.inject({ method: 'GET', url: '/', headers: { host: 'control.example.test' } });
  const deepLink = await app.inject({
    method: 'GET',
    url: '/bots/example-bot',
    headers: { host: 'control.example.test' },
  });
  const missingApi = await app.inject({
    method: 'GET',
    url: '/api/does-not-exist',
    headers: { host: 'control.example.test' },
  });

  assert.equal(home.statusCode, 200);
  assert.match(home.headers['content-type'] ?? '', /text\/html/);
  assert.match(home.body, /Control Center UI/);
  assert.equal(deepLink.statusCode, 200);
  assert.match(deepLink.body, /Control Center UI/);
  assert.equal(missingApi.statusCode, 404);
  assert.equal(missingApi.json().error.code, 'NOT_FOUND');
});

test('allows authenticated Flutter Web preflight headers only from the configured app origin', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'OPTIONS',
    url: '/api/session',
    headers: {
      origin: testConfig().APP_ORIGIN,
      'access-control-request-method': 'GET',
      'access-control-request-headers': 'authorization,x-csrf-token',
    },
  });

  assert.equal(response.statusCode, 204);
  assert.equal(response.headers['access-control-allow-origin'], testConfig().APP_ORIGIN);
  assert.equal(response.headers['access-control-allow-credentials'], 'true');
  assert.match(response.headers['access-control-allow-headers']?.toString() ?? '', /authorization/i);
});

test('allows a same-host Codespaces API origin while retaining credentials', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'OPTIONS',
    url: '/api/auth/register',
    headers: {
      origin: 'http://localhost:3000',
      host: 'localhost:3000',
      'access-control-request-method': 'POST',
      'access-control-request-headers': 'content-type',
    },
  });

  assert.equal(response.statusCode, 204);
  assert.equal(response.headers['access-control-allow-origin'], 'http://localhost:3000');
  assert.equal(response.headers['access-control-allow-credentials'], 'true');
});

test('accepts a same-host origin and rejects a foreign origin on state-changing requests', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());
  const post = (origin: string) => app.inject({
    method: 'POST',
    url: '/api/auth/register',
    headers: { origin, host: 'localhost:4173' },
    payload: {},
  });

  assert.equal((await post('http://localhost:4173')).statusCode, 400);
  const foreign = await post('https://attacker.example');
  assert.equal(foreign.statusCode, 403);
  assert.equal(foreign.json().error.code, 'INVALID_ORIGIN');
});

test('requires a local Control Center account before connecting GitHub', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/auth/github/start',
    payload: { client: 'BROWSER' },
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.json().error.code, 'UNAUTHENTICATED');
});

test('registers a local account with a normalized email and hashed credentials', async (context) => {
  let createdUser: Record<string, unknown> | undefined;
  let createdSession: Record<string, unknown> | undefined;
  const transaction = {
    user: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        createdUser = data;
        return { id: 'local-user-id' };
      },
    },
    authSession: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        createdSession = data;
        return { id: 'local-session-id' };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  const prisma = makePrisma(undefined, {
    user: { findUnique: async () => null },
    $transaction: async (callback: (client: typeof transaction) => Promise<unknown>) => callback(transaction),
  });
  const app = createApp({ prisma, config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: {
      email: '  New.User@Example.COM  ',
      password: 'correct horse battery staple',
      displayName: 'New User',
    },
  });

  assert.equal(response.statusCode, 201);
  assert.equal(createdUser?.email, 'new.user@example.com');
  assert.match(String(createdUser?.passwordHash), /^\$scrypt\$v1\$/);
  assert.notEqual(createdUser?.passwordHash, 'correct horse battery staple');
  assert.ok(createdSession?.tokenHash);
  assert.ok(createdSession?.csrfTokenHash);
  assert.notEqual(createdSession?.tokenHash, response.json().sessionToken);
  assert.equal(response.json().user.id, 'local-user-id');
});

test('rejects weak local registration passwords', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'person@example.com', password: 'short' },
  });

  assert.equal(response.statusCode, 400);
  assert.equal(response.json().error.code, 'INVALID_REQUEST');
});

test('signs a local user in with case-insensitive email and issues a fresh session', async (context) => {
  const passwordHash = await hashPassword('correct horse battery staple');
  let createdSession: Record<string, unknown> | undefined;
  const transaction = {
    authSession: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        createdSession = data;
        return { id: 'local-session-id' };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  let searchedEmail: string | undefined;
  const prisma = makePrisma(undefined, {
    user: {
      findUnique: async ({ where }: { where: { email: string } }) => {
        searchedEmail = where.email;
        return { id: 'local-user-id', passwordHash };
      },
    },
    $transaction: async (callback: (client: typeof transaction) => Promise<unknown>) => callback(transaction),
  });
  const app = createApp({ prisma, config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { email: 'PERSON@example.com', password: 'correct horse battery staple' },
  });

  assert.equal(response.statusCode, 200);
  assert.equal(searchedEmail, 'person@example.com');
  assert.ok(response.json().sessionToken);
  assert.ok(response.json().csrfToken);
  assert.ok(createdSession?.tokenHash);
  assert.notEqual(createdSession?.tokenHash, response.json().sessionToken);
});

test('issues a short-lived editor cookie only to an authenticated session and verifies it', async (context) => {
  const config = parseConfig({
    NODE_ENV: 'production',
    DATABASE_URL: 'postgresql://127.0.0.1:5432/control_center_test',
    APP_ORIGIN: 'https://staging.copilotcontrolcenter.com',
    PUBLIC_API_URL: 'https://staging.copilotcontrolcenter.com',
    EDITOR_URL: 'https://editor.staging.copilotcontrolcenter.com/editor/',
    APP_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64url'),
  });
  const app = createApp({ prisma: makePrisma('csrf-secret'), config });
  context.after(() => app.close());

  const unauthorized = await app.inject({
    method: 'POST',
    url: '/api/auth/editor/session',
  });
  assert.equal(unauthorized.statusCode, 401);

  const invalidCsrf = await app.inject({
    method: 'POST',
    url: '/api/auth/editor/session',
    headers: {
      authorization: 'Bearer valid-session-token',
      'x-csrf-token': 'invalid-csrf-token',
    },
  });
  assert.equal(invalidCsrf.statusCode, 403);

  const issued = await app.inject({
    method: 'POST',
    url: '/api/auth/editor/session',
    headers: {
      authorization: 'Bearer valid-session-token',
      'x-csrf-token': 'csrf-secret',
    },
  });

  assert.equal(issued.statusCode, 200);
  assert.deepEqual(issued.json(), { editorUrl: config.EDITOR_URL });
  const setCookie = issued.headers['set-cookie'];
  assert.ok(setCookie);
  assert.match(String(setCookie), /ccc_editor_session=/);
  assert.match(String(setCookie), /Path=\/editor/);
  assert.match(String(setCookie), /Domain=staging\.copilotcontrolcenter\.com/i);
  assert.match(String(setCookie), /Secure/i);
  assert.match(String(setCookie), /HttpOnly/i);
  assert.match(String(setCookie), /SameSite=Strict/i);
  const editorCookie = String(setCookie).split(';')[0];

  const verified = await app.inject({
    method: 'GET',
    url: '/api/auth/editor/verify',
    headers: { cookie: editorCookie },
  });
  assert.equal(verified.statusCode, 204);
});

test('uses one generic error for missing local accounts or incorrect passwords', async (context) => {
  const app = createApp({
    prisma: makePrisma(undefined, { user: { findUnique: async () => null } }),
    config: testConfig(),
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { email: 'missing@example.com', password: 'correct horse battery staple' },
  });

  assert.equal(response.statusCode, 401);
  assert.deepEqual(response.json().error, {
    code: 'INVALID_CREDENTIALS',
    message: 'Nieprawidłowy e-mail lub hasło.',
  });
});

test('documents supported and unsupported Copilot coding-agent operations', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({ method: 'GET', url: '/api/capabilities' });

  assert.equal(response.statusCode, 200);
  assert.equal(response.json().stageApproval, false);
  assert.deepEqual(response.json().reviewEvidence, {
    ci: false,
    preview: false,
    manualTests: false,
  });
  assert.deepEqual(response.json().copilotAgent, {
    launchTasks: true,
    readTaskStatus: true,
    readTaskLogs: false,
    resumeTasks: false,
    updateRunningTasks: false,
  });
});

test('does not expose stage actions without GitHub authentication', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/stages/clstage00000000000000000000/approve',
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.json().error.code, 'UNAUTHENTICATED');
});

test('requires a valid CSRF token for authenticated stage actions', async (context) => {
  const app = createApp({ prisma: makePrisma('csrf-secret'), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/stages/clstage00000000000000000000/approve',
    headers: { authorization: 'Bearer session-secret' },
  });

  assert.equal(response.statusCode, 403);
  assert.equal(response.json().error.code, 'INVALID_CSRF_TOKEN');
});

test('blocks stage approval until server-verified review evidence is available', async (context) => {
  const app = createApp({ prisma: makePrisma('csrf-secret'), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/stages/clstage00000000000000000000/approve',
    headers: {
      authorization: 'Bearer review-test-session',
      'x-csrf-token': 'csrf-secret',
    },
  });

  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'REVIEW_EVIDENCE_REQUIRED');
});

test('only starts Copilot tasks for a stage owned by the authenticated user', async (context) => {
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (transaction: unknown) => Promise<unknown>) => callback({
        stage: { findFirst: async () => null },
      }),
    }),
    config: testConfig(),
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/stages/clstage00000000000000000000/start',
    headers: {
      authorization: 'Bearer session-secret',
      'x-csrf-token': 'csrf-secret',
    },
  });

  assert.equal(response.statusCode, 404);
  assert.equal(response.json().error.code, 'STAGE_NOT_FOUND');
});

test('reports an unconfirmed GitHub task before validating a RUNNING to RUNNING transition', async (context) => {
  let checkedUnconfirmedJob = false;
  const transaction = {
    stage: {
      findFirst: async () => ({
        id: 'clstage00000000000000000000',
        botId: 'clbot0000000000000000000000',
        number: 1,
        status: 'RUNNING',
      }),
    },
    backgroundJob: {
      findFirst: async () => {
        checkedUnconfirmedJob = true;
        return { id: 'cljob00000000000000000000000' };
      },
    },
  };
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction),
    }),
    config: testConfig(),
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/stages/clstage00000000000000000000/start',
    headers: {
      authorization: 'Bearer unconfirmed-test-session',
      'x-csrf-token': 'csrf-secret',
    },
    payload: {},
  });

  assert.equal(checkedUnconfirmedJob, true);
  assert.equal(response.statusCode, 409);
  assert.deepEqual(response.json().error, {
    code: 'COPILOT_TASK_SUBMISSION_UNCONFIRMED',
    message: 'Poprzednie zgłoszenie mogło dotrzeć do GitHuba. Sprawdź zadania Copilot w repozytorium, zanim spróbujesz ponownie.',
  });
});

test('explains in Polish when an uncertain task has no confirmed GitHub task ID', async (context) => {
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      stage: {
        findFirst: async () => ({
          id: 'clstage00000000000000000000',
          status: 'RUNNING',
          botId: 'clbot0000000000000000000000',
          jobs: [
            {
              externalTaskId: null,
              lastError: 'SUBMISSION_RESULT_UNCONFIRMED',
            },
          ],
        }),
      },
    }),
    config: testConfig(),
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'GET',
    url: '/api/stages/clstage00000000000000000000/task',
    headers: { authorization: 'Bearer unconfirmed-test-session' },
  });

  assert.equal(response.statusCode, 409);
  assert.deepEqual(response.json().error, {
    code: 'COPILOT_TASK_SUBMISSION_UNCONFIRMED',
    message: 'Nie wiadomo, czy GitHub przyjął poprzednie zadanie. Sprawdź zadania Copilot w repozytorium przed ponowieniem.',
  });
});

test('retries an unconfirmed task only after explicit confirmation that GitHub has no task', async (context) => {
  const config = testConfig();
  const stageId = 'clstage00000000000000000000';
  let stageStatus = 'RUNNING';
  let launched = false;
  const transitions: string[] = [];
  const updatedJobs: Record<string, unknown>[] = [];
  const stage = {
    id: stageId,
    botId: 'clbot0000000000000000000000',
    number: 1,
    title: 'Update the application',
    description: 'Implement a user-requested feature.',
    acceptanceCriteria: ['Add tests'],
    branchName: null,
    status: stageStatus,
    transitions: [],
    bot: {
      id: 'clbot0000000000000000000000',
      systemPrompt: 'Work only in the selected repository.',
      repository: 'owner/repository',
      defaultBranch: 'main',
      githubAccount: {
        id: 'claccount000000000000000000',
        status: 'ACTIVE',
        tokenExpiresAt: null,
        encryptedAccessToken: encryptSecret('github-user-token', config.APP_ENCRYPTION_KEY!),
      },
    },
  };
  const transaction = {
    stage: {
      findFirst: async () => ({ ...stage, status: stageStatus }),
      findMany: async () => [{ number: 1, status: stageStatus }],
      updateMany: async ({ where, data }: {
        where: { status: string };
        data: { status: string };
      }) => {
        if (where.status !== stageStatus) return { count: 0 };
        stageStatus = data.status;
        return { count: 1 };
      },
    },
    backgroundJob: {
      findFirst: async () => ({ id: 'cljob00000000000000000000000' }),
      update: async ({ data }: { data: Record<string, unknown> }) => {
        updatedJobs.push(data);
        return { id: 'cljob00000000000000000000000' };
      },
      create: async () => ({ id: 'cljob00000000000000000000001' }),
    },
    stageTransitionEvent: {
      create: async ({ data }: { data: { fromStatus: string; toStatus: string } }) => {
        transitions.push(`${data.fromStatus}>${data.toStatus}`);
        return { id: `event-${transitions.length}` };
      },
    },
    notification: { create: async () => ({ id: 'notification-id' }) },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction),
    }),
    config,
    copilotProvider: {
      capabilities: copilotCapabilities,
      launchTask: async () => {
        launched = true;
        return { id: 'task_retry', state: 'queued' as const };
      },
      getTask: async () => ({ id: 'task_retry', state: 'queued' as const }),
    },
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: `/api/stages/${stageId}/start`,
    headers: {
      authorization: 'Bearer unconfirmed-test-session',
      'x-csrf-token': 'csrf-secret',
    },
    payload: { confirmedNoTaskExists: true },
  });

  assert.equal(response.statusCode, 202);
  assert.equal(launched, true);
  assert.equal(stageStatus, 'RUNNING');
  assert.deepEqual(transitions, ['RUNNING>FAILED', 'FAILED>RUNNING']);
  assert.ok(updatedJobs.some((data) => data.lastError === 'SUBMISSION_RETRY_CONFIRMED'));
  assert.ok(updatedJobs.some((data) => data.externalTaskId === 'task_retry'));
});

test('starts an owned stage with its encrypted GitHub account and persisted task notification', async (context) => {
  const config = testConfig();
  let currentStatus = 'PENDING';
  let recordedTaskId: string | undefined;
  let recordedNotification: Record<string, unknown> | undefined;
  let launchedRequest: Record<string, unknown> | undefined;
  const stage = {
    id: 'clstage00000000000000000000',
    botId: 'clbot0000000000000000000000',
    number: 1,
    title: 'Update the application',
    description: 'Implement a user-requested feature.',
    acceptanceCriteria: ['Add tests', 'Keep secrets safe'],
    branchName: null,
    status: 'PENDING',
    transitions: [],
    bot: {
      id: 'clbot0000000000000000000000',
      systemPrompt: 'Work only in the selected repository.',
      repository: 'owner/repository',
      defaultBranch: 'main',
      githubAccount: {
        id: 'claccount000000000000000000',
        status: 'ACTIVE',
        tokenExpiresAt: null,
        encryptedAccessToken: encryptSecret('github-user-token', config.APP_ENCRYPTION_KEY!),
      },
    },
  };
  const transaction = {
    stage: {
      findFirst: async () => ({ ...stage, status: currentStatus }),
      findMany: async () => [{ number: 1, status: currentStatus }],
      updateMany: async ({ data }: { data: { status: string } }) => {
        currentStatus = data.status;
        return { count: 1 };
      },
    },
    backgroundJob: {
      findFirst: async () => null,
      create: async () => ({ id: 'cljob00000000000000000000000' }),
      update: async ({ data }: { data: { externalTaskId?: string } }) => {
        recordedTaskId = data.externalTaskId;
        return { id: 'cljob00000000000000000000000' };
      },
    },
    stageTransitionEvent: { create: async () => ({ id: 'event-id' }) },
    notification: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        recordedNotification = data;
        return { id: 'notification-id' };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  const provider = {
    capabilities: copilotCapabilities,
    launchTask: async (request: CopilotTaskRequest) => {
      launchedRequest = request;
      return { id: 'task_123', state: 'queued' as const };
    },
    getTask: async () => ({ id: 'task_123', state: 'queued' as const }),
  };
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction),
    }),
    config,
    copilotProvider: provider,
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: `/api/stages/${stage.id}/start`,
    headers: {
      authorization: 'Bearer local-test-session',
      'x-csrf-token': 'csrf-secret',
    },
    payload: {},
  });

  assert.equal(response.statusCode, 202);
  assert.deepEqual(response.json(), {
    task: { id: 'task_123', state: 'queued', url: null },
    stage: { id: stage.id, status: 'RUNNING' },
  });
  assert.equal(currentStatus, 'RUNNING');
  assert.equal(recordedTaskId, 'task_123');
  assert.equal(recordedNotification?.type, 'COPILOT_TASK_STARTED');
  assert.equal(launchedRequest?.accessToken, 'github-user-token');
  assert.equal(launchedRequest?.repository, 'owner/repository');
  assert.equal(launchedRequest?.baseBranch, 'main');
  assert.match(String(launchedRequest?.prompt), /Keep secrets safe/);
});

test('syncs a completed cloud-agent task through testing to approval and records one notification', async (context) => {
  const config = testConfig();
  const stageId = 'clstage00000000000000000000';
  const events: Record<string, unknown>[] = [];
  const notifications: Record<string, unknown>[] = [];
  const transitions: Record<string, unknown>[] = [];
  const stage = {
    id: stageId,
    botId: 'clbot0000000000000000000000',
    number: 1,
    status: 'RUNNING',
    bot: {
      id: 'clbot0000000000000000000000',
      repository: 'owner/repository',
      githubAccount: {
        id: 'claccount000000000000000000',
        status: 'ACTIVE',
        tokenExpiresAt: null,
        encryptedAccessToken: encryptSecret('github-user-token', config.APP_ENCRYPTION_KEY!),
      },
    },
    jobs: [{ id: 'cljob00000000000000000000000', externalTaskId: 'task_123' }],
  };
  const transaction = {
    stage: {
      updateMany: async ({ data }: { data: { status: string } }) => {
        transitions.push(data);
        return { count: 1 };
      },
    },
    stageTransitionEvent: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        events.push(data);
        return { id: 'event-id' };
      },
    },
    notification: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        notifications.push(data);
        return { id: 'notification-id' };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  const provider = {
    capabilities: copilotCapabilities,
    launchTask: async () => ({ id: 'task_123', state: 'queued' as const }),
    getTask: async (
      request: Pick<CopilotTaskRequest, 'accessToken' | 'repository'> & { taskId: string },
    ) => {
      assert.equal(request.accessToken, 'github-user-token');
      assert.equal(request.repository, 'owner/repository');
      assert.equal(request.taskId, 'task_123');
      return {
        id: 'task_123',
        state: 'completed' as const,
        html_url: 'https://github.com/owner/repository',
      };
    },
  };
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      stage: { findFirst: async () => stage },
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction),
    }),
    config,
    copilotProvider: provider,
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'GET',
    url: `/api/stages/${stageId}/task`,
    headers: { authorization: 'Bearer local-test-session' },
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    task: {
      id: 'task_123',
      state: 'completed',
      url: 'https://github.com/owner/repository',
      updatedAt: null,
    },
    stage: { id: stageId, status: 'WAITING_APPROVAL' },
  });
  assert.deepEqual(transitions.map((event) => event.status), ['TESTING', 'WAITING_APPROVAL']);
  assert.equal(events.length, 2);
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0]?.type, 'COPILOT_TASK_COMPLETED');
});

test('rejects a mobile OAuth handoff with a different state', async (context) => {
  const prisma = {
    oAuthHandoff: {
      findUnique: async () => ({
        id: 'handoff-id',
        userId: 'user-id',
        stateHash: hashToken('expected-oauth-state-value-0000000'),
        consumedAt: null,
        expiresAt: new Date(Date.now() + 60000),
      }),
    },
    $disconnect: async () => undefined,
  };
  const app = createApp({ prisma: prisma as unknown as PrismaClient, config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/auth/github/session/exchange',
    payload: {
      code: 'one-time-code-value-that-is-at-least-32-characters',
      state: 'attacker-state-value-that-is-32-char',
    },
  });

  assert.equal(response.statusCode, 401);
  assert.equal(response.json().error.code, 'INVALID_MOBILE_HANDOFF');
});