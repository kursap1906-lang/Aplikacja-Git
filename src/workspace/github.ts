import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { PrismaClient } from '../generated/prisma/client.ts';
import { decryptSecret } from '../security/secrets.ts';
import { ApiError, parseRequest } from '../http/errors.ts';

const repositoryName = z.string().regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/);
const selection = z.object({ accountId: z.string().cuid(), repository: repositoryName }).strict();
const listQuery = selection.extend({
  page: z.coerce.number().int().min(1).max(1000).default(1),
  state: z.enum(['open', 'closed', 'all']).default('open'),
});
const numberParams = z.object({ number: z.coerce.number().int().positive() }).strict();
const githubUrl = z.url().refine((value) => {
  const url = new URL(value);
  return url.protocol === 'https:' && url.hostname === 'github.com' && !url.username && !url.password;
});
const author = z.object({ login: z.string() }).nullable();
const pullSchema = z.object({
  number: z.number().int().positive(), title: z.string(), body: z.string().nullable(),
  html_url: githubUrl, state: z.enum(['open', 'closed']), draft: z.boolean().optional(),
  merged_at: z.string().nullable(), user: author,
  head: z.object({ ref: z.string(), sha: z.string().regex(/^[a-f0-9]{40}$/) }),
  base: z.object({ ref: z.string() }), updated_at: z.string(),
});
const commentSchema = z.object({
  id: z.number().int(), body: z.string(), user: author, created_at: z.string(), html_url: githubUrl,
});
const fileSchema = z.object({
  filename: z.string(), status: z.string(), additions: z.number(), deletions: z.number(),
  patch: z.string().optional(),
});
const checkSchema = z.object({
  name: z.string(), status: z.string(), conclusion: z.string().nullable(), html_url: githubUrl.nullable(),
});
const statusSchema = z.object({
  context: z.string(), state: z.string(), target_url: z.string().nullable(),
});

type GitHubOptions = {
  prisma: PrismaClient;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
  encryptionKey: () => string;
  fetcher: typeof fetch;
};

export async function workspaceGitHubClient(options: Pick<GitHubOptions, 'prisma' | 'encryptionKey' | 'fetcher'>, userId: string, accountId: string, repository: string) {
  const { prisma, fetcher } = options;
    const account = await prisma.gitHubAccount.findFirst({ where: { id: accountId, userId, status: 'ACTIVE' } });
    if (!account) throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'Wybierz własne aktywne konto GitHub.');
    if (account.tokenExpiresAt && account.tokenExpiresAt <= new Date()) {
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Połącz ponownie konto GitHub.');
    }
    const token = decryptSecret(account.encryptedAccessToken, options.encryptionKey());
    const base = `https://api.github.com/repos/${repository.split('/').map(encodeURIComponent).join('/')}`;
    return async <T>(path: string, schema: z.ZodType<T>, method = 'GET', body?: unknown) => {
      let response: Response;
      try {
        response = await fetcher(`${base}${path}`, {
          method, redirect: 'error', signal: AbortSignal.timeout(15_000),
          headers: {
            accept: 'application/vnd.github+json', authorization: `Bearer ${token}`,
            'x-github-api-version': '2022-11-28', 'content-type': 'application/json',
          },
          body: body === undefined ? undefined : JSON.stringify(body),
        });
      } catch (error) {
        if (!(error instanceof TypeError) && !(error instanceof DOMException)) throw error;
        throw new ApiError(502, 'GITHUB_UNAVAILABLE', 'Nie udało się połączyć z GitHub. Sprawdź wynik operacji przed ponowieniem zapisu.');
      }
      if (response.status === 401) throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Połącz ponownie konto GitHub.');
      if (response.status === 429 || (response.status === 403 && response.headers.get('x-ratelimit-remaining') === '0')) {
        throw new ApiError(429, 'GITHUB_RATE_LIMITED', 'GitHub ograniczył liczbę żądań.');
      }
      if (response.status === 403) throw new ApiError(403, 'GITHUB_PERMISSION_DENIED', 'GitHub odmówił dostępu do tej operacji.');
      if (response.status === 404) throw new ApiError(404, 'GITHUB_NOT_FOUND', 'Nie znaleziono repozytorium lub PR albo konto nie ma dostępu.');
      if (response.status === 422) throw new ApiError(409, 'GITHUB_REJECTED', 'GitHub odrzucił zapis. Sprawdź gałęzie i istniejące PR.');
      if (!response.ok) throw new ApiError(502, 'GITHUB_UNAVAILABLE', `GitHub zwrócił HTTP ${response.status}.`);
      let json: unknown;
      try { json = await response.json(); } catch (error) {
        if (!(error instanceof SyntaxError)) throw error;
        throw new ApiError(502, 'GITHUB_RESPONSE_INVALID', 'GitHub zwrócił nieprawidłowy JSON.');
      }
      const parsed = schema.safeParse(json);
      if (!parsed.success) throw new ApiError(502, 'GITHUB_RESPONSE_INVALID', 'GitHub zwrócił nieprawidłowe dane.');
      return { data: parsed.data, hasNext: /rel="next"/.test(response.headers.get('link') ?? '') };
    };
  }
export function registerWorkspaceGitHubRoutes(app: FastifyInstance, options: GitHubOptions): void {
  const { prisma, authenticate } = options;
  const client = (userId: string, accountId: string, repository: string) =>
    workspaceGitHubClient(options, userId, accountId, repository);
  const summarize = (pull: z.infer<typeof pullSchema>) => ({
    number: pull.number, title: pull.title, body: pull.body, url: pull.html_url,
    state: pull.merged_at ? 'merged' : pull.draft ? 'draft' : pull.state,
    author: pull.user?.login ?? '[deleted]', head: pull.head.ref, base: pull.base.ref,
    headSha: pull.head.sha, updatedAt: pull.updated_at,
  });
  app.get('/api/workspace/github/pulls', async (request) => {
    const userId = await authenticate(request, false);
    const query = parseRequest(listQuery, request.query);
    const github = await client(userId, query.accountId, query.repository);
    const result = await github(`/pulls?state=${query.state}&page=${query.page}&per_page=20&sort=updated&direction=desc`, z.array(pullSchema));
    return { pulls: result.data.map(summarize), nextPage: result.hasNext ? query.page + 1 : null };
  });
  app.get('/api/workspace/github/pulls/:number', async (request) => {
    const userId = await authenticate(request, false);
    const query = parseRequest(selection, request.query);
    const { number } = parseRequest(numberParams, request.params);
    const github = await client(userId, query.accountId, query.repository);
    const pull = (await github(`/pulls/${number}`, pullSchema)).data;
    const [files, comments, checks, statuses] = await Promise.all([
      github(`/pulls/${number}/files?per_page=100`, z.array(fileSchema)),
      github(`/issues/${number}/comments?per_page=100`, z.array(commentSchema)),
      github(`/commits/${pull.head.sha}/check-runs?per_page=100`, z.object({ check_runs: z.array(checkSchema) })),
      github(`/commits/${pull.head.sha}/status?per_page=100`, z.object({ state: z.string(), statuses: z.array(statusSchema) })),
    ]);
    return {
      pull: summarize(pull), files: files.data, comments: comments.data,
      checks: checks.data.check_runs, statuses: statuses.data.statuses,
      truncated: files.hasNext || comments.hasNext || checks.hasNext || statuses.hasNext,
      ciSha: pull.head.sha,
    };
  });
  app.post('/api/workspace/github/pulls/:number/comments', async (request, reply) => {
    const userId = await authenticate(request, true);
    const query = parseRequest(selection, request.query);
    const { number } = parseRequest(numberParams, request.params);
    const input = parseRequest(z.object({ body: z.string().trim().min(1).max(20_000) }).strict(), request.body);
    const github = await client(userId, query.accountId, query.repository);
    const result = await github(`/issues/${number}/comments`, commentSchema, 'POST', input);
    await prisma.auditEvent.create({ data: {
      userId, action: 'GITHUB_PR_COMMENT_CREATED', targetType: 'GitHubPullRequest',
      targetId: `${query.repository}#${number}`, details: { accountId: query.accountId, commentId: result.data.id },
    } });
    return reply.status(201).send({ comment: result.data });
  });
  app.post('/api/workspace/github/pulls/:number/link-stage', async request => {
    const userId = await authenticate(request, true);
    const query = parseRequest(selection, request.query);
    const { number } = parseRequest(numberParams, request.params);
    const { stageId } = parseRequest(z.object({ stageId: z.string().cuid() }).strict(), request.body);
    const stage = await prisma.stage.findFirst({
      where: { id: stageId, bot: { userId, githubAccountId: query.accountId, repository: query.repository } },
      select: { id: true, botId: true },
    });
    if (!stage) throw new ApiError(404, 'STAGE_NOT_FOUND', 'Wybierz własny etap tego konta i repozytorium.');
    const github = await client(userId, query.accountId, query.repository);
    const pull = (await github(`/pulls/${number}`, pullSchema)).data;
    const linked = await prisma.$transaction(async tx => {
      const saved = await tx.pullRequest.upsert({
        where: { repository_number: { repository: query.repository, number } },
        create: {
          stageId, repository: query.repository, number, title: pull.title, url: pull.html_url,
          headBranch: pull.head.ref, baseBranch: pull.base.ref,
          status: pull.merged_at ? 'MERGED' : pull.state === 'closed' ? 'CLOSED' : 'OPEN',
        },
        update: {},
      });
      if (saved.stageId !== stageId) {
        throw new ApiError(409, 'PULL_REQUEST_ALREADY_LINKED', 'Ten PR jest już powiązany z innym etapem. Nie zmieniono jego historii.');
      }
      await tx.auditEvent.create({ data: {
        userId, botId: stage.botId, stageId, action: 'GITHUB_PR_LINKED',
        targetType: 'PullRequest', targetId: saved.id, details: { number, repository: query.repository, sha: pull.head.sha },
      } });
      return saved;
    });
    return { pullRequestId: linked.id, botId: stage.botId, stageId };
  });
  app.post('/api/workspace/github/pulls', async (request, reply) => {
    const userId = await authenticate(request, true);
    const query = parseRequest(selection, request.query);
    const input = parseRequest(z.object({
      title: z.string().trim().min(1).max(200), body: z.string().max(20_000).default(''),
      head: z.string().trim().min(1).max(250), base: z.string().trim().min(1).max(250),
      draft: z.boolean().default(true),
    }).strict(), request.body);
    if (input.head === input.base) throw new ApiError(400, 'INVALID_REQUEST', 'Gałąź źródłowa i docelowa muszą się różnić.');
    const github = await client(userId, query.accountId, query.repository);
    const pull = (await github('/pulls', pullSchema, 'POST', input)).data;
    await prisma.auditEvent.create({ data: {
      userId, action: 'GITHUB_PR_CREATED', targetType: 'GitHubPullRequest',
      targetId: `${query.repository}#${pull.number}`, details: { accountId: query.accountId },
    } });
    return reply.status(201).send({ pull: summarize(pull) });
  });
}
