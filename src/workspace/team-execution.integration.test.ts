import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import { randomUUID } from 'node:crypto';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client.ts';
import { encryptSecret } from '../security/secrets.ts';
import { ApiError } from '../http/errors.ts';
import { copilotCapabilities, type CopilotProvider } from '../github/copilot-provider.ts';
import { registerTeamExecution } from './team-execution.ts';
import { executionDataSchema } from './team-execution-state.ts';

test('persistent remote team: leader plans, owner gates, test integration, real deployment and exact-SHA main approval', async context => {
  const databaseUrl = process.env.WORKSPACE_TEST_DATABASE_URL;
  if (!databaseUrl || new URL(databaseUrl).hostname !== 'workspace-db' || new URL(databaseUrl).pathname !== '/workspace_integration') throw new Error('Disposable workspace integration database required.');
  const prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  const user = await prisma.user.create({ data: { displayName: `Coordinator fixture ${randomUUID()}` } });
  const key = Buffer.alloc(32, 7).toString('base64url');
  const account = await prisma.gitHubAccount.create({ data: { userId: user.id, githubUserId: randomUUID(), login: 'fixture', encryptedAccessToken: encryptSecret('synthetic-team-token', key), scopes: ['repo'] } });
  const project = await prisma.project.create({ data: { userId: user.id, name: 'Coordinator fixture', repository: 'fixture/coordinator', defaultBranch: 'main', mainGithubAccountId: account.id, brief: 'Build a working application.' } });
  const team = await prisma.team.create({ data: { userId: user.id, projectId: project.id, name: `Team ${randomUUID()}` } });
  const botData = { userId: user.id, githubAccountId: account.id, repositoryId: '123', repository: 'fixture/coordinator', defaultBranch: 'main', systemPrompt: 'Use tested increments.' };
  const leader = await prisma.bot.create({ data: { ...botData, name: 'Leader' } });
  const developer = await prisma.bot.create({ data: { ...botData, name: 'Developer' } });
  const root = await prisma.teamBot.create({ data: { teamId: team.id, botId: leader.id } });
  await prisma.teamBot.create({ data: { teamId: team.id, botId: developer.id, parentId: root.id } });
  const mainSha = 'a'.repeat(40);
  const testBranch = `ccc/test-${project.id}`;
  const refs = new Map([['main', mainSha]]);
  const pulls = new Map<number, { number: number; html_url: string; state: string; draft: boolean; merged?: boolean; head: { ref: string; sha: string }; base: { ref: string } }>();
  const merges: string[] = [];
  let launched = 0;
  let simulateLostSubmission = false;
  let simulateLostMerge = false;
  let roadmapMode = false;
  let planRequestId: string | undefined;
  let workflowOk = true;
  let deploymentOk = true;
  let requestSha = 'e'.repeat(40);
  let workflowContent = 'name: Preview\non: push\njobs: {}';
  const jsonFile = (json: unknown) => ({ sha: 'f'.repeat(40), encoding: 'base64', content: Buffer.from(JSON.stringify(json)).toString('base64') });
  const fetcher: typeof fetch = async (value, init) => {
    assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer synthetic-team-token');
    const url = new URL(String(value));
    const path = url.pathname.replace('/repos/fixture/coordinator', '');
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    if (path.startsWith('/git/ref/heads/')) {
      const ref = decodeURIComponent(path.slice('/git/ref/heads/'.length));
      return refs.has(ref) ? Response.json({ object: { sha: refs.get(ref) } }) : Response.json({}, { status: 404 });
    }
    if (path === '/git/refs') {
      refs.set(body.ref.replace('refs/heads/', ''), body.sha);
      return Response.json({ ref: body.ref }, { status: 201 });
    }
    if (path === '/contents/.ccc/team-plan.json') return Response.json(jsonFile({
      requestId: planRequestId,
      summary: 'Build configuration, application increment and deployment.',
      tasks: [
        { key: 'build', botId: developer.id, title: 'Build ccc-preview workflow', description: 'Implement the real build, tests and deployment configuration, with evidence.', dependsOn: [], approval: 'leader' },
        { key: 'migration', botId: developer.id, title: 'Reviewed application migration', description: 'Implement the owner-approved application increment and verify the full migration.', dependsOn: ['build'], approval: roadmapMode ? 'leader' : 'owner' },
      ],
    }));
    if (path.startsWith('/contents/.ccc/reviews/')) {
      const itemKey = path.split('/').at(-1)!.replace('.json', '');
      const pull = [...pulls.values()].at(-1)!;
      return Response.json(jsonFile({ sha: pull.head.sha, decision: roadmapMode || itemKey === 'build' ? 'approve' : 'owner', reason: 'Reviewed actual diff and successful tests for the exact SHA.' }));
    }
    if (path === '/pulls' && init?.method === 'POST') {
      const number = pulls.size + 1;
      const pull = { number, html_url: `https://github.com/fixture/coordinator/pull/${number}`, state: 'open', draft: false, head: { ref: body.head, sha: refs.get(body.head)! }, base: { ref: body.base } };
      pulls.set(number, pull); return Response.json(pull, { status: 201 });
    }
    if (path === '/pulls') return Response.json([...pulls.values()].filter(pull => pull.state === 'open' && (!url.searchParams.get('head') || `fixture:${pull.head.ref}` === url.searchParams.get('head')) && (!url.searchParams.get('base') || pull.base.ref === url.searchParams.get('base'))));
    if (/^\/pulls\/\d+$/.test(path)) return Response.json(pulls.get(Number(path.split('/')[2])));
    if (/^\/pulls\/\d+\/merge$/.test(path)) {
      const pull = pulls.get(Number(path.split('/')[2]))!;
      assert.equal(body.sha, pull.head.sha);
      merges.push(pull.base.ref); pull.state = 'closed'; refs.set(pull.base.ref, pull.head.sha);
      pull.merged = true;
      if (simulateLostMerge) throw new TypeError('Synthetic lost merge response');
      return Response.json({ merged: true, sha: pull.head.sha });
    }
    if (path.endsWith('/check-runs')) return Response.json({ check_runs: [{ status: 'completed', conclusion: 'success' }] });
    if (path.endsWith('/status')) return Response.json({ statuses: [] });
    if (path.startsWith('/compare/')) return Response.json({ status: 'ahead' });
    if (path.endsWith('/contents/.github/workflows/ccc-preview.yml')) return Response.json({ encoding: 'base64', content: Buffer.from(workflowContent).toString('base64'), sha: 'f'.repeat(40) });
    if (path === '/contents/.ccc/preview-request.json' && init?.method === 'PUT') {
      refs.set(testBranch, requestSha); return Response.json({ commit: { sha: requestSha } }, { status: 201 });
    }
    if (path === '/contents/.ccc/preview-request.json') return Response.json({}, { status: 404 });
    if (path === '/actions/runs') return Response.json({ workflow_runs: [{ id: 101, head_sha: requestSha, status: 'completed', conclusion: workflowOk ? 'success' : 'failure', html_url: 'https://github.com/fixture/coordinator/actions/runs/101', path: '.github/workflows/ccc-preview.yml' }] });
    if (path === '/deployments') return Response.json(deploymentOk ? [{ id: 202, sha: requestSha }] : []);
    if (path === '/deployments/202/statuses') return Response.json([{ state: 'success', environment_url: 'https://fixture.github.io/coordinator/' }]);
    throw new Error(`Unexpected GitHub request ${init?.method ?? 'GET'} ${path}`);
  };
  const provider: CopilotProvider = {
    capabilities: copilotCapabilities,
    launchTask: async input => {
      launched++;
      if (simulateLostSubmission) throw new TypeError('Synthetic lost submission response');
      assert.equal(input.baseBranch, testBranch);
      assert.ok(input.headBranch?.startsWith('ccc/'));
      assert.ok(input.prompt.includes('Nie scalaj PR ani nie pushuj do main'));
      if (input.prompt.includes('"requestId"')) planRequestId = input.prompt.match(/"requestId":"([a-f0-9-]+)"/)?.[1];
      if (roadmapMode) {
        assert.match(input.headBranch!, /^ccc\/roadmap-/);
        if (!input.prompt.includes('Przeprowadź review')) {
          refs.set(input.headBranch!, '7'.repeat(40));
          const current = [...pulls.values()].find(pull => pull.head.ref === input.headBranch && pull.state === 'open');
          if (current) current.head.sha = refs.get(input.headBranch!)!;
          else {
            const number = pulls.size + 1;
            pulls.set(number, { number, html_url: `https://github.com/fixture/coordinator/pull/${number}`, state: 'open', draft: false, head: { ref: input.headBranch!, sha: refs.get(input.headBranch!)! }, base: { ref: testBranch } });
          }
        }
      }
      if (input.headBranch === `ccc/bot-${developer.id}`) {
        const head = launched === 2 ? 'b'.repeat(40) : 'c'.repeat(40);
        refs.set(input.headBranch, head);
        const number = pulls.size + 1;
        pulls.set(number, { number, html_url: `https://github.com/fixture/coordinator/pull/${number}`, state: 'open', draft: false, head: { ref: input.headBranch, sha: head }, base: { ref: testBranch } });
      }
      return { id: `remote-${launched}`, state: 'queued' };
    },
    getTask: async input => ({
      id: input.taskId, state: 'completed',
      ...(input.taskId === 'recovered-leader' ? { sessions: [{ id: 'verified-session', state: 'completed' as const, head_ref: `ccc/leader-${team.id}`, created_at: new Date().toISOString() }] } : {}),
    }),
  };
  const app = Fastify();
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ApiError) return reply.status(error.statusCode).send({ error: { code: error.code, message: error.message } });
    throw error;
  });
  const controller = registerTeamExecution(app, {
    prisma, fetcher, copilotProvider: provider, encryptionKey: () => key,
    assertStart: async () => {},
    authenticate: async request => request.headers['x-fixture-user'] === 'other' ? 'other-user' : user.id,
  }, false);
  context.after(async () => { await controller.stop(); await app.close(); await prisma.$disconnect(); });
  const path = `/api/workspace/teams/${team.id}/execution`;
  const post = (action: string, payload: Record<string, unknown> = {}) => app.inject({ method: 'POST', url: `${path}/${action}`, payload });
  assert.equal((await app.inject({ url: path })).json().execution, null);
  assert.equal(launched, 0);
  const start = await post('start');
  assert.equal(start.statusCode, 202, start.body);
  const id = start.json().executionId;
  assert.equal((await post('start')).statusCode, 409);
  const data = async () => executionDataSchema.parse((await prisma.teamExecution.findUniqueOrThrow({ where: { id } })).data);
  await controller.tick(id);
  assert.equal((await data()).phase, 'PLANNING');
  await controller.tick(id);
  assert.equal((await data()).items.length, 2);
  assert.equal((await data()).items[1]?.approval, 'owner');
  await controller.tick(id); await controller.tick(id); await controller.tick(id);
  assert.deepEqual(merges, [testBranch]);
  assert.equal(refs.get('main'), mainSha);
  await controller.tick(id);
  const ownerGate = (await data()).items[1]!;
  assert.equal(ownerGate.state, 'OWNER_REVIEW');
  assert.equal((await app.inject({ method: 'POST', url: `${path}/approve-task`, headers: { 'x-fixture-user': 'other' }, payload: { key: ownerGate.key } })).statusCode, 404);
  assert.equal((await post('approve-task', { key: ownerGate.key })).statusCode, 200);
  await controller.tick(id); await controller.tick(id); await controller.tick(id);
  const reviewed = (await data()).items[1]!;
  assert.equal(reviewed.state, 'OWNER_REVIEW');
  assert.equal((await post('approve-task', { key: reviewed.key, sha: 'd'.repeat(40) })).statusCode, 409);
  assert.equal((await post('approve-task', { key: reviewed.key, sha: reviewed.headSha })).statusCode, 200);
  await controller.tick(id);
  assert.equal((await data()).phase, 'READY');
  assert.equal((await post('release', { sha: refs.get(testBranch), confirmed: true })).statusCode, 409);
  const preview = await post('preview');
  assert.equal(preview.statusCode, 200, preview.body);
  await controller.tick(id);
  assert.equal((await data()).preview?.success, true);
  assert.equal((await data()).preview?.url, 'https://fixture.github.io/coordinator/');
  refs.set(testBranch, 'd'.repeat(40));
  assert.equal((await post('release', { sha: requestSha, confirmed: true })).statusCode, 409);
  refs.set(testBranch, requestSha);
  const release = await post('release', { sha: requestSha, confirmed: true });
  assert.equal(release.statusCode, 200, release.body);
  assert.equal((await data()).phase, 'RELEASED');
  assert.equal(refs.get('main'), requestSha);
  assert.deepEqual(merges, [testBranch, testBranch, 'main']);
  assert.equal(launched, 5);
  // A build without a deployed application must never unlock main.
  const saved = await data();
  saved.phase = 'READY'; saved.preview = undefined;
  await prisma.teamExecution.update({ where: { id }, data: { state: 'READY', data: JSON.parse(JSON.stringify(saved)) } });
  deploymentOk = false; requestSha = '9'.repeat(40);
  assert.equal((await post('preview')).statusCode, 200);
  await controller.tick(id);
  assert.equal((await data()).phase, 'ERROR');
  assert.match((await data()).error!, /PREVIEW_DEPLOYMENT_MISSING/);
  assert.equal((await post('release', { sha: requestSha, confirmed: true })).statusCode, 409);
  workflowOk = false; deploymentOk = true; requestSha = '8'.repeat(40);
  assert.equal((await post('preview')).statusCode, 200);
  await controller.tick(id);
  assert.match((await data()).error!, /PREVIEW_BUILD_FAILED/);
  assert.equal((await post('stop')).statusCode, 200);
  const secondStart = await post('start');
  assert.equal(secondStart.statusCode, 202, secondStart.body);
  simulateLostSubmission = true;
  const secondId = secondStart.json().executionId;
  await controller.tick(secondId);
  const uncertain = executionDataSchema.parse((await prisma.teamExecution.findUniqueOrThrow({ where: { id: secondId } })).data);
  assert.equal(uncertain.phase, 'ERROR');
  assert.equal(uncertain.uncertain, true);
  const beforeRetry = launched;
  assert.equal((await post('resume')).statusCode, 409);
  assert.equal((await post('stop')).statusCode, 200);
  assert.equal((await post('start')).statusCode, 409);
  const reconciled = await post('reconcile', { key: 'leader', remoteTaskId: 'recovered-leader' });
  assert.equal(reconciled.statusCode, 200, reconciled.body);
  assert.equal(launched, beforeRetry);
  const restored = executionDataSchema.parse((await prisma.teamExecution.findUniqueOrThrow({ where: { id: secondId } })).data);
  assert.equal(restored.leaderTaskId, 'recovered-leader');
  assert.equal(restored.phase, 'PLANNING');
  assert.equal(restored.uncertain, false);
  assert.equal((await post('stop')).statusCode, 200);
  simulateLostSubmission = false;
  roadmapMode = true;
  const roadmapPath = `/api/workspace/teams/${team.id}/roadmap`;
  const version = (await app.inject({ url: roadmapPath })).json().version;
  const roadmap = [{ id: 'login', title: 'Ekran logowania', description: 'Working login flow with validation and handoffs.', dueDate: '2026-11-15', fields: { priority: 'High' }, status: 'PLANNED' }];
  const savedRoadmap = await app.inject({ method: 'PUT', url: roadmapPath, payload: { version, roadmap } });
  assert.equal(savedRoadmap.statusCode, 200, savedRoadmap.body);
  assert.equal((await post('start')).statusCode, 409);
  const milestoneStart = await post('start', { milestoneId: 'login' });
  assert.equal(milestoneStart.statusCode, 202, milestoneStart.body);
  const milestoneId = milestoneStart.json().executionId;
  const milestoneData = async () => executionDataSchema.parse((await prisma.teamExecution.findUniqueOrThrow({ where: { id: milestoneId } })).data);
  await controller.tick(milestoneId); await controller.tick(milestoneId);
  const planned = await milestoneData();
  assert.ok(planned.items.every(item => item.branch === planned.leaderBranch && item.approval === 'leader'));
  const priorMerges = merges.length;
  // Both workers and the leader reuse exactly one branch; no per-task merge or owner approval.
  for (let index = 0; index < 7; index++) await controller.tick(milestoneId);
  const ready = await milestoneData();
  assert.equal(ready.phase, 'READY', JSON.stringify(ready));
  assert.ok(ready.items.every(item => item.state === 'COMPLETED'));
  assert.equal(merges.length, priorMerges);
  assert.equal((await post('approve-milestone', { sha: '6'.repeat(40), confirmed: true })).statusCode, 409);
  simulateLostMerge = true;
  const milestoneApproval = await post('approve-milestone', { sha: '7'.repeat(40), confirmed: true });
  assert.equal(milestoneApproval.statusCode, 502, milestoneApproval.body);
  assert.equal((await milestoneData()).uncertain, true);
  assert.equal((await post('resume')).statusCode, 409);
  simulateLostMerge = false;
  const reconcileMilestone = await post('reconcile', { key: 'milestone' });
  assert.equal(reconcileMilestone.statusCode, 200, reconcileMilestone.body);
  assert.equal(merges.length, priorMerges + 1);
  const roadmapAfter = (await app.inject({ url: roadmapPath })).json();
  assert.equal(roadmapAfter.roadmap[0].status, 'APPROVED');
  assert.equal((await milestoneData()).milestoneApproved, true);
  assert.equal((await post('start', { milestoneId: 'login' })).statusCode, 409);
  const tamper = await app.inject({ method: 'PUT', url: roadmapPath, payload: { version: roadmapAfter.version, roadmap: [{ ...roadmap[0], status: 'PLANNED' }] } });
  assert.equal(tamper.statusCode, 409);
  workflowContent = 'name: Application preview';
});
