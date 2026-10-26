import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { AiAnalysis, PrismaClient } from '../generated/prisma/client.ts';
import { ApiError, parseRequest } from '../http/errors.ts';
import { reserveAiAnalysis } from './budget.ts';
import { analysisModel, maximumAnalysisCostMicros, monthlyAnalysisBudgetMicros } from './openai.ts';
import { loadTeamAnalysisSource } from './team-analysis.ts';

const idSchema = z.object({ id: z.string().cuid() });
const requestSchema = z.object({ requestKey: z.uuid() }).strict();

export function analysisDto(job: AiAnalysis) {
  return {
    id: job.id, kind: job.kind, status: job.status, model: job.model,
    projectId: job.projectId, teamId: job.teamId, requestKey: job.requestKey,
    createdAt: job.createdAt, finishedAt: job.finishedAt,
    estimatedCostMicros: job.estimatedCostMicros,
    reservationHeldMicros: ['QUEUED', 'RUNNING', 'UNKNOWN'].includes(job.status) ? job.reservedCostMicros : 0,
    errorCode: job.errorCode, errorMessage: job.errorMessage, result: job.result,
  };
}

export function registerAnalysisRoutes(app: FastifyInstance, options: {
  prisma: PrismaClient;
  enabled: () => boolean;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
}): void {
  const { prisma, authenticate } = options;
  app.get('/api/workspace/teams/:id/analyses', async (request) => {
    const userId = await authenticate(request, false);
    const { id } = parseRequest(idSchema, request.params);
    if (!await prisma.team.findFirst({ where: { id, userId }, select: { id: true } })) {
      throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono zespołu.');
    }
    const analyses = await prisma.aiAnalysis.findMany({
      where: { userId, teamId: id }, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: 10,
    });
    return {
      enabled: options.enabled(), model: analysisModel,
      maximumCostMicros: maximumAnalysisCostMicros, monthlyBudgetMicros: monthlyAnalysisBudgetMicros,
      analyses: analyses.map(analysisDto),
    };
  });
  app.get('/api/workspace/analyses/:id', async (request) => {
    const userId = await authenticate(request, false);
    const { id } = parseRequest(idSchema, request.params);
    const job = await prisma.aiAnalysis.findFirst({ where: { id, userId } });
    if (!job) throw new ApiError(404, 'AI_ANALYSIS_NOT_FOUND', 'Nie znaleziono analizy.');
    return { analysis: analysisDto(job) };
  });
  app.post('/api/workspace/teams/:id/analyses', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const { requestKey } = parseRequest(requestSchema, request.body);
    const previous = await prisma.aiAnalysis.findUnique({ where: { userId_requestKey: { userId, requestKey } } });
    if (previous) {
      if (previous.kind !== 'TEAM_TASKS' || previous.teamId !== id) throw new ApiError(409, 'AI_REQUEST_KEY_CONFLICT', 'Ten identyfikator wykorzystano dla innej analizy.');
      return reply.status(200).send({ analysis: analysisDto(previous) });
    }
    if (!options.enabled()) throw new ApiError(503, 'OPENAI_NOT_CONFIGURED', 'Analiza OpenAI nie jest teraz dostępna. Nie pobrano opłaty.');
    const source = await prisma.$transaction(
      (tx) => loadTeamAnalysisSource(tx, userId, id), { isolationLevel: 'RepeatableRead' },
    );
    const projectId = source.team.project?.id;
    if (!projectId) throw new Error('Validated team analysis project is missing.');
    const job = await reserveAiAnalysis(prisma, {
      userId, projectId, teamId: id, kind: 'TEAM_TASKS',
      requestKey, inputFingerprint: source.fingerprint,
    });
    return reply.status(202).send({ analysis: analysisDto(job) });
  });
}
