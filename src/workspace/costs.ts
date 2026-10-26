import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { PrismaClient } from '../generated/prisma/client.ts';
import { ApiError, parseRequest } from '../http/errors.ts';
import { analysisModel, maximumAnalysisCostMicros, monthlyAnalysisBudgetMicros } from '../ai/openai.ts';

const policySchema = z.object({
  monthlyExtraLimitMinor: z.number().int().min(0).max(1_000_000),
  updatedAt: z.iso.datetime().nullable(),
}).strict();

export function registerWorkspaceCostRoutes(app: FastifyInstance, options: {
  prisma: PrismaClient;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
  metadataEnabled: boolean;
}): void {
  const { prisma, authenticate } = options;
  app.get('/api/workspace/costs', async (request) => {
    const userId = await authenticate(request, false);
    const month = new Date().toISOString().slice(0, 7);
    const totalsQuery = prisma.aiAnalysis.groupBy({
      where: { userId, budgetMonth: month }, by: ['status'], orderBy: { status: 'asc' },
      _sum: { estimatedCostMicros: true, reservedCostMicros: true }, _count: true,
    });
    const [policy, accounts, totals, recent] = await prisma.$transaction([
      prisma.sdkCostPolicy.findUnique({ where: { userId } }),
      prisma.gitHubAccount.findMany({
        where: { userId }, orderBy: { createdAt: 'asc' },
        select: { id: true, login: true, status: true, sdkMetadata: true },
      }),
      totalsQuery,
      prisma.aiAnalysis.findMany({
        where: { userId }, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: 20,
        select: {
          id: true, kind: true, status: true, model: true, createdAt: true,
          estimatedCostMicros: true, reservedCostMicros: true, budgetMonth: true,
        },
      }),
    ]);
    return {
      sdk: {
        model: 'auto', currency: 'USD', executionAvailable: false,
        providerBudgetManagedByApplication: false, metadataEnabled: options.metadataEnabled,
        policy: policy ? { monthlyExtraLimitMinor: policy.monthlyExtraLimitMinor, updatedAt: policy.updatedAt } : null,
        accounts: accounts.map((account) => ({
          id: account.id, login: account.login, status: account.status,
          metadata: account.sdkMetadata ? {
            status: account.sdkMetadata.status, fetchedAt: account.sdkMetadata.fetchedAt,
            requestedAt: account.sdkMetadata.requestedAt, quota: account.sdkMetadata.quota,
            errorCode: account.sdkMetadata.errorCode, errorMessage: account.sdkMetadata.errorMessage,
            autoAvailable: account.sdkMetadata.catalog === null ? null
              : catalogHasAuto(account.sdkMetadata.catalog),
          } : null,
        })),
      },
      openai: {
        model: analysisModel, currency: 'USD', month,
        maximumAnalysisCostMicros, globalMonthlyBudgetMicros: monthlyAnalysisBudgetMicros,
        spentMicros: totals.reduce((sum, row) => sum + (row._sum.estimatedCostMicros ?? 0), 0),
        reservedMicros: totals.filter((row) => ['QUEUED', 'RUNNING', 'UNKNOWN'].includes(row.status))
          .reduce((sum, row) => sum + (row._sum.reservedCostMicros ?? 0), 0),
        unknownCount: totals.find((row) => row.status === 'UNKNOWN')?._count ?? 0,
        recent: recent.map(({ reservedCostMicros, ...job }) => ({
          ...job, reservationHeldMicros: ['QUEUED', 'RUNNING', 'UNKNOWN'].includes(job.status) ? reservedCostMicros : 0,
        })),
      },
    };
  });
  app.post('/api/workspace/costs/sdk-policy', async (request) => {
    const userId = await authenticate(request, true);
    const input = parseRequest(policySchema, request.body);
    const policy = await prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "User" WHERE "id" = ${userId} FOR UPDATE`;
      const previous = await tx.sdkCostPolicy.findUnique({ where: { userId } });
      if ((previous?.updatedAt.toISOString() ?? null) !== input.updatedAt) {
        throw new ApiError(409, 'SDK_COST_POLICY_CHANGED', 'Limit zmienił się w innym oknie. Odśwież zapisane dane przed ponowną edycją.');
      }
      const saved = await tx.sdkCostPolicy.upsert({
        where: { userId },
        create: { userId, monthlyExtraLimitMinor: input.monthlyExtraLimitMinor },
        update: {
          monthlyExtraLimitMinor: input.monthlyExtraLimitMinor,
          updatedAt: new Date(Math.max(Date.now(), (previous?.updatedAt.getTime() ?? 0) + 1)),
        },
      });
      await tx.auditEvent.create({
        data: {
          userId, action: 'SDK_COST_POLICY_UPDATED', targetType: 'SdkCostPolicy', targetId: userId,
          details: { previousLimitMinor: previous?.monthlyExtraLimitMinor ?? null, monthlyExtraLimitMinor: saved.monthlyExtraLimitMinor, currency: 'USD', model: 'auto' },
        },
      });
      return saved;
    });
    return { policy: { monthlyExtraLimitMinor: policy.monthlyExtraLimitMinor, updatedAt: policy.updatedAt } };
  });
  app.post('/api/workspace/github-accounts/:id/sdk-metadata', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(z.object({ id: z.string().cuid() }), request.params);
    const account = await prisma.gitHubAccount.findFirst({ where: { id, userId, status: 'ACTIVE' }, select: { id: true } });
    if (!account) throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'Wybierz własne aktywne konto GitHub.');
    if (!options.metadataEnabled) throw new ApiError(503, 'SDK_METADATA_UNAVAILABLE', 'Odczyt kredytów SDK nie jest jeszcze włączony.');
    const state = await prisma.$transaction(async (tx) => {
      const owned = await tx.$queryRaw<{ id: string }[]>`
        SELECT "id" FROM "GitHubAccount" WHERE "id" = ${id} AND "userId" = ${userId} AND "status" = 'ACTIVE' FOR UPDATE
      `;
      if (owned.length !== 1) throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'Konto GitHub nie jest już aktywne.');
      const previous = await tx.sdkAccountMetadata.findUnique({ where: { githubAccountId: id } });
      if (previous && ['QUEUED', 'RUNNING'].includes(previous.status)) return previous;
      return tx.sdkAccountMetadata.upsert({
        where: { githubAccountId: id }, create: { githubAccountId: id },
        update: {
          status: 'QUEUED', requestedAt: new Date(), errorCode: null, errorMessage: null,
          leaseToken: null, leaseExpiresAt: null,
        },
      });
    });
    return reply.status(202).send({ status: state.status, requestedAt: state.requestedAt });
  });
}

function catalogHasAuto(value: unknown): boolean {
  const parsed = z.object({ models: z.array(z.object({ id: z.string() })) }).safeParse(value);
  if (!parsed.success) throw new Error('Stored SDK model catalog is invalid.');
  return parsed.data.models.some((model) => model.id === 'auto');
}
