import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from './app.ts';
import { parseConfig } from './config.ts';
import type { PrismaClient } from './generated/prisma/client.ts';
import { hashPassword } from './security/passwords.ts';
import { hashToken } from './security/secrets.ts';

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

test('documents unavailable Copilot coding-agent operations', async (context) => {
  const app = createApp({ prisma: makePrisma(), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({ method: 'GET', url: '/api/capabilities' });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json().copilotAgent, {
    launchTasks: false,
    readTaskStatus: false,
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

test('returns an explicit unsupported response instead of faking a Copilot task', async (context) => {
  const app = createApp({ prisma: makePrisma('csrf-secret'), config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: '/api/stages/clstage00000000000000000000/start',
    headers: {
      authorization: 'Bearer session-secret',
      'x-csrf-token': 'csrf-secret',
    },
  });

  assert.equal(response.statusCode, 501);
  assert.equal(response.json().error.code, 'COPILOT_TASK_EXECUTION_UNAVAILABLE');
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