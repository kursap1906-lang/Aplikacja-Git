import { z } from 'zod';

export const copilotCapabilities = {
  launchTasks: true,
  readTaskStatus: true,
  readTaskLogs: false,
  resumeTasks: false,
  updateRunningTasks: false,
} as const;

const taskStateSchema = z.enum([
  'queued',
  'in_progress',
  'completed',
  'failed',
  'idle',
  'waiting_for_user',
  'timed_out',
  'cancelled',
]);

const taskSchema = z.object({
  id: z.string().min(1),
  state: taskStateSchema,
  url: z.url().optional(),
  html_url: z.url().optional(),
  name: z.string().optional(),
  created_at: z.iso.datetime().optional(),
  updated_at: z.iso.datetime().optional(),
  sessions: z.array(z.object({
    id: z.string(), state: taskStateSchema, prompt: z.string().optional(),
    head_ref: z.string().optional(), base_ref: z.string().optional(), model: z.string().optional(),
    created_at: z.string(), updated_at: z.string().optional(),
    usage: z.object({ type: z.enum(['ai_credits', 'premium_requests']), amount: z.number() }).optional(),
    error: z.object({ message: z.string().optional() }).optional(),
  })).optional(),
  artifacts: z.array(z.object({
    provider: z.literal('github'), type: z.enum(['pull', 'branch']),
    data: z.object({
      id: z.number().int().positive().optional(),
      head_ref: z.string().optional(), base_ref: z.string().optional(),
    }),
  })).optional(),
});

export type CopilotTaskState = z.infer<typeof taskStateSchema>;

export type CopilotTaskRequest = {
  accessToken: string;
  repository: string;
  prompt: string;
  baseBranch: string;
  headBranch?: string;
};

export type CopilotTask = z.infer<typeof taskSchema>;

export class GitHubCopilotApiError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(statusCode: number, code: string) {
    super('GitHub Copilot Agent Tasks API request failed.');
    this.name = 'GitHubCopilotApiError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export interface CopilotProvider {
  readonly capabilities: typeof copilotCapabilities;
  launchTask(request: CopilotTaskRequest): Promise<CopilotTask>;
  getTask(request: Pick<CopilotTaskRequest, 'accessToken' | 'repository'> & { taskId: string }): Promise<CopilotTask>;
}

function repositoryPath(repository: string): string {
  const parts = repository.split('/');
  if (parts.length !== 2 || parts.some((part) => !/^[A-Za-z0-9_.-]+$/.test(part))) {
    throw new TypeError('Repository must be in owner/repository format.');
  }

  return parts.map(encodeURIComponent).join('/');
}

export class GitHubCopilotProvider implements CopilotProvider {
  readonly capabilities = copilotCapabilities;
  private readonly fetcher: typeof fetch;

  constructor(fetcher: typeof fetch = fetch) {
    this.fetcher = fetcher;
  }

  async launchTask(request: CopilotTaskRequest): Promise<CopilotTask> {
    const response = await this.fetcher(
      `https://api.github.com/agents/repos/${repositoryPath(request.repository)}/tasks`,
      {
        method: 'POST',
        headers: this.headers(request.accessToken),
        body: JSON.stringify({
          prompt: request.prompt,
          base_ref: request.baseBranch,
          ...(request.headBranch ? { head_ref: request.headBranch } : {}),
          create_pull_request: true,
        }),
        signal: AbortSignal.timeout(20000),
      },
    );

    return this.readTask(response, 201);
  }

  async getTask(
    request: Pick<CopilotTaskRequest, 'accessToken' | 'repository'> & { taskId: string },
  ): Promise<CopilotTask> {
    if (!/^[A-Za-z0-9_-]+$/.test(request.taskId)) {
      throw new TypeError('Task ID contains unsupported characters.');
    }

    const response = await this.fetcher(
      `https://api.github.com/agents/repos/${repositoryPath(request.repository)}/tasks/${encodeURIComponent(request.taskId)}`,
      {
        headers: this.headers(request.accessToken),
        signal: AbortSignal.timeout(15000),
      },
    );

    return this.readTask(response, 200);
  }

  private headers(accessToken: string): HeadersInit {
    if (!accessToken) {
      throw new TypeError('A GitHub user access token is required.');
    }

    return {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
      'x-github-api-version': '2026-03-10',
    };
  }

  private async readTask(response: Response, expectedStatus: number): Promise<CopilotTask> {
    if (response.status !== expectedStatus) {
      throw new GitHubCopilotApiError(response.status, `GITHUB_AGENT_TASK_HTTP_${response.status}`);
    }

    const task = taskSchema.safeParse(await response.json());
    if (!task.success) {
      throw new GitHubCopilotApiError(response.status, 'GITHUB_AGENT_TASK_RESPONSE_INVALID');
    }

    return task.data;
  }
}
