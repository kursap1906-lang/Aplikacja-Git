import { prisma } from '../../src/db/prisma.ts';
import { approvedRepository, parseProbeReport, readLimited } from './isolation.ts';

try {
  if (process.env.CCC_APPROVED_SMOKE_TEST !== approvedRepository) {
    throw new Error('Recording the SDK diagnostic requires administrative test authorization.');
  }
  const report = parseProbeReport(JSON.parse((await readLimited(process.stdin, 8192)).toString('utf8')));
  const accounts = await prisma.gitHubAccount.findMany({
    where: { login: 'kursap1906-lang', status: 'ACTIVE' },
    select: { id: true, userId: true },
  });
  if (accounts.length !== 1) throw new Error('The authorized test account is no longer unambiguous.');
  const [account] = accounts;
  await prisma.auditEvent.create({
    data: {
      userId: account.userId,
      action: 'SDK_SMOKE_TEST_COMPLETED',
      targetType: 'GitHubAccount',
      targetId: account.id,
      details: report,
    },
  });
  console.log('Verified SDK diagnostic saved in the account audit history.');
} finally {
  await prisma.$disconnect();
}
