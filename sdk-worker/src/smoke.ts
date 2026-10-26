import { CopilotClient, RuntimeConnection, type Tool } from '@github/copilot-sdk';
import { randomUUID } from 'node:crypto';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  approvedRepository, docker, parseProbeArguments, parseProbeInput,
  readLimited, redactError, sandboxCreateArguments,
} from './isolation.ts';

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

const probeScript = `
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
let input = '';
for await (const chunk of process.stdin) input += chunk;
const { message, nonce } = JSON.parse(input);
assert.match(nonce, /^[a-f0-9-]{36}$/);
assert.equal(message, 'CCC SDK smoke');
const filename = '/workspace/.ccc-sdk-probe-' + nonce + '.json';
await writeFile(filename, JSON.stringify({ message, nonce }), { flag: 'wx', mode: 0o600 });
const bytes = await readFile(filename);
const result = JSON.parse(bytes);
assert.equal(result.message, message);
assert.equal(result.nonce, nonce);
console.log(JSON.stringify({ passed: true, sha256: createHash('sha256').update(bytes).digest('hex') }));
`;

let token = '';
let home: string | undefined;
let container: string | undefined;
let client: CopilotClient | undefined;
let result: Record<string, unknown> | undefined;
let failure: unknown;

try {
  const input = await readLimited(process.stdin, 8192);
  if (!input.length) throw new Error('The credential broker did not provide an authorized test identity.');
  ({ token } = parseProbeInput(JSON.parse(input.toString('utf8'))));
  const headers = {
    accept: 'application/vnd.github+json',
    authorization: `Bearer ${token}`,
    'x-github-api-version': '2022-11-28',
  };
  const repositoryResponse = await fetch(`https://api.github.com/repos/${approvedRepository}`, {
    headers, signal: AbortSignal.timeout(15_000),
  });
  if (!repositoryResponse.ok) throw new Error(`Repository verification failed: HTTP ${repositoryResponse.status}.`);
  const repository: unknown = await repositoryResponse.json();
  if (
    !object(repository) || repository.full_name !== approvedRepository ||
    !object(repository.permissions) || repository.permissions.push !== true ||
    typeof repository.default_branch !== 'string' || !repository.default_branch
  ) {
    throw new Error('GitHub did not confirm the approved repository and write permission.');
  }
  const commitResponse = await fetch(
    `https://api.github.com/repos/${approvedRepository}/commits/${encodeURIComponent(repository.default_branch)}`,
    { headers, signal: AbortSignal.timeout(15_000) },
  );
  if (!commitResponse.ok) throw new Error(`Commit lookup failed: HTTP ${commitResponse.status}.`);
  const commit: unknown = await commitResponse.json();
  if (!object(commit) || typeof commit.sha !== 'string' || !/^[a-f0-9]{40}$/.test(commit.sha)) {
    throw new Error('GitHub returned an invalid commit.');
  }
  const archiveResponse = await fetch(
    `https://api.github.com/repos/${approvedRepository}/tarball/${commit.sha}`,
    { headers, signal: AbortSignal.timeout(30_000) },
  );
  if (!archiveResponse.ok || !archiveResponse.body) {
    throw new Error(`Repository archive download failed: HTTP ${archiveResponse.status}.`);
  }
  const archive = await readLimited(archiveResponse.body, 30 * 1024 * 1024);
  const runId = randomUUID();
  const name = `ccc-sdk-smoke-${runId}`;
  const created = await docker(sandboxCreateArguments(name));
  if (!/^[a-f0-9]{64}$/.test(created)) throw new Error('Docker returned an invalid container ID.');
  container = created;
  const executorId = created;
  await docker(['start', container]);
  await docker([
    'exec', '-i', container, 'tar', '-xz', '--strip-components=1',
    '--no-same-owner', '--no-same-permissions', '-C', '/workspace',
  ], archive);
  let probe: Record<string, unknown> | undefined;
  let toolInvocations = 0;
  const tool: Tool = {
    name: 'run_repository_probe',
    description: 'Create a diagnostic JSON file in the isolated approved repository and verify it using Node assertions. No push.',
    parameters: {
      type: 'object',
      properties: { message: { type: 'string', const: 'CCC SDK smoke' } },
      required: ['message'],
      additionalProperties: false,
    },
    skipPermission: true,
    defer: 'never',
    handler: async (input) => {
      const args = parseProbeArguments(input);
      if (toolInvocations !== 0) throw new Error('Only one diagnostic execution is authorized.');
      toolInvocations++;
      const output = await docker(
        ['exec', '-i', executorId, 'node', '--input-type=module', '-e', probeScript],
        Buffer.from(JSON.stringify({ ...args, nonce: runId })),
      );
      const parsed: unknown = JSON.parse(output);
      if (!object(parsed) || parsed.passed !== true || typeof parsed.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(parsed.sha256)) {
        throw new Error('The sandbox did not produce a verified probe result.');
      }
      probe = parsed;
      return JSON.stringify(parsed);
    },
  };
  home = await mkdtemp(join(tmpdir(), 'ccc-sdk-smoke-'));
  const runtimeWorkingDirectory = join(home, 'runtime');
  await mkdir(runtimeWorkingDirectory, { mode: 0o700 });
  client = new CopilotClient({
    mode: 'empty',
    connection: RuntimeConnection.forStdio(),
    baseDirectory: join(home, 'state'),
    workingDirectory: runtimeWorkingDirectory,
    useLoggedInUser: false,
    gitHubToken: token,
    env: { PATH: '/usr/local/bin:/usr/bin:/bin', HOME: home, TMPDIR: home },
    logLevel: 'none',
  });
  await client.start();
  const auth = await client.getAuthStatus();
  if (!auth.isAuthenticated) throw new Error('The connected GitHub account cannot authenticate to Copilot.');
  const session = await client.createSession({
    tools: [tool],
    availableTools: ['custom:run_repository_probe'],
    excludedTools: ['builtin:*', 'mcp:*'],
    onPermissionRequest: () => ({ kind: 'reject', feedback: 'Only the pre-approved isolated diagnostic tool may execute.' }),
    systemMessage: {
      mode: 'replace',
      content: 'You are verifying a Copilot SDK integration. Use only run_repository_probe with message "CCC SDK smoke", exactly once. Do not claim success without a passed tool result. Do not access external services or request additional tools.',
    },
  });
  const response = await session.sendAndWait(
    'Run the approved diagnostic in the isolated test repository, then briefly report its result.',
    120_000,
  );
  if (!response || !probe || toolInvocations !== 1) {
    throw new Error('SDK did not complete a real, verified tool execution.');
  }
  result = {
    passed: true, runId, repository: approvedRepository, commitSha: commit.sha,
    sessionId: session.sessionId, toolInvocations, probeHash: probe.sha256,
    pushed: false, sdkVersion: '1.0.26',
  };
} catch (error) {
  failure = error;
} finally {
  const cleanupErrors: unknown[] = [];
  if (client) {
    try {
      const errors = await client.stop();
      cleanupErrors.push(...errors);
      if (errors.length) await client.forceStop();
    } catch (error) {
      cleanupErrors.push(error);
      try { await client.forceStop(); } catch (stopError) { cleanupErrors.push(stopError); }
    }
  }
  if (container) {
    try { await docker(['rm', '-f', container]); } catch (error) { cleanupErrors.push(error); }
  }
  if (home) {
    try { await rm(home, { recursive: true }); } catch (error) { cleanupErrors.push(error); }
  }
  if (cleanupErrors.length) {
    const messages = cleanupErrors.map((error) => redactError(error, token)).join('; ');
    failure = new Error(`${failure ? redactError(failure, token) + '; ' : ''}Cleanup failed: ${messages}`);
  }
}
if (failure) {
  console.error(redactError(failure, token));
  process.exitCode = 1;
} else if (result) {
  console.log(JSON.stringify(result));
} else {
  console.error('SDK diagnostic ended without a result.');
  process.exitCode = 1;
}
