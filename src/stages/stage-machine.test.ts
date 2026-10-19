import assert from 'node:assert/strict';
import test from 'node:test';
import {
  StageTransitionError,
  transitionStage,
  type StageSnapshot,
} from './stage-machine.ts';

test('blocks the next stage until the previous stage is approved', () => {
  const stages: StageSnapshot[] = [
    { number: 1, status: 'WAITING_APPROVAL' },
    { number: 2, status: 'PENDING' },
  ];

  assert.throws(
    () => transitionStage(stages[1], 'RUNNING', stages),
    StageTransitionError,
  );
});

test('allows starting the next stage after explicit approval', () => {
  const stages: StageSnapshot[] = [
    { number: 1, status: 'APPROVED' },
    { number: 2, status: 'PENDING' },
  ];

  assert.deepEqual(
    transitionStage(stages[1], 'RUNNING', stages, new Date('2026-01-02T03:04:05.000Z')),
    {
      previousStatus: 'PENDING',
      status: 'RUNNING',
      occurredAt: '2026-01-02T03:04:05.000Z',
    },
  );
});

test('allows requesting changes and restarting only the approved stage', () => {
  const stages: StageSnapshot[] = [
    { number: 1, status: 'CHANGES_REQUESTED' },
    { number: 2, status: 'PENDING' },
  ];

  assert.equal(transitionStage(stages[0], 'RUNNING', stages).status, 'RUNNING');
  assert.throws(
    () => transitionStage(stages[1], 'RUNNING', stages),
    StageTransitionError,
  );
});

test('does not allow bypassing testing or manually approving a running stage', () => {
  const stages: StageSnapshot[] = [{ number: 1, status: 'RUNNING' }];

  assert.throws(
    () => transitionStage(stages[0], 'WAITING_APPROVAL', stages),
    StageTransitionError,
  );
  assert.throws(
    () => transitionStage(stages[0], 'APPROVED', stages),
    StageTransitionError,
  );
});