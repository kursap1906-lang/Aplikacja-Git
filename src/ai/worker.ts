import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { AiAnalysis, Prisma, PrismaClient } from '../generated/prisma/client.ts';
import { ApiError } from '../http/errors.ts';
import { claimAiAnalysis, markAiGenerationStarted, settleAiAnalysis } from './budget.ts';
import {
  buildAnalysisRequest, countAnalysisInput, generateAnalysis, OpenAiRequestError,
  parseAnalysisResult, parseAnalysisUsage, type AnalysisRequest, type AnalysisUsage,
} from './openai.ts';
import { applyTeamPlan, loadTeamAnalysisSource, prepareTeamAnalysis } from './team-analysis.ts';

const diagnosticSchema = z.object({
  summary: z.string().min(1).max(1000),
  steps: z.array(z.string().min(1).max(500)).min(2).max(4),
}).strict();

export function diagnosticRequest(): AnalysisRequest {
  return buildAnalysisRequest({
    name: 'synthetic_diagnostic',
    instructions: 'Zwróć krótki plan po polsku zgodny ze schematem. To wyłącznie syntetyczny test protokołu analizy, nie test gotowości całej aplikacji.',
    input: [{ type: 'input_text', text: 'Syntetyczny przykład: zaplanuj prostą listę zakupów, w której można dodać produkt i oznaczyć go jako kupiony. Podaj 2–4 kroki, uwzględniając testy.' }],
    schema: {
      type: 'object', additionalProperties: false, required: ['summary', 'steps'],
      properties: {
        summary: { type: 'string', minLength: 1, maxLength: 1000 },
        steps: { type: 'array', minItems: 2, maxItems: 4, items: { type: 'string', minLength: 1, maxLength: 500 } },
      },
    },
  });
}

export function diagnosticFingerprint(): string {
  return createHash('sha256').update(JSON.stringify(diagnosticRequest())).digest('hex');
}

type Operation = {
  request: AnalysisRequest;
  verifySource: () => Promise<void>;
  apply: (raw: unknown, tx: Prisma.TransactionClient) => Promise<Prisma.InputJsonValue>;
};

async function prepareOperation(prisma: PrismaClient, job: AiAnalysis, encryptionKey: () => string): Promise<Operation> {
  if (job.kind === 'DIAGNOSTIC') {
    if (job.inputFingerprint !== diagnosticFingerprint()) throw new ApiError(409, 'AI_SOURCE_CHANGED', 'Zmieniono wersję syntetycznego testu.');
    return {
      request: diagnosticRequest(),
      verifySource: async () => {},
      apply: async (raw) => parseAnalysisResult(raw, diagnosticSchema),
    };
  }
  if (job.kind !== 'TEAM_TASKS' || !job.teamId) throw new ApiError(409, 'AI_KIND_UNAVAILABLE', 'Ten rodzaj analizy nie jest jeszcze dostępny.');
  const teamId = job.teamId;
  const load = () => prisma.$transaction(
    (tx) => loadTeamAnalysisSource(tx, job.userId, teamId), { isolationLevel: 'RepeatableRead' },
  );
  const source = await load();
  if (source.fingerprint !== job.inputFingerprint || source.team.project?.id !== job.projectId) {
    throw new ApiError(409, 'AI_SOURCE_CHANGED', 'Materiały zmieniły się w kolejce. Uruchom nową analizę aktualnego projektu.');
  }
  const prepared = await prepareTeamAnalysis(prisma, source, encryptionKey());
  return {
    request: prepared.request,
    verifySource: async () => {
      if ((await load()).fingerprint !== source.fingerprint) throw new ApiError(409, 'AI_SOURCE_CHANGED', 'Materiały zmieniły się przed płatnym wywołaniem.');
    },
    apply: (raw, tx) => applyTeamPlan(tx, source, parseAnalysisResult(raw, prepared.schema)),
  };
}

export async function processNextAiAnalysis(options: {
  prisma: PrismaClient; key: string; encryptionKey: () => string;
  fetcher?: typeof fetch; signal?: AbortSignal; now?: () => Date;
  diagnosticId?: string;
  logError: (code: string, analysisId?: string) => void;
}): Promise<boolean> {
  const now = options.now ?? (() => new Date());
  const job = await claimAiAnalysis(options.prisma, now(), options.diagnosticId);
  if (!job) return false;
  if (!job.leaseToken) throw new Error('Claimed analysis has no lease token.');
  const token = job.leaseToken;
  const timeout = AbortSignal.timeout(270_000);
  const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout;
  let generationStarted = false;
  let usage: AnalysisUsage | undefined;
  let providerResponseId: string | undefined;
  try {
    signal.throwIfAborted();
    const operation = await prepareOperation(options.prisma, job, options.encryptionKey);
    await countAnalysisInput({ key: options.key, request: operation.request, fetcher: options.fetcher, signal });
    await operation.verifySource();
    signal.throwIfAborted();
    await markAiGenerationStarted(options.prisma, job.id, token, now());
    generationStarted = true;
    const raw = await generateAnalysis({ key: options.key, request: operation.request, fetcher: options.fetcher, signal });
    usage = parseAnalysisUsage(raw);
    const identity = z.object({ id: z.string().min(1) }).safeParse(raw);
    if (!identity.success) throw new ApiError(502, 'OPENAI_RESULT_INVALID', 'Brak identyfikatora odpowiedzi OpenAI.');
    providerResponseId = identity.data.id;
    await settleAiAnalysis(options.prisma, job.id, token, {
      status: 'COMPLETED', usage, providerResponseId, apply: (tx) => operation.apply(raw, tx),
    }, now());
  } catch (error) {
    const code = error instanceof ApiError ? error.code : 'AI_PROCESSING_FAILED';
    const message = error instanceof ApiError ? error.message : 'Nie ukończono analizy. Nie ponawiamy wywołania automatycznie.';
    options.logError(code, job.id);
    const uncertain = generationStarted && !usage && !(error instanceof OpenAiRequestError && !error.chargeUncertain);
    await settleAiAnalysis(options.prisma, job.id, token, uncertain
      ? { status: 'UNKNOWN', errorCode: code, errorMessage: message }
      : {
        status: 'FAILED', billing: usage ? { kind: 'usage', usage } : { kind: 'not_charged' },
        errorCode: code, errorMessage: message, providerResponseId,
      }, now());
  }
  return true;
}

export function attachAnalysisWorker(app: FastifyInstance, options: {
  prisma: PrismaClient; key: string; encryptionKey: () => string; fetcher: typeof fetch;
}): { healthy: () => boolean; stop: () => Promise<void> } {
  const controller = new AbortController();
  let active: Promise<void> | undefined;
  let healthy = true;
  const logError = (code: string, analysisId?: string) => app.log.error({ code, analysisId }, 'OpenAI analysis failed');
  const loop = async () => {
    while (!controller.signal.aborted) {
      try {
        await processNextAiAnalysis({ ...options, signal: controller.signal, logError });
      } catch (error) {
        logError(error instanceof ApiError ? error.code : 'AI_WORKER_STORAGE_ERROR');
      }
      try {
        await delay(1000, undefined, { signal: controller.signal });
      } catch (error) {
        if (!(error instanceof Error) || error.name !== 'AbortError') throw error;
      }
    }
  };
  app.addHook('onReady', async () => {
    active = loop().catch(() => {
      healthy = false;
      logError('AI_WORKER_STOPPED');
    });
  });
  return {
    healthy: () => healthy,
    stop: async () => {
      controller.abort();
      await active;
    },
  };
}
