import { createHash } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Prisma, PrismaClient } from '../generated/prisma/client.ts';
import { ApiError, parseRequest } from '../http/errors.ts';
import { isValidTimezone } from '../planning/planning.ts';
import { decryptSecret, encryptSecret } from '../security/secrets.ts';

const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_COLLECTION_BYTES = 30 * 1024 * 1024;
const idSchema = z.object({ id: z.string().cuid() });
const filenameSchema = z.object({
  filename: z.string().trim().min(1).max(255).regex(/^[^/\\\u0000-\u001f\u007f]+$/),
}).strict();
const messageSchema = z.object({ content: z.string().trim().max(20000) }).strict();
const time = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/);
const scheduleSchema = z.object({
  timezone: z.string().refine(isValidTimezone),
  enabled: z.boolean(),
  days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
  startTime: time,
  endTime: time,
}).strict().refine((value) =>
  new Set(value.days).size === value.days.length && value.endTime > value.startTime);
const fileMetadata = {
  id: true, filename: true, sizeBytes: true, contentHash: true, createdAt: true,
} as const;

type FileOwner = { projectId: string } | { messageId: string } | { transitionId: string };

async function lockFileOwner(tx: Prisma.TransactionClient, owner: FileOwner, userId: string): Promise<void> {
  let rows: { id: string }[];
  if ('projectId' in owner) {
    rows = await tx.$queryRaw`
      SELECT "id" FROM "Project" WHERE "id" = ${owner.projectId} AND "userId" = ${userId} FOR UPDATE
    `;
  } else if ('messageId' in owner) {
    rows = await tx.$queryRaw`
      SELECT m."id" FROM "BotMessage" m JOIN "Bot" b ON b."id" = m."botId"
      WHERE m."id" = ${owner.messageId} AND b."userId" = ${userId} AND m."status" = 'DRAFT'
      FOR UPDATE OF m
    `;
  } else {
    rows = await tx.$queryRaw`
      SELECT t."id" FROM "StageTransitionEvent" t
      JOIN "Stage" s ON s."id" = t."stageId" JOIN "Bot" b ON b."id" = s."botId"
      WHERE t."id" = ${owner.transitionId} AND b."userId" = ${userId}
      AND t."toStatus" = 'CHANGES_REQUESTED' AND s."status" = 'CHANGES_REQUESTED'
      AND t."id" = (
        SELECT latest."id" FROM "StageTransitionEvent" latest
        WHERE latest."stageId" = s."id"
        ORDER BY latest."createdAt" DESC, latest."id" DESC LIMIT 1
      )
      FOR UPDATE OF t, s
    `;
  }
  if (rows.length !== 1) {
    throw new ApiError(409, 'ATTACHMENT_TARGET_UNAVAILABLE', 'Nie można teraz zmienić tych załączników. Odśwież widok.');
  }
}

export function registerWorkspaceMaterialRoutes(app: FastifyInstance, options: {
  prisma: PrismaClient;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
  encryptionKey: () => string;
}): void {
  const { prisma, authenticate, encryptionKey } = options;
  app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer' }, (_request, body, done) => done(null, body));

  for (const kind of ['projects', 'messages', 'revisions'] as const) {
    app.post(`/api/workspace/${kind}/:id/files`, { bodyLimit: MAX_FILE_BYTES }, async (request, reply) => {
      const userId = await authenticate(request, true);
      const { id } = parseRequest(idSchema, request.params);
      const { filename } = parseRequest(filenameSchema, request.query);
      if (!Buffer.isBuffer(request.body) || request.body.length === 0) {
        throw new ApiError(400, 'FILE_REQUIRED', 'Prześlij niepusty plik jako application/octet-stream.');
      }
      const bytes = request.body;
      if (bytes.length > MAX_FILE_BYTES) throw new ApiError(413, 'FILE_TOO_LARGE', 'Maksymalny rozmiar pliku to 10 MB.');
      const owner: FileOwner = kind === 'projects' ? { projectId: id }
        : kind === 'messages' ? { messageId: id } : { transitionId: id };
      const file = await prisma.$transaction(async (tx) => {
        await lockFileOwner(tx, owner, userId);
        const existing = await tx.workspaceFile.aggregate({ where: owner, _sum: { sizeBytes: true } });
        if ((existing._sum.sizeBytes ?? 0) + bytes.length > MAX_COLLECTION_BYTES) {
          throw new ApiError(413, 'ATTACHMENTS_TOO_LARGE', 'Łączny rozmiar załączników w tej kolekcji nie może przekroczyć 30 MB.');
        }
        const created = await tx.workspaceFile.create({
          data: {
            userId, ...owner, filename, sizeBytes: bytes.length,
            contentHash: createHash('sha256').update(bytes).digest('hex'),
            encryptedContent: encryptSecret(bytes.toString('base64'), encryptionKey()),
          },
          select: fileMetadata,
        });
        await tx.auditEvent.create({
          data: { userId, action: 'WORKSPACE_FILE_UPLOADED', targetType: 'WorkspaceFile', targetId: created.id },
        });
        return created;
      });
      return reply.status(201).send({ file });
    });
  }

  app.get('/api/workspace/files/:id/download', async (request, reply) => {
    const userId = await authenticate(request, false);
    const { id } = parseRequest(idSchema, request.params);
    const file = await prisma.workspaceFile.findFirst({ where: { id, userId } });
    if (!file) throw new ApiError(404, 'FILE_NOT_FOUND', 'Nie znaleziono pliku.');
    const bytes = Buffer.from(decryptSecret(file.encryptedContent, encryptionKey()), 'base64');
    if (bytes.length !== file.sizeBytes || createHash('sha256').update(bytes).digest('hex') !== file.contentHash) {
      throw new Error(`Workspace file integrity check failed: ${file.id}`);
    }
    return reply
      .header('Content-Type', 'application/octet-stream')
      .header('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent(file.filename).replace(/['()*]/g, (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`)}`)
      .header('Cache-Control', 'private, no-store')
      .send(bytes);
  });

  app.delete('/api/workspace/files/:id', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    await prisma.$transaction(async (tx) => {
      const file = await tx.workspaceFile.findFirst({ where: { id, userId } });
      if (!file) throw new ApiError(404, 'FILE_NOT_FOUND', 'Nie znaleziono pliku.');
      let owner: FileOwner;
      if (file.projectId) owner = { projectId: file.projectId };
      else if (file.messageId) owner = { messageId: file.messageId };
      else if (file.transitionId) owner = { transitionId: file.transitionId };
      else throw new Error(`Workspace file has no owner: ${file.id}`);
      await lockFileOwner(tx, owner, userId);
      await tx.workspaceFile.delete({ where: { id } });
      await tx.auditEvent.create({
        data: { userId, action: 'WORKSPACE_FILE_DELETED', targetType: 'WorkspaceFile', targetId: id },
      });
    });
    return reply.status(204).send();
  });

  app.get('/api/workspace/bots/:id/messages', async (request) => {
    const userId = await authenticate(request, false);
    const { id } = parseRequest(idSchema, request.params);
    const bot = await prisma.bot.findFirst({ where: { id, userId }, select: { id: true } });
    if (!bot) throw new ApiError(404, 'BOT_NOT_FOUND', 'Nie znaleziono bota.');
    const messages = await prisma.botMessage.findMany({
      where: { botId: id },
      orderBy: { createdAt: 'asc' },
      include: { files: { select: fileMetadata } },
    });
    return { messages };
  });

  app.post('/api/workspace/bots/:id/messages', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(messageSchema, request.body);
    const message = await prisma.$transaction(async (tx) => {
      const bot = await tx.bot.findFirst({ where: { id, userId }, select: { id: true } });
      if (!bot) throw new ApiError(404, 'BOT_NOT_FOUND', 'Nie znaleziono bota.');
      const created = await tx.botMessage.create({ data: { botId: id, content: input.content } });
      await tx.auditEvent.create({
        data: { userId, botId: id, action: 'BOT_MESSAGE_DRAFTED', targetType: 'BotMessage', targetId: created.id },
      });
      return created;
    });
    return reply.status(201).send({ message });
  });

  app.post('/api/workspace/bots/:id/schedule', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(scheduleSchema, request.body);
    const schedule = await prisma.$transaction(async (tx) => {
      const bot = await tx.bot.findFirst({ where: { id, userId }, select: { id: true } });
      if (!bot) throw new ApiError(404, 'BOT_NOT_FOUND', 'Nie znaleziono bota.');
      const result = await tx.botWorkSchedule.upsert({
        where: { botId: id },
        create: { botId: id, ...input },
        update: input,
      });
      await tx.auditEvent.create({
        data: { userId, botId: id, action: 'BOT_SCHEDULE_UPDATED', targetType: 'BotWorkSchedule', targetId: result.id },
      });
      return result;
    });
    return { schedule };
  });

  app.delete('/api/workspace/messages/:id', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    await prisma.$transaction(async (tx) => {
      await lockFileOwner(tx, { messageId: id }, userId);
      await tx.workspaceFile.deleteMany({ where: { messageId: id, userId } });
      await tx.botMessage.delete({ where: { id } });
      await tx.auditEvent.create({
        data: { userId, action: 'BOT_MESSAGE_DRAFT_DELETED', targetType: 'BotMessage', targetId: id },
      });
    });
    return reply.status(204).send();
  });

  app.get('/api/workspace/stages/:id/revisions', async (request) => {
    const userId = await authenticate(request, false);
    const { id } = parseRequest(idSchema, request.params);
    const stage = await prisma.stage.findFirst({
      where: { id, bot: { userId } }, select: { id: true },
    });
    if (!stage) throw new ApiError(404, 'STAGE_NOT_FOUND', 'Nie znaleziono etapu.');
    const revisions = await prisma.stageTransitionEvent.findMany({
      where: { stageId: id, toStatus: 'CHANGES_REQUESTED' },
      orderBy: { createdAt: 'asc' },
      include: { files: { select: fileMetadata } },
    });
    return { revisions };
  });
}
