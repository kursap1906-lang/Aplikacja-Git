import { spawn } from 'node:child_process';

export const approvedRepository = 'kursap1906-lang/test';
export const sandboxImage = 'node:24-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205';

export function sandboxCreateArguments(name: string): string[] {
  if (!/^ccc-sdk-smoke-[a-f0-9-]{36}$/.test(name)) {
    throw new Error('Invalid sandbox name.');
  }
  return [
    'create', '--name', name,
    '--network', 'none',
    '--read-only',
    '--tmpfs', '/workspace:rw,nosuid,nodev,size=128m,uid=1000,gid=1000,mode=0700',
    '--tmpfs', '/tmp:rw,nosuid,nodev,noexec,size=32m,uid=1000,gid=1000,mode=0700',
    '--user', '1000:1000',
    '--workdir', '/workspace',
    '--cap-drop', 'ALL',
    '--security-opt', 'no-new-privileges:true',
    '--memory', '512m', '--memory-swap', '512m',
    '--cpus', '1', '--pids-limit', '64', '--init',
    sandboxImage, 'node', '-e', 'setInterval(() => {}, 1000)',
  ];
}

export async function docker(
  args: readonly string[],
  input?: Uint8Array,
  timeout = 60_000,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn('sudo', ['-n', 'docker', ...args], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { PATH: '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' },
    });
    const output: Buffer[] = [];
    const errors: Buffer[] = [];
    let size = 0;
    let failure: Error | undefined;
    const timer = setTimeout(() => {
      failure = new Error('Docker operation timed out.');
      child.kill('SIGKILL');
    }, timeout);
    const collect = (target: Buffer[], chunk: Buffer) => {
      size += chunk.length;
      if (size > 1024 * 1024) {
        failure = new Error('Docker output exceeded the 1 MB safety limit.');
        child.kill('SIGKILL');
      } else {
        target.push(chunk);
      }
    };
    child.stdout.on('data', (chunk: Buffer) => collect(output, chunk));
    child.stderr.on('data', (chunk: Buffer) => collect(errors, chunk));
    child.stdin.on('error', (error: Error) => { failure ??= error; });
    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (failure) return reject(failure);
      if (code !== 0) {
        return reject(new Error(`Docker exited ${code}: ${Buffer.concat(errors).toString('utf8')}`));
      }
      resolve(Buffer.concat(output).toString('utf8').trim());
    });
    child.stdin.end(input);
  });
}

export async function readLimited(
  stream: AsyncIterable<Uint8Array>,
  limit: number,
): Promise<Buffer> {
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of stream) {
    size += chunk.length;
    if (size > limit) throw new Error(`Input exceeded the ${limit} byte safety limit.`);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export function parseProbeInput(value: unknown): { token: string } {
  if (
    typeof value !== 'object' || value === null ||
    !('repository' in value) || value.repository !== approvedRepository ||
    !('token' in value) || typeof value.token !== 'string' ||
    value.token.length < 20 || value.token.length > 1024 ||
    /[\r\n]/.test(value.token)
  ) {
    throw new Error('An explicit token for the approved test repository is required on stdin.');
  }
  return { token: value.token };
}

export function parseProbeArguments(value: unknown): { message: string } {
  if (
    typeof value !== 'object' || value === null ||
    !('message' in value) || value.message !== 'CCC SDK smoke' ||
    Object.keys(value).some((key) => key !== 'message')
  ) {
    throw new Error('The probe accepts only the approved diagnostic message.');
  }
  return { message: value.message };
}

export function redactError(error: unknown, token: string): string {
  const message = error instanceof Error ? error.message : 'Unknown SDK test error.';
  return (token ? message.replaceAll(token, '[REDACTED]') : message)
    .replace(/\b(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]+\b/g, '[REDACTED]')
    .replace(/\bBearer\s+[A-Za-z0-9._~-]+/gi, 'Bearer [REDACTED]');
}

export function parseProbeReport(value: unknown) {
  if (
    typeof value !== 'object' || value === null ||
    !('repository' in value) || value.repository !== approvedRepository ||
    !('passed' in value) || value.passed !== true ||
    !('pushed' in value) || value.pushed !== false ||
    !('sdkVersion' in value) || value.sdkVersion !== '1.0.26' ||
    !('toolInvocations' in value) || value.toolInvocations !== 1 ||
    !('runId' in value) || typeof value.runId !== 'string' || !/^[a-f0-9-]{36}$/.test(value.runId) ||
    !('sessionId' in value) || typeof value.sessionId !== 'string' || !/^[a-f0-9-]{36}$/.test(value.sessionId) ||
    !('commitSha' in value) || typeof value.commitSha !== 'string' || !/^[a-f0-9]{40}$/.test(value.commitSha) ||
    !('probeHash' in value) || typeof value.probeHash !== 'string' || !/^[a-f0-9]{64}$/.test(value.probeHash)
  ) {
    throw new Error('Invalid SDK diagnostic report; success cannot be recorded.');
  }
  return {
    repository: value.repository, passed: value.passed, pushed: value.pushed,
    sdkVersion: value.sdkVersion, toolInvocations: value.toolInvocations,
    runId: value.runId, sessionId: value.sessionId,
    commitSha: value.commitSha, probeHash: value.probeHash,
  };
}
