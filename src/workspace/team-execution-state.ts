import { z } from 'zod';
import { ApiError } from '../http/errors.ts';
import type { Prisma } from '../generated/prisma/client.ts';

export async function assertTeamNotCoordinated(tx: Prisma.TransactionClient, teamId: string | null | undefined) {
  if (teamId && await tx.teamExecution.count({ where: { teamId, state: { notIn: ['STOPPED', 'RELEASED'] } } })) {
    throw new ApiError(409, 'TASK_CONTROLLED_BY_TEAM', 'Plan i status zadania prowadzi lider. Zatrzymaj koordynację przed ręczną zmianą zadań.');
  }
}

export const shaSchema = z.string().regex(/^[a-f0-9]{40}$/);
export const previewWorkflow = '.github/workflows/ccc-preview.yml';
export const previewEnvironment = 'ccc-preview';
export const roadmapSchema = z.array(z.object({
  id: z.string().regex(/^[a-z][a-z0-9-]{0,49}$/),
  title: z.string().trim().min(1).max(200),
  description: z.string().max(10000).default(''),
  dueDate: z.string().date().nullable().default(null),
  fields: z.record(z.string().min(1).max(80), z.string().max(2000)).refine(value => Object.keys(value).length <= 20).default({}),
  status: z.enum(['PLANNED', 'APPROVED']).default('PLANNED'),
})).max(100).refine(items => new Set(items.map(item => item.id)).size === items.length, 'Unique milestone IDs required.');
export const planTaskSchema = z.object({
  key: z.string().regex(/^[a-z][a-z0-9-]{0,49}$/),
  botId: z.string().min(1), title: z.string().trim().min(1).max(200),
  description: z.string().trim().min(50).max(5000),
  dependsOn: z.array(z.string()).max(100),
  approval: z.enum(['leader', 'owner']),
}).strict();
export const leaderPlanSchema = z.object({
  requestId: z.uuid(),
  summary: z.string().min(1).max(5000),
  tasks: z.array(planTaskSchema).min(1).max(100),
}).strict().superRefine((plan, context) => {
  const seen = new Set<string>();
  for (const [index, task] of plan.tasks.entries()) {
    if (seen.has(task.key) || new Set(task.dependsOn).size !== task.dependsOn.length ||
      task.dependsOn.some(key => !seen.has(key))) {
      context.addIssue({ code: 'custom', path: ['tasks', index], message: 'Unique keys and dependencies on earlier tasks are required.' });
    }
    seen.add(task.key);
  }
});
const itemSchema = planTaskSchema.extend({
  taskId: z.string(), state: z.enum(['PENDING', 'SUBMITTING', 'RUNNING', 'REVIEWING', 'OWNER_REVIEW', 'MERGING', 'COMPLETED']),
  branch: z.string(), taskIdExternal: z.string().optional(), reviewTaskId: z.string().optional(),
  pullNumber: z.number().int().positive().optional(), headSha: shaSchema.optional(),
  reviewDecision: z.enum(['approve', 'owner']).optional(), reviewReason: z.string().optional(),
});
export const executionDataSchema = z.object({
  repository: z.string(), accountId: z.string(), baseBranch: z.string(), baseSha: shaSchema,
  testBranch: z.string(), leaderBotId: z.string(), leaderBranch: z.string(),
  phase: z.enum(['START', 'PLANNING_SUBMITTING', 'PLANNING', 'WORK', 'PREVIEW_SUBMITTING', 'PREVIEW', 'READY', 'RELEASING', 'ERROR', 'STOPPED', 'RELEASED']),
  leaderTaskId: z.string().optional(), planSummary: z.string().optional(),
  planRequestId: z.uuid().optional(),
  milestoneId: z.string().optional(), milestoneTitle: z.string().optional(),
  milestoneApproved: z.boolean().default(false),
  milestonePull: z.number().int().positive().optional(),
  milestoneSha: shaSchema.optional(),
  items: z.array(itemSchema).max(100),
  preview: z.object({
    branch: z.string().optional(),
    sha: shaSchema, baseSha: shaSchema, requestedAt: z.string(), runId: z.number().optional(),
    url: z.string().optional(), buildUrl: z.string().optional(), success: z.boolean().default(false),
  }).optional(),
  releasePull: z.number().optional(), error: z.string().optional(),
  uncertain: z.boolean().default(false),
  resumePhase: z.enum(['START', 'PLANNING', 'WORK', 'PREVIEW', 'READY']).optional(),
  events: z.array(z.object({ at: z.string(), message: z.string() })).max(200),
});
export type ExecutionData = z.infer<typeof executionDataSchema>;
export type ExecutionItem = ExecutionData['items'][number];

export function nextExecutionItem(items: ExecutionData['items']) {
  const completed = new Set(items.filter(item => item.state === 'COMPLETED').map(item => item.key));
  return items.find(item => item.state !== 'COMPLETED' &&
    item.dependsOn.every(key => completed.has(key)));
}

export function validateLeaderAssignments(plan: z.infer<typeof leaderPlanSchema>, botIds: string[]) {
  if (plan.tasks.some(task => !botIds.includes(task.botId))) {
    throw new ApiError(409, 'LEADER_INVALID_ASSIGNEE', 'Lider przypisał zadanie poza zespołem.');
  }
  if (!plan.tasks.some(task => /ccc-preview|kompil|build|preview/i.test(`${task.title} ${task.description}`))) {
    throw new ApiError(409, 'LEADER_BUILD_TASK_REQUIRED', 'Plan lidera musi zawierać konfigurację kompilacji, testów i działającego podglądu.');
  }
}

export function assertReleaseReady(data: ExecutionData, headSha: string, baseSha: string) {
  if (data.phase !== 'READY' || !data.preview?.success || !data.preview.url ||
    data.preview.sha !== headSha || data.preview.baseSha !== baseSha ||
    data.items.some(item => item.state !== 'COMPLETED')) {
    throw new ApiError(409, 'RELEASE_REQUIRES_CURRENT_PREVIEW', 'Najpierw ukończ zadania i zbuduj działający podgląd aktualnego SHA. Zmiana gałęzi testowej lub main wymaga ponownego zintegrowania i testu.');
  }
}

export function publicPreviewUrl(value: string) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || !url.hostname.includes('.') ||
    /^(localhost|127\.|10\.|192\.168\.|169\.254\.|0\.|172\.(1[6-9]|2\d|3[01])\.)/.test(url.hostname)) {
    throw new ApiError(409, 'PREVIEW_URL_INVALID', 'Workflow nie opublikował publicznego adresu HTTPS.');
  }
  return url.toString();
}
