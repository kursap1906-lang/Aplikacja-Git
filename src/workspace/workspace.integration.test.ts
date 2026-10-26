import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client.ts';
import { createApp } from '../app.ts';
import { parseConfig } from '../config.ts';
import { encryptSecret } from '../security/secrets.ts';
import { copilotCapabilities, type CopilotProvider } from '../github/copilot-provider.ts';

test('real database persists shared projects and isolates team bot instances', async (context) => {
  const databaseUrl = process.env.WORKSPACE_TEST_DATABASE_URL;
  if (!databaseUrl) throw new Error('Set WORKSPACE_TEST_DATABASE_URL to the disposable integration database.');
  const url = new URL(databaseUrl);
  if (url.hostname !== 'workspace-db' || url.pathname !== '/workspace_integration') {
    throw new Error('Refusing to run integration tests outside the disposable workspace-db/workspace_integration database.');
  }
  const encryptionKey = Buffer.alloc(32, 7).toString('base64url');
  const config = parseConfig({
    NODE_ENV: 'test',
    DATABASE_URL: databaseUrl,
    APP_ORIGIN: 'http://workspace.example.test',
    APP_ENCRYPTION_KEY: encryptionKey,
  });
  const connect = () => new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
  let prisma = connect();
  let githubStatus = 200;
  const accountTokens: string[] = [];
  let branchCreates = 0;
  let openBotPull = false;
  const branches = new Set<string>();
  const fetcher: typeof fetch = async (_url, options) => {
    const authorization = new Headers(options?.headers).get('authorization');
    assert.ok(authorization === 'Bearer fixture-access-a' || authorization === 'Bearer fixture-access-b');
    accountTokens.push(authorization);
    if (String(_url).includes('/pulls?')) return Response.json(openBotPull ? [{ number: 8 }] : []);
    if (String(_url).includes('/git/ref/heads/ccc/')) {
      return branches.has(String(_url).split('/heads/')[1]!) ? Response.json({ object: { sha: 'a'.repeat(40) } }) : new Response('', { status: 404 });
    }
    if (String(_url).includes('/git/ref/heads/')) return Response.json({ object: { sha: 'a'.repeat(40) } });
    if (String(_url).endsWith('/git/refs')) {
      branchCreates++;
      const body = JSON.parse(String(options?.body));
      branches.add(body.ref.replace('refs/heads/', ''));
      return Response.json({ ref: body.ref }, { status: 201 });
    }
    if (String(_url).endsWith('/pulls/7')) {
      return Response.json({
        number: 7, title: 'Remote fixture result', body: 'Test fixture PR', state: 'open', draft: false,
        html_url: 'https://github.com/fixture/repository/pull/7', merged_at: null,
        head: { ref: 'copilot/fixture', sha: 'a'.repeat(40) }, base: { ref: 'main' },
        user: { login: 'fixture' }, updated_at: '2026-10-26T22:00:00Z',
      });
    }
    return Response.json({
      id: 123, full_name: 'fixture/repository', default_branch: 'main',
      permissions: { push: true },
    }, { status: githubStatus });
  };
  let launches = 0;
  const provider: CopilotProvider = {
    capabilities: copilotCapabilities,
    launchTask: async input => {
      assert.equal(input.repository, 'fixture/repository');
      assert.ok(input.prompt.includes('Test fixture only') || input.prompt.includes('Pracuj zdalnie'));
      if (input.prompt.includes('Pracuj zdalnie')) assert.match(input.headBranch!, /^ccc\/bot-/);
      launches++;
      return { id: `fixture-task-${launches}`, state: 'queued', html_url: 'https://github.com/fixture/repository' };
    },
    getTask: async () => ({ id: `fixture-task-${launches}`, state: 'completed' }),
  };
  let app = createApp({ prisma, config, fetcher, copilotProvider: provider });
  context.after(async () => app.close());

  const register = async (email: string) => {
    const response = await app.inject({
      method: 'POST', url: '/api/auth/register',
      payload: { email, password: 'Fixture-password-12345' },
    });
    assert.equal(response.statusCode, 201, response.body);
    const body = response.json();
    return {
      userId: body.user.id as string,
      headers: { authorization: `Bearer ${body.sessionToken}`, 'x-csrf-token': body.csrfToken as string },
    };
  };
  const runId = randomUUID();
  const alice = await register(`alice+${runId}@workspace.example.test`);
  const bob = await register(`bob+${runId}@workspace.example.test`);
  const accountA = await prisma.gitHubAccount.create({
    data: {
      userId: alice.userId, githubUserId: '1', login: 'fixture-a',
      encryptedAccessToken: encryptSecret('fixture-access-a', encryptionKey),
      scopes: ['repo', 'read:user'],
    },
  });
  const accountB = await prisma.gitHubAccount.create({
    data: {
      userId: alice.userId, githubUserId: '2', login: 'fixture-b',
      encryptedAccessToken: encryptSecret('fixture-access-b', encryptionKey),
      scopes: ['repo', 'read:user'],
    },
  });
  const definitionInput = {
    name: 'Developer', role: 'Implementation', description: 'Build and test',
    systemPrompt: 'Write tested code.', skills: ['TypeScript'],
  };
  const definitionResponse = await app.inject({
    method: 'POST', url: '/api/bot-definitions', headers: alice.headers, payload: definitionInput,
  });
  assert.equal(definitionResponse.statusCode, 201, definitionResponse.body);
  const definitionId: string = definitionResponse.json().definition.id;
  const reviewResponse = await app.inject({
    method: 'POST', url: '/api/bot-definitions', headers: alice.headers,
    payload: { ...definitionInput, name: 'Reviewer', role: 'Review' },
  });
  assert.equal(reviewResponse.statusCode, 201, reviewResponse.body);
  const reviewId: string = reviewResponse.json().definition.id;
  const projectResponse = await app.inject({
    method: 'POST', url: '/api/workspace/projects', headers: alice.headers,
    payload: {
      name: 'Shared project', description: 'Two teams', brief: 'Project specification',
      repository: 'fixture/repository', githubAccountId: accountA.id,
    },
  });
  assert.equal(projectResponse.statusCode, 201, projectResponse.body);
  const projectId: string = projectResponse.json().project.id;
  const createTeam = (name: string) => app.inject({
    method: 'POST', url: '/api/workspace/teams', headers: alice.headers,
    payload: {
      name, projectId,
      members: [
        { definitionId, githubAccountId: accountA.id },
        { definitionId: reviewId, githubAccountId: accountB.id },
      ],
    },
  });
  const first = await createTeam('Frontend');
  const second = await createTeam('Backend');
  assert.equal(first.statusCode, 201, first.body);
  assert.equal(second.statusCode, 201, second.body);
  const firstTeamId: string = first.json().team.id;
  const secondTeamId: string = second.json().team.id;
  let workspaceResponse = await app.inject({ method: 'GET', url: '/api/workspace', headers: alice.headers });
  assert.equal(workspaceResponse.statusCode, 200, workspaceResponse.body);
  let workspace = workspaceResponse.json();
  assert.equal(workspace.projects.length, 1);
  assert.equal(workspace.teams.length, 2);
  const frontend = workspace.teams.find((team: { id: string }) => team.id === firstTeamId);
  const backend = workspace.teams.find((team: { id: string }) => team.id === secondTeamId);
  assert.equal(frontend.projectId, projectId);
  assert.equal(backend.projectId, projectId);
  assert.notEqual(frontend.bots[0].botId, backend.bots[0].botId);
  assert.equal(frontend.bots[0].bot.definitionId, backend.bots[0].bot.definitionId);
  assert.equal(frontend.bots[0].bot.githubAccountId, accountA.id);
  assert.equal(frontend.bots[1].bot.githubAccountId, accountB.id);
  assert.equal(workspaceResponse.body.includes('fixture-access'), false);
  assert.equal(workspaceResponse.body.includes('encryptedAccessToken'), false);
  assert.ok(accountTokens.includes('Bearer fixture-access-a'));
  assert.ok(accountTokens.includes('Bearer fixture-access-b'));

  const taskResponse = await app.inject({
    method: 'POST', url: `/api/workspace/teams/${firstTeamId}/tasks`, headers: alice.headers,
    payload: { title: 'Implement UI', botId: frontend.bots[0].botId, priority: 'URGENT' },
  });
  assert.equal(taskResponse.statusCode, 201, taskResponse.body);
  const taskId: string = taskResponse.json().task.id;
  assert.equal(taskResponse.json().task.teamId, firstTeamId);
  assert.equal(taskResponse.json().task.projectId, projectId);
  assert.equal(taskResponse.json().task.priority, 'URGENT');
  assert.equal(taskResponse.json().task.status, 'TODO');
  const crossTeamTask = await app.inject({
    method: 'POST', url: `/api/workspace/teams/${firstTeamId}/tasks`, headers: alice.headers,
    payload: { title: 'Invalid assignment', botId: backend.bots[0].botId },
  });
  assert.equal(crossTeamTask.statusCode, 400, crossTeamTask.body);
  const crossTeamEdit = await app.inject({
    method: 'PATCH', url: `/api/workspace/tasks/${taskId}`, headers: alice.headers,
    payload: { botId: backend.bots[0].botId },
  });
  assert.equal(crossTeamEdit.statusCode, 400, crossTeamEdit.body);
  const editTask = await app.inject({
    method: 'PATCH', url: `/api/workspace/tasks/${taskId}`, headers: alice.headers,
    payload: { title: 'Implement tested UI', priority: 'HIGH', botId: frontend.bots[1].botId },
  });
  assert.equal(editTask.statusCode, 200, editTask.body);
  const legacyProjectTask = await prisma.projectTask.create({
    data: { projectId, userId: alice.userId, title: 'Legacy project-only task' },
  });

  const hierarchyMembers = [
    { id: frontend.bots[0].id, parentId: null },
    { id: frontend.bots[1].id, parentId: frontend.bots[0].id },
  ];
  const hierarchy = await app.inject({
    method: 'PATCH', url: `/api/workspace/teams/${firstTeamId}/hierarchy`, headers: alice.headers,
    payload: { updatedAt: frontend.updatedAt, members: hierarchyMembers },
  });
  assert.equal(hierarchy.statusCode, 200, hierarchy.body);
  const staleHierarchy = await app.inject({
    method: 'PATCH', url: `/api/workspace/teams/${firstTeamId}/hierarchy`, headers: alice.headers,
    payload: { updatedAt: frontend.updatedAt, members: hierarchyMembers },
  });
  assert.equal(staleHierarchy.statusCode, 409, staleHierarchy.body);
  const cycle = await app.inject({
    method: 'PATCH', url: `/api/workspace/teams/${firstTeamId}/hierarchy`, headers: alice.headers,
    payload: {
      updatedAt: frontend.updatedAt,
      members: [
        { id: frontend.bots[0].id, parentId: frontend.bots[1].id },
        { id: frontend.bots[1].id, parentId: frontend.bots[0].id },
      ],
    },
  });
  assert.equal(cycle.statusCode, 400, cycle.body);
  assert.equal(cycle.json().error.code, 'TEAM_HIERARCHY_CYCLE');
  const duplicateTeam = await createTeam('Frontend');
  assert.equal(duplicateTeam.statusCode, 409, duplicateTeam.body);
  assert.equal(await prisma.bot.count({ where: { userId: alice.userId } }), 4);
  githubStatus = 403;
  const deniedTeam = await createTeam('No permission');
  assert.equal(deniedTeam.statusCode, 403, deniedTeam.body);
  assert.equal(await prisma.bot.count({ where: { userId: alice.userId } }), 4);
  assert.equal(await prisma.team.count({ where: { userId: alice.userId } }), 2);
  assert.equal((await prisma.gitHubAccount.findUniqueOrThrow({ where: { id: accountA.id } })).status, 'ACTIVE');
  githubStatus = 200;

  const updatedDefinition = await app.inject({
    method: 'PATCH', url: `/api/bot-definitions/${definitionId}`, headers: alice.headers,
    payload: { ...definitionInput, systemPrompt: 'A new prompt for future instances.' },
  });
  assert.equal(updatedDefinition.statusCode, 200, updatedDefinition.body);
  assert.equal((await prisma.bot.findUniqueOrThrow({ where: { id: frontend.bots[0].botId } })).systemPrompt, 'Write tested code.');

  const bobWorkspace = await app.inject({ method: 'GET', url: '/api/workspace', headers: bob.headers });
  assert.deepEqual(bobWorkspace.json(), { definitions: [], projects: [], teams: [] });
  for (const [method, path, payload] of [
    ['PATCH', `/api/workspace/projects/${projectId}`, { brief: 'Unauthorized change' }],
    ['PATCH', `/api/workspace/tasks/${taskId}`, { title: 'Unauthorized change' }],
    ['PATCH', `/api/bot-definitions/${definitionId}`, definitionInput],
    ['POST', '/api/workspace/teams', {
      name: 'Foreign project', projectId, members: [{ definitionId, githubAccountId: accountA.id }],
    }],
  ] as const) {
    const response = await app.inject({ method, url: path, headers: bob.headers, payload });
    assert.equal(response.statusCode, 404, response.body);
  }
  const noCsrf = await app.inject({
    method: 'POST', url: '/api/bot-definitions',
    headers: { authorization: alice.headers.authorization }, payload: definitionInput,
  });
  assert.equal(noCsrf.statusCode, 403, noCsrf.body);
  const foreignOrigin = await app.inject({
    method: 'POST', url: '/api/bot-definitions',
    headers: { ...alice.headers, origin: 'https://foreign.example.test' }, payload: definitionInput,
  });
  assert.equal(foreignOrigin.statusCode, 403, foreignOrigin.body);
  assert.equal(foreignOrigin.json().error.code, 'INVALID_ORIGIN');
  const cookieWorkspace = await app.inject({
    method: 'GET', url: '/api/workspace',
    headers: { cookie: `ccc_session=${alice.headers.authorization.slice('Bearer '.length)}` },
  });
  assert.equal(cookieWorkspace.statusCode, 200, cookieWorkspace.body);
  assert.equal(cookieWorkspace.json().projects[0].id, projectId);
  const unauthenticated = await app.inject({ method: 'GET', url: '/api/workspace' });
  assert.equal(unauthenticated.statusCode, 401, unauthenticated.body);
  const repoChange = await app.inject({
    method: 'PATCH', url: `/api/projects/${projectId}`, headers: alice.headers,
    payload: { repository: 'fixture/different' },
  });
  assert.equal(repoChange.statusCode, 409, repoChange.body);
  const globalAssignment = await app.inject({
    method: 'POST', url: `/api/teams/${secondTeamId}/bots`, headers: alice.headers,
    payload: { botId: frontend.bots[0].botId },
  });
  assert.equal(globalAssignment.statusCode, 409, globalAssignment.body);

  const plannedTeam = await app.inject({
    method: 'POST', url: '/api/workspace/teams', headers: alice.headers,
    payload: {
      name: 'Planning', projectId,
      members: [{ definitionId, githubAccountId: accountA.id }],
      tasks: [{ definitionId, title: 'Planned before saving', priority: 'URGENT' }],
    },
  });
  assert.equal(plannedTeam.statusCode, 201, plannedTeam.body);
  const plannedTasks = await prisma.projectTask.findMany({ where: { teamId: plannedTeam.json().team.id } });
  assert.equal(plannedTasks.length, 1);
  assert.equal(plannedTasks[0].priority, 'URGENT');
  const plannedBotId = plannedTasks[0].botId;
  assert.ok(plannedBotId);
  assert.equal((await prisma.bot.findUniqueOrThrow({ where: { id: plannedBotId } })).systemPrompt, 'A new prompt for future instances.');
  const invalidPlan = await app.inject({
    method: 'POST', url: '/api/workspace/teams', headers: alice.headers,
    payload: {
      name: 'Invalid planning', projectId,
      members: [{ definitionId, githubAccountId: accountA.id }],
      tasks: [{ definitionId: reviewId, title: 'Assignee not selected' }],
    },
  });
  assert.equal(invalidPlan.statusCode, 400, invalidPlan.body);
  assert.equal(await prisma.team.count({ where: { userId: alice.userId } }), 3);
  const renamed = await app.inject({
    method: 'PATCH', url: `/api/workspace/teams/${firstTeamId}`, headers: alice.headers,
    payload: { name: 'Frontend updated', description: 'Updated persisted details' },
  });
  assert.equal(renamed.statusCode, 200, renamed.body);
  const designerResponse = await app.inject({
    method: 'POST', url: '/api/bot-definitions', headers: alice.headers,
    payload: { ...definitionInput, name: 'Designer' },
  });
  assert.equal(designerResponse.statusCode, 201, designerResponse.body);
  const designerId: string = designerResponse.json().definition.id;
  const addDesigner = () => app.inject({
    method: 'POST', url: `/api/workspace/teams/${firstTeamId}/members`, headers: alice.headers,
    payload: { definitionId: designerId, githubAccountId: accountB.id },
  });
  const designer = await addDesigner();
  assert.equal(designer.statusCode, 201, designer.body);
  const designerMemberId: string = designer.json().member.id;
  const designerBotId: string = designer.json().member.botId;
  const duplicateDesigner = await addDesigner();
  assert.equal(duplicateDesigner.statusCode, 409, duplicateDesigner.body);
  const temporaryTask = await app.inject({
    method: 'POST', url: `/api/workspace/teams/${firstTeamId}/tasks`, headers: alice.headers,
    payload: { title: 'Temporary draft task', botId: designerBotId },
  });
  assert.equal(temporaryTask.statusCode, 201, temporaryTask.body);
  const removeDesigner = () => app.inject({
    method: 'DELETE', url: `/api/workspace/teams/${firstTeamId}/members/${designerMemberId}`, headers: alice.headers,
  });
  const blockedRemoval = await removeDesigner();
  assert.equal(blockedRemoval.statusCode, 409, blockedRemoval.body);
  assert.equal(blockedRemoval.json().error.code, 'BOT_HAS_TASKS');
  await prisma.taskDependency.create({
    data: { taskId: temporaryTask.json().task.id, dependsOnTaskId: taskId },
  });
  const blockedTaskDelete = await app.inject({
    method: 'DELETE', url: `/api/workspace/tasks/${taskId}`, headers: alice.headers,
  });
  assert.equal(blockedTaskDelete.statusCode, 409, blockedTaskDelete.body);
  const temporaryDelete = await app.inject({
    method: 'DELETE', url: `/api/workspace/tasks/${temporaryTask.json().task.id}`, headers: alice.headers,
  });
  assert.equal(temporaryDelete.statusCode, 204, temporaryDelete.body);
  const removedDesigner = await removeDesigner();
  assert.equal(removedDesigner.statusCode, 204, removedDesigner.body);
  assert.ok(await prisma.bot.findUnique({ where: { id: designerBotId } }));

  const sampleBytes = Buffer.from([0, 255, 13, 10, 37, 80, 68, 70, 128, 129]);
  const upload = (path: string, bytes: Buffer, filename = 'fixture.pdf') => app.inject({
    method: 'POST', url: `${path}?filename=${encodeURIComponent(filename)}`,
    headers: { ...alice.headers, 'content-type': 'application/octet-stream' }, payload: bytes,
  });
  const uploaded = await upload(`/api/workspace/projects/${projectId}/files`, sampleBytes);
  assert.equal(uploaded.statusCode, 201, uploaded.body);
  const fileId: string = uploaded.json().file.id;
  assert.equal(uploaded.json().file.sizeBytes, sampleBytes.length);
  assert.equal('encryptedContent' in uploaded.json().file, false);
  const storedFile = await prisma.workspaceFile.findUniqueOrThrow({ where: { id: fileId } });
  assert.notEqual(storedFile.encryptedContent, sampleBytes.toString('base64'));
  const downloaded = await app.inject({
    method: 'GET', url: `/api/workspace/files/${fileId}/download`, headers: alice.headers,
  });
  assert.equal(downloaded.statusCode, 200, downloaded.body);
  assert.deepEqual(downloaded.rawPayload, sampleBytes);
  const foreignDownload = await app.inject({
    method: 'GET', url: `/api/workspace/files/${fileId}/download`, headers: bob.headers,
  });
  assert.equal(foreignDownload.statusCode, 404, foreignDownload.body);
  const removedFile = await app.inject({
    method: 'DELETE', url: `/api/workspace/files/${fileId}`, headers: alice.headers,
  });
  assert.equal(removedFile.statusCode, 204, removedFile.body);
  const invalidFilename = await upload(`/api/workspace/projects/${projectId}/files`, sampleBytes, '../file.pdf');
  assert.equal(invalidFilename.statusCode, 400, invalidFilename.body);

  const exactLimit = Buffer.alloc(10 * 1024 * 1024, 0xa5);
  const concurrentFiles = await Promise.all([1, 2, 3, 4].map((index) =>
    upload(`/api/workspace/projects/${projectId}/files`, exactLimit, `limit-${index}.bin`)));
  assert.deepEqual(concurrentFiles.map((response) => response.statusCode).sort(), [201, 201, 201, 413]);
  const projectSize = await prisma.workspaceFile.aggregate({ where: { projectId }, _sum: { sizeBytes: true } });
  assert.equal(projectSize._sum.sizeBytes, 30 * 1024 * 1024);
  const overFileLimit = await upload(`/api/workspace/projects/${projectId}/files`, Buffer.alloc(exactLimit.length + 1));
  assert.equal(overFileLimit.statusCode, 413, overFileLimit.body);
  assert.equal(overFileLimit.json().error.code, 'FILE_TOO_LARGE');

  const draft = await app.inject({
    method: 'POST', url: `/api/workspace/bots/${frontend.bots[0].botId}/messages`, headers: alice.headers,
    payload: { content: 'Review this attachment after I approve execution.' },
  });
  assert.equal(draft.statusCode, 201, draft.body);
  assert.equal(draft.json().message.status, 'DRAFT');
  assert.equal(draft.json().message.role, 'USER');
  const messageId: string = draft.json().message.id;
  const chatFile = await upload(`/api/workspace/messages/${messageId}/files`, sampleBytes, 'image.bin');
  assert.equal(chatFile.statusCode, 201, chatFile.body);
  const otherTeamMessages = await app.inject({
    method: 'GET', url: `/api/workspace/bots/${backend.bots[0].botId}/messages`, headers: alice.headers,
  });
  assert.deepEqual(otherTeamMessages.json(), { messages: [] });
  const foreignMessages = await app.inject({
    method: 'GET', url: `/api/workspace/bots/${frontend.bots[0].botId}/messages`, headers: bob.headers,
  });
  assert.equal(foreignMessages.statusCode, 404, foreignMessages.body);

  const scheduleInput = {
    timezone: 'Europe/Warsaw', enabled: true, days: [1, 2, 3, 4, 5],
    startTime: '09:00', endTime: '17:00',
  };
  const scheduleResponse = await app.inject({
    method: 'POST', url: `/api/workspace/bots/${frontend.bots[0].botId}/schedule`, headers: alice.headers,
    payload: scheduleInput,
  });
  assert.equal(scheduleResponse.statusCode, 200, scheduleResponse.body);
  for (const invalid of [
    { ...scheduleInput, timezone: 'Not/AZone' },
    { ...scheduleInput, endTime: '08:00' },
    { ...scheduleInput, days: [1, 1] },
    { ...scheduleInput, startTime: '24:00' },
  ]) {
    const rejected = await app.inject({
      method: 'POST', url: `/api/workspace/bots/${frontend.bots[0].botId}/schedule`, headers: alice.headers,
      payload: invalid,
    });
    assert.equal(rejected.statusCode, 400, rejected.body);
  }
  assert.equal(await prisma.botWorkSchedule.count({ where: { bot: { userId: alice.userId } } }), 1);
  assert.equal(await prisma.botWorkSchedule.findUnique({ where: { botId: backend.bots[0].botId } }), null);

  const stage = await prisma.stage.create({
    data: {
      botId: frontend.bots[0].botId, number: 1, title: 'Fixture review stage',
      description: 'Test fixture only; no agent execution.', acceptanceCriteria: ['Approved manually'],
      status: 'WAITING_APPROVAL',
    },
  });
  const missingInstructions = await app.inject({
    method: 'POST', url: `/api/stages/${stage.id}/request-changes`, headers: alice.headers, payload: {},
  });
  assert.equal(missingInstructions.statusCode, 400, missingInstructions.body);
  const revision = await app.inject({
    method: 'POST', url: `/api/stages/${stage.id}/request-changes`, headers: alice.headers,
    payload: { reason: 'Add the missing loading state.' },
  });
  assert.equal(revision.statusCode, 200, revision.body);
  const transitionId: string = revision.json().stage.transitionId;
  assert.ok(transitionId);
  const revisionFile = await upload(`/api/workspace/revisions/${transitionId}/files`, sampleBytes, 'review.bin');
  assert.equal(revisionFile.statusCode, 201, revisionFile.body);
  await prisma.botWorkSchedule.update({ where: { botId: frontend.bots[0].botId }, data: { enabled: false } });
  const legacyStart = await app.inject({
    method: 'POST', url: `/api/stages/${stage.id}/start`, headers: alice.headers, payload: {},
  });
  assert.equal(legacyStart.statusCode, 202, legacyStart.body);

  await app.close();
  prisma = connect();
  app = createApp({ prisma, config, fetcher, copilotProvider: provider });
  workspaceResponse = await app.inject({ method: 'GET', url: '/api/workspace', headers: alice.headers });
  assert.equal(workspaceResponse.statusCode, 200, workspaceResponse.body);
  workspace = workspaceResponse.json();
  assert.equal(workspace.projects[0].brief, 'Project specification');
  assert.ok(workspace.projects[0].tasks.some((task: { id: string; teamId: string | null }) =>
    task.id === legacyProjectTask.id && task.teamId === null));
  assert.ok(workspace.projects[0].tasks.some((task: { id: string; botId: string }) =>
    task.id === taskId && task.botId === frontend.bots[1].botId));
  const persisted = workspace.teams.find((team: { id: string }) => team.id === firstTeamId);
  assert.equal(persisted.name, 'Frontend updated');
  assert.equal(persisted.description, 'Updated persisted details');
  assert.equal(persisted.tasks[0].title, 'Implement tested UI');
  assert.equal(persisted.tasks[0].priority, 'HIGH');
  assert.equal(persisted.bots.find((member: { id: string }) => member.id === frontend.bots[1].id).parentId, frontend.bots[0].id);
  assert.equal(workspace.projects[0].files.length, 3);
  const persistedBot = persisted.bots.find((member: { botId: string }) => member.botId === frontend.bots[0].botId);
  assert.equal(persistedBot.bot.workSchedule.timezone, 'Europe/Warsaw');
  assert.deepEqual(persistedBot.bot.workSchedule.days, [1, 2, 3, 4, 5]);
  const persistedMessages = await app.inject({
    method: 'GET', url: `/api/workspace/bots/${frontend.bots[0].botId}/messages`, headers: alice.headers,
  });
  assert.equal(persistedMessages.json().messages[0].id, messageId);
  assert.equal(persistedMessages.json().messages[0].files[0].filename, 'image.bin');
  assert.equal(persistedMessages.json().messages[0].status, 'DRAFT');
  const persistedRevisions = await app.inject({
    method: 'GET', url: `/api/workspace/stages/${stage.id}/revisions`, headers: alice.headers,
  });
  assert.equal(persistedRevisions.json().revisions[0].details.reason, 'Add the missing loading state.');
  assert.equal(persistedRevisions.json().revisions[0].files[0].filename, 'review.bin');

  const templateInput = { githubAccountId: accountA.id, repository: 'fixture/repository' };
  const templates = await Promise.all([1, 2].map(() => app.inject({
    method: 'POST', url: '/api/workspace/templates/construction', headers: alice.headers, payload: templateInput,
  })));
  assert.deepEqual(templates.map(result => result.statusCode).sort(), [200, 201]);
  assert.equal(templates[0].json().teamId, templates[1].json().teamId);
  const templateTeam = await prisma.team.findUniqueOrThrow({
    where: { id: templates[0].json().teamId }, include: { bots: true, tasks: true },
  });
  assert.equal(templateTeam.bots.length, 5);
  assert.equal(templateTeam.tasks.length, 5);
  const remoteTask = templateTeam.tasks.find(task => task.title.startsWith('Zaprojektuj MVP'))!;
  const agentUrl = `/api/workspace/tasks/${remoteTask.id}/agent-stage`;
  const notPrepared = await app.inject({ url: agentUrl, headers: alice.headers });
  assert.equal(notPrepared.json().stage, null);
  const foreign = await app.inject({ method: 'POST', url: agentUrl, headers: bob.headers });
  assert.equal(foreign.statusCode, 404);
  const prepared = await Promise.all([1, 2].map(() => app.inject({ method: 'POST', url: agentUrl, headers: alice.headers })));
  assert.equal(prepared[0].statusCode, 200, prepared[0].body);
  assert.equal(prepared[0].json().stage.id, prepared[1].json().stage.id);
  const remoteStageId: string = prepared[0].json().stage.id;
  const beforeLaunch = launches;
  const beforeBranch = branchCreates;
  const remoteStart = await app.inject({
    method: 'POST', url: `/api/stages/${remoteStageId}/start`, headers: alice.headers, payload: {},
  });
  assert.equal(remoteStart.statusCode, 202, remoteStart.body);
  assert.equal(branchCreates, beforeBranch + 1);
  assert.equal(launches, beforeLaunch + 1);
  assert.equal(branchCreates, beforeBranch + 1);
  assert.equal((await prisma.projectTask.findUniqueOrThrow({ where: { id: remoteTask.id } })).status, 'IN_PROGRESS');
  const duplicateStart = await app.inject({
    method: 'POST', url: `/api/stages/${remoteStageId}/start`, headers: alice.headers, payload: {},
  });
  assert.equal(duplicateStart.statusCode, 409);
  assert.equal(launches, beforeLaunch + 1);
  const remoteStatus = await app.inject({ url: `/api/stages/${remoteStageId}/task`, headers: alice.headers });
  assert.equal(remoteStatus.statusCode, 200, remoteStatus.body);
  assert.equal(remoteStatus.json().stage.status, 'WAITING_APPROVAL');
  assert.equal((await prisma.projectTask.findUniqueOrThrow({ where: { id: remoteTask.id } })).status, 'IN_PROGRESS');
  const deleteHistory = await app.inject({ method: 'DELETE', url: `/api/workspace/tasks/${remoteTask.id}`, headers: alice.headers });
  assert.equal(deleteHistory.statusCode, 409);
  const linkUrl = `/api/workspace/github/pulls/7/link-stage?accountId=${accountA.id}&repository=fixture/repository`;
  const linked = await app.inject({
    method: 'POST', url: linkUrl, headers: alice.headers, payload: { stageId: remoteStageId },
  });
  assert.equal(linked.statusCode, 200, linked.body);
  assert.equal(linked.json().stageId, remoteStageId);
  const storedPull = await prisma.pullRequest.findUniqueOrThrow({ where: { id: linked.json().pullRequestId } });
  assert.equal(storedPull.stageId, remoteStageId);
  assert.equal(storedPull.headBranch, 'copilot/fixture');
  const foreignLink = await app.inject({
    method: 'POST', url: linkUrl, headers: bob.headers, payload: { stageId: remoteStageId },
  });
  assert.equal(foreignLink.statusCode, 404);
  const duplicateLink = await app.inject({
    method: 'POST', url: linkUrl, headers: alice.headers, payload: { stageId: remoteStageId },
  });
  assert.equal(duplicateLink.statusCode, 200, duplicateLink.body);
  assert.equal(duplicateLink.json().pullRequestId, linked.json().pullRequestId);
  const bypass = await app.inject({
    method: 'PATCH', url: `/api/tasks/${remoteTask.id}`, headers: alice.headers, payload: { status: 'COMPLETED' },
  });
  assert.equal(bypass.statusCode, 409, bypass.body);
  await prisma.stage.update({ where: { id: remoteStageId }, data: { status: 'APPROVED' } });
  const nextTask = await prisma.projectTask.create({ data: {
    userId: remoteTask.userId, projectId: remoteTask.projectId, teamId: remoteTask.teamId,
    botId: remoteTask.botId, title: 'Next fixture increment', description: 'Synthetic continuation.',
  } });
  const nextPrepared = await app.inject({
    method: 'POST', url: `/api/workspace/tasks/${nextTask.id}/agent-stage`, headers: alice.headers,
  });
  assert.equal(nextPrepared.statusCode, 200, nextPrepared.body);
  const nextStage = nextPrepared.json().stage.id;
  openBotPull = true;
  const blockedNext = await app.inject({
    method: 'POST', url: `/api/stages/${nextStage}/start`, headers: alice.headers, payload: {},
  });
  assert.equal(blockedNext.statusCode, 409, blockedNext.body);
  assert.equal(blockedNext.json().error.code, 'BOT_BRANCH_PR_OPEN');
  assert.equal(launches, beforeLaunch + 1);
  assert.equal((await prisma.stage.findUniqueOrThrow({ where: { id: nextStage } })).status, 'PENDING');
  openBotPull = false;
  const nextStart = await app.inject({
    method: 'POST', url: `/api/stages/${nextStage}/start`, headers: alice.headers, payload: {},
  });
  assert.equal(nextStart.statusCode, 202, nextStart.body);
  assert.equal(branchCreates, beforeBranch + 1);
  const stageBranches = await prisma.stage.findMany({ where: { id: { in: [remoteStageId, nextStage] } } });
  assert.equal(stageBranches[0]?.branchName, stageBranches[1]?.branchName);
});
