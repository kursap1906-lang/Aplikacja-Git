import { z } from 'zod';
import type { PrismaClient } from '../generated/prisma/client.ts';
import { ApiError } from '../http/errors.ts';
import { decryptSecret } from '../security/secrets.ts';

const repositorySchema = z.object({
  id: z.number().int().positive(),
  full_name: z.string().regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/),
  default_branch: z.string().min(1),
  permissions: z.object({ push: z.boolean().optional() }).passthrough().optional(),
});

export type VerifiedRepository = {
  githubAccountId: string;
  repositoryId: string;
  repository: string;
  defaultBranch: string;
};

export async function verifyRepositoryAccess(input: {
  prisma: PrismaClient;
  userId: string;
  githubAccountId: string;
  repository: string;
  encryptionKey: string;
  fetcher: typeof fetch;
}): Promise<VerifiedRepository> {
  const account = await input.prisma.gitHubAccount.findFirst({
    where: { id: input.githubAccountId, userId: input.userId, status: 'ACTIVE' },
  });
  if (!account) {
    throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'Wybierz aktywne konto GitHub należące do Ciebie.');
  }
  if (account.tokenExpiresAt && account.tokenExpiresAt <= new Date()) {
    await input.prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
    throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Połącz ponownie konto GitHub.');
  }

  let response: Response;
  try {
    response = await input.fetcher(
      `https://api.github.com/repos/${input.repository.split('/').map(encodeURIComponent).join('/')}`,
      {
        headers: {
          accept: 'application/vnd.github+json',
          authorization: `Bearer ${decryptSecret(account.encryptedAccessToken, input.encryptionKey)}`,
          'x-github-api-version': '2022-11-28',
        },
        signal: AbortSignal.timeout(10000),
      },
    );
  } catch (error) {
    if (!(error instanceof TypeError) && !(error instanceof DOMException)) throw error;
    throw new ApiError(502, 'GITHUB_REPOSITORIES_UNAVAILABLE', 'Nie udało się połączyć z GitHub.');
  }
  if (response.status === 401) {
    await input.prisma.gitHubAccount.update({ where: { id: account.id }, data: { status: 'REAUTH_REQUIRED' } });
    throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Połącz ponownie konto GitHub.');
  }
  if (response.status === 429 || (response.status === 403 && response.headers.get('x-ratelimit-remaining') === '0')) {
    throw new ApiError(429, 'GITHUB_RATE_LIMITED', 'GitHub ograniczył liczbę żądań. Spróbuj później.');
  }
  if (response.status === 403) {
    throw new ApiError(403, 'GITHUB_REPOSITORY_FORBIDDEN', 'To konto nie ma uprawnień do repozytorium.');
  }
  if (response.status === 404) {
    throw new ApiError(404, 'GITHUB_REPOSITORY_NOT_FOUND', 'Nie znaleziono repozytorium lub konto nie ma do niego dostępu.');
  }
  if (!response.ok) {
    throw new ApiError(502, 'GITHUB_REPOSITORIES_UNAVAILABLE', 'GitHub nie potwierdził dostępu do repozytorium.');
  }
  let body: unknown;
  try {
    body = await response.json();
  } catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
    throw new ApiError(502, 'GITHUB_REPOSITORIES_INVALID', 'GitHub zwrócił nieprawidłowe dane repozytorium.');
  }
  const repository = repositorySchema.safeParse(body);
  if (!repository.success || repository.data.full_name.toLowerCase() !== input.repository.toLowerCase()) {
    throw new ApiError(400, 'GITHUB_REPOSITORY_MISMATCH', 'Wybierz repozytorium zweryfikowane przez GitHub.');
  }
  if (repository.data.permissions?.push !== true) {
    throw new ApiError(403, 'GITHUB_REPOSITORY_READ_ONLY', 'Wybrane konto GitHub musi mieć prawo zapisu.');
  }
  return {
    githubAccountId: account.id,
    repositoryId: String(repository.data.id),
    repository: repository.data.full_name,
    defaultBranch: repository.data.default_branch,
  };
}
