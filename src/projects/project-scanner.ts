import { z } from 'zod';

const githubHeaders = (accessToken: string): HeadersInit => ({
  accept: 'application/vnd.github+json',
  authorization: `Bearer ${accessToken}`,
  'x-github-api-version': '2022-11-28',
});

const repositorySchema = z.object({
  full_name: z.string().min(1),
  default_branch: z.string().min(1),
  open_issues_count: z.number().int().nonnegative(),
});

const commitListSchema = z.array(z.object({
  sha: z.string().regex(/^[a-f0-9]{40}$/i),
})).min(1);

const treeSchema = z.object({
  truncated: z.boolean(),
  tree: z.array(z.object({
    path: z.string(),
    type: z.enum(['blob', 'tree', 'commit']),
    size: z.number().int().nonnegative().optional(),
  })),
});

const contentSchema = z.object({
  type: z.literal('file'),
  encoding: z.literal('base64'),
  content: z.string(),
  size: z.number().int().nonnegative(),
});

const progressPaths = new Set([
  'TASKS.md',
  'PROJECT_STATUS.md',
  'docs/TASKS.md',
  'docs/PROJECT_STATUS.md',
  'docs/STATUS.md',
]);
const MAX_PROGRESS_FILE_BYTES = 64 * 1024;
const MAX_PROGRESS_FILES = 5;
const MAX_GITHUB_RESPONSE_BYTES = 16 * 1024 * 1024;

export type ProjectProgressStage = 'DISCOVERY' | 'PLANNING' | 'IMPLEMENTATION' | 'BLOCKED' | 'VALIDATION';

export type ProjectScanResult = {
  repository: string;
  branch: string;
  commitSha: string;
  lifecycleStage: ProjectProgressStage;
  filesScanned: number;
  sourceFiles: number;
  testFiles: number;
  openItems: number;
  taskCounts: { done: number; inProgress: number; blocked: number; todo: number };
  technologies: string[];
  evidenceFiles: string[];
  treeTruncated: boolean;
  summary: string;
};

export class ProjectScannerError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(statusCode: number, code: string) {
    super('GitHub repository scan failed.');
    this.name = 'ProjectScannerError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

async function getJson(
  fetcher: typeof fetch,
  url: string,
  accessToken: string,
): Promise<unknown> {
  let response: Response;
  try {
    response = await fetcher(url, {
      headers: githubHeaders(accessToken),
      signal: AbortSignal.timeout(15000),
    });
  } catch (error) {
    if (error instanceof TypeError || (error instanceof DOMException && error.name === 'TimeoutError')) {
      throw new ProjectScannerError(502, 'GITHUB_SCAN_UNAVAILABLE');
    }
    throw error;
  }
  if (!response.ok) {
    throw new ProjectScannerError(response.status, `GITHUB_SCAN_HTTP_${response.status}`);
  }
  const contentLength = Number(response.headers.get('content-length'));
  if (Number.isFinite(contentLength) && contentLength > MAX_GITHUB_RESPONSE_BYTES) {
    throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_TOO_LARGE');
  }

  const reader = response.body?.getReader();
  if (!reader) throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_INVALID');
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const result = await reader.read();
    if (result.done) break;
    size += result.value.byteLength;
    if (size > MAX_GITHUB_RESPONSE_BYTES) {
      await reader.cancel();
      throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_TOO_LARGE');
    }
    chunks.push(result.value);
  }

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_INVALID');
    }
    throw error;
  }
}

function classifyStage(
  counts: ProjectScanResult['taskCounts'],
  hasProgressDocument: boolean,
): ProjectProgressStage {
  if (counts.blocked > 0) return 'BLOCKED';
  if (counts.inProgress > 0) return 'IMPLEMENTATION';
  if (counts.todo > 0 && counts.done === 0) return 'PLANNING';
  if (hasProgressDocument && counts.todo === 0 && counts.inProgress === 0 && counts.done > 0) {
    return 'VALIDATION';
  }
  if (counts.done > 0) return 'IMPLEMENTATION';
  return 'DISCOVERY';
}

function countTaskMarkers(contents: string[]): ProjectScanResult['taskCounts'] {
  const counts = { done: 0, inProgress: 0, blocked: 0, todo: 0 };
  for (const content of contents) {
    for (const match of content.matchAll(/\[(DONE|IN_PROGRESS|BLOCKED|TODO)\]/gi)) {
      switch (match[1].toUpperCase()) {
        case 'DONE':
          counts.done += 1;
          break;
        case 'IN_PROGRESS':
          counts.inProgress += 1;
          break;
        case 'BLOCKED':
          counts.blocked += 1;
          break;
        case 'TODO':
          counts.todo += 1;
          break;
      }
    }
  }
  return counts;
}

export async function scanGitHubProject(
  options: {
    repository: string;
    accessToken: string;
    fetcher?: typeof fetch;
  },
): Promise<ProjectScanResult> {
  const fetcher = options.fetcher ?? fetch;
  const repositoryPath = options.repository.split('/').map(encodeURIComponent).join('/');
  const apiUrl = `https://api.github.com/repos/${repositoryPath}`;
  const metadata = repositorySchema.safeParse(
    await getJson(fetcher, apiUrl, options.accessToken),
  );
  if (!metadata.success || metadata.data.full_name.toLowerCase() !== options.repository.toLowerCase()) {
    throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_INVALID');
  }

  const commits = commitListSchema.safeParse(
    await getJson(fetcher, `${apiUrl}/commits?per_page=1`, options.accessToken),
  );
  if (!commits.success) throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_INVALID');
  const commitSha = commits.data[0].sha;

  const tree = treeSchema.safeParse(
    await getJson(fetcher, `${apiUrl}/git/trees/${commitSha}?recursive=1`, options.accessToken),
  );
  if (!tree.success) throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_INVALID');

  const blobs = tree.data.tree.filter((item) => item.type === 'blob');
  const paths = blobs.map((item) => item.path);
  const sourceFiles = paths.filter((path) =>
    /\.(?:c|cc|cpp|cs|dart|go|h|java|js|jsx|kt|php|py|rb|rs|sh|swift|ts|tsx|vue|svelte)$/i.test(path),
  ).length;
  const testFiles = paths.filter((path) =>
    /(?:^|\/)(?:test|tests|__tests__|spec)(?:\/|$)|(?:^|[._-])(?:test|spec)\.[^.]+$/i.test(path),
  ).length;
  const technologyRules: Array<[string, RegExp]> = [
    ['Node.js', /(^|\/)(?:package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$/i],
    ['Flutter/Dart', /(^|\/)(?:pubspec\.yaml|analysis_options\.yaml)$/i],
    ['Python', /(^|\/)(?:pyproject\.toml|requirements\.txt|Pipfile)$/i],
    ['Rust', /(^|\/)Cargo\.toml$/i],
    ['Go', /(^|\/)go\.mod$/i],
    ['Java/Kotlin', /(^|\/)(?:pom\.xml|build\.gradle(?:\.kts)?)$/i],
    ['.NET', /\.(?:csproj|sln)$/i],
  ];
  const technologies = technologyRules
    .filter(([, pattern]) => paths.some((path) => pattern.test(path)))
    .map(([name]) => name);

  const progressFiles = blobs
    .filter((item) => progressPaths.has(item.path) && (item.size ?? MAX_PROGRESS_FILE_BYTES + 1) <= MAX_PROGRESS_FILE_BYTES)
    .slice(0, MAX_PROGRESS_FILES);
  const progressContents = await Promise.all(progressFiles.map(async (file) => {
    const encodedPath = file.path.split('/').map(encodeURIComponent).join('/');
    const response = await getJson(
      fetcher,
      `${apiUrl}/contents/${encodedPath}?ref=${commitSha}`,
      options.accessToken,
    );
    const content = contentSchema.safeParse(response);
    if (!content.success || content.data.size > MAX_PROGRESS_FILE_BYTES) {
      throw new ProjectScannerError(502, 'GITHUB_SCAN_RESPONSE_INVALID');
    }
    return { path: file.path, text: Buffer.from(content.data.content.replace(/\s/g, ''), 'base64').toString('utf8') };
  }));
  const taskDocument = progressContents.find((file) => /(^|\/)TASKS\.md$/i.test(file.path));
  const taskCounts = countTaskMarkers(taskDocument ? [taskDocument.text] : progressContents.map((file) => file.text));
  const lifecycleStage = classifyStage(taskCounts, progressContents.length > 0);
  const evidenceFiles = progressContents.map((file) => file.path);
  const summary = [
    `Repozytorium ${metadata.data.full_name}, gałąź ${metadata.data.default_branch}, commit ${commitSha}.`,
    `Etap oszacowany na podstawie markerów postępu: ${lifecycleStage}.`,
    `Struktura: ${sourceFiles} plików źródłowych, ${testFiles} plików testowych.`,
    `Zadania: ${taskCounts.done} ukończone, ${taskCounts.inProgress} w toku, ${taskCounts.blocked} zablokowane, ${taskCounts.todo} do zrobienia.`,
    `Otwarte elementy zgłoszone przez GitHub: ${metadata.data.open_issues_count}.`,
    `Dokumenty postępu: ${evidenceFiles.length ? evidenceFiles.join(', ') : 'nie znaleziono'}.`,
    ...(tree.data.truncated ? ['Drzewo GitHub jest niepełne (limit odpowiedzi).'] : []),
  ].join(' ');

  return {
    repository: metadata.data.full_name,
    branch: metadata.data.default_branch,
    commitSha,
    lifecycleStage,
    filesScanned: blobs.length,
    sourceFiles,
    testFiles,
    openItems: metadata.data.open_issues_count,
    taskCounts,
    technologies,
    evidenceFiles,
    treeTruncated: tree.data.truncated,
    summary,
  };
}
