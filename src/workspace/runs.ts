import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { PrismaClient } from '../generated/prisma/client.ts';
import { ApiError, parseRequest } from '../http/errors.ts';
import { decryptSecret } from '../security/secrets.ts';
import { branchNameForRun, maxRunEvents, runChangesSchema, type RunChange } from './run-shared.ts';

const idSchema = z.object({ id: z.string().cuid() }).strict();
const listSchema = z.object({ taskId: z.string().cuid().optional() }).strict();
const approveSchema = z.object({ acceptFailingTests: z.boolean().default(false) }).strict();
const rejectSchema = z.object({ reason: z.string().trim().min(3).max(2000) }).strict();
const previewBytes = 20 * 1024;

function preview(change: RunChange): string | null {
  if (!change.contentBase64) return null;
  const bytes = Buffer.from(change.contentBase64, 'base64');
  if (bytes.includes(0)) return null;
  return bytes.subarray(0, previewBytes).toString('utf8');
}

export function registerTaskRunRoutes(app: FastifyInstance, options: {
  prisma: PrismaClient;
  encryptionKey: () => string;
  fetcher: typeof fetch;
  executionEnabled: boolean;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
}): void {
  const { prisma, authenticate, fetcher } = options;
  const ownedRun = async (id: string, userId: string) => {
    const run = await prisma.taskRun.findFirst({ where: { id, userId } });
    if (!run) throw new ApiError(404, 'RUN_NOT_FOUND', 'Nie znaleziono uruchomienia.');
    return run;
  };
  const summary = (run: {
    id: string; taskId: string; botId: string; status: string; stack: string | null; testsPassed: boolean | null;
    errorCode: string | null; branchName: string | null; pullRequestUrl: string | null;
    queuedAt: Date; startedAt: Date | null; finishedAt: Date | null;
  }) => ({
    id: run.id, taskId: run.taskId, botId: run.botId, status: run.status, stack: run.stack,
    testsPassed: run.testsPassed, errorCode: run.errorCode, branchName: run.branchName,
    pullRequestUrl: run.pullRequestUrl, queuedAt: run.queuedAt, startedAt: run.startedAt,
    finishedAt: run.finishedAt,
  });

  app.post('/api/workspace/tasks/:id/runs', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    if (!options.executionEnabled) {
      throw new ApiError(503, 'SDK_EXECUTION_UNAVAILABLE', 'Wykonawca zadań SDK nie jest jeszcze dostępny. Zadanie nie zostało uruchomione.');
    }
    const run = await prisma.$transaction(async (tx) => {
      const task = await tx.projectTask.findFirst({
        where: { id, userId },
        include: {
          bot: { include: { githubAccount: true } },
          prerequisites: { include: { dependsOn: { select: { title: true, status: true } } } },
        },
      });
      if (!task) throw new ApiError(404, 'TASK_NOT_FOUND', 'Nie znaleziono zadania.');
      if (!task.bot) throw new ApiError(409, 'TASK_BOT_REQUIRED', 'Przypisz zadanie botowi.');
      if (task.status === 'COMPLETED') throw new ApiError(409, 'TASK_ALREADY_COMPLETED', 'To zadanie jest już ukończone.');
      if (task.bot.githubAccount.status !== 'ACTIVE') {
        throw new ApiError(409, 'GITHUB_REAUTH_REQUIRED', 'Połącz ponownie konto GitHub tego bota.');
      }
      const unmet = task.prerequisites.filter((item) => item.dependsOn.status !== 'COMPLETED');
      if (unmet.length) {
        throw new ApiError(409, 'TASK_PREREQUISITES_UNMET', `Najpierw ukończ: ${unmet.map((item) => item.dependsOn.title).join(', ')}.`);
      }
      const active = await tx.taskRun.findFirst({
        where: { taskId: id, status: { in: ['QUEUED', 'RUNNING'] } }, select: { id: true },
      });
      if (active) throw new ApiError(409, 'RUN_ALREADY_ACTIVE', 'To zadanie ma już aktywne uruchomienie.');
      const created = await tx.taskRun.create({
        data: {
          userId, taskId: id, botId: task.bot.id,
          repository: task.bot.repository, defaultBranch: task.bot.defaultBranch,
        },
      });
      await tx.projectTask.update({ where: { id }, data: { status: 'IN_PROGRESS' } });
      await tx.auditEvent.create({
        data: { userId, botId: task.bot.id, action: 'TASK_RUN_QUEUED', targetType: 'TaskRun', targetId: created.id },
      });
      return created;
    }).catch((error: unknown) => {
      if (typeof error === 'object' && error !== null && 'code' in error && error.code === 'P2002') {
        throw new ApiError(409, 'RUN_ALREADY_ACTIVE', 'To zadanie ma już aktywne uruchomienie.');
      }
      throw error;
    });
    return reply.status(202).send({ run: summary(run) });
  });

  app.get('/api/workspace/runs', async (request) => {
    const userId = await authenticate(request, false);
    const { taskId } = parseRequest(listSchema, request.query ?? {});
    const runs = await prisma.taskRun.findMany({
      where: { userId, ...(taskId ? { taskId } : {}) },
      orderBy: { createdAt: 'desc' }, take: 50,
    });
    return { runs: runs.map(summary) };
  });

  app.get('/api/workspace/runs/:id', async (request) => {
    const userId = await authenticate(request, false);
    const { id } = parseRequest(idSchema, request.params);
    const run = await prisma.taskRun.findFirst({
      where: { id, userId },
      include: { events: { orderBy: { seq: 'asc' }, take: maxRunEvents }, task: { select: { title: true } } },
    });
    if (!run) throw new ApiError(404, 'RUN_NOT_FOUND', 'Nie znaleziono uruchomienia.');
    const parsed = run.changes === null ? null : runChangesSchema.safeParse(run.changes);
    if (parsed && !parsed.success) {
      throw new ApiError(500, 'RUN_RESULT_INVALID', 'Zapisany wynik uruchomienia jest nieprawidłowy.');
    }
    return {
      run: {
        ...summary(run), taskTitle: run.task.title, repository: run.repository, baseSha: run.baseSha,
        summary: run.summary, testCommand: run.testCommand, testOutput: run.testOutput,
        errorMessage: run.errorMessage, pushedCommitSha: run.pushedCommitSha,
        files: parsed?.data.map((change) => ({
          path: change.path, status: change.status, size: change.size, preview: preview(change),
        })) ?? [],
        events: run.events.map((event) => ({
          seq: event.seq, kind: event.kind, text: event.text, createdAt: event.createdAt,
        })),
      },
    };
  });

  app.post('/api/workspace/runs/:id/cancel', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    await ownedRun(id, userId);
    const queued = await prisma.taskRun.updateMany({
      where: { id, userId, status: 'QUEUED' },
      data: { status: 'CANCELLED', finishedAt: new Date() },
    });
    if (queued.count === 0) {
      const running = await prisma.taskRun.updateMany({
        where: { id, userId, status: 'RUNNING' }, data: { cancelRequested: true },
      });
      if (running.count === 0) throw new ApiError(409, 'RUN_NOT_ACTIVE', 'To uruchomienie nie jest aktywne.');
    }
    const run = await ownedRun(id, userId);
    if (run.status === 'CANCELLED') {
      await prisma.projectTask.updateMany({ where: { id: run.taskId, status: 'IN_PROGRESS' }, data: { status: 'TODO' } });
    }
    return { run: summary(run) };
  });

  app.post('/api/workspace/runs/:id/approve', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const { acceptFailingTests } = parseRequest(approveSchema, request.body ?? {});
    const run = await ownedRun(id, userId);
    if (run.status !== 'AWAITING_REVIEW') {
      throw new ApiError(409, 'RUN_NOT_REVIEWABLE', 'Tylko wynik oczekujący na przegląd można zatwierdzić.');
    }
    if (run.testsPassed !== true && !acceptFailingTests) {
      throw new ApiError(409, 'TESTS_NOT_PASSED', 'Testy nie przeszły. Potwierdź jawnie, że akceptujesz wynik mimo to.');
    }
    const updated = await prisma.$transaction(async (tx) => {
      const claimed = await tx.taskRun.updateMany({
        where: { id, userId, status: 'AWAITING_REVIEW' },
        data: { status: 'APPROVED', reviewedAt: new Date() },
      });
      if (claimed.count !== 1) throw new ApiError(409, 'RUN_CHANGED_CONCURRENTLY', 'Uruchomienie zostało zmienione. Odśwież widok.');
      await tx.projectTask.update({ where: { id: run.taskId }, data: { status: 'COMPLETED' } });
      await tx.auditEvent.create({
        data: {
          userId, botId: run.botId, action: 'TASK_RUN_APPROVED', targetType: 'TaskRun', targetId: id,
          details: { testsPassed: run.testsPassed, acceptedFailingTests: run.testsPassed !== true },
        },
      });
      return tx.taskRun.findUniqueOrThrow({ where: { id } });
    });
    return { run: summary(updated) };
  });

  app.post('/api/workspace/runs/:id/reject', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const { reason } = parseRequest(rejectSchema, request.body);
    const run = await ownedRun(id, userId);
    if (run.status !== 'AWAITING_REVIEW') {
      throw new ApiError(409, 'RUN_NOT_REVIEWABLE', 'Tylko wynik oczekujący na przegląd można odrzucić.');
    }
    const updated = await prisma.$transaction(async (tx) => {
      const claimed = await tx.taskRun.updateMany({
        where: { id, userId, status: 'AWAITING_REVIEW' },
        data: { status: 'REJECTED', reviewedAt: new Date(), errorMessage: reason },
      });
      if (claimed.count !== 1) throw new ApiError(409, 'RUN_CHANGED_CONCURRENTLY', 'Uruchomienie zostało zmienione. Odśwież widok.');
      await tx.projectTask.update({ where: { id: run.taskId }, data: { status: 'TODO' } });
      await tx.auditEvent.create({
        data: { userId, botId: run.botId, action: 'TASK_RUN_REJECTED', targetType: 'TaskRun', targetId: id },
      });
      return tx.taskRun.findUniqueOrThrow({ where: { id } });
    });
    return { run: summary(updated) };
  });

  const githubHeaders = async (runId: string, userId: string) => {
    const run = await prisma.taskRun.findFirst({
      where: { id: runId, userId }, include: { bot: { include: { githubAccount: true } }, task: true },
    });
    if (!run) throw new ApiError(404, 'RUN_NOT_FOUND', 'Nie znaleziono uruchomienia.');
    if (run.bot.githubAccount.status !== 'ACTIVE') {
      throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Połącz ponownie konto GitHub tego bota.');
    }
    const token = decryptSecret(run.bot.githubAccount.encryptedAccessToken, options.encryptionKey());
    return {
      run,
      headers: {
        accept: 'application/vnd.github+json',
        authorization: `Bearer ${token}`,
        'x-github-api-version': '2022-11-28',
        'content-type': 'application/json',
      },
      api: `https://api.github.com/repos/${run.repository.split('/').map(encodeURIComponent).join('/')}`,
    };
  };

  async function github(
    url: string, headers: Record<string, string>, method: string, body: unknown,
  ): Promise<Record<string, unknown>> {
    const response = await fetcher(url, {
      method, headers, body: JSON.stringify(body), signal: AbortSignal.timeout(30_000),
    });
    if (response.status === 401 || response.status === 403 || response.status === 404) {
      throw new ApiError(502, 'GITHUB_PERMISSION_DENIED', 'GitHub odmówił zapisu. Konto potrzebuje uprawnień zapisu do repozytorium.');
    }
    if (response.status === 422) {
      throw new ApiError(409, 'GITHUB_REJECTED', 'GitHub odrzucił żądanie (np. gałąź już istnieje).');
    }
    if (!response.ok) throw new ApiError(502, 'GITHUB_REQUEST_FAILED', `GitHub zwrócił błąd HTTP ${response.status}.`);
    const parsed: unknown = await response.json();
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      throw new ApiError(502, 'GITHUB_RESPONSE_INVALID', 'GitHub zwrócił nieprawidłową odpowiedź.');
    }
    return parsed as Record<string, unknown>;
  }
  const sha = (value: unknown): string => {
    if (typeof value !== 'string' || !/^[0-9a-f]{40}$/.test(value)) {
      throw new ApiError(502, 'GITHUB_RESPONSE_INVALID', 'GitHub zwrócił nieprawidłowy identyfikator.');
    }
    return value;
  };

  // The commit is rebuilt from the reviewed, stored result through the Git Data API;
  // no sandbox-produced .git directory or hook ever touches a credentialed process.
  app.post('/api/workspace/runs/:id/push', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const { run, headers, api } = await githubHeaders(id, userId);
    if (run.status !== 'APPROVED') {
      throw new ApiError(409, 'RUN_NOT_APPROVED', 'Najpierw zatwierdź wynik uruchomienia.');
    }
    if (!run.baseSha) throw new ApiError(409, 'RUN_BASE_MISSING', 'Brak commita bazowego.');
    const parsed = runChangesSchema.safeParse(run.changes);
    if (!parsed.success || parsed.data.length === 0) {
      throw new ApiError(409, 'RUN_HAS_NO_CHANGES', 'Uruchomienie nie zawiera zmian do wypchnięcia.');
    }
    const branch = branchNameForRun(run.id);
    const claim = await prisma.taskRun.updateMany({
      where: { id, userId, status: 'APPROVED' }, data: { status: 'PUSHED', branchName: branch },
    });
    if (claim.count !== 1) throw new ApiError(409, 'RUN_CHANGED_CONCURRENTLY', 'Uruchomienie zostało zmienione. Odśwież widok.');
    try {
      const base = await fetcher(`${api}/git/commits/${run.baseSha}`, { headers, signal: AbortSignal.timeout(30_000) });
      if (!base.ok) throw new ApiError(502, 'GITHUB_REQUEST_FAILED', 'Nie udało się odczytać commita bazowego.');
      const baseJson = await base.json() as { tree?: { sha?: unknown } };
      const baseTree = sha(baseJson.tree?.sha);
      const entries: Record<string, unknown>[] = [];
      for (const change of parsed.data) {
        const mode = change.executable ? '100755' : '100644';
        if (change.status === 'deleted') {
          entries.push({ path: change.path, mode, type: 'blob', sha: null });
          continue;
        }
        const blob = await github(`${api}/git/blobs`, headers, 'POST', {
          content: change.contentBase64, encoding: 'base64',
        });
        entries.push({ path: change.path, mode, type: 'blob', sha: sha(blob.sha) });
      }
      const tree = await github(`${api}/git/trees`, headers, 'POST', { base_tree: baseTree, tree: entries });
      const commit = await github(`${api}/git/commits`, headers, 'POST', {
        message: `${run.task.title}\n\nPrepared by Copilot Control Center run ${run.id} after manual review.`,
        tree: sha(tree.sha), parents: [run.baseSha],
      });
      const commitSha = sha(commit.sha);
      await github(`${api}/git/refs`, headers, 'POST', { ref: `refs/heads/${branch}`, sha: commitSha });
      await prisma.taskRun.update({ where: { id }, data: { pushedCommitSha: commitSha } });
      await prisma.auditEvent.create({
        data: {
          userId, botId: run.botId, action: 'TASK_RUN_PUSHED', targetType: 'TaskRun', targetId: id,
          details: { branch, commitSha, files: parsed.data.length },
        },
      });
      return { run: summary(await ownedRun(id, userId)), commitSha };
    } catch (error) {
      await prisma.taskRun.updateMany({
        where: { id, userId, status: 'PUSHED', pushedCommitSha: null },
        data: { status: 'APPROVED', branchName: null },
      });
      throw error;
    }
  });

  app.post('/api/workspace/runs/:id/pull-request', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const { run, headers, api } = await githubHeaders(id, userId);
    if (run.status !== 'PUSHED' || !run.branchName) {
      throw new ApiError(409, 'RUN_NOT_PUSHED', 'Najpierw wypchnij zatwierdzoną gałąź.');
    }
    const claim = await prisma.taskRun.updateMany({ where: { id, userId, status: 'PUSHED' }, data: { status: 'PR_OPENED' } });
    if (claim.count !== 1) throw new ApiError(409, 'RUN_CHANGED_CONCURRENTLY', 'Uruchomienie zostało zmienione. Odśwież widok.');
    try {
      const pull = await github(`${api}/pulls`, headers, 'POST', {
        title: run.task.title,
        head: run.branchName,
        base: run.defaultBranch,
        body: `Wynik zadania wykonanego przez bota i zatwierdzony ręcznie w Copilot Control Center (run ${run.id}).\n\nTesty wykonane przez serwer: ${run.testsPassed === true ? 'zaliczone' : 'niezaliczone/niepotwierdzone'}.`,
      });
      const url = pull.html_url;
      if (typeof url !== 'string' || !url.startsWith('https://github.com/')) {
        throw new ApiError(502, 'GITHUB_RESPONSE_INVALID', 'GitHub zwrócił nieprawidłowy adres PR.');
      }
      await prisma.taskRun.update({ where: { id }, data: { pullRequestUrl: url } });
      await prisma.auditEvent.create({
        data: { userId, botId: run.botId, action: 'TASK_RUN_PR_OPENED', targetType: 'TaskRun', targetId: id, details: { url } },
      });
      return { run: summary(await ownedRun(id, userId)) };
    } catch (error) {
      await prisma.taskRun.updateMany({ where: { id, userId, status: 'PR_OPENED', pullRequestUrl: null }, data: { status: 'PUSHED' } });
      throw error;
    }
  });
}
