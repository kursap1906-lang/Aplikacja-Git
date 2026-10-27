import assert from 'node:assert/strict';
import test from 'node:test';
import {
  leaderPlanSchema, validateLeaderAssignments, nextExecutionItem,
  assertReleaseReady, publicPreviewUrl, executionDataSchema,
} from './team-execution-state.ts';

const task = {
  key: 'build', botId: 'developer', title: 'Build ccc-preview',
  description: 'Configure reproducible build, real tests, deployment and documented startup.',
  dependsOn: [], approval: 'leader' as const,
};
const requestId = 'c8d90715-2588-44c8-96f6-c59f04591072';
test('leader plans require bounded, acyclic assignments and an application build task', () => {
  const plan = leaderPlanSchema.parse({ requestId, summary: 'Complete application workflow', tasks: [task] });
  validateLeaderAssignments(plan, ['developer']);
  assert.throws(() => validateLeaderAssignments(plan, ['other']), /poza zespołem/);
  assert.throws(() => validateLeaderAssignments({ ...plan, tasks: [{ ...task, title: 'Form', description: 'Implement form validation with actual unit tests and API integration.' }] }, ['developer']), /kompilacji/);
  for (const tasks of [
    [task, task], [{ ...task, dependsOn: ['future'] }], [{ ...task, description: 'too short' }],
    [task, { ...task, key: 'next', dependsOn: ['build', 'build'] }],
  ]) assert.equal(leaderPlanSchema.safeParse({ requestId, summary: 'Plan', tasks }).success, false);
});
test('coordinator selects only dependency-ready work and preserves owner gates', () => {
  const pending = { ...task, taskId: 't1', branch: 'ccc/bot-developer', state: 'PENDING' as const };
  const dependent = { ...pending, key: 'ui', taskId: 't2', dependsOn: ['build'] };
  assert.equal(nextExecutionItem([dependent, pending])?.key, 'build');
  assert.equal(nextExecutionItem([{ ...pending, state: 'COMPLETED' }, dependent])?.key, 'ui');
  assert.equal(nextExecutionItem([{ ...pending, state: 'OWNER_REVIEW' }, dependent])?.state, 'OWNER_REVIEW');
});
test('main requires current successful deployed preview and unchanged base, not merely a successful build', () => {
  const data = executionDataSchema.parse({
    repository: 'owner/repo', accountId: 'account', baseBranch: 'main', baseSha: 'a'.repeat(40),
    testBranch: 'ccc/test-project', leaderBotId: 'leader', leaderBranch: 'ccc/leader-team',
    phase: 'READY', items: [{ ...task, taskId: 't1', branch: 'ccc/bot-developer', state: 'COMPLETED' }], events: [],
    preview: { sha: 'b'.repeat(40), baseSha: 'a'.repeat(40), success: true, url: 'https://owner.github.io/repo/', requestedAt: new Date().toISOString() },
  });
  assertReleaseReady(data, 'b'.repeat(40), 'a'.repeat(40));
  assert.throws(() => assertReleaseReady(data, 'c'.repeat(40), 'a'.repeat(40)), /aktualnego SHA/);
  assert.throws(() => assertReleaseReady(data, 'b'.repeat(40), 'c'.repeat(40)), /aktualnego SHA/);
  assert.throws(() => assertReleaseReady({ ...data, preview: { ...data.preview!, success: false } }, 'b'.repeat(40), 'a'.repeat(40)));
  assert.throws(() => assertReleaseReady({ ...data, items: [{ ...data.items[0]!, state: 'OWNER_REVIEW' }] }, 'b'.repeat(40), 'a'.repeat(40)));
  for (const value of ['http://example.com', 'https://user:password@example.com', 'https://127.0.0.1', 'https://localhost', 'https://10.1.2.3']) {
    assert.throws(() => publicPreviewUrl(value));
  }
});
