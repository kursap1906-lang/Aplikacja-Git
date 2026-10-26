import assert from 'node:assert/strict';
import test from 'node:test';
import { ProjectScannerError, scanGitHubProject } from './project-scanner.ts';

const commitSha = 'a'.repeat(40);
const progress = Buffer.from([
  '- [DONE] Login and session',
  '- [IN_PROGRESS] Project scan',
  '- [BLOCKED] Preview deployment',
  '- [TODO] Cost reports',
].join('\n')).toString('base64');

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status });
}

test('scans repository inventory and derives progress stage from pinned task evidence', async () => {
  const requested: string[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    const url = String(input);
    requested.push(url);
    assert.equal(new Headers(init?.headers).get('authorization'), 'Bearer scan-token');
    if (url.endsWith('/repos/owner/repo')) {
      return response({ full_name: 'owner/repo', default_branch: 'main', open_issues_count: 4 });
    }
    if (url.endsWith('/commits?per_page=1')) return response([{ sha: commitSha }]);
    if (url.endsWith(`/git/trees/${commitSha}?recursive=1`)) {
      return response({
        truncated: false,
        tree: [
          { path: 'TASKS.md', type: 'blob', size: 90 },
          { path: 'package.json', type: 'blob', size: 10 },
          { path: 'src/main.ts', type: 'blob', size: 20 },
          { path: 'src/main.test.ts', type: 'blob', size: 20 },
          { path: 'mobile/pubspec.yaml', type: 'blob', size: 15 },
          { path: 'src', type: 'tree' },
        ],
      });
    }
    if (url.endsWith(`/contents/TASKS.md?ref=${commitSha}`)) {
      return response({ type: 'file', encoding: 'base64', content: progress, size: 90 });
    }
    throw new Error(`Unexpected GitHub API request: ${url}`);
  };

  const result = await scanGitHubProject({
    repository: 'owner/repo',
    accessToken: 'scan-token',
    fetcher,
  });

  assert.equal(result.repository, 'owner/repo');
  assert.equal(result.branch, 'main');
  assert.equal(result.commitSha, commitSha);
  assert.equal(result.lifecycleStage, 'BLOCKED');
  assert.equal(result.filesScanned, 5);
  assert.equal(result.sourceFiles, 2);
  assert.equal(result.testFiles, 1);
  assert.equal(result.openItems, 4);
  assert.deepEqual(result.taskCounts, { done: 1, inProgress: 1, blocked: 1, todo: 1 });
  assert.deepEqual(result.technologies, ['Node.js', 'Flutter/Dart']);
  assert.deepEqual(result.evidenceFiles, ['TASKS.md']);
  assert.match(result.summary, /Etap oszacowany.*BLOCKED/);
  assert.equal(requested.length, 4);
});

test('does not claim a lifecycle stage when the repository has no progress evidence', async () => {
  const fetcher: typeof fetch = async (input) => {
    const url = String(input);
    if (url.endsWith('/repos/owner/repo')) {
      return response({ full_name: 'owner/repo', default_branch: 'main', open_issues_count: 0 });
    }
    if (url.endsWith('/commits?per_page=1')) return response([{ sha: commitSha }]);
    return response({ truncated: false, tree: [{ path: 'src/main.ts', type: 'blob', size: 20 }] });
  };

  const result = await scanGitHubProject({ repository: 'owner/repo', accessToken: 'token', fetcher });

  assert.equal(result.lifecycleStage, 'DISCOVERY');
  assert.deepEqual(result.taskCounts, { done: 0, inProgress: 0, blocked: 0, todo: 0 });
  assert.deepEqual(result.evidenceFiles, []);
});

test('surfaces GitHub access failures instead of returning an empty scan', async () => {
  const fetcher: typeof fetch = async () => response({ message: 'Forbidden' }, 403);
  await assert.rejects(
    scanGitHubProject({ repository: 'owner/repo', accessToken: 'token', fetcher }),
    (error: unknown) => error instanceof ProjectScannerError && error.statusCode === 403,
  );
});

test('surfaces transport failures instead of returning an empty scan', async () => {
  const fetcher: typeof fetch = async () => {
    throw new TypeError('network unavailable');
  };
  await assert.rejects(
    scanGitHubProject({ repository: 'owner/repo', accessToken: 'token', fetcher }),
    (error: unknown) =>
      error instanceof ProjectScannerError && error.code === 'GITHUB_SCAN_UNAVAILABLE',
  );
});
