import { prisma } from '../../src/db/prisma.ts';
import { decryptSecret } from '../../src/security/secrets.ts';
import { redactError } from './isolation.ts';
import { discoverAccountMetadata } from './metadata.ts';

let token = '';
let report: unknown;
let failure: unknown;
try {
  if (process.env.CCC_SDK_MODELS_READ_ONLY !== 'true') {
    throw new Error('Explicit authorization for read-only SDK model discovery is required.');
  }
  const accountId = process.env.CCC_SDK_MODELS_ACCOUNT_ID;
  const key = process.env.APP_ENCRYPTION_KEY;
  if (!accountId || !key) throw new Error('A connected account and encryption key are required.');
  const account = await prisma.gitHubAccount.findFirst({
    where: { id: accountId, status: 'ACTIVE' },
    select: { userId: true, encryptedAccessToken: true },
  });
  if (!account) throw new Error('The selected connected account is not active.');
  token = decryptSecret(account.encryptedAccessToken, key);
  const metadata = await discoverAccountMetadata(token);
  report = { ...metadata.catalog, quota: metadata.quota };
  await prisma.auditEvent.create({
    data: {
      userId: account.userId, action: 'SDK_MODELS_DISCOVERED', targetType: 'GitHubAccount', targetId: accountId,
      details: { readOnly: true, sessionsCreated: 0 },
    },
  });
} catch (error) {
  failure = error;
} finally {
  const errors: unknown[] = [];
  try { await prisma.$disconnect(); } catch (error) { errors.push(error); }
  if (errors.length) failure = new AggregateError([...(failure ? [failure] : []), ...errors], 'SDK model discovery cleanup failed.');
}
if (failure) {
  console.error(redactError(failure, token));
  process.exitCode = 1;
} else {
  console.log(JSON.stringify(report));
}
