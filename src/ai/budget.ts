import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { AiAnalysis, Prisma, PrismaClient } from '../generated/prisma/client.ts';
import { ApiError } from '../http/errors.ts';
import {
  analysisCostMicros, analysisModel, maximumAnalysisCostMicros,
  monthlyAnalysisBudgetMicros, type AnalysisUsage,
} from './openai.ts';

const leaseMilliseconds = 300_000;
const reservationSchema = z.object({
  userId: z.string().min(1),
  projectId: z.string().min(1).nullable(),
  teamId: z.string().min(1).nullable(),
  kind: z.enum(['TEAM_TASKS', 'REPOSITORY_CONTEXT', 'DIAGNOSTIC']),
  requestKey: z.uuid(),
  inputFingerprint: z.string().regex(/^[a-f0-9]{64}$/),
}).strict();

export type AnalysisReservation = z.infer<typeof reservationSchema>;
export type AnalysisOutcome =
  | { status: 'UNKNOWN'; errorCode: string; errorMessage: string }
  | {
    status: 'FAILED';
    billing: { kind: 'not_charged' } | { kind: 'usage'; usage: AnalysisUsage };
    errorCode: string; errorMessage: string; providerResponseId?: string;
  }
  | {
    status: 'COMPLETED'; usage: AnalysisUsage; providerResponseId: string;
    apply: (tx: Prisma.TransactionClient) => Promise<Prisma.InputJsonValue>;
  };

function monthAt(now: Date): string {
  if (!Number.isFinite(now.getTime())) throw new Error('An explicit valid budget timestamp is required.');
  return now.toISOString().slice(0, 7);
}

async function lockBudget(tx: Prisma.TransactionClient): Promise<void> {
  await tx.$queryRaw`SELECT 1 AS locked FROM pg_advisory_xact_lock(10626001900::bigint)`;
}

async function period(tx: Prisma.TransactionClient, month: string) {
  return tx.aiBudgetPeriod.upsert({ where: { month }, create: { month }, update: {} });
}

async function reservePeriod(tx: Prisma.TransactionClient, month: string, amount: number): Promise<void> {
  const budget = await period(tx, month);
  if (budget.spentMicros + budget.reservedMicros + amount > monthlyAnalysisBudgetMicros) {
    throw new ApiError(409, 'AI_MONTHLY_BUDGET_EXCEEDED', 'Wyczerpano globalny miesięczny limit OpenAI: 10 USD. Rezerwacje niepotwierdzonych wywołań również zajmują limit.');
  }
  await tx.aiBudgetPeriod.update({ where: { month }, data: { reservedMicros: { increment: amount } } });
}

async function transferReservation(tx: Prisma.TransactionClient, job: AiAnalysis, now: Date): Promise<AiAnalysis> {
  const month = monthAt(now);
  if (job.budgetMonth === month) return job;
  if (job.providerStartedAt) throw new Error('A submitted analysis cannot change its billing period.');
  await reservePeriod(tx, month, job.reservedCostMicros);
  await tx.aiBudgetPeriod.update({
    where: { month: job.budgetMonth }, data: { reservedMicros: { decrement: job.reservedCostMicros } },
  });
  return tx.aiAnalysis.update({ where: { id: job.id }, data: { budgetMonth: month } });
}

export async function reserveAiAnalysis(
  prisma: PrismaClient, value: AnalysisReservation, now = new Date(),
): Promise<AiAnalysis> {
  const parsed = reservationSchema.safeParse(value);
  if (!parsed.success) throw new ApiError(400, 'INVALID_REQUEST', 'Nieprawidłowe dane rezerwacji analizy.');
  const input = parsed.data;
  const validScope = input.kind === 'DIAGNOSTIC' ? input.projectId === null && input.teamId === null
    : input.kind === 'REPOSITORY_CONTEXT' ? input.projectId !== null && input.teamId === null
      : input.projectId !== null && input.teamId !== null;
  if (!validScope) throw new ApiError(400, 'INVALID_REQUEST', 'Nieprawidłowy zakres analizy.');
  const month = monthAt(now);
  return prisma.$transaction(async (tx) => {
    await lockBudget(tx);
    const previous = await tx.aiAnalysis.findUnique({
      where: { userId_requestKey: { userId: input.userId, requestKey: input.requestKey } },
    });
    if (previous) {
      if (previous.kind !== input.kind || previous.projectId !== input.projectId ||
          previous.teamId !== input.teamId || previous.inputFingerprint !== input.inputFingerprint) {
        throw new ApiError(409, 'AI_REQUEST_KEY_CONFLICT', 'Ten identyfikator żądania został już użyty dla innej analizy.');
      }
      return previous;
    }
    if (input.projectId && !await tx.project.findFirst({ where: { id: input.projectId, userId: input.userId }, select: { id: true } })) {
      throw new ApiError(404, 'PROJECT_NOT_FOUND', 'Nie znaleziono własnego projektu.');
    }
    if (input.teamId && !await tx.team.findFirst({
      where: { id: input.teamId, userId: input.userId, projectId: input.projectId }, select: { id: true },
    })) {
      throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono własnego zespołu tego projektu.');
    }
    if (await tx.aiAnalysis.findFirst({
      where: { userId: input.userId, status: { in: ['QUEUED', 'RUNNING'] } }, select: { id: true },
    })) {
      throw new ApiError(409, 'AI_ANALYSIS_ACTIVE', 'Masz już analizę w kolejce lub w trakcie wykonywania.');
    }
    await reservePeriod(tx, month, maximumAnalysisCostMicros);
    const job = await tx.aiAnalysis.create({
      data: {
        ...input, model: analysisModel, budgetMonth: month,
        reservedCostMicros: maximumAnalysisCostMicros, createdAt: now,
      },
    });
    await tx.auditEvent.create({
      data: {
        userId: input.userId, action: 'AI_ANALYSIS_QUEUED', targetType: 'AiAnalysis', targetId: job.id,
        details: { kind: input.kind, budgetMonth: month, maximumCostMicros: maximumAnalysisCostMicros },
      },
    });
    return job;
  });
}

async function releaseAndCharge(tx: Prisma.TransactionClient, job: AiAnalysis, usage?: AnalysisUsage): Promise<number> {
  const cost = usage ? analysisCostMicros(usage.inputTokens, usage.outputTokens, usage.cachedTokens) : 0;
  if (usage && cost !== usage.costMicros) throw new Error('Analysis cost must match validated token accounting.');
  if (cost > job.reservedCostMicros) throw new Error('Analysis exceeded its reserved budget.');
  const changed = await tx.aiBudgetPeriod.updateMany({
    where: { month: job.budgetMonth, reservedMicros: { gte: job.reservedCostMicros } },
    data: {
      reservedMicros: { decrement: job.reservedCostMicros }, spentMicros: { increment: cost },
    },
  });
  if (changed.count !== 1) throw new Error('Analysis reservation is missing; refusing an inconsistent settlement.');
  return cost;
}

function assertLease(job: AiAnalysis | null, token: string, now: Date): asserts job is AiAnalysis {
  if (!job || job.status !== 'RUNNING' || job.leaseToken !== token ||
      !job.leaseExpiresAt || job.leaseExpiresAt <= now) {
    throw new ApiError(409, 'AI_LEASE_LOST', 'Analiza nie ma już aktywnej dzierżawy wykonawcy.');
  }
}

export async function claimAiAnalysis(prisma: PrismaClient, now = new Date(), diagnosticId?: string): Promise<AiAnalysis | null> {
  return prisma.$transaction(async (tx) => {
    await lockBudget(tx);
    const running = await tx.aiAnalysis.findFirst({ where: { status: 'RUNNING' } });
    if (running) {
      if (running.leaseExpiresAt && running.leaseExpiresAt > now) return null;
      const uncertain = running.providerStartedAt !== null;
      if (!uncertain) await releaseAndCharge(tx, running);
      await tx.aiAnalysis.update({
        where: { id: running.id },
        data: {
          status: uncertain ? 'UNKNOWN' : 'FAILED',
          estimatedCostMicros: uncertain ? null : 0,
          errorCode: 'AI_WORKER_INTERRUPTED',
          errorMessage: uncertain
            ? 'Przerwano wykonawcę po rozpoczęciu wywołania. Rezerwacja pozostaje zajęta; nie ponawiamy płatnej analizy automatycznie.'
            : 'Przerwano wykonawcę przed płatnym wywołaniem. Zwolniono rezerwację.',
          leaseToken: null, leaseExpiresAt: null, finishedAt: now,
        },
      });
      await tx.auditEvent.create({
        data: {
          userId: running.userId, action: 'AI_WORKER_INTERRUPTED', targetType: 'AiAnalysis', targetId: running.id,
          details: { budgetMonth: running.budgetMonth, reservationHeldMicros: uncertain ? running.reservedCostMicros : 0 },
        },
      });
    }
    let next = await tx.aiAnalysis.findFirst({
      where: { status: 'QUEUED', ...(diagnosticId ? { id: diagnosticId, kind: 'DIAGNOSTIC' } : {}) },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    if (!next) return null;
    try {
      next = await transferReservation(tx, next, now);
    } catch (error) {
      if (!(error instanceof ApiError) || error.code !== 'AI_MONTHLY_BUDGET_EXCEEDED') throw error;
      await releaseAndCharge(tx, next);
      await tx.aiAnalysis.update({
        where: { id: next.id },
        data: { status: 'FAILED', estimatedCostMicros: 0, errorCode: error.code, errorMessage: error.message, finishedAt: now },
      });
      return null;
    }
    return tx.aiAnalysis.update({
      where: { id: next.id },
      data: { status: 'RUNNING', leaseToken: randomUUID(), leaseExpiresAt: new Date(now.getTime() + leaseMilliseconds) },
    });
  });
}

export async function heartbeatAiAnalysis(prisma: PrismaClient, id: string, token: string, now = new Date()): Promise<void> {
  const updated = await prisma.aiAnalysis.updateMany({
    where: { id, status: 'RUNNING', leaseToken: token, leaseExpiresAt: { gt: now } },
    data: { leaseExpiresAt: new Date(now.getTime() + leaseMilliseconds) },
  });
  if (updated.count !== 1) throw new ApiError(409, 'AI_LEASE_LOST', 'Nie potwierdzono dzierżawy analizy.');
}

export async function markAiGenerationStarted(prisma: PrismaClient, id: string, token: string, now = new Date()): Promise<AiAnalysis> {
  return prisma.$transaction(async (tx) => {
    await lockBudget(tx);
    let job = await tx.aiAnalysis.findUnique({ where: { id } });
    assertLease(job, token, now);
    if (job.providerStartedAt) throw new ApiError(409, 'AI_ALREADY_SUBMITTED', 'Płatne wywołanie już rozpoczęto. Nie ponawiamy go automatycznie.');
    job = await transferReservation(tx, job, now);
    return tx.aiAnalysis.update({ where: { id }, data: { providerStartedAt: now } });
  });
}

export async function settleAiAnalysis(
  prisma: PrismaClient, id: string, token: string, outcome: AnalysisOutcome, now = new Date(),
): Promise<AiAnalysis> {
  return prisma.$transaction(async (tx) => {
    await lockBudget(tx);
    const job = await tx.aiAnalysis.findUnique({ where: { id } });
    assertLease(job, token, now);
    let usage: AnalysisUsage | undefined;
    let estimatedCostMicros: number | null = null;
    let result: Prisma.InputJsonValue | undefined;
    if (outcome.status !== 'UNKNOWN') {
      usage = outcome.status === 'COMPLETED' ? outcome.usage
        : outcome.billing.kind === 'usage' ? outcome.billing.usage : undefined;
      if (usage && !job.providerStartedAt) throw new Error('Cannot charge usage before a provider submission.');
      estimatedCostMicros = await releaseAndCharge(tx, job, usage);
      if (outcome.status === 'COMPLETED') result = await outcome.apply(tx);
    }
    const updated = await tx.aiAnalysis.update({
      where: { id },
      data: {
        status: outcome.status, estimatedCostMicros,
        inputTokens: usage?.inputTokens, cachedTokens: usage?.cachedTokens, outputTokens: usage?.outputTokens,
        providerResponseId: outcome.status === 'UNKNOWN' ? undefined : outcome.providerResponseId,
        result, finishedAt: now, leaseToken: null, leaseExpiresAt: null,
        errorCode: outcome.status === 'COMPLETED' ? null : outcome.errorCode,
        errorMessage: outcome.status === 'COMPLETED' ? null : outcome.errorMessage,
      },
    });
    await tx.auditEvent.create({
      data: {
        userId: job.userId, action: `AI_ANALYSIS_${outcome.status}`, targetType: 'AiAnalysis', targetId: id,
        details: {
          budgetMonth: job.budgetMonth, estimatedCostMicros,
          reservationHeldMicros: outcome.status === 'UNKNOWN' ? job.reservedCostMicros : 0,
        },
      },
    });
    return updated;
  });
}
