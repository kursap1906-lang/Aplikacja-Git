import assert from 'node:assert/strict';
import test from 'node:test';
import {
  GitHubCopilotApiError,
  GitHubCopilotProvider,
  copilotCapabilities,
} from './copilot-provider.ts';

test('declares only the coding-agent operations exposed by the REST API', () => {
  assert.deepEqual(copilotCapabilities, {
    launchTasks: true,
    readTaskStatus: true,
    readTaskLogs: false,
    resumeTasks: false,
    updateRunningTasks: false,
  });
});

test('starts a real cloud-agent task with a pull request and the current API version', async () => {
  let requestedUrl = '';
  let requestedInit: RequestInit | undefined;
  const provider = new GitHubCopilotProvider(async (input, init) => {
    requestedUrl = String(input);
    requestedInit = init;
    return Response.json({ id: 'task_123', state: 'queued' }, { status: 201 });
  });

  const task = await provider.launchTask({
    accessToken: 'user-token',
    repository: 'octo-org/control-center',
    prompt: 'Implement the requested feature.',
    baseBranch: 'main',
  });

  assert.equal(requestedUrl, 'https://api.github.com/agents/repos/octo-org/control-center/tasks');
  assert.equal(requestedInit?.method, 'POST');
  assert.equal(new Headers(requestedInit?.headers).get('authorization'), 'Bearer user-token');
  assert.equal(new Headers(requestedInit?.headers).get('x-github-api-version'), '2026-03-10');
  assert.deepEqual(JSON.parse(String(requestedInit?.body)), {
    prompt: 'Implement the requested feature.',
    base_ref: 'main',
    create_pull_request: true,
  });
  assert.deepEqual(task, { id: 'task_123', state: 'queued' });
});

test('reads the task state from the repository-scoped task endpoint', async () => {
  let requestedUrl = '';
  const provider = new GitHubCopilotProvider(async (input) => {
    requestedUrl = String(input);
    return Response.json({
      id: 'task_123',
      state: 'completed',
      html_url: 'https://github.com/octo-org/control-center',
    });

    test('continues work on the supplied working branch without requesting a new branch', async () => {
      const provider = new GitHubCopilotProvider(async (_url, init) => {
        const body = JSON.parse(String(init?.body));
        assert.equal(body.head_ref, 'ccc/bot-fixture');
        assert.equal(body.base_ref, 'main');
        return Response.json({
          id: 'task_123', state: 'waiting_for_user',
          sessions: [{ id: 'session-1', state: 'waiting_for_user', created_at: '2026-10-26T23:00:00Z', head_ref: 'ccc/bot-fixture', prompt: 'Detailed task' }],
        }, { status: 201 });
      });
      const result = await provider.launchTask({ accessToken: 'fixture', repository: 'owner/repo', prompt: 'Detailed task', baseBranch: 'main', headBranch: 'ccc/bot-fixture' });
      assert.equal(result.sessions?.[0]?.head_ref, 'ccc/bot-fixture');
    });
  });

  const task = await provider.getTask({
    accessToken: 'user-token',
    repository: 'octo-org/control-center',
    taskId: 'task_123',
  });

  assert.equal(requestedUrl, 'https://api.github.com/agents/repos/octo-org/control-center/tasks/task_123');
  assert.equal(task.state, 'completed');
  assert.equal(task.html_url, 'https://github.com/octo-org/control-center');
});

test('does not disclose a GitHub response body in errors', async () => {
  const provider = new GitHubCopilotProvider(async () => new Response('private response details', { status: 403 }));

  await assert.rejects(
    provider.launchTask({
      accessToken: 'user-token',
      repository: 'octo-org/control-center',
      prompt: 'Do the work.',
      baseBranch: 'main',
    }),
    (error: unknown) => error instanceof GitHubCopilotApiError
      && error.statusCode === 403
      && error.code === 'GITHUB_AGENT_TASK_HTTP_403'
      && !error.message.includes('private response details'),
  );
});

test('rejects malformed tasks and invalid path components without making requests', async () => {
  let requestCount = 0;
  const provider = new GitHubCopilotProvider(async () => {
    requestCount += 1;
    return Response.json({ id: 'task_123', state: 'unknown' });
  });

  await assert.rejects(
    provider.getTask({ accessToken: 'user-token', repository: 'octo-org/control-center', taskId: 'task_123' }),
    (error: unknown) => error instanceof GitHubCopilotApiError
      && error.code === 'GITHUB_AGENT_TASK_RESPONSE_INVALID',
  );
  await assert.rejects(
    provider.launchTask({ accessToken: 'user-token', repository: 'owner/../other', prompt: 'x', baseBranch: 'main' }),
    TypeError,
  );
  await assert.rejects(
    provider.getTask({ accessToken: 'user-token', repository: 'owner/repo', taskId: '../task' }),
    TypeError,
  );
  assert.equal(requestCount, 1);
});
