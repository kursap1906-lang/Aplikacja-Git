import 'dotenv/config';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { prisma } from '../db/prisma.ts';
import { parseConfig } from '../config.ts';
import { reserveAiAnalysis } from './budget.ts';
import { analysisModel } from './openai.ts';
import { diagnosticFingerprint, processNextAiAnalysis } from './worker.ts';

const config = parseConfig();
try {
  if (!config.OPENAI_ANALYSIS_ENABLED || !config.OPENAI_API_KEY ||
      process.env.AI_DIAGNOSTIC_CONFIRMATION !== 'synthetic-only-up-to-1-usd') {
    throw new Error('Enable OpenAI and explicitly confirm the synthetic-only diagnostic before queuing it.');
  }
  const userId = process.env.AI_DIAGNOSTIC_USER_ID;
  if (!userId || !await prisma.user.findUnique({ where: { id: userId }, select: { id: true } })) {
    throw new Error('Select an existing diagnostic owner with AI_DIAGNOSTIC_USER_ID.');
  }
  let job = await prisma.aiAnalysis.findFirst({
    where: { userId, kind: 'DIAGNOSTIC', model: analysisModel, inputFingerprint: diagnosticFingerprint() },
    orderBy: { createdAt: 'desc' },
  });
  if (!job) {
    job = await reserveAiAnalysis(prisma, {
      userId, kind: 'DIAGNOSTIC', projectId: null, teamId: null,
      requestKey: randomUUID(), inputFingerprint: diagnosticFingerprint(),
    });
  }
  if (process.env.AI_DIAGNOSTIC_RUN_ONCE === 'true' && job.status === 'QUEUED') {
    await processNextAiAnalysis({
      prisma, key: config.OPENAI_API_KEY,
      encryptionKey: () => {
        if (!config.APP_ENCRYPTION_KEY) throw new Error('No encryption key configured.');
        return config.APP_ENCRYPTION_KEY;
      },
      diagnosticId: job.id,
      logError: (code, analysisId) => console.error(JSON.stringify({ code, analysisId })),
    });
  }
  const deadline = Date.now() + 330_000;
  while (['QUEUED', 'RUNNING'].includes(job.status)) {
    if (Date.now() > deadline) throw new Error(`Diagnostic ${job.id} is still pending. No second request was queued.`);
    await delay(2000);
    job = await prisma.aiAnalysis.findUniqueOrThrow({ where: { id: job.id } });
  }
  console.log(JSON.stringify({
    id: job.id, status: job.status, model: job.model, providerResponseId: job.providerResponseId,
    inputTokens: job.inputTokens, cachedTokens: job.cachedTokens, outputTokens: job.outputTokens,
    estimatedCostMicros: job.estimatedCostMicros,
    reservationHeldMicros: job.status === 'UNKNOWN' ? job.reservedCostMicros : 0,
    result: job.result, errorCode: job.errorCode, errorMessage: job.errorMessage,
  }));
  if (job.status !== 'COMPLETED') process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
