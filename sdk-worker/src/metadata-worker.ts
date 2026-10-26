import { setTimeout as delay } from 'node:timers/promises';
import { writeFile } from 'node:fs/promises';
import { prisma } from '../../src/db/prisma.ts';
import { processMetadataJob } from './metadata-jobs.ts';

const key = process.env.APP_ENCRYPTION_KEY;
if (!key) throw new Error('SDK metadata worker requires the encryption key.');
const controller = new AbortController();
process.once('SIGTERM', () => controller.abort());
process.once('SIGINT', () => controller.abort());
const logError = (code: string, accountId?: string) => console.error(JSON.stringify({ code, accountId }));
try {
  while (!controller.signal.aborted) {
    try {
      await processMetadataJob({ prisma, encryptionKey: key, signal: controller.signal, logError });
      await writeFile('/tmp/ccc-sdk-metadata-heartbeat', new Date().toISOString(), { mode: 0o600 });
    } catch {
      logError('SDK_METADATA_STORAGE_ERROR');
    }
    try {
      await delay(2000, undefined, { signal: controller.signal });
    } catch (error) {
      if (!(error instanceof Error) || error.name !== 'AbortError') throw error;
    }
  }
} finally {
  await prisma.$disconnect();
}
