import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import test from 'node:test';
import {
  approvedRepository, parseProbeArguments, parseProbeInput, parseProbeReport, readLimited,
  redactError, sandboxCreateArguments, sandboxImage,
} from './isolation.ts';

test('sandbox has no host mounts, credentials, network or application image', () => {
  const args = sandboxCreateArguments('ccc-sdk-smoke-12345678-1234-1234-1234-123456789abc');
  const option = (name: string) => args[args.indexOf(name) + 1];
  assert.equal(option('--network'), 'none');
  assert.equal(option('--user'), '1000:1000');
  assert.equal(option('--workdir'), '/workspace');
  assert.equal(option('--cap-drop'), 'ALL');
  assert.equal(option('--memory'), '512m');
  assert.equal(option('--memory-swap'), '512m');
  assert.equal(option('--security-opt'), 'no-new-privileges:true');
  assert.ok(args.includes('--read-only'));
  assert.ok(args.includes(sandboxImage));
  const options = args.slice(0, args.indexOf(sandboxImage));
  assert.ok(!options.some((arg) => ['-v', '--volume', '--mount', '--env', '-e', '--privileged', '--pid'].includes(arg)));
});

test('sandbox name cannot inject Docker options or refer to another container', () => {
  for (const name of ['', '--privileged', 'ccc-staging-api-1', 'ccc-sdk-smoke-../api']) {
    assert.throws(() => sandboxCreateArguments(name));
  }
});

test('only the explicitly approved repository and bounded token are accepted', () => {
  const token = 'fixture-token-not-a-real-credential';
  assert.deepEqual(parseProbeInput({ repository: approvedRepository, token }), { token });
  for (const value of [
    null, {}, { repository: 'other/private', token },
    { repository: approvedRepository, token: 'short' },
    { repository: approvedRepository, token: `${token}\n` },
    { repository: approvedRepository, token: 'x'.repeat(1025) },
  ]) {
    assert.throws(() => parseProbeInput(value));
  }
});

test('model cannot provide executable code, paths, commands or arbitrary content', () => {
  assert.deepEqual(parseProbeArguments({ message: 'CCC SDK smoke' }), { message: 'CCC SDK smoke' });
  for (const value of [
    null, {}, { message: 'other' }, { message: 'CCC SDK smoke', command: 'anything' },
    { message: 'CCC SDK smoke', path: '/etc/passwd' },
  ]) {
    assert.throws(() => parseProbeArguments(value));
  }
});

test('bounded streams preserve binary bytes and reject the exact over-limit case', async () => {
  assert.deepEqual(await readLimited(Readable.from([Buffer.from([0, 255]), Buffer.from([1])]), 3), Buffer.from([0, 255, 1]));
  await assert.rejects(readLimited(Readable.from([Buffer.alloc(4)]), 3), /safety limit/);
});

test('credentials are removed from failures before reporting', () => {
  assert.equal(redactError(new Error('token secret and secret'), 'secret'), 'token [REDACTED] and [REDACTED]');
  assert.equal(redactError(null, ''), 'Unknown SDK test error.');
  assert.equal(redactError(new Error('gho_fixture_token Bearer temporary.token'), ''), '[REDACTED] Bearer [REDACTED]');
});

const report = {
  passed: true, pushed: false, repository: approvedRepository, sdkVersion: '1.0.26',
  toolInvocations: 1, runId: '12345678-1234-1234-1234-123456789abc',
  sessionId: '12345678-1234-1234-1234-123456789abc',
  commitSha: 'a'.repeat(40), probeHash: 'b'.repeat(64),
};

test('success records contain only verified report fields and never credentials', () => {
  assert.deepEqual(parseProbeReport({ ...report, token: 'do-not-persist' }), report);
});

test('unverified or differently scoped executions cannot be recorded as success', () => {
  for (const value of [
    null, {}, { ...report, passed: false }, { ...report, pushed: true },
    { ...report, toolInvocations: 0 }, { ...report, toolInvocations: 2 },
    { ...report, repository: 'other/repo' }, { ...report, sdkVersion: 'other' },
    { ...report, commitSha: 'branch-name' }, { ...report, probeHash: '' },
    { ...report, sessionId: '' }, { ...report, runId: '' },
  ]) {
    assert.throws(() => parseProbeReport(value));
  }
});
