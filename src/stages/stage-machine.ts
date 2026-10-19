export const stageStatuses = [
  'PENDING',
  'RUNNING',
  'TESTING',
  'WAITING_APPROVAL',
  'APPROVED',
  'CHANGES_REQUESTED',
  'FAILED',
  'PAUSED',
  'CANCELLED',
] as const;

export type StageStatus = (typeof stageStatuses)[number];

export interface StageSnapshot {
  number: number;
  status: StageStatus;
}

export interface StageTransition {
  previousStatus: StageStatus;
  status: StageStatus;
  occurredAt: string;
}

export class StageTransitionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StageTransitionError';
  }
}

const allowedTransitions: Record<StageStatus, readonly StageStatus[]> = {
  PENDING: ['RUNNING', 'CANCELLED'],
  RUNNING: ['TESTING', 'FAILED', 'PAUSED', 'CANCELLED'],
  TESTING: ['WAITING_APPROVAL', 'FAILED', 'PAUSED', 'CANCELLED'],
  WAITING_APPROVAL: ['APPROVED', 'CHANGES_REQUESTED', 'FAILED', 'PAUSED'],
  APPROVED: [],
  CHANGES_REQUESTED: ['RUNNING', 'PAUSED', 'CANCELLED'],
  FAILED: ['RUNNING', 'PAUSED', 'CANCELLED'],
  PAUSED: ['RUNNING', 'CANCELLED'],
  CANCELLED: [],
};

export function transitionStage(
  current: StageSnapshot,
  nextStatus: StageStatus,
  stages: readonly StageSnapshot[],
  occurredAt: Date = new Date(),
): StageTransition {
  if (!allowedTransitions[current.status].includes(nextStatus)) {
    throw new StageTransitionError(
      `Transition from ${current.status} to ${nextStatus} is not allowed.`,
    );
  }

  if (nextStatus === 'RUNNING' && current.number > 1) {
    const previousStage = stages.find((stage) => stage.number === current.number - 1);

    if (!previousStage || previousStage.status !== 'APPROVED') {
      throw new StageTransitionError(
        `Stage ${current.number - 1} must be approved before stage ${current.number} can start.`,
      );
    }
  }

  return {
    previousStatus: current.status,
    status: nextStatus,
    occurredAt: occurredAt.toISOString(),
  };
}