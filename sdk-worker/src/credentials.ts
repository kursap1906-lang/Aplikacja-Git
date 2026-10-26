import { prisma } from '../../src/db/prisma.ts';
import { verifyRepositoryAccess } from '../../src/github/repository-access.ts';
import { decryptSecret } from '../../src/security/secrets.ts';
import { approvedRepository } from './isolation.ts';

try {
  if (process.env.CCC_APPROVED_SMOKE_TEST !== approvedRepository) {
    throw new Error('This administrative probe requires explicit authorization for the test repository.');
  }
  const accounts = await prisma.gitHubAccount.findMany({
    where: { login: 'kursap1906-lang', status: 'ACTIVE' },
    select: { id: true, userId: true, encryptedAccessToken: true },
  });
  if (accounts.length !== 1) {
    throw new Error('Exactly one connected test-repository owner is required; do not guess a tenant.');
  }
  const [account] = accounts;
  const key = process.env.APP_ENCRYPTION_KEY;
  if (!key) throw new Error('The configured encryption key is required.');
  await verifyRepositoryAccess({
    prisma,
    userId: account.userId,
    githubAccountId: account.id,
    repository: approvedRepository,
    encryptionKey: key,
    fetcher: fetch,
  });
  await prisma.auditEvent.create({
    data: {
      userId: account.userId,
      action: 'SDK_SMOKE_TEST_REQUESTED',
      targetType: 'GitHubAccount',
      targetId: account.id,
      details: { repository: approvedRepository, administrativeTest: true, pushAllowed: false },
    },
  });
  process.stdout.write(JSON.stringify({
    repository: approvedRepository,
    token: decryptSecret(account.encryptedAccessToken, key),
  }));
} finally {
  await prisma.$disconnect();
}
