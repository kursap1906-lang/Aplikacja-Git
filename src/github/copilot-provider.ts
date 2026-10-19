export const copilotCapabilities = {
  launchTasks: false,
  readTaskStatus: false,
  readTaskLogs: false,
  resumeTasks: false,
  updateRunningTasks: false,
} as const;

export type CopilotTaskRequest = {
  repository: string;
  prompt: string;
  baseBranch: string;
};

export class UnsupportedCopilotCapabilityError extends Error {
  readonly capability = 'copilot_task_execution';

  constructor() {
    super('GitHub REST API does not document a public endpoint to launch coding-agent tasks.');
    this.name = 'UnsupportedCopilotCapabilityError';
  }
}

export interface CopilotProvider {
  readonly capabilities: typeof copilotCapabilities;
  launchTask(request: CopilotTaskRequest): Promise<never>;
}

export class GitHubCopilotProvider implements CopilotProvider {
  readonly capabilities = copilotCapabilities;

  async launchTask(_request: CopilotTaskRequest): Promise<never> {
    throw new UnsupportedCopilotCapabilityError();
  }
}