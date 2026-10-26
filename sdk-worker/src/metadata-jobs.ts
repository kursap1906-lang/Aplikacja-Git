import { randomUUID } from 'node:crypto';
import type { PrismaClient } from '../../src/generated/prisma/client.ts';
import { decryptSecret } from '../../src/security/secrets.ts';
import { discoverAccountMetadata } from './metadata.ts';
import { redactError } from './isolation.ts';

export async function processMetadataJob(options: {
  prisma: PrismaClient; encryptionKey: string; signal?: AbortSignal;
  discover?: typeof discoverAccountMetadata;
  logError: (code: string, accountId?: string) => void;
}): Promise<boolean> {
  const { prisma } = options;
  const now = new Date();
  const job = await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT 1 AS locked FROM pg_advisory_xact_lock(10626002030::bigint)`;
    await tx.sdkAccountMetadata.updateMany({
      where: { status: 'RUNNING', OR: [{ leaseExpiresAt: { lte: now } }, { leaseExpiresAt: null }] },
      data: {
        status: 'FAILED', leaseToken: null, leaseExpiresAt: null,
        errorCode: 'SDK_METADATA_INTERRUPTED', errorMessage: 'Przerwano odczyt kredytów. Odśwież je ponownie; nie uruchomiono bota.',
      },
    });
    if (await tx.sdkAccountMetadata.findFirst({ where: { status: 'RUNNING' }, select: { githubAccountId: true } })) return null;
    const next = await tx.sdkAccountMetadata.findFirst({ where: { status: 'QUEUED' }, orderBy: [{ requestedAt: 'asc' }, { githubAccountId: 'asc' }] });
    if (!next) return null;
    return tx.sdkAccountMetadata.update({
      where: { githubAccountId: next.githubAccountId },
      data: { status: 'RUNNING', leaseToken: randomUUID(), leaseExpiresAt: new Date(now.getTime() + 120_000) },
    });
  });
  if (!job) return false;
  let token = '';
  try {
    const account = await prisma.gitHubAccount.findUnique({ where: { id: job.githubAccountId } });
    if (!account || account.status !== 'ACTIVE' || (account.tokenExpiresAt && account.tokenExpiresAt <= new Date())) {
      throw new Error('Wybrane konto GitHub wymaga ponownej autoryzacji.');
    }
    token = decryptSecret(account.encryptedAccessToken, options.encryptionKey);
    const metadata = await (options.discover ?? discoverAccountMetadata)(token, options.signal);
    await prisma.$transaction(async (tx) => {
      const saved = await tx.sdkAccountMetadata.updateMany({
        where: { githubAccountId: job.githubAccountId, status: 'RUNNING', leaseToken: job.leaseToken, leaseExpiresAt: { gt: new Date() } },
        data: {
          status: 'READY', catalog: metadata.catalog, quota: metadata.quota, fetchedAt: new Date(),
          errorCode: null, errorMessage: null, leaseToken: null, leaseExpiresAt: null,
        },
      });
      if (saved.count !== 1) throw new Error('Utracono dzierżawę odczytu SDK.');
      await tx.auditEvent.create({
        data: {
          userId: account.userId, action: 'SDK_ACCOUNT_METADATA_REFRESHED', targetType: 'GitHubAccount', targetId: account.id,
          details: { readOnly: true, sessionsCreated: 0, model: 'auto' },
        },
      });
    });
  } catch (error) {
    options.logError('SDK_METADATA_FAILED', job.githubAccountId);
    const failed = await prisma.sdkAccountMetadata.updateMany({
      where: { githubAccountId: job.githubAccountId, status: 'RUNNING', leaseToken: job.leaseToken },
      data: {
        status: 'FAILED', leaseToken: null, leaseExpiresAt: null,
        errorCode: 'SDK_METADATA_FAILED', errorMessage: redactError(error, token).slice(0, 1600),
      },
    });
    if (failed.count !== 1) throw new Error('Cannot record SDK metadata failure: lease lost.');
  }
  return true;
}
