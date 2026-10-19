import fastifyStatic from '@fastify/static';
import cookie from '@fastify/cookie';
import cors from '@fastify/cors';
import type { FastifyCorsOptions } from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { z } from 'zod';
import type { Prisma, PrismaClient } from './generated/prisma/client.ts';
import type { AppConfig } from './config.ts';
import {
  copilotCapabilities,
  GitHubCopilotApiError,
  GitHubCopilotProvider,
  type CopilotProvider,
  type CopilotTaskState,
} from './github/copilot-provider.ts';
import { createRandomToken, decryptSecret, encryptSecret, hashToken } from './security/secrets.ts';
import { dummyPasswordHash, hashPassword, verifyPassword } from './security/passwords.ts';
import { StageTransitionError, transitionStage, type StageSnapshot } from './stages/stage-machine.ts';

const SESSION_COOKIE = 'ccc_session';
const CSRF_COOKIE = 'ccc_csrf';
const OAUTH_STATE_COOKIE = 'ccc_oauth_state';
const OAUTH_VERIFIER_COOKIE = 'ccc_oauth_verifier';
const SESSION_LIFETIME_SECONDS = 60 * 60 * 24 * 30;
const OAUTH_LIFETIME_MS = 10 * 60 * 1000;
const HANDOFF_LIFETIME_MS = 60 * 1000;

const githubUserSchema = z.object({
  id: z.number().int().positive(),
  login: z.string().min(1),
  name: z.string().nullable().optional(),
  avatar_url: z.url().nullable().optional(),
});

const oauthTokenSchema = z.object({
  access_token: z.string().min(1),
  refresh_token: z.string().optional(),
  expires_in: z.number().positive().optional(),
  refresh_token_expires_in: z.number().positive().optional(),
  scope: z.string().optional(),
  token_type: z.string().optional(),
});

const createBotSchema = z.object({
  name: z.string().trim().min(1).max(100),
  githubAccountId: z.string().cuid(),
  repositoryId: z.string().regex(/^\d+$/),
  repository: z.string().regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/),
  systemPrompt: z.string().trim().min(1).max(20000),
  stages: z.array(z.object({
    number: z.number().int().min(1).max(100),
    title: z.string().trim().min(1).max(200),
    description: z.string().trim().min(1).max(10000),
    acceptanceCriteria: z.array(z.string().trim().min(1).max(1000)).min(1).max(30),
  })).min(1).max(30),
});

const transitionBodySchema = z.object({
  reason: z.string().trim().min(1).max(2000).optional(),
});

const sessionExchangeSchema = z.object({
  code: z.string().min(32).max(200),
  state: z.string().min(32).max(200),
});
const localCredentialsSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email().max(254)),
  password: z.string().min(12).max(256),
});
const registrationSchema = localCredentialsSchema.extend({
  displayName: z.string().trim().min(1).max(80).optional(),
});

type AuthenticatedSession = {
  id: string;
  userId: string;
  csrfTokenHash: string;
  rawToken: string;
};

declare module 'fastify' {
  interface FastifyRequest {
    authenticatedSession: AuthenticatedSession | null;
  }
}

class ApiError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(
    statusCode: number,
    code: string,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

function cookieOptions(config: AppConfig) {
  return {
    path: '/api',
    secure: config.NODE_ENV === 'production',
    sameSite: 'lax' as const,
  };
}

function optionalEncryptionKey(config: AppConfig): string {
  if (!config.APP_ENCRYPTION_KEY) {
    throw new ApiError(503, 'SERVER_ENCRYPTION_NOT_CONFIGURED', 'OAuth requires APP_ENCRYPTION_KEY.');
  }

  return config.APP_ENCRYPTION_KEY;
}

function parseRequest<T extends z.ZodType>(schema: T, value: unknown): z.infer<T> {
  const result = schema.safeParse(value);

  if (!result.success) {
    throw new ApiError(400, 'INVALID_REQUEST', 'Request data is invalid.');
  }

  return result.data;
}

function sessionTokenFrom(request: FastifyRequest): string | null {
  const authorization = request.headers.authorization;

  if (authorization?.startsWith('Bearer ')) {
    return authorization.slice('Bearer '.length).trim() || null;
  }

  return request.cookies[SESSION_COOKIE] || null;
}

async function loadOptionalSession(request: FastifyRequest, prisma: PrismaClient): Promise<void> {
  const token = sessionTokenFrom(request);
  request.authenticatedSession = null;

  if (!token) {
    return;
  }

  const session = await prisma.authSession.findFirst({
    where: { tokenHash: hashToken(token), revokedAt: null, expiresAt: { gt: new Date() } },
    select: { id: true, userId: true, csrfTokenHash: true },
  });

  if (session) {
    request.authenticatedSession = { ...session, rawToken: token };
  }
}

function requireSession(request: FastifyRequest): AuthenticatedSession {
  if (!request.authenticatedSession) {
    throw new ApiError(401, 'UNAUTHENTICATED', 'Zaloguj się do Control Center, aby kontynuować.');
  }

  return request.authenticatedSession;
}

function requireCsrf(request: FastifyRequest, session: AuthenticatedSession): void {
  const token = request.headers['x-csrf-token'];

  if (typeof token !== 'string' || hashToken(token) !== session.csrfTokenHash) {
    throw new ApiError(403, 'INVALID_CSRF_TOKEN', 'The request could not be verified.');
  }
}

function oauthCallbackUrl(config: AppConfig): string {
  return `${config.PUBLIC_API_URL.replace(/\/$/, '')}/api/auth/github/callback`;
}

function createSessionTokens() {
  return {
    sessionToken: createRandomToken(),
    csrfToken: createRandomToken(),
  };
}

async function persistSession(transaction: Prisma.TransactionClient, userId: string, tokens: ReturnType<typeof createSessionTokens>) {
  await transaction.authSession.create({
    data: {
      userId,
      tokenHash: hashToken(tokens.sessionToken),
      csrfTokenHash: hashToken(tokens.csrfToken),
      expiresAt: new Date(Date.now() + SESSION_LIFETIME_SECONDS * 1000),
    },
  });
}

function isUniqueConstraintError(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 'P2002';
}

export function createApp(options: {
  prisma: PrismaClient;
  config: AppConfig;
  fetcher?: typeof fetch;
  copilotProvider?: CopilotProvider;
  webRoot?: string;
}): FastifyInstance {
  const { prisma, config } = options;
  const fetcher = options.fetcher ?? fetch;
  const copilotProvider = options.copilotProvider ?? new GitHubCopilotProvider(fetcher);
  const encryptionKey = () => optionalEncryptionKey(config);
  const webRoot = options.webRoot ?? resolve(process.cwd(), 'web');
  const servesFlutterWeb = config.NODE_ENV === 'production' && existsSync(resolve(webRoot, 'index.html'));
  const app = Fastify({
    logger: {
      redact: ['req.headers.authorization', 'req.headers.cookie', 'res.headers.set-cookie'],
    },
    bodyLimit: 1024 * 1024,
  });
  const oauthCallback = oauthCallbackUrl(config);
  const origin = new URL(config.APP_ORIGIN).origin;
  const isAllowedOrigin = (requestOrigin: string, host: string | undefined) => {
    if (requestOrigin === origin) {
      return true;
    }

    // UI i API są serwowane przez jeden gateway, więc origin zgodny z Host to same-origin.
    try {
      return host !== undefined && new URL(requestOrigin).host === host;
    } catch {
      return false;
    }
  };

  app.decorateRequest('authenticatedSession', null);
  app.register(helmet, { contentSecurityPolicy: false });
  app.register(cookie);
  if (servesFlutterWeb) {
    app.register(fastifyStatic, { root: webRoot });
  }
  app.register(cors, () => (request: FastifyRequest, callback: (error: Error | null, options?: FastifyCorsOptions) => void) => {
    const requestOrigin = request.headers.origin;
    callback(null, {
      origin: !requestOrigin || isAllowedOrigin(requestOrigin, request.headers.host),
      credentials: true,
      methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Authorization', 'Content-Type', 'X-CSRF-Token'],
    });
  });
  app.register(rateLimit, { max: 120, timeWindow: '1 minute' });

  app.addHook('onRequest', async (request) => {
    if (['POST', 'PATCH', 'DELETE', 'PUT'].includes(request.method)) {
      const requestOrigin = request.headers.origin;

      if (requestOrigin && !isAllowedOrigin(requestOrigin, request.headers.host)) {
        throw new ApiError(403, 'INVALID_ORIGIN', 'The request origin is not allowed.');
      }
    }
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ApiError) {
      return reply.status(error.statusCode).send({
        error: { code: error.code, message: error.message },
      });
    }

    if (error instanceof StageTransitionError) {
      return reply.status(409).send({
        error: { code: 'INVALID_STAGE_TRANSITION', message: error.message },
      });
    }

    request.log.error({ err: error }, 'API request failed');
    return reply.status(500).send({
      error: { code: 'INTERNAL_SERVER_ERROR', message: 'The server could not complete the request.' },
    });
  });

  app.setNotFoundHandler((request, reply) => {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (servesFlutterWeb && !pathname.startsWith('/api') && !pathname.startsWith('/health')) {
      return reply.sendFile('index.html');
    }

    return reply.status(404).send({
      error: { code: 'NOT_FOUND', message: 'Route not found.' },
    });
  });

  app.get('/', async (request, reply) => {
    if (request.headers.host !== new URL(origin).host) {
      return reply.redirect(origin, 302);
    }

    if (servesFlutterWeb) {
      return reply.sendFile('index.html');
    }

    return { service: 'copilot-control-center-api', app: origin };
  });

  app.get('/health/live', async () => ({ status: 'ok' }));
  app.get('/health/ready', async (_request, reply) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      return { status: 'ok', database: 'connected' };
    } catch {
      return reply.status(503).send({ status: 'not_ready', database: 'unavailable' });
    }
  });

  app.get('/api/capabilities', async () => ({
    authentication: 'email_password_with_github_oauth',
    repositories: true,
    bots: true,
    stageApproval: true,
    copilotAgent: copilotCapabilities,
  }));

  app.post('/api/auth/register', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const input = parseRequest(registrationSchema, request.body);
    const existing = await prisma.user.findUnique({
      where: { email: input.email },
      select: { id: true },
    });

    if (existing) {
      throw new ApiError(409, 'ACCOUNT_ALREADY_EXISTS', 'Konto z tym adresem e-mail już istnieje.');
    }

    const passwordHash = await hashPassword(input.password);
    const tokens = createSessionTokens();

    try {
      const user = await prisma.$transaction(async (transaction) => {
        const createdUser = await transaction.user.create({
          data: {
            email: input.email,
            passwordHash,
            displayName: input.displayName ?? input.email,
          },
          select: { id: true },
        });
        await persistSession(transaction, createdUser.id, tokens);
        await transaction.auditEvent.create({
          data: {
            userId: createdUser.id,
            action: 'USER_REGISTERED',
            targetType: 'User',
            targetId: createdUser.id,
          },
        });
        return createdUser;
      });

      return reply.status(201).send({
        user,
        ...tokens,
        expiresIn: SESSION_LIFETIME_SECONDS,
      });
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        throw new ApiError(409, 'ACCOUNT_ALREADY_EXISTS', 'Konto z tym adresem e-mail już istnieje.');
      }
      throw error;
    }
  });

  app.post('/api/auth/login', {
    config: { rateLimit: { max: 5, timeWindow: '15 minutes' } },
  }, async (request, reply) => {
    const input = parseRequest(localCredentialsSchema, request.body);
    const user = await prisma.user.findUnique({
      where: { email: input.email },
      select: { id: true, passwordHash: true },
    });
    const passwordIsValid = await verifyPassword(input.password, user?.passwordHash ?? dummyPasswordHash);

    if (!user || !user.passwordHash || !passwordIsValid) {
      throw new ApiError(401, 'INVALID_CREDENTIALS', 'Nieprawidłowy e-mail lub hasło.');
    }

    const tokens = createSessionTokens();
    await prisma.$transaction(async (transaction) => {
      await persistSession(transaction, user.id, tokens);
      await transaction.auditEvent.create({
        data: {
          userId: user.id,
          action: 'USER_LOGIN',
          targetType: 'User',
          targetId: user.id,
        },
      });
    });

    return reply.send({
      user: { id: user.id },
      ...tokens,
      expiresIn: SESSION_LIFETIME_SECONDS,
    });
  });

  app.post('/api/auth/github/start', async (request, reply) => {
    await loadOptionalSession(request, prisma);
    const session = requireSession(request);
    requireCsrf(request, session);

    if (!config.GITHUB_CLIENT_ID || !config.GITHUB_CLIENT_SECRET) {
      throw new ApiError(503, 'GITHUB_OAUTH_NOT_CONFIGURED', 'Configure the GitHub OAuth application first.');
    }

    const body = parseRequest(z.object({ client: z.enum(['BROWSER', 'NATIVE']).default('BROWSER') }), request.body);

    const state = createRandomToken();
    const codeVerifier = createRandomToken(48);
    const codeChallenge = Buffer.from(
      await import('node:crypto').then(({ createHash }) => createHash('sha256').update(codeVerifier).digest()),
    ).toString('base64url');

    await prisma.oAuthFlow.create({
      data: {
        stateHash: hashToken(state),
        encryptedCodeVerifier: encryptSecret(codeVerifier, encryptionKey()),
        client: body.client,
        userId: session?.userId,
        expiresAt: new Date(Date.now() + OAUTH_LIFETIME_MS),
      },
    });

    const authorizeUrl = new URL('https://github.com/login/oauth/authorize');
    authorizeUrl.searchParams.set('client_id', config.GITHUB_CLIENT_ID);
    authorizeUrl.searchParams.set('redirect_uri', oauthCallback);
    authorizeUrl.searchParams.set('scope', 'read:user repo');
    authorizeUrl.searchParams.set('state', state);
    authorizeUrl.searchParams.set('code_challenge', codeChallenge);
    authorizeUrl.searchParams.set('code_challenge_method', 'S256');

    const stateCookie = {
      ...cookieOptions(config),
      path: '/api/auth/github',
      httpOnly: true,
      maxAge: OAUTH_LIFETIME_MS / 1000,
    };
    reply.setCookie(OAUTH_STATE_COOKIE, state, stateCookie);
    reply.setCookie(OAUTH_VERIFIER_COOKIE, codeVerifier, stateCookie);

    return {
      authorizationUrl: authorizeUrl.toString(),
      state,
    };
  });

  app.get('/api/auth/github/callback', async (request, reply) => {
    if (!config.GITHUB_CLIENT_ID || !config.GITHUB_CLIENT_SECRET) {
      throw new ApiError(503, 'GITHUB_OAUTH_NOT_CONFIGURED', 'Configure the GitHub OAuth application first.');
    }

    const query = parseRequest(
      z.object({ code: z.string().min(1), state: z.string().min(32) }),
      request.query,
    );
    const browserState = request.cookies[OAUTH_STATE_COOKIE];
    const browserVerifier = request.cookies[OAUTH_VERIFIER_COOKIE];
    reply.clearCookie(OAUTH_STATE_COOKIE, { ...cookieOptions(config), path: '/api/auth/github' });
    reply.clearCookie(OAUTH_VERIFIER_COOKIE, { ...cookieOptions(config), path: '/api/auth/github' });

    const flow = await prisma.oAuthFlow.findUnique({ where: { stateHash: hashToken(query.state) } });

    if (!flow || flow.expiresAt <= new Date() || flow.consumedAt) {
      throw new ApiError(403, 'EXPIRED_OAUTH_FLOW', 'GitHub authentication expired. Restart login.');
    }

    if (flow.client === 'BROWSER' && (!browserState || browserState !== query.state || !browserVerifier)) {
      throw new ApiError(403, 'INVALID_OAUTH_STATE', 'GitHub authentication could not be verified. Restart login.');
    }

    const verifier = decryptSecret(flow.encryptedCodeVerifier, encryptionKey());

    if (flow.client === 'BROWSER' && verifier !== browserVerifier) {
      throw new ApiError(403, 'INVALID_OAUTH_VERIFIER', 'GitHub authentication could not be verified.');
    }

    const claimed = await prisma.oAuthFlow.updateMany({
      where: { id: flow.id, consumedAt: null, expiresAt: { gt: new Date() } },
      data: { consumedAt: new Date() },
    });

    if (claimed.count !== 1) {
      throw new ApiError(403, 'REPLAYED_OAUTH_FLOW', 'This GitHub authentication has already been used.');
    }

    const tokenResponse = await fetcher('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify({
        client_id: config.GITHUB_CLIENT_ID,
        client_secret: config.GITHUB_CLIENT_SECRET,
        code: query.code,
        redirect_uri: oauthCallback,
        code_verifier: verifier,
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (!tokenResponse.ok) {
      throw new ApiError(502, 'GITHUB_TOKEN_EXCHANGE_FAILED', 'GitHub could not complete sign-in.');
    }

    const tokenResult = oauthTokenSchema.safeParse(await tokenResponse.json());

    if (!tokenResult.success) {
      throw new ApiError(502, 'GITHUB_TOKEN_RESPONSE_INVALID', 'GitHub returned an invalid authorization response.');
    }

    const githubResponse = await fetcher('https://api.github.com/user', {
      headers: {
        accept: 'application/vnd.github+json',
        authorization: `Bearer ${tokenResult.data.access_token}`,
        'x-github-api-version': '2022-11-28',
      },
      signal: AbortSignal.timeout(10000),
    });

    if (githubResponse.status === 401 || githubResponse.status === 403) {
      throw new ApiError(502, 'GITHUB_AUTHORIZATION_DENIED', 'GitHub did not accept the account authorization.');
    }

    if (!githubResponse.ok) {
      throw new ApiError(502, 'GITHUB_USER_LOOKUP_FAILED', 'GitHub account could not be verified.');
    }

    const githubUserResult = githubUserSchema.safeParse(await githubResponse.json());

    if (!githubUserResult.success) {
      throw new ApiError(502, 'GITHUB_USER_RESPONSE_INVALID', 'GitHub returned invalid account details.');
    }

    const githubUser = githubUserResult.data;
    if (!flow.userId) {
      throw new ApiError(401, 'LOCAL_ACCOUNT_REQUIRED', 'Zaloguj się do Control Center przed połączeniem konta GitHub.');
    }
    const user = await prisma.user.findUniqueOrThrow({ where: { id: flow.userId } });

    const githubAccount = await prisma.$transaction(async (transaction) => {
      const account = await transaction.gitHubAccount.upsert({
        where: { userId_githubUserId: { userId: user.id, githubUserId: String(githubUser.id) } },
        create: {
          userId: user.id,
          githubUserId: String(githubUser.id),
          login: githubUser.login,
          encryptedAccessToken: encryptSecret(tokenResult.data.access_token, encryptionKey()),
          encryptedRefreshToken: tokenResult.data.refresh_token
            ? encryptSecret(tokenResult.data.refresh_token, encryptionKey())
            : null,
          tokenExpiresAt: tokenResult.data.expires_in
            ? new Date(Date.now() + tokenResult.data.expires_in * 1000)
            : null,
          scopes: tokenResult.data.scope?.split(',').filter(Boolean) ?? [],
          status: 'ACTIVE',
        },
        update: {
          login: githubUser.login,
          encryptedAccessToken: encryptSecret(tokenResult.data.access_token, encryptionKey()),
          encryptedRefreshToken: tokenResult.data.refresh_token
            ? encryptSecret(tokenResult.data.refresh_token, encryptionKey())
            : null,
          tokenExpiresAt: tokenResult.data.expires_in
            ? new Date(Date.now() + tokenResult.data.expires_in * 1000)
            : null,
          scopes: tokenResult.data.scope?.split(',').filter(Boolean) ?? [],
          status: 'ACTIVE',
        },
      });

      await transaction.auditEvent.create({
        data: {
          userId: user.id,
          action: 'GITHUB_ACCOUNT_CONNECTED',
          targetType: 'GitHubAccount',
          targetId: account.id,
          details: { githubLogin: githubUser.login },
        },
      });

      return account;
    });

    if (flow.client === 'NATIVE') {
      const handoffToken = createRandomToken();
      await prisma.oAuthHandoff.create({
        data: {
          userId: user.id,
          tokenHash: hashToken(handoffToken),
          stateHash: flow.stateHash,
          expiresAt: new Date(Date.now() + HANDOFF_LIFETIME_MS),
        },
      });
      const deepLink = new URL('copilotcontrol://oauth/callback');
      deepLink.searchParams.set('code', handoffToken);
      deepLink.searchParams.set('state', query.state);
      return reply.redirect(deepLink.toString());
    }

    const handoffToken = createRandomToken();
    await prisma.oAuthHandoff.create({
      data: {
        userId: user.id,
        tokenHash: hashToken(handoffToken),
        stateHash: flow.stateHash,
        expiresAt: new Date(Date.now() + HANDOFF_LIFETIME_MS),
      },
    });

    return reply.redirect(
      `${origin}/auth/complete?code=${encodeURIComponent(handoffToken)}&state=${encodeURIComponent(query.state)}`,
    );
  });

  app.post('/api/auth/github/session/exchange', async (request, reply) => {
    const { code, state } = parseRequest(sessionExchangeSchema, request.body);
    const handoff = await prisma.oAuthHandoff.findUnique({ where: { tokenHash: hashToken(code) } });

    if (!handoff || handoff.stateHash !== hashToken(state) || handoff.consumedAt || handoff.expiresAt <= new Date()) {
      throw new ApiError(401, 'INVALID_MOBILE_HANDOFF', 'Mobile sign-in expired or was already used. Sign in again.');
    }

    const rawSessionToken = createRandomToken();
    const csrfToken = createRandomToken();
    await prisma.$transaction(async (transaction) => {
      const claimed = await transaction.oAuthHandoff.updateMany({
        where: { id: handoff.id, consumedAt: null, expiresAt: { gt: new Date() } },
        data: { consumedAt: new Date() },
      });

      if (claimed.count !== 1) {
        throw new ApiError(401, 'INVALID_MOBILE_HANDOFF', 'Mobile sign-in expired or was already used. Sign in again.');
      }

      await transaction.authSession.create({
        data: {
          userId: handoff.userId,
          tokenHash: hashToken(rawSessionToken),
          csrfTokenHash: hashToken(csrfToken),
          expiresAt: new Date(Date.now() + SESSION_LIFETIME_SECONDS * 1000),
        },
      });
    });

    return reply.send({ sessionToken: rawSessionToken, csrfToken, expiresIn: SESSION_LIFETIME_SECONDS });
  });

  app.get('/api/session', { preHandler: async (request) => loadOptionalSession(request, prisma) }, async (request) => {
    const session = requireSession(request);
    const [user, githubAccounts] = await Promise.all([
      prisma.user.findUniqueOrThrow({
        where: { id: session.userId },
        select: { id: true, email: true, displayName: true, identityLogin: true },
      }),
      prisma.gitHubAccount.findMany({
        where: { userId: session.userId },
        select: {
          id: true,
          login: true,
          githubUserId: true,
          scopes: true,
          status: true,
          tokenExpiresAt: true,
          createdAt: true,
        },
        orderBy: { createdAt: 'asc' },
      }),
    ]);

    return { user, githubAccounts };
  });

  app.post('/api/auth/logout', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request, reply) => {
    const session = requireSession(request);
    await prisma.authSession.updateMany({
      where: { id: session.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    const cookies = cookieOptions(config);
    reply.clearCookie(SESSION_COOKIE, cookies);
    reply.clearCookie(CSRF_COOKIE, cookies);

    return { ok: true };
  });

  app.get('/api/github/accounts/:accountId/repositories', {
    preHandler: async (request) => loadOptionalSession(request, prisma),
  }, async (request) => {
    const session = requireSession(request);
    const params = parseRequest(z.object({ accountId: z.string().cuid() }), request.params);
    const account = await prisma.gitHubAccount.findFirst({
      where: { id: params.accountId, userId: session.userId },
    });

    if (!account || account.status !== 'ACTIVE') {
      throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'GitHub account is unavailable or needs reauthorization.');
    }

    if (account.tokenExpiresAt && account.tokenExpiresAt <= new Date()) {
      await prisma.gitHubAccount.update({
        where: { id: account.id },
        data: { status: 'REAUTH_REQUIRED' },
      });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect this GitHub account to continue.');
    }

    const response = await fetcher(
      'https://api.github.com/user/repos?affiliation=owner%2Ccollaborator%2Corganization_member&sort=updated&per_page=100',
      {
        headers: {
          accept: 'application/vnd.github+json',
          authorization: `Bearer ${decryptSecret(account.encryptedAccessToken, encryptionKey())}`,
          'x-github-api-version': '2022-11-28',
        },
        signal: AbortSignal.timeout(10000),
      },
    );

    if (response.status === 401 || response.status === 403) {
      await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'GitHub authorization expired or lost repository access.');
    }

    if (!response.ok) {
      throw new ApiError(502, 'GITHUB_REPOSITORIES_UNAVAILABLE', 'GitHub repositories could not be loaded.');
    }

    const repositories = z.array(z.object({
      id: z.number().int().positive(),
      full_name: z.string(),
      name: z.string(),
      default_branch: z.string(),
      private: z.boolean(),
      owner: z.object({ login: z.string() }),
      permissions: z.object({ push: z.boolean().optional() }).passthrough().optional(),
    })).safeParse(await response.json());

    if (!repositories.success) {
      throw new ApiError(502, 'GITHUB_REPOSITORIES_INVALID', 'GitHub returned invalid repository data.');
    }

    return {
      repositories: repositories.data.map((repository) => ({
        id: String(repository.id),
        fullName: repository.full_name,
        name: repository.name,
        owner: repository.owner.login,
        defaultBranch: repository.default_branch,
        isPrivate: repository.private,
        canPush: repository.permissions?.push === true,
      })),
    };
  });

  app.get('/api/bots', {
    preHandler: async (request) => loadOptionalSession(request, prisma),
  }, async (request) => {
    const session = requireSession(request);
    const bots = await prisma.bot.findMany({
      where: { userId: session.userId },
      include: {
        githubAccount: { select: { id: true, login: true } },
        stages: {
          orderBy: { number: 'asc' },
          select: {
            id: true,
            number: true,
            title: true,
            status: true,
            branchName: true,
            pullRequests: { select: { number: true, url: true, status: true, ciStatus: true } },
          },
        },
        _count: { select: { notifications: true } },
      },
      orderBy: { updatedAt: 'desc' },
    });

    return { bots };
  });

  app.post('/api/bots', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request, reply) => {
    const session = requireSession(request);
    const body = parseRequest(createBotSchema, request.body);
    const stageNumbers = body.stages.map((stage) => stage.number);

    if (new Set(stageNumbers).size !== stageNumbers.length || stageNumbers.some((number, index) => number !== index + 1)) {
      throw new ApiError(400, 'INVALID_STAGE_ORDER', 'Stage numbers must be unique and start at 1 without gaps.');
    }

    const account = await prisma.gitHubAccount.findFirst({
      where: { id: body.githubAccountId, userId: session.userId, status: 'ACTIVE' },
    });

    if (!account) {
      throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'Choose an active GitHub account you own.');
    }

    const repositoryResponse = await fetcher(
      `https://api.github.com/repos/${body.repository.split('/').map(encodeURIComponent).join('/')}`,
      {
        headers: {
          accept: 'application/vnd.github+json',
          authorization: `Bearer ${decryptSecret(account.encryptedAccessToken, encryptionKey())}`,
          'x-github-api-version': '2022-11-28',
        },
        signal: AbortSignal.timeout(10000),
      },
    );

    if (repositoryResponse.status === 401 || repositoryResponse.status === 403) {
      await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'GitHub authorization expired or cannot access this repository.');
    }

    if (!repositoryResponse.ok) {
      throw new ApiError(404, 'GITHUB_REPOSITORY_NOT_FOUND', 'Repository was not found or is not accessible.');
    }

    const repository = z.object({
      id: z.number().int().positive(),
      full_name: z.string(),
      default_branch: z.string(),
      permissions: z.object({ push: z.boolean().optional() }).passthrough().optional(),
    }).safeParse(await repositoryResponse.json());

    if (!repository.success || String(repository.data.id) !== body.repositoryId || repository.data.full_name.toLowerCase() !== body.repository.toLowerCase()) {
      throw new ApiError(400, 'GITHUB_REPOSITORY_MISMATCH', 'Choose the verified repository returned by GitHub.');
    }

    if (repository.data.permissions?.push !== true) {
      throw new ApiError(403, 'GITHUB_REPOSITORY_READ_ONLY', 'The selected GitHub account must have push access.');
    }

    const bot = await prisma.$transaction(async (transaction) => {
      const created = await transaction.bot.create({
        data: {
          userId: session.userId,
          githubAccountId: account.id,
          name: body.name,
          repositoryId: body.repositoryId,
          repository: repository.data.full_name,
          defaultBranch: repository.data.default_branch,
          systemPrompt: body.systemPrompt,
          stages: {
            create: body.stages.map((stage) => ({
              number: stage.number,
              title: stage.title,
              description: stage.description,
              acceptanceCriteria: stage.acceptanceCriteria,
            })),
          },
        },
        include: { stages: { orderBy: { number: 'asc' } } },
      });

      await transaction.auditEvent.create({
        data: {
          userId: session.userId,
          botId: created.id,
          action: 'BOT_CREATED',
          targetType: 'Bot',
          targetId: created.id,
          details: { repository: created.repository, stages: created.stages.length },
        },
      });

      return created;
    });

    return reply.status(201).send({ bot });
  });

  app.get('/api/bots/:botId', {
    preHandler: async (request) => loadOptionalSession(request, prisma),
  }, async (request) => {
    const session = requireSession(request);
    const { botId } = parseRequest(z.object({ botId: z.string().cuid() }), request.params);
    const bot = await prisma.bot.findFirst({
      where: { id: botId, userId: session.userId },
      include: {
        githubAccount: { select: { id: true, login: true } },
        stages: {
          orderBy: { number: 'asc' },
          include: {
            transitions: { orderBy: { createdAt: 'asc' } },
            pullRequests: { orderBy: { number: 'desc' } },
          },
        },
      },
    });

    if (!bot) {
      throw new ApiError(404, 'BOT_NOT_FOUND', 'Bot was not found.');
    }

    return { bot };
  });

  app.get('/api/bots/:botId/pull-requests/:pullRequestId', {
    preHandler: async (request) => loadOptionalSession(request, prisma),
  }, async (request) => {
    const session = requireSession(request);
    const { botId, pullRequestId } = parseRequest(z.object({
      botId: z.string().cuid(),
      pullRequestId: z.string().cuid(),
    }), request.params);
    const pullRequest = await prisma.pullRequest.findFirst({
      where: { id: pullRequestId, stage: { botId, bot: { userId: session.userId } } },
      include: {
        stage: { include: { bot: { include: { githubAccount: true } } } },
      },
    });

    if (!pullRequest) {
      throw new ApiError(404, 'PULL_REQUEST_NOT_FOUND', 'Pull request was not found.');
    }

    const account = pullRequest.stage.bot.githubAccount;
    if (account.status !== 'ACTIVE') {
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the GitHub account to inspect this pull request.');
    }

    const ownerToken = decryptSecret(account.encryptedAccessToken, encryptionKey());
    const apiUrl = `https://api.github.com/repos/${pullRequest.repository
      .split('/')
      .map(encodeURIComponent)
      .join('/')}`;
    const headers = {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${ownerToken}`,
      'x-github-api-version': '2022-11-28',
    };
    const prUrl = `${apiUrl}/pulls/${pullRequest.number}`;
    const [detailsResponse, diffResponse, commentsResponse] = await Promise.all([
      fetcher(prUrl, { headers, signal: AbortSignal.timeout(15000) }),
      fetcher(prUrl, {
        headers: { ...headers, accept: 'application/vnd.github.diff' },
        signal: AbortSignal.timeout(15000),
      }),
      fetcher(`${apiUrl}/issues/${pullRequest.number}/comments?per_page=100`, {
        headers,
        signal: AbortSignal.timeout(15000),
      }),
    ]);

    const responses = [detailsResponse, diffResponse, commentsResponse];
    if (responses.some((response) => response.status === 401 || response.status === 403)) {
      await prisma.gitHubAccount.update({
        where: { id: account.id },
        data: { status: 'REAUTH_REQUIRED' },
      });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'GitHub authorization expired or cannot inspect this pull request.');
    }

    if (responses.some((response) => !response.ok)) {
      throw new ApiError(502, 'PULL_REQUEST_UNAVAILABLE', 'GitHub could not load the pull request, diff, or comments.');
    }

    const details = z.object({
      number: z.number().int().positive(),
      title: z.string(),
      body: z.string().nullable(),
      state: z.enum(['open', 'closed']),
      merged: z.boolean().optional(),
      html_url: z.url(),
      head: z.object({ ref: z.string(), sha: z.string() }),
      base: z.object({ ref: z.string() }),
      updated_at: z.iso.datetime(),
    }).safeParse(await detailsResponse.json());

    if (!details.success) {
      throw new ApiError(502, 'PULL_REQUEST_RESPONSE_INVALID', 'GitHub returned invalid pull request data.');
    }

    const comments = z.array(z.object({
      id: z.number().int().positive(),
      body: z.string(),
      html_url: z.url(),
      created_at: z.iso.datetime(),
      updated_at: z.iso.datetime(),
      user: z.object({ login: z.string() }).nullable(),
    })).safeParse(await commentsResponse.json());

    if (!comments.success) {
      throw new ApiError(502, 'PULL_REQUEST_COMMENTS_INVALID', 'GitHub returned invalid pull request comments.');
    }

    const checksResponse = await fetcher(
      `${apiUrl}/commits/${encodeURIComponent(details.data.head.sha)}/check-runs?per_page=100`,
      { headers, signal: AbortSignal.timeout(15000) },
    );
    if (checksResponse.status === 401 || checksResponse.status === 403) {
      await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'GitHub authorization does not allow reading CI checks.');
    }

    const checkRuns = checksResponse.ok
      ? z.object({
          check_runs: z.array(z.object({
            name: z.string(),
            status: z.string(),
            conclusion: z.string().nullable(),
            html_url: z.url().optional(),
          })),
        }).safeParse(await checksResponse.json())
      : null;
    const checks = checkRuns?.success ? checkRuns.data.check_runs : [];
    const ciStatus = checks.length === 0
      ? 'NO_CHECKS'
      : checks.every((check) => check.conclusion === 'success')
          ? 'SUCCESS'
          : checks.some((check) => check.conclusion === 'failure' || check.conclusion === 'cancelled')
              ? 'FAILURE'
              : 'IN_PROGRESS';

    const rawDiff = await diffResponse.text();
    const diffTruncated = rawDiff.length > 200000;
    const diff = diffTruncated ? rawDiff.slice(0, 200000) : rawDiff;
    const githubPr = details.data;
    const stageStatus: 'OPEN' | 'CLOSED' | 'MERGED' = githubPr.merged
      ? 'MERGED'
      : githubPr.state === 'closed'
          ? 'CLOSED'
          : 'OPEN';

    const updatedPullRequest = await prisma.$transaction(async (transaction) => {
      const updated = await transaction.pullRequest.update({
        where: { id: pullRequest.id },
        data: {
          title: githubPr.title,
          url: githubPr.html_url,
          headBranch: githubPr.head.ref,
          baseBranch: githubPr.base.ref,
          status: stageStatus,
          ciStatus,
        },
      });

      for (const comment of comments.data) {
        await transaction.pullRequestComment.upsert({
          where: {
            pullRequestId_githubCommentId: {
              pullRequestId: pullRequest.id,
              githubCommentId: String(comment.id),
            },
          },
          create: {
            pullRequestId: pullRequest.id,
            githubCommentId: String(comment.id),
            authorLogin: comment.user?.login ?? 'github-user',
            body: comment.body,
            htmlUrl: comment.html_url,
            postedAt: new Date(comment.created_at),
            updatedAt: new Date(comment.updated_at),
          },
          update: {
            authorLogin: comment.user?.login ?? 'github-user',
            body: comment.body,
            htmlUrl: comment.html_url,
            updatedAt: new Date(comment.updated_at),
          },
        });
      }

      return updated;
    });

    return {
      pullRequest: {
        id: updatedPullRequest.id,
        number: updatedPullRequest.number,
        title: updatedPullRequest.title,
        body: githubPr.body,
        url: updatedPullRequest.url,
        status: updatedPullRequest.status,
        headBranch: updatedPullRequest.headBranch,
        baseBranch: updatedPullRequest.baseBranch,
        ciStatus: updatedPullRequest.ciStatus,
        updatedAt: githubPr.updated_at,
      },
      diff,
      diffTruncated,
      checks,
      comments: comments.data,
    };
  });

  app.post('/api/bots/:botId/pull-requests/:pullRequestId/comments', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request, reply) => {
    const session = requireSession(request);
    const { botId, pullRequestId } = parseRequest(z.object({
      botId: z.string().cuid(),
      pullRequestId: z.string().cuid(),
    }), request.params);
    const { body } = parseRequest(z.object({ body: z.string().trim().min(1).max(20000) }), request.body);
    const pullRequest = await prisma.pullRequest.findFirst({
      where: { id: pullRequestId, stage: { botId, bot: { userId: session.userId } } },
      include: { stage: { include: { bot: { include: { githubAccount: true } } } } },
    });

    if (!pullRequest) {
      throw new ApiError(404, 'PULL_REQUEST_NOT_FOUND', 'Pull request was not found.');
    }

    const account = pullRequest.stage.bot.githubAccount;
    if (account.status !== 'ACTIVE') {
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to comment.');
    }

    const response = await fetcher(
      `https://api.github.com/repos/${pullRequest.repository
        .split('/')
        .map(encodeURIComponent)
        .join('/')}/issues/${pullRequest.number}/comments`,
      {
        method: 'POST',
        headers: {
          accept: 'application/vnd.github+json',
          authorization: `Bearer ${decryptSecret(account.encryptedAccessToken, encryptionKey())}`,
          'content-type': 'application/json',
          'x-github-api-version': '2022-11-28',
        },
        body: JSON.stringify({ body }),
        signal: AbortSignal.timeout(15000),
      },
    );

    if (response.status === 401 || response.status === 403) {
      await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'GitHub authorization expired or cannot comment on this PR.');
    }

    if (!response.ok) {
      throw new ApiError(502, 'PULL_REQUEST_COMMENT_FAILED', 'GitHub could not publish this comment.');
    }

    const comment = z.object({
      id: z.number().int().positive(),
      body: z.string(),
      html_url: z.url(),
      created_at: z.iso.datetime(),
      updated_at: z.iso.datetime(),
      user: z.object({ login: z.string() }).nullable(),
    }).safeParse(await response.json());

    if (!comment.success) {
      throw new ApiError(502, 'PULL_REQUEST_COMMENT_INVALID', 'GitHub returned invalid comment data.');
    }

    const stored = await prisma.$transaction(async (transaction) => {
      const saved = await transaction.pullRequestComment.upsert({
        where: {
          pullRequestId_githubCommentId: {
            pullRequestId: pullRequest.id,
            githubCommentId: String(comment.data.id),
          },
        },
        create: {
          pullRequestId: pullRequest.id,
          githubCommentId: String(comment.data.id),
          authorLogin: comment.data.user?.login ?? account.login,
          body: comment.data.body,
          htmlUrl: comment.data.html_url,
          postedAt: new Date(comment.data.created_at),
          updatedAt: new Date(comment.data.updated_at),
        },
        update: {
          authorLogin: comment.data.user?.login ?? account.login,
          body: comment.data.body,
          htmlUrl: comment.data.html_url,
          updatedAt: new Date(comment.data.updated_at),
        },
      });
      await transaction.auditEvent.create({
        data: {
          userId: session.userId,
          botId,
          stageId: pullRequest.stageId,
          action: 'PULL_REQUEST_COMMENT_CREATED',
          targetType: 'PullRequest',
          targetId: pullRequest.id,
          details: { githubCommentId: saved.githubCommentId },
        },
      });

      return saved;
    });

    return reply.status(201).send({ comment: stored });
  });

  async function persistUserStageTransition(
    request: FastifyRequest,
    action: 'APPROVED' | 'CHANGES_REQUESTED' | 'PAUSED' | 'CANCELLED',
  ) {
    const session = requireSession(request);
    const { stageId } = parseRequest(z.object({ stageId: z.string().cuid() }), request.params);
    const { reason } = parseRequest(transitionBodySchema, request.body ?? {});

    return prisma.$transaction(async (transaction) => {
      const stage = await transaction.stage.findFirst({
        where: { id: stageId, bot: { userId: session.userId } },
        include: { bot: true },
      });

      if (!stage) {
        throw new ApiError(404, 'STAGE_NOT_FOUND', 'Stage was not found.');
      }

      const stages: StageSnapshot[] = await transaction.stage.findMany({
        where: { botId: stage.botId },
        select: { number: true, status: true },
      });
      const occurredAt = new Date();
      const transition = transitionStage(stage, action, stages, occurredAt);
      const updated = await transaction.stage.updateMany({
        where: { id: stage.id, status: stage.status },
        data: {
          status: transition.status,
          approvedAt: action === 'APPROVED' ? occurredAt : null,
        },
      });

      if (updated.count !== 1) {
        throw new ApiError(409, 'STAGE_CHANGED_CONCURRENTLY', 'This stage has changed. Refresh and try again.');
      }

      await transaction.stageTransitionEvent.create({
        data: {
          stageId: stage.id,
          fromStatus: transition.previousStatus,
          toStatus: transition.status,
          details: { actor: 'user', reason: reason ?? null, occurredAt: transition.occurredAt },
        },
      });
      await transaction.auditEvent.create({
        data: {
          userId: session.userId,
          botId: stage.botId,
          stageId: stage.id,
          action: `STAGE_${action}`,
          targetType: 'Stage',
          targetId: stage.id,
          details: { fromStatus: transition.previousStatus, reason: reason ?? null },
        },
      });

      return { id: stage.id, status: transition.status, occurredAt: transition.occurredAt };
    }, { isolationLevel: 'Serializable' });
  }

  app.post('/api/stages/:stageId/approve', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request) => ({ stage: await persistUserStageTransition(request, 'APPROVED') }));

  app.post('/api/stages/:stageId/request-changes', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request) => ({ stage: await persistUserStageTransition(request, 'CHANGES_REQUESTED') }));

  app.post('/api/stages/:stageId/pause', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request) => ({ stage: await persistUserStageTransition(request, 'PAUSED') }));

  app.post('/api/stages/:stageId/cancel', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request) => ({ stage: await persistUserStageTransition(request, 'CANCELLED') }));

  app.post('/api/stages/:stageId/start', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request, reply) => {
    const session = requireSession(request);
    const { stageId } = parseRequest(z.object({ stageId: z.string().cuid() }), request.params);
    const claim = await prisma.$transaction(async (transaction) => {
      const stage = await transaction.stage.findFirst({
        where: { id: stageId, bot: { userId: session.userId } },
        include: {
          bot: { include: { githubAccount: true } },
          transitions: {
            where: { toStatus: 'CHANGES_REQUESTED' },
            orderBy: { createdAt: 'desc' },
            take: 1,
          },
        },
      });

      if (!stage) {
        throw new ApiError(404, 'STAGE_NOT_FOUND', 'Stage was not found.');
      }

      const stages: StageSnapshot[] = await transaction.stage.findMany({
        where: { botId: stage.botId },
        select: { number: true, status: true },
      });
      const transition = transitionStage(stage, 'RUNNING', stages);
      const unconfirmedJob = await transaction.backgroundJob.findFirst({
        where: {
          stageId: stage.id,
          status: 'FAILED',
          externalTaskId: null,
          lastError: 'SUBMISSION_RESULT_UNCONFIRMED',
        },
        select: { id: true },
      });

      if (unconfirmedJob) {
        throw new ApiError(
          409,
          'COPILOT_TASK_SUBMISSION_UNCONFIRMED',
          'The previous request may have reached GitHub. Check GitHub Agent Tasks before attempting another run.',
        );
      }

      const updated = await transaction.stage.updateMany({
        where: { id: stage.id, status: stage.status },
        data: { status: 'RUNNING', approvedAt: null },
      });

      if (updated.count !== 1) {
        throw new ApiError(409, 'STAGE_CHANGED_CONCURRENTLY', 'This stage has changed. Refresh and try again.');
      }

      await transaction.stageTransitionEvent.create({
        data: {
          stageId: stage.id,
          fromStatus: transition.previousStatus,
          toStatus: transition.status,
          details: { actor: 'copilot_agent', occurredAt: transition.occurredAt },
        },
      });
      const job = await transaction.backgroundJob.create({
        data: {
          stageId: stage.id,
          idempotencyKey: createRandomToken(),
          status: 'RUNNING',
          attempts: 1,
          lockedAt: new Date(),
        },
        select: { id: true },
      });

      return { stage, previousStatus: transition.previousStatus, jobId: job.id };
    }, { isolationLevel: 'Serializable' });

    const account = claim.stage.bot.githubAccount;
    if (account.status !== 'ACTIVE') {
      await prisma.backgroundJob.update({
        where: { id: claim.jobId },
        data: { status: 'FAILED', lastError: 'GITHUB_REAUTH_REQUIRED', lockedAt: null },
      });
      await prisma.stage.updateMany({
        where: { id: claim.stage.id, status: 'RUNNING' },
        data: { status: claim.previousStatus },
      });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to start this task.');
    }

    if (account.tokenExpiresAt && account.tokenExpiresAt <= new Date()) {
      await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      await prisma.backgroundJob.update({
        where: { id: claim.jobId },
        data: { status: 'FAILED', lastError: 'GITHUB_REAUTH_REQUIRED', lockedAt: null },
      });
      await prisma.stage.updateMany({
        where: { id: claim.stage.id, status: 'RUNNING' },
        data: { status: claim.previousStatus },
      });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to start this task.');
    }

    const bot = claim.stage.bot;
    const changeRequest = claim.stage.transitions[0]?.details;
    const changeRequestReason = changeRequest
      && typeof changeRequest === 'object'
      && 'reason' in changeRequest
      && typeof changeRequest.reason === 'string'
      ? changeRequest.reason
      : null;
    const prompt = [
      bot.systemPrompt,
      `Task: ${claim.stage.title}`,
      claim.stage.description,
      ...(claim.previousStatus === 'CHANGES_REQUESTED' && changeRequestReason
        ? [`Address this user-requested revision: ${changeRequestReason}`]
        : []),
      'Acceptance criteria:',
      ...claim.stage.acceptanceCriteria.map((criterion) => `- ${criterion}`),
    ].join('\n\n');

    let task;
    try {
      task = await copilotProvider.launchTask({
        accessToken: decryptSecret(account.encryptedAccessToken, encryptionKey()),
        repository: bot.repository,
        prompt,
        baseBranch: claim.stage.branchName ?? bot.defaultBranch,
      });
    } catch (error) {
      const definiteRejection = error instanceof GitHubCopilotApiError
        && [400, 401, 403, 404, 422, 429].includes(error.statusCode);

      if (error instanceof GitHubCopilotApiError && error.statusCode === 401) {
        await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      }

      await prisma.backgroundJob.update({
        where: { id: claim.jobId },
        data: {
          status: 'FAILED',
          lastError: definiteRejection ? (error instanceof GitHubCopilotApiError ? error.code : 'GITHUB_TASK_REJECTED')
            : 'SUBMISSION_RESULT_UNCONFIRMED',
          lockedAt: null,
        },
      });

      if (definiteRejection) {
        await prisma.stage.updateMany({
          where: { id: claim.stage.id, status: 'RUNNING' },
          data: { status: claim.previousStatus },
        });

        const rejectedStatus = error instanceof GitHubCopilotApiError ? error.statusCode : 502;
        if (rejectedStatus === 401) {
          throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to start this task.');
        }
        if (rejectedStatus === 403) {
          throw new ApiError(
            403,
            'GITHUB_AGENT_TASK_FORBIDDEN',
            'GitHub denied this task. Verify the Copilot plan and Agent tasks repository permissions.',
          );
        }
        if (rejectedStatus === 429) {
          throw new ApiError(503, 'GITHUB_AGENT_TASK_RATE_LIMITED', 'GitHub temporarily rate-limited task creation.');
        }
        throw new ApiError(502, 'GITHUB_AGENT_TASK_REJECTED', 'GitHub rejected the coding-agent task request.');
      }

      throw new ApiError(
        502,
        'COPILOT_TASK_SUBMISSION_UNCONFIRMED',
        'The request may have reached GitHub. Check GitHub Agent Tasks before attempting another run.',
      );
    }

    await prisma.$transaction(async (transaction) => {
      await transaction.backgroundJob.update({
        where: { id: claim.jobId },
        data: { externalTaskId: task.id, lockedAt: null },
      });
      await transaction.notification.create({
        data: {
          userId: session.userId,
          botId: bot.id,
          stageId: claim.stage.id,
          type: 'COPILOT_TASK_STARTED',
          title: 'Copilot started a task',
          body: `GitHub accepted the task for ${bot.repository}.`,
        },
      });
      await transaction.auditEvent.create({
        data: {
          userId: session.userId,
          botId: bot.id,
          stageId: claim.stage.id,
          action: 'COPILOT_TASK_STARTED',
          targetType: 'BackgroundJob',
          targetId: claim.jobId,
          details: { externalTaskId: task.id },
        },
      });
    });

    return reply.status(202).send({
      task: { id: task.id, state: task.state, url: task.html_url ?? task.url ?? null },
      stage: { id: claim.stage.id, status: 'RUNNING' },
    });
  });

  app.get('/api/stages/:stageId/task', {
    preHandler: async (request) => loadOptionalSession(request, prisma),
  }, async (request) => {
    const session = requireSession(request);
    const { stageId } = parseRequest(z.object({ stageId: z.string().cuid() }), request.params);
    const stage = await prisma.stage.findFirst({
      where: { id: stageId, bot: { userId: session.userId } },
      include: {
        bot: { include: { githubAccount: true } },
        jobs: {
          where: { externalTaskId: { not: null } },
          orderBy: { createdAt: 'desc' },
          take: 1,
        },
      },
    });

    if (!stage) {
      throw new ApiError(404, 'STAGE_NOT_FOUND', 'Stage was not found.');
    }
    const job = stage.jobs[0];
    if (!job?.externalTaskId) {
      throw new ApiError(404, 'COPILOT_TASK_NOT_FOUND', 'No confirmed Copilot task is recorded for this stage.');
    }

    const account = stage.bot.githubAccount;
    if (account.status !== 'ACTIVE') {
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to read this task.');
    }
    if (account.tokenExpiresAt && account.tokenExpiresAt <= new Date()) {
      await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to read this task.');
    }

    let task;
    try {
      task = await copilotProvider.getTask({
        accessToken: decryptSecret(account.encryptedAccessToken, encryptionKey()),
        repository: stage.bot.repository,
        taskId: job.externalTaskId,
      });
    } catch (error) {
      if (error instanceof GitHubCopilotApiError && error.statusCode === 401) {
        await prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
        throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Reconnect the associated GitHub account to read this task.');
      }
      if (error instanceof GitHubCopilotApiError && error.statusCode === 403) {
        throw new ApiError(403, 'GITHUB_AGENT_TASK_FORBIDDEN', 'GitHub denied access to this task.');
      }
      if (error instanceof GitHubCopilotApiError && error.statusCode === 404) {
        throw new ApiError(404, 'COPILOT_TASK_NOT_FOUND', 'GitHub could not find this task for the selected repository.');
      }
      throw error;
    }

    const terminalStatuses: Partial<Record<CopilotTaskState, StageSnapshot['status']>> = {
      completed: 'WAITING_APPROVAL',
      failed: 'FAILED',
      timed_out: 'FAILED',
      cancelled: 'CANCELLED',
      idle: 'PAUSED',
      waiting_for_user: 'PAUSED',
    };
    const terminalStatus = terminalStatuses[task.state];

    let currentStageStatus = stage.status;
    if (terminalStatus && stage.status === 'RUNNING') {
      const nextStatuses = terminalStatus === 'WAITING_APPROVAL'
        ? ['TESTING', 'WAITING_APPROVAL'] as const
        : [terminalStatus] as const;
      await prisma.$transaction(async (transaction) => {
        let current = stage.status;
        for (const nextStatus of nextStatuses) {
          const updated = await transaction.stage.updateMany({
            where: { id: stage.id, status: current },
            data: {
              status: nextStatus,
              ...(nextStatus === 'WAITING_APPROVAL' ? { approvedAt: null } : {}),
            },
          });
          if (updated.count !== 1) {
            break;
          }
          await transaction.stageTransitionEvent.create({
            data: {
              stageId: stage.id,
              fromStatus: current,
              toStatus: nextStatus,
              details: { actor: 'copilot_agent', externalTaskId: task.id },
            },
          });
          current = nextStatus;
        }

        if (current !== stage.status) {
          await transaction.notification.create({
            data: {
              userId: session.userId,
              botId: stage.botId,
              stageId: stage.id,
              type: `COPILOT_TASK_${task.state.toUpperCase()}`,
              title: task.state === 'completed'
                ? 'Copilot completed the task'
                : `Copilot task ${task.state.replaceAll('_', ' ')}`,
              body: task.state === 'completed'
                ? 'Review the result and pull request before approving the stage.'
                : `GitHub reports the task state as ${task.state.replaceAll('_', ' ')}.`,
            },
          });
          await transaction.auditEvent.create({
            data: {
              userId: session.userId,
              botId: stage.botId,
              stageId: stage.id,
              action: `COPILOT_TASK_${task.state.toUpperCase()}`,
              targetType: 'BackgroundJob',
              targetId: job.id,
              details: { externalTaskId: task.id, stageStatus: current },
            },
          });
        }
        currentStageStatus = current;
      });
    }

    return {
      task: { id: task.id, state: task.state, url: task.html_url ?? task.url ?? null, updatedAt: task.updated_at ?? null },
      stage: { id: stage.id, status: currentStageStatus },
    };
  });

  app.get('/api/notifications', {
    preHandler: async (request) => loadOptionalSession(request, prisma),
  }, async (request) => {
    const session = requireSession(request);
    const query = parseRequest(z.object({
      cursor: z.string().cuid().optional(),
      limit: z.coerce.number().int().min(1).max(100).default(30),
    }), request.query);
    const notifications = await prisma.notification.findMany({
      where: { userId: session.userId },
      ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
      take: query.limit,
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        botId: true,
        stageId: true,
        type: true,
        title: true,
        body: true,
        readAt: true,
        createdAt: true,
      },
    });

    return { notifications };
  });

  app.patch('/api/notifications/:notificationId/read', {
    preHandler: async (request) => {
      await loadOptionalSession(request, prisma);
      const session = requireSession(request);
      requireCsrf(request, session);
    },
  }, async (request) => {
    const session = requireSession(request);
    const { notificationId } = parseRequest(z.object({ notificationId: z.string().cuid() }), request.params);
    const updated = await prisma.notification.updateMany({
      where: { id: notificationId, userId: session.userId, readAt: null },
      data: { readAt: new Date() },
    });

    if (!updated.count) {
      throw new ApiError(404, 'NOTIFICATION_NOT_FOUND', 'Notification was not found or is already read.');
    }

    return { id: notificationId, read: true };
  });

  app.addHook('onClose', async () => prisma.$disconnect());

  return app;
}

export type { Prisma };