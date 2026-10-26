import { z } from 'zod';

export const maxChangedFiles = 200;
export const maxFileBytes = 256 * 1024;
export const maxTotalBytes = 2 * 1024 * 1024;
export const maxRunEvents = 500;

// Paths are applied to a repository through the GitHub API, so they must stay inside the tree
// and must never touch Git metadata or workflows (a bot must not be able to change CI/automation).
export function unsafePathReason(path: string): string | null {
  if (path.length === 0 || path.length > 300) return 'invalid length';
  if (path.includes('\0') || path.includes('\\') || path.startsWith('/')) return 'invalid characters';
  const segments = path.split('/');
  if (segments.some((segment) => segment === '' || segment === '.' || segment === '..')) {
    return 'path traversal';
  }
  if (segments.some((segment) => segment.toLowerCase() === '.git')) return 'git metadata';
  if (path.toLowerCase().startsWith('.github/')) return 'GitHub automation files are not allowed';
  return null;
}

export const runChangeSchema = z.object({
  path: z.string().refine((path) => unsafePathReason(path) === null),
  status: z.enum(['added', 'modified', 'deleted']),
  executable: z.boolean().default(false),
  size: z.number().int().min(0).max(maxFileBytes),
  contentBase64: z.string().max(Math.ceil(maxFileBytes * 4 / 3) + 8).optional(),
}).strict().refine((change) => change.status === 'deleted' || change.contentBase64 !== undefined);

export const runChangesSchema = z.array(runChangeSchema).max(maxChangedFiles).refine(
  (changes) => new Set(changes.map((change) => change.path)).size === changes.length &&
    changes.reduce((total, change) => total + change.size, 0) <= maxTotalBytes,
);

export type RunChange = z.infer<typeof runChangeSchema>;

export const supportedStacks = ['node', 'python', 'static', 'go'] as const;
export type SupportedStack = (typeof supportedStacks)[number];

export function branchNameForRun(runId: string): string {
  return `ccc/run-${runId.slice(-10).toLowerCase()}`;
}
