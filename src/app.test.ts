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
import { decryptSecret, encryptSecret, hashToken } from './security/secrets.ts';

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

test('disabled SDK executor rejects starts without queuing or mutating tasks', async (context) => {
  const app = createApp({ config: testConfig(), prisma: makePrisma('csrf-secret') });
  context.after(() => app.close());
  const url = '/api/workspace/tasks/cltesttask000000000000001/runs';
  const unauthorized = await app.inject({ method: 'POST', url });
  assert.equal(unauthorized.statusCode, 401);
  const headers = { authorization: 'Bearer fixture-session' };
  const noCsrf = await app.inject({ method: 'POST', url, headers });
  assert.equal(noCsrf.statusCode, 403);
  const unavailable = await app.inject({
    method: 'POST', url, headers: { ...headers, 'x-csrf-token': 'csrf-secret' },
  });
  assert.equal(unavailable.statusCode, 503, unavailable.body);
  assert.equal(unavailable.json().error.code, 'SDK_EXECUTION_UNAVAILABLE');
  const capabilities = await app.inject({ url: '/api/capabilities' });
  assert.equal(capabilities.json().workspace.sdkExecution, false);
});

test('workspace GitHub PRs use the owned account, pagination, SHA-pinned checks and explicit writes', async context => {
  const config = testConfig();
  const accountId = 'cltestaccount0000000000001';
  const sha = 'a'.repeat(40);
  const pull = {
    number: 7, title: 'Fixture PR', body: 'Description', html_url: 'https://github.com/fixture/repository/pull/7',
    state: 'open', draft: true, merged_at: null, user: { login: 'fixture' },
    head: { ref: 'feature/test', sha }, base: { ref: 'main' }, updated_at: '2026-10-26T20:00:00Z',
  };
  const calls: Array<{ path: string; method: string }> = [];
  const audits: string[] = [];
  const app = createApp({
    config, prisma: makePrisma('csrf', {
      gitHubAccount: { findFirst: async ({ where }: { where: { id: string; userId: string; status: string } }) => {
        assert.equal(where.userId, 'user-id');
        assert.equal(where.status, 'ACTIVE');
        return where.id === accountId ? {
          tokenExpiresAt: null, encryptedAccessToken: encryptSecret('fixture-pr-token', config.APP_ENCRYPTION_KEY!),
        } : null;
      } },
      auditEvent: { create: async ({ data }: { data: { action: string } }) => { audits.push(data.action); } },
    }),
    fetcher: async (input, options) => {
      const url = new URL(String(input));
      const method = options?.method ?? 'GET';
      assert.equal(new Headers(options?.headers).get('authorization'), 'Bearer fixture-pr-token');
      calls.push({ path: url.pathname, method });
      if (url.pathname.endsWith('/files')) return Response.json([{ filename: 'app.ts', status: 'modified', additions: 2, deletions: 1, patch: '+tested' }]);
      if (url.pathname.endsWith('/comments')) return Response.json(method === 'POST'
        ? { id: 1, body: 'Review', user: null, created_at: '2026-10-26T20:00:00Z', html_url: pull.html_url } : []);
      if (url.pathname.endsWith('/check-runs')) {
        assert.ok(url.pathname.includes(sha));
        return Response.json({ check_runs: [{ name: 'tests', status: 'completed', conclusion: 'success', html_url: pull.html_url }] });
      }
      if (url.pathname.endsWith('/status')) return Response.json({ state: 'success', statuses: [] });
      if (url.pathname.endsWith('/pulls') && method === 'GET') return Response.json([pull], {
        headers: { link: '<https://api.github.com/repos/fixture/repository/pulls?page=2>; rel="next"' },
      });
      if (method === 'POST') assert.equal(JSON.parse(String(options?.body)).draft, true);
      return Response.json(pull);
    },
  });
  context.after(() => app.close());
  const query = `accountId=${accountId}&repository=fixture/repository`;
  const base = '/api/workspace/github/pulls';
  const headers = { authorization: 'Bearer fixture-session', 'x-csrf-token': 'csrf' };
  assert.equal((await app.inject({ url: `${base}?${query}` })).statusCode, 401);
  const list = await app.inject({ url: `${base}?${query}`, headers });
  assert.equal(list.statusCode, 200, list.body);
  assert.equal(list.json().nextPage, 2);
  assert.equal(list.json().pulls[0].state, 'draft');
  assert.ok(!list.body.includes('fixture-pr-token'));
  const detail = await app.inject({ url: `${base}/7?${query}`, headers });
  assert.equal(detail.statusCode, 200, detail.body);
  assert.equal(detail.json().ciSha, sha);
  assert.equal(detail.json().files[0].patch, '+tested');
  assert.equal(detail.json().truncated, false);
  const before = calls.length;
  const foreign = await app.inject({ url: `${base}?accountId=clotheraccount00000000001&repository=fixture/repository`, headers });
  assert.equal(foreign.statusCode, 404);
  assert.equal(calls.length, before);
  assert.equal((await app.inject({
    method: 'POST', url: `${base}/7/comments?${query}`, headers: { authorization: headers.authorization }, payload: { body: 'Review' },
  })).statusCode, 403);
  const comment = await app.inject({
    method: 'POST', url: `${base}/7/comments?${query}`, headers, payload: { body: 'Review' },
  });
  assert.equal(comment.statusCode, 201, comment.body);
  const created = await app.inject({
    method: 'POST', url: `${base}?${query}`, headers, payload: { title: 'Fixture PR', head: 'feature/test', base: 'main' },
  });
  assert.equal(created.statusCode, 201, created.body);
  assert.deepEqual(audits, ['GITHUB_PR_COMMENT_CREATED', 'GITHUB_PR_CREATED']);
});

test('workspace settings reports unavailable adapters honestly without secrets', async context => {
  const app = createApp({
    config: testConfig(), prisma: makePrisma('csrf', {
      gitHubAccount: { findMany: async () => [{ id: 'account', login: 'fixture', status: 'ACTIVE' }] },
    }),
  });
  context.after(() => app.close());
  assert.equal((await app.inject({ url: '/api/workspace/settings' })).statusCode, 401);
  const response = await app.inject({ url: '/api/workspace/settings', headers: { authorization: 'Bearer fixture-session' } });
  assert.equal(response.statusCode, 200, response.body);
  const report = response.json();
  assert.equal(report.integrations.find((entry: { id: string }) => entry.id === 'agents').status, 'CONFIGURED');
  assert.equal(report.integrations.find((entry: { id: string }) => entry.id === 'blender').supported, false);
  assert.equal(report.security.agentExecution, 'GITHUB_HOSTED');
  assert.ok(!response.body.includes('encryptedAccessToken'));
  assert.ok(!response.body.includes('DATABASE_URL='));
});

test('repository listing supports explicit pages and indicates continuation without exposing credentials', async (context) => {
  const config = testConfig();
  const accountId = 'cltestaccount0000000000001';
  const pages: string[] = [];
  const app = createApp({
    config,
    prisma: makePrisma('csrf', {
      gitHubAccount: {
        findFirst: async (args: { where: { id: string; userId: string } }) => {
          assert.deepEqual(args.where, { id: accountId, userId: 'user-id' });
          return {
            id: accountId, userId: 'user-id', status: 'ACTIVE', tokenExpiresAt: null,
            encryptedAccessToken: encryptSecret('fixture-github-token', config.APP_ENCRYPTION_KEY!),
          };
        },
      },
    }),
    fetcher: async (input) => {
      const url = new URL(String(input));
      pages.push(url.searchParams.get('page')!);
      return new Response(JSON.stringify([{
        id: 123, full_name: 'fixture/repository', name: 'repository',
        default_branch: 'main', private: true, owner: { login: 'fixture' },
        permissions: { push: true },
      }]), {
        status: 200,
        headers: url.searchParams.get('page') === '2'
          ? { link: '<https://api.github.com/user/repos?page=3>; rel="next"' }
          : {},
      });
    },
  });
  context.after(() => app.close());
  const headers = { authorization: 'Bearer fixture-session' };
  const second = await app.inject({ url: `/api/github/accounts/${accountId}/repositories?page=2`, headers });
  assert.equal(second.statusCode, 200);
  assert.equal(second.json().nextPage, 3);
  assert.deepEqual(second.json().repositories[0], {
    id: '123', fullName: 'fixture/repository', name: 'repository', owner: 'fixture',
    defaultBranch: 'main', isPrivate: true, canPush: true,
  });
  assert.ok(!second.body.includes('fixture-github-token'));
  const third = await app.inject({ url: `/api/github/accounts/${accountId}/repositories?page=3`, headers });
  assert.equal(third.json().nextPage, null);
  assert.deepEqual(pages, ['2', '3']);
  for (const page of ['0', '-1', '1.5', 'invalid']) {
    const invalid = await app.inject({ url: `/api/github/accounts/${accountId}/repositories?page=${page}`, headers });
    assert.equal(invalid.statusCode, 400);
  }
  assert.deepEqual(pages, ['2', '3']);
});

for (const scenario of [
  { status: 401, rateLimited: false, expected: 401, code: 'GITHUB_REAUTH_REQUIRED', updates: 1 },
  { status: 403, rateLimited: false, expected: 403, code: 'GITHUB_REPOSITORY_FORBIDDEN', updates: 0 },
  { status: 403, rateLimited: true, expected: 429, code: 'GITHUB_RATE_LIMITED', updates: 0 },
  { status: 429, rateLimited: false, expected: 429, code: 'GITHUB_RATE_LIMITED', updates: 0 },
]) {
  test(`repository listing handles ${scenario.status}${scenario.rateLimited ? ' rate limit' : ''} without falsely revoking an account`, async (context) => {
    const config = testConfig();
    let updates = 0;
    const app = createApp({
      config,
      prisma: makePrisma('csrf', {
        gitHubAccount: {
          findFirst: async () => ({
            status: 'ACTIVE', tokenExpiresAt: null,
            encryptedAccessToken: encryptSecret('fixture-token', config.APP_ENCRYPTION_KEY!),
          }),
          update: async () => { updates++; },
        },
      }),
      fetcher: async () => new Response('{}', {
        status: scenario.status,
        headers: scenario.rateLimited ? { 'x-ratelimit-remaining': '0' } : {},
      }),
    });
    context.after(() => app.close());
    const response = await app.inject({
      url: '/api/github/accounts/cltestaccount0000000000001/repositories',
      headers: { authorization: 'Bearer fixture-session' },
    });
    assert.equal(response.statusCode, scenario.expected);
    assert.equal(response.json().error.code, scenario.code);
    assert.equal(updates, scenario.updates);
  });
}

test('repository listing reports transport and malformed-response errors explicitly', async (context) => {
  const config = testConfig();
  const replies: Array<Response | Error> = [
    new TypeError('offline'),
    new Response('invalid-json', { status: 200 }),
    new Response('{}', { status: 200 }),
  ];
  const app = createApp({
    config,
    prisma: makePrisma('csrf', {
      gitHubAccount: {
        findFirst: async () => ({
          status: 'ACTIVE', tokenExpiresAt: null,
          encryptedAccessToken: encryptSecret('fixture-token', config.APP_ENCRYPTION_KEY!),
        }),
      },
    }),
    fetcher: async () => {
      const reply = replies.shift();
      if (!reply) throw new Error('Unexpected GitHub request.');
      if (reply instanceof Error) throw reply;
      return reply;
    },
  });
  context.after(() => app.close());
  for (const code of ['GITHUB_REPOSITORIES_UNAVAILABLE', 'GITHUB_REPOSITORIES_INVALID', 'GITHUB_REPOSITORIES_INVALID']) {
    const response = await app.inject({
      url: '/api/github/accounts/cltestaccount0000000000001/repositories',
      headers: { authorization: 'Bearer fixture-session' },
    });
    assert.equal(response.statusCode, 502);
    assert.equal(response.json().error.code, code);
  }
});

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
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
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

  assert.equal(response.statusCode, 201, response.body);
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

test('stores encrypted PDF versions, extracts text, and only serves project documents to their owner', async (context) => {
  const key = testConfig().APP_ENCRYPTION_KEY!;
  const projectId = `c${'1'.repeat(24)}`;
  type TestDocument = { id: string; projectId: string; filename: string; currentVersion: number };
  type TestDocumentVersion = {
    id: string;
    documentId: string;
    uploadedById: string;
    version: number;
    contentHash: string;
    sizeBytes: number;
    pageCount: number;
    encryptedContent: string;
    extractedText: string;
    createdAt: Date;
  };
  let currentDocument: TestDocument | undefined;
  const documentVersions: TestDocumentVersion[] = [];
  const prisma = makePrisma('csrf-secret', {
    project: {
      create: async ({ data }: { data: Record<string, unknown> }) => ({
        id: projectId,
        ...data,
        createdAt: new Date(),
        updatedAt: new Date(),
      }),
      findFirst: async ({ where }: { where: { id: string; userId: string } }) =>
        where.id === projectId && where.userId === 'user-id' ? { id: projectId } : null,
    },
    documentVersion: {
      findFirst: async ({ where }: {
        where: {
          documentId: string;
          version: number;
          document: { project: { userId: string } };
        };
      }) => {
        if (where.document.project.userId !== 'user-id' || currentDocument?.id !== where.documentId) {
          return null;
        }
        const version = documentVersions.find((candidate) =>
          candidate.documentId === where.documentId && candidate.version === where.version);
        return version ? { ...version, document: { filename: currentDocument.filename } } : null;
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  });
  const transaction = {
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
    document: {
      findFirst: async () => currentDocument ?? null,
      create: async ({ data }: { data: Record<string, unknown> }) => {
        currentDocument = {
          id: `c${'2'.repeat(24)}`,
          projectId: String(data.projectId),
          filename: String(data.filename),
          currentVersion: 1,
        };
        return currentDocument;
      },
      updateMany: async ({ where, data }: {
        where: { id: string; currentVersion: number };
        data: { currentVersion: number };
      }) => {
        if (currentDocument?.id !== where.id || currentDocument.currentVersion !== where.currentVersion) {
          return { count: 0 };
        }
        currentDocument.currentVersion = data.currentVersion;
        return { count: 1 };
      },
    },
    documentVersion: {
      create: async ({ data }: { data: Omit<TestDocumentVersion, 'id' | 'createdAt'> }) => {
        const version: TestDocumentVersion = {
          id: `version-${data.version}`,
          ...data,
          createdAt: new Date(),
        };
        documentVersions.push(version);
        return {
          id: version.id,
          version: version.version,
          contentHash: version.contentHash,
          sizeBytes: version.sizeBytes,
          pageCount: version.pageCount,
          createdAt: version.createdAt,
        };
      },
      findFirst: async ({ where }: { where: { documentId: string; version: number } }) => {
        const version = documentVersions.find(
          (candidate) => candidate.documentId === where.documentId && candidate.version === where.version,
        );
        return version && currentDocument
          ? { ...version, document: { filename: currentDocument.filename } }
          : null;
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  Object.assign(prisma, { $transaction: async (callback: (client: typeof transaction) => Promise<unknown>) => callback(transaction) });
  const app = createApp({
    prisma,
    config: testConfig(),
    pdfExtractor: async () => ({ text: 'Project requirement, page one.', pageCount: 1 }),
  });
  context.after(() => app.close());
  const headers = { authorization: 'Bearer test-session-token', 'x-csrf-token': 'csrf-secret' };
  const created = await app.inject({
    method: 'POST',
    url: '/api/projects',
    headers: { ...headers, 'content-type': 'application/json' },
    payload: { name: 'PDF project', description: 'Requirements', repository: 'owner/repo' },
  });
  assert.equal(created.statusCode, 201);
  assert.equal(created.json().project.id, projectId);

  const pdf = Buffer.from('%PDF-1.7\\nprivate document content\\n%%EOF');
  const firstUpload = await app.inject({
    method: 'POST',
    url: `/api/projects/${projectId}/documents?filename=requirements.pdf`,
    headers: { ...headers, 'content-type': 'application/pdf' },
    payload: pdf,
  });
  assert.equal(firstUpload.statusCode, 201);
  assert.equal(firstUpload.json().document.version, 1);
  assert.equal(documentVersions.length, 1);
  assert.notEqual(documentVersions[0].encryptedContent, pdf.toString('base64'));
  assert.deepEqual(
    Buffer.from(decryptSecret(documentVersions[0].encryptedContent, key), 'base64'),
    pdf,
  );

  const secondUpload = await app.inject({
    method: 'POST',
    url: `/api/projects/${projectId}/documents?filename=requirements.pdf`,
    headers: { ...headers, 'content-type': 'application/pdf' },
    payload: pdf,
  });
  assert.equal(secondUpload.statusCode, 201);
  assert.equal(secondUpload.json().document.version, 2);

  const textVersion = await app.inject({
    method: 'GET',
    url: `/api/documents/${currentDocument!.id}/versions/1`,
    headers: { authorization: 'Bearer test-session-token' },
  });
  assert.equal(textVersion.statusCode, 200);
  assert.equal(textVersion.json().document.extractedText, 'Project requirement, page one.');

  const download = await app.inject({
    method: 'GET',
    url: `/api/documents/${currentDocument!.id}/versions/1/download`,
    headers: { authorization: 'Bearer test-session-token' },
  });
  assert.equal(download.statusCode, 200);
  assert.match(download.headers['content-disposition']?.toString() ?? '', /requirements\.pdf/);
  assert.deepEqual(download.rawPayload, pdf);

  const invalidPdf = await app.inject({
    method: 'POST',
    url: `/api/projects/${projectId}/documents?filename=bad.pdf`,
    headers: { ...headers, 'content-type': 'application/pdf' },
    payload: Buffer.from('not a PDF'),
  });
  assert.equal(invalidPdf.statusCode, 415);
  assert.equal(invalidPdf.json().error.code, 'PDF_INVALID');

  const privateProject = await app.inject({
    method: 'POST',
    url: `/api/projects/c${'3'.repeat(24)}/documents?filename=private.pdf`,
    headers: { ...headers, 'content-type': 'application/pdf' },
    payload: pdf,
  });
  assert.equal(privateProject.statusCode, 404);
  assert.equal(privateProject.json().error.code, 'PROJECT_NOT_FOUND');
});

test('scans an owned GitHub project and stores pinned progress evidence', async (context) => {
  const config = testConfig();
  const commitSha = 'a'.repeat(40);
  let savedScan: Record<string, unknown> | undefined;
  const progressText = Buffer.from('- [DONE] Authentication\n- [IN_PROGRESS] Project scan').toString('base64');
  const prisma = makePrisma('csrf-secret', {
    project: {
      findFirst: async ({ where }: { where: { id: string; userId: string } }) =>
        where.id === `c${'1'.repeat(24)}` && where.userId === 'user-id'
          ? { id: where.id, name: 'Project', repository: 'owner/repository' }
          : null,
    },
    gitHubAccount: {
      findFirst: async ({ where }: { where: { id: string; userId: string } }) =>
        where.id === `c${'2'.repeat(24)}` && where.userId === 'user-id'
          ? {
              id: where.id,
              login: 'owner',
              status: 'ACTIVE',
              tokenExpiresAt: null,
              encryptedAccessToken: encryptSecret('scan-token', config.APP_ENCRYPTION_KEY!),
            }
          : null,
    },
    projectScan: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        savedScan = data;
        return { id: 'scan-id', ...data, scannedAt: new Date() };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  });
  const fetcher: typeof fetch = async (input) => {
    const url = String(input);
    if (url.endsWith('/repos/owner/repository')) {
      return Response.json({
        full_name: 'owner/repository',
        default_branch: 'main',
        open_issues_count: 2,
      });
    }
    if (url.endsWith('/commits?per_page=1')) return Response.json([{ sha: commitSha }]);
    if (url.endsWith(`/git/trees/${commitSha}?recursive=1`)) {
      return Response.json({
        truncated: false,
        tree: [
          { path: 'TASKS.md', type: 'blob', size: 48 },
          { path: 'src/main.ts', type: 'blob', size: 20 },
          { path: 'tests/main.test.ts', type: 'blob', size: 20 },
        ],
      });
    }
    if (url.endsWith(`/contents/TASKS.md?ref=${commitSha}`)) {
      return Response.json({
        type: 'file',
        encoding: 'base64',
        content: progressText,
        size: 48,
      });
    }
    throw new Error(`Unexpected GitHub API request: ${url}`);
  };
  const app = createApp({ prisma, config, fetcher });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'POST',
    url: `/api/projects/c${'1'.repeat(24)}/scan`,
    headers: {
      authorization: 'Bearer project-scan-session',
      'x-csrf-token': 'csrf-secret',
    },
    payload: { githubAccountId: `c${'2'.repeat(24)}` },
  });

  assert.equal(response.statusCode, 201, response.body);
  assert.equal(response.json().scan.lifecycleStage, 'IMPLEMENTATION');
  assert.equal(response.json().scan.commitSha, commitSha);
  assert.equal(savedScan?.accountLogin, 'owner');
  assert.equal(savedScan?.repository, 'owner/repository');
  assert.deepEqual(savedScan?.taskCounts, { done: 1, inProgress: 1, blocked: 0, todo: 0 });
});

test('does not start or complete project tasks while prerequisites remain open', async (context) => {
  const taskId = `c${'4'.repeat(24)}`;
  let updateCalled = false;
  const transaction = {
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
    projectTask: {
      findFirst: async () => ({
        id: taskId,
        prerequisites: [{ dependsOn: { id: `c${'5'.repeat(24)}`, title: 'Prerequisite', status: 'IN_PROGRESS' } }],
      }),
      update: async () => {
        updateCalled = true;
        return { id: taskId, status: 'IN_PROGRESS' };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) =>
        callback(transaction),
    }),
    config: testConfig(),
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'PATCH',
    url: `/api/tasks/${taskId}`,
    headers: {
      authorization: 'Bearer project-task-session',
      'x-csrf-token': 'csrf-secret',
    },
    payload: { status: 'IN_PROGRESS' },
  });

  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'TASK_DEPENDENCIES_UNMET');
  assert.equal(updateCalled, false);
});

test('rejects a project task dependency update that would form a cycle', async (context) => {
  const taskId = `c${'4'.repeat(24)}`;
  const dependencyId = `c${'5'.repeat(24)}`;
  let dependenciesDeleted = false;
  const transaction = {
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
    projectTask: {
      findFirst: async () => ({ id: taskId, projectId: 'project-id' }),
      findMany: async () => [{ id: dependencyId }],
    },
    taskDependency: {
      findMany: async () => [{ taskId: dependencyId, dependsOnTaskId: taskId }],
      deleteMany: async () => {
        dependenciesDeleted = true;
        return { count: 1 };
      },
      createMany: async () => ({ count: 1 }),
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  };
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) =>
        callback(transaction),
    }),
    config: testConfig(),
  });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'PUT',
    url: `/api/tasks/${taskId}/dependencies`,
    headers: {
      authorization: 'Bearer project-task-session',
      'x-csrf-token': 'csrf-secret',
    },
    payload: { dependencyIds: [dependencyId] },
  });

  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'TASK_DEPENDENCY_CYCLE');
  assert.equal(dependenciesDeleted, false);
});

test('creates a user-owned team and assigns only a bot owned by the same user', async (context) => {
  let createdTeam: Record<string, unknown> | undefined;
  let assignedBot: Record<string, unknown> | undefined;
  const prisma = makePrisma('csrf-secret', {
    team: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        createdTeam = data;
        return { id: `c${'6'.repeat(24)}`, ...data };
      },
      findFirst: async () => ({ id: `c${'6'.repeat(24)}` }),
    },
    bot: {
      findFirst: async () => ({ id: `c${'7'.repeat(24)}` }),
    },
    teamBot: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        assignedBot = data;
        return { id: 'membership-id', ...data };
      },
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  });
  const app = createApp({ prisma, config: testConfig() });
  context.after(() => app.close());

  const headers = {
    authorization: 'Bearer teams-session',
    'x-csrf-token': 'csrf-secret',
  };
  const created = await app.inject({
    method: 'POST',
    url: '/api/teams',
    headers,
    payload: { name: 'Frontend', description: 'Web application agents' },
  });
  assert.equal(created.statusCode, 201);
  assert.equal(createdTeam?.userId, 'user-id');
  const assigned = await app.inject({
    method: 'POST',
    url: `/api/teams/c${'6'.repeat(24)}/bots`,
    headers,
    payload: { botId: `c${'7'.repeat(24)}` },
  });
  assert.equal(assigned.statusCode, 201);
  assert.deepEqual(assignedBot, {
    teamId: `c${'6'.repeat(24)}`,
    botId: `c${'7'.repeat(24)}`,
  });
});

test('persists project collaboration messages, help requests and manual checkpoints', async (context) => {
  const projectId = `c${'8'.repeat(24)}`;
  const messages: Record<string, unknown>[] = [];
  const helpRequests: Record<string, unknown>[] = [];
  const checkpoints: Record<string, unknown>[] = [];
  let id = 0;
  const nextId = () => `c${String(++id).padStart(24, '0')}`;
  const author = { id: 'user-id', displayName: 'Project owner' };
  const prisma = makePrisma('csrf-secret', {
    project: {
      findFirst: async ({ where }: { where: { id: string; userId: string } }) =>
        where.id === projectId && where.userId === 'user-id' ? { id: projectId } : null,
    },
    projectMessage: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        const message = { id: nextId(), ...data, author };
        messages.push(message);
        return message;
      },
      findMany: async () => messages,
    },
    projectHelpRequest: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        const helpRequest = { id: nextId(), status: 'OPEN', ...data, author };
        helpRequests.push(helpRequest);
        return helpRequest;
      },
      findMany: async () => helpRequests,
      findFirst: async ({ where }: { where: { id: string; projectId: string } }) =>
        helpRequests.find((item) => item.id === where.id && item.projectId === where.projectId) ?? null,
      update: async ({ where, data }: {
        where: { id: string };
        data: Record<string, unknown>;
      }) => {
        const existing = helpRequests.find((item) => item.id === where.id)!;
        Object.assign(existing, data);
        return existing;
      },
    },
    projectCheckpoint: {
      create: async ({ data }: { data: Record<string, unknown> }) => {
        const checkpoint = { id: nextId(), ...data, author };
        checkpoints.push(checkpoint);
        return checkpoint;
      },
      findMany: async () => checkpoints,
    },
    auditEvent: { create: async () => ({ id: 'audit-id' }) },
  });
  const app = createApp({ prisma, config: testConfig() });
  context.after(() => app.close());
  const headers = {
    authorization: 'Bearer collaboration-test-session',
    'x-csrf-token': 'csrf-secret',
  };

  const message = await app.inject({
    method: 'POST',
    url: `/api/projects/${projectId}/messages`,
    headers,
    payload: { content: 'Review the new project plan.' },
  });
  assert.equal(message.statusCode, 201);
  assert.equal(message.json().message.authorUserId, 'user-id');

  const helpRequest = await app.inject({
    method: 'POST',
    url: `/api/projects/${projectId}/help-requests`,
    headers,
    payload: { title: 'Need API review', description: 'Please check the contract.' },
  });
  assert.equal(helpRequest.statusCode, 201);
  const resolved = await app.inject({
    method: 'PATCH',
    url: `/api/projects/${projectId}/help-requests/${helpRequest.json().helpRequest.id}`,
    headers,
    payload: { status: 'RESOLVED' },
  });
  assert.equal(resolved.statusCode, 200);
  assert.equal(resolved.json().helpRequest.status, 'RESOLVED');

  const checkpoint = await app.inject({
    method: 'POST',
    url: `/api/projects/${projectId}/checkpoints`,
    headers,
    payload: {
      title: 'Plan review',
      notes: 'Manual progress note.',
      commitSha: 'a'.repeat(40),
      progressStage: 'PLANNING',
    },
  });
  assert.equal(checkpoint.statusCode, 201);
  assert.equal(checkpoint.json().checkpoint.commitSha, 'a'.repeat(40));

  const history = await app.inject({
    method: 'GET',
    url: `/api/projects/${projectId}/collaboration`,
    headers: { authorization: 'Bearer collaboration-test-session' },
  });
  assert.equal(history.statusCode, 200);
  assert.equal(history.json().messages.length, 1);
  assert.equal(history.json().helpRequests[0].status, 'RESOLVED');
  assert.equal(history.json().checkpoints[0].progressStage, 'PLANNING');
});

test('does not expose collaboration records for another user project', async (context) => {
  const prisma = makePrisma('csrf-secret', {
    project: { findFirst: async () => null },
  });
  const app = createApp({ prisma, config: testConfig() });
  context.after(() => app.close());

  const response = await app.inject({
    method: 'GET',
    url: `/api/projects/c${'9'.repeat(24)}/collaboration`,
    headers: { authorization: 'Bearer collaboration-test-session' },
  });

  assert.equal(response.statusCode, 404);
  assert.equal(response.json().error.code, 'PROJECT_NOT_FOUND');
});

test('signs in with a legacy short password and case-insensitive email', async (context) => {
  const passwordHash = await hashPassword('short');
  let createdSession: Record<string, unknown> | undefined;
  const transaction = {
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
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
    payload: { email: 'PERSON@example.com', password: 'short' },
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
  assert.equal(response.json().stageApproval, true);
  assert.deepEqual(response.json().projectScanning, {
    repositoryInventory: true,
    progressEvidence: true,
    commitPinned: true,
    latestScanIncludedInCopilotTask: true,
  });
  assert.deepEqual(response.json().projectCollaboration, {
    messages: true,
    helpRequests: true,
    manualCheckpointNotes: true,
    agentMessaging: false,
    runtimeCheckpointResume: false,
  });
  assert.deepEqual(response.json().reviewEvidence, {
    ci: true,
    manualTests: true,
    preview: false,
    previewEnforced: false,
  });
  assert.equal(response.json().planning.automaticBilling, false);
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

const sha = 'a'.repeat(40);

function approvalApp(options: { ci: string; manual: string | null; stageStatus?: string }) {
  const config = testConfig();
  const pullRequest = {
    id: 'clpr0000000000000000000000',
    stageId: 'clstage00000000000000000000',
    repository: 'owner/repo',
    number: 7,
    stage: {
      bot: { githubAccount: { status: 'ACTIVE', encryptedAccessToken: encryptSecret('tok', config.APP_ENCRYPTION_KEY!) } },
    },
  };
  const fetcher: typeof fetch = async (input) => {
    const url = String(input);
    if (url.endsWith('/pulls/7')) {
      return Response.json({ state: 'open', head: { sha } });
    }
    return Response.json({ check_runs: options.ci === 'none' ? [] : [{ status: 'completed', conclusion: options.ci }] });
  };
  let status = options.stageStatus ?? 'WAITING_APPROVAL';
  const transaction = {
    stage: {
      findFirst: async () => ({ id: 'clstage00000000000000000000', botId: 'b', number: 1, status, bot: {} }),
      findMany: async () => [{ number: 1, status }],
      updateMany: async ({ data }: { data: { status: string; approvedAt: Date | null } }) => {
        status = data.status;
        assert.ok(data.approvedAt instanceof Date);
        return { count: 1 };
      },
    },
    stageTransitionEvent: { create: async () => ({}) },
    auditEvent: { create: async () => ({}) },
  };
  const prisma = makePrisma('csrf-secret', {
    pullRequest: { findFirst: async () => pullRequest },
    reviewEvidence: {
      findFirst: async ({ where }: { where: { kind: string; commitSha: string } }) => (
        where.kind === 'MANUAL_TEST' && options.manual && where.commitSha === sha
          ? { result: options.manual }
          : null
      ),
    },
    $transaction: async (callback: (client: unknown) => Promise<unknown>) => callback(transaction),
  });
  return { app: createApp({ prisma, config, fetcher }), getStatus: () => status };
}

const approveRequest = {
  method: 'POST' as const,
  url: '/api/stages/clstage00000000000000000000/approve',
  headers: {
    authorization: 'Bearer review-test-session',
    'x-csrf-token': 'csrf-secret',
  },
};

test('blocks stage approval without green CI for the exact commit', async (context) => {
  const { app } = approvalApp({ ci: 'failure', manual: 'PASSED' });
  context.after(() => app.close());
  const response = await app.inject(approveRequest);
  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'REVIEW_EVIDENCE_REQUIRED');
});

test('blocks stage approval without a passed manual test bound to the head SHA', async (context) => {
  const { app } = approvalApp({ ci: 'success', manual: null });
  context.after(() => app.close());
  const response = await app.inject(approveRequest);
  assert.equal(response.statusCode, 409);
  const failed = approvalApp({ ci: 'success', manual: 'FAILED' });
  context.after(() => failed.app.close());
  assert.equal((await failed.app.inject(approveRequest)).statusCode, 409);
});

test('approves a stage only after verified CI and a manual test for the head SHA', async (context) => {
  const { app, getStatus } = approvalApp({ ci: 'success', manual: 'PASSED' });
  context.after(() => app.close());
  const response = await app.inject(approveRequest);
  assert.equal(response.statusCode, 200);
  assert.equal(getStatus(), 'APPROVED');
});

test('blocks stage start outside the configured work window and over budget', async (context) => {
  const outside = (extra: Record<string, unknown>) => createApp({
    prisma: makePrisma('csrf-secret', {
      $transaction: async (callback: (client: unknown) => Promise<unknown>) => callback({
        stage: { findFirst: async () => ({ id: 'x', bot: { githubAccount: {} }, transitions: [] }) },
        workSchedule: { findUnique: async () => ({ enabled: true, timezone: 'UTC', windows: [] }) },
        costBudget: { findUnique: async () => null },
        costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
        ...extra,
      }),
    }),
    config: testConfig(),
  });
  const app = outside({});
  context.after(() => app.close());
  const response = await app.inject({ ...approveRequest, url: '/api/stages/clstage00000000000000000000/start' });
  assert.equal(response.statusCode, 409);
  assert.equal(response.json().error.code, 'OUTSIDE_WORK_WINDOW');

  const budgeted = outside({
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => ({ enforce: true, currency: 'USD', monthlyLimitMinor: 1000 }) },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 1000 } }) },
  });
  context.after(() => budgeted.close());
  const second = await budgeted.inject({ ...approveRequest, url: '/api/stages/clstage00000000000000000000/start' });
  assert.equal(second.json().error.code, 'BUDGET_EXCEEDED');
});

test('imports costs from CSV and rejects invalid rows', async (context) => {
  let created: unknown[] = [];
  const app = createApp({
    prisma: makePrisma('csrf-secret', {
      costEntry: { createMany: async ({ data }: { data: unknown[] }) => { created = data; return { count: data.length }; } },
    }),
    config: testConfig(),
  });
  context.after(() => app.close());
  const send = (csv: string) => app.inject({ ...approveRequest, url: '/api/costs/import', payload: { csv } });
  const ok = await send('date,category,amount,currency,description\n2026-10-01,USAGE,5.25,usd,Calls');
  assert.equal(ok.statusCode, 201);
  assert.equal((created[0] as { amountMinor: number }).amountMinor, 525);
  const bad = await send('date,category,amount,currency,description\n2026-10-01,FREE,5,usd,x');
  assert.equal(bad.statusCode, 400);
  assert.equal(bad.json().error.code, 'COST_CSV_INVALID');
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
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
    stage: {
      findFirst: async () => ({
        id: 'clstage00000000000000000000',
        botId: 'clbot0000000000000000000000',
        number: 1,
        status: 'RUNNING',
        bot: { definitionId: null },
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
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
    stage: {
      findFirst: async () => ({ ...stage, status: stageStatus }),
      findMany: async () => [{ number: 1, title: 'Update the application', status: stageStatus }],
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
      projectScan: { findFirst: async () => null },
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

test('starts a team-role stage remotely with its encrypted GitHub account and persisted task notification', async (context) => {
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
      definitionId: 'cldefinition000000000000001',
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
    $queryRaw: async () => [],
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
    stage: {
      findFirst: async (query: { where: { id?: unknown } }) => typeof query.where.id === 'object' ? null : ({ ...stage, status: currentStatus }),
      findMany: async () => [{ number: 1, title: 'Update the application', status: currentStatus }],
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
      stage: { update: async () => stage },
      projectScan: {
        findFirst: async () => ({
          branch: 'main',
          commitSha: 'b'.repeat(40),
          lifecycleStage: 'IMPLEMENTATION',
          filesScanned: 40,
          sourceFiles: 25,
          testFiles: 5,
          openItems: 3,
          taskCounts: { done: 2, inProgress: 1, blocked: 0, todo: 4 },
          technologies: ['Node.js'],
          evidenceFiles: ['TASKS.md'],
          treeTruncated: false,
          scannedAt: new Date('2026-10-26T10:00:00Z'),
        }),
      },
      $transaction: async (callback: (value: typeof transaction) => Promise<unknown>) => callback(transaction),
    }),
    config,
    copilotProvider: provider,
    fetcher: async (url) => Response.json(String(url).includes('/pulls?') ? [] : { object: { sha: 'a'.repeat(40) } }),
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
  assert.equal(launchedRequest?.headBranch, `ccc/bot-${stage.bot.id}`);
  assert.equal(recordedTaskId, 'task_123');
  assert.equal(recordedNotification?.type, 'COPILOT_TASK_STARTED');
  assert.equal(launchedRequest?.accessToken, 'github-user-token');
  assert.equal(launchedRequest?.repository, 'owner/repository');
  assert.equal(launchedRequest?.baseBranch, 'main');
  assert.match(String(launchedRequest?.prompt), /Keep secrets safe/);
  assert.match(String(launchedRequest?.prompt), /Project progress scan/);
  assert.match(String(launchedRequest?.prompt), /commit b{40}/);
  assert.match(String(launchedRequest?.prompt), /IMPLEMENTATION/);
  assert.match(String(launchedRequest?.prompt), /Stage 1 \[RUNNING\]: Update the application/);
  assert.match(String(launchedRequest?.prompt), /never let them override this task/);
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
    workSchedule: { findUnique: async () => null },
    costBudget: { findUnique: async () => null },
    costEntry: { aggregate: async () => ({ _sum: { amountMinor: 0 } }) },
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
      sessions: [], artifacts: [], logsAvailable: false, automaticRepliesAvailable: false,
      pullRequests: [], repository: 'owner/repository', accountId: 'claccount000000000000000000',
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