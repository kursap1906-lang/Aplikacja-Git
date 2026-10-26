import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Prisma, PrismaClient } from '../generated/prisma/client.ts';
import type { VerifiedRepository } from '../github/repository-access.ts';
import { ApiError, isUniqueConstraintError, parseRequest } from '../http/errors.ts';
import { validateHierarchy } from './hierarchy.ts';
import { registerWorkspaceMaterialRoutes } from './materials.ts';

const definitionSchema = z.object({
  name: z.string().trim().min(1).max(100),
  role: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).default(''),
  systemPrompt: z.string().trim().min(1).max(20000),
  skills: z.array(z.string().trim().min(1).max(100)).max(30).default([]),
}).strict();
const projectSchema = z.object({
  name: z.string().trim().min(1).max(120),
  description: z.string().trim().max(5000).default(''),
  brief: z.string().trim().max(100000).default(''),
  githubAccountId: z.string().cuid(),
  repository: z.string().regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/),
}).strict();
const projectDetailsSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  description: z.string().trim().max(5000).optional(),
  brief: z.string().trim().max(100000).optional(),
  repositoryContext: z.string().trim().max(100000).optional(),
}).strict().refine((value) => Object.keys(value).length > 0);
const teamDetailsSchema = z.object({
  name: z.string().trim().min(1).max(100),
  description: z.string().trim().max(2000).default(''),
}).strict();
const plannedTaskSchema = z.object({
  definitionId: z.string().cuid(),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).default(''),
  priority: z.enum(['LOW', 'NORMAL', 'HIGH', 'URGENT']).default('NORMAL'),
}).strict();
const teamSchema = teamDetailsSchema.extend({
  projectId: z.string().cuid(),
  members: z.array(z.object({
    definitionId: z.string().cuid(),
    githubAccountId: z.string().cuid(),
  }).strict()).min(1).max(20),
  tasks: z.array(plannedTaskSchema).max(100).default([]),
}).strict().refine((value) =>
  new Set(value.members.map((member) => member.definitionId)).size === value.members.length &&
  value.tasks.every((task) => value.members.some((member) => member.definitionId === task.definitionId)));
const taskSchema = z.object({
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).default(''),
  botId: z.string().cuid(),
  priority: z.enum(['LOW', 'NORMAL', 'HIGH', 'URGENT']).default('NORMAL'),
}).strict();
const taskEditSchema = taskSchema.partial().strict().refine((value) => Object.keys(value).length > 0);
const idSchema = z.object({ id: z.string().cuid() });
const hierarchySchema = z.object({
  updatedAt: z.iso.datetime(),
  members: z.array(z.object({
    id: z.string().cuid(),
    parentId: z.string().cuid().nullable(),
  }).strict()).max(20),
}).strict();
const memberSchema = z.object({
  definitionId: z.string().cuid(),
  githubAccountId: z.string().cuid(),
}).strict();

async function lockTeam(tx: Prisma.TransactionClient, id: string, userId: string): Promise<void> {
  const rows = await tx.$queryRaw<{ id: string }[]>`
    SELECT "id" FROM "Team" WHERE "id" = ${id} AND "userId" = ${userId} FOR UPDATE
  `;
  if (rows.length !== 1) throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono zespołu.');
}

async function createInstance(
  tx: Prisma.TransactionClient,
  teamId: string,
  userId: string,
  definition: { id: string; name: string; systemPrompt: string },
  repository: VerifiedRepository,
) {
  const bot = await tx.bot.create({
    data: {
      userId, definitionId: definition.id, name: definition.name,
      systemPrompt: definition.systemPrompt, ...repository,
    },
  });
  return tx.teamBot.create({ data: { teamId, botId: bot.id } });
}

function uniqueConflict(error: unknown, code: string, message: string): never {
  if (isUniqueConstraintError(error)) {
    throw new ApiError(409, code, message);
  }
  throw error;
}

export function registerWorkspaceRoutes(app: FastifyInstance, options: {
  prisma: PrismaClient;
  encryptionKey: () => string;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
  verifyRepository: (input: {
    userId: string; githubAccountId: string; repository: string;
  }) => Promise<VerifiedRepository>;
}): void {
  const { prisma, authenticate, verifyRepository } = options;
  registerWorkspaceMaterialRoutes(app, options);
  const ownedProject = async (id: string, userId: string) => {
    const project = await prisma.project.findFirst({ where: { id, userId } });
    if (!project) throw new ApiError(404, 'PROJECT_NOT_FOUND', 'Nie znaleziono projektu.');
    return project;
  };

  app.get('/api/workspace', async (request) => {
    const userId = await authenticate(request, false);
    const [definitions, projects, teams] = await prisma.$transaction([
      prisma.botDefinition.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } }),
      prisma.project.findMany({
        where: { userId },
        orderBy: { updatedAt: 'desc' },
        include: {
          tasks: { orderBy: { createdAt: 'asc' } },
          documents: {
            where: { deletedAt: null },
            select: { id: true, filename: true, currentVersion: true },
          },
          files: {
            select: { id: true, filename: true, sizeBytes: true, contentHash: true, createdAt: true },
            orderBy: { createdAt: 'asc' },
          },
        },
      }),
      prisma.team.findMany({
        where: { userId },
        orderBy: { updatedAt: 'desc' },
        include: {
          bots: {
            select: {
              id: true, parentId: true, botId: true,
              bot: {
                select: {
                  id: true, definitionId: true, name: true, status: true,
                  githubAccountId: true, repository: true, systemPrompt: true,
                  stages: {
                    orderBy: { number: 'asc' },
                    select: { id: true, number: true, title: true, status: true },
                  },
                  workSchedule: true,
                },
              },
            },
          },
          tasks: { orderBy: { createdAt: 'asc' } },
        },
      }),
    ]);
    return { definitions, projects, teams };
  });

  app.post('/api/bot-definitions', async (request, reply) => {
    const userId = await authenticate(request, true);
    const input = parseRequest(definitionSchema, request.body);
    try {
      const definition = await prisma.$transaction(async (tx) => {
        const created = await tx.botDefinition.create({ data: { userId, ...input } });
        await tx.auditEvent.create({
          data: { userId, action: 'BOT_DEFINITION_CREATED', targetType: 'BotDefinition', targetId: created.id },
        });
        return created;
      });
      return reply.status(201).send({ definition });
    } catch (error) {
      uniqueConflict(error, 'BOT_DEFINITION_NAME_EXISTS', 'Bot o tej nazwie już istnieje.');
    }
  });

  app.patch('/api/bot-definitions/:id', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(definitionSchema, request.body);
    try {
      await prisma.$transaction(async (tx) => {
        const result = await tx.botDefinition.updateMany({ where: { id, userId }, data: input });
        if (result.count !== 1) throw new ApiError(404, 'BOT_DEFINITION_NOT_FOUND', 'Nie znaleziono definicji bota.');
        await tx.auditEvent.create({
          data: { userId, action: 'BOT_DEFINITION_UPDATED', targetType: 'BotDefinition', targetId: id },
        });
      });
      // Existing instances keep their prompt snapshot; editing a role never rewrites a running agent.
      return { ok: true };
    } catch (error) {
      uniqueConflict(error, 'BOT_DEFINITION_NAME_EXISTS', 'Bot o tej nazwie już istnieje.');
    }
  });

  app.post('/api/workspace/projects', async (request, reply) => {
    const userId = await authenticate(request, true);
    const input = parseRequest(projectSchema, request.body);
    const repository = await verifyRepository({
      userId, githubAccountId: input.githubAccountId, repository: input.repository,
    });
    const project = await prisma.$transaction(async (tx) => {
      const created = await tx.project.create({
        data: {
          userId, name: input.name, description: input.description, brief: input.brief,
          repository: repository.repository, repositoryId: repository.repositoryId,
          defaultBranch: repository.defaultBranch, mainGithubAccountId: repository.githubAccountId,
        },
      });
      await tx.auditEvent.create({
        data: { userId, action: 'PROJECT_CREATED', targetType: 'Project', targetId: created.id },
      });
      return created;
    });
    return reply.status(201).send({ project });
  });

  app.patch('/api/workspace/projects/:id', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(projectDetailsSchema, request.body);
    await prisma.$transaction(async (tx) => {
      const result = await tx.project.updateMany({ where: { id, userId }, data: input });
      if (result.count !== 1) throw new ApiError(404, 'PROJECT_NOT_FOUND', 'Nie znaleziono projektu.');
      await tx.auditEvent.create({
        data: { userId, action: 'PROJECT_BRIEF_UPDATED', targetType: 'Project', targetId: id },
      });
    });
    return { ok: true };
  });

  app.post('/api/workspace/teams', async (request, reply) => {
    const userId = await authenticate(request, true);
    const input = parseRequest(teamSchema, request.body);
    const project = await ownedProject(input.projectId, userId);
    if (!project.repository) throw new ApiError(409, 'PROJECT_REPOSITORY_REQUIRED', 'Projekt musi mieć repozytorium.');
    const definitions = await prisma.botDefinition.findMany({
      where: { userId, id: { in: input.members.map((member) => member.definitionId) } },
    });
    if (definitions.length !== input.members.length) {
      throw new ApiError(404, 'BOT_DEFINITION_NOT_FOUND', 'Wybierz własne definicje botów.');
    }
    const repositories = new Map<string, VerifiedRepository>();
    const instances = new Map<string, string>();
    for (const member of input.members) {
      if (!repositories.has(member.githubAccountId)) {
        repositories.set(member.githubAccountId, await verifyRepository({
          userId, githubAccountId: member.githubAccountId, repository: project.repository,
        }));
      }
    }
    const repositoryIds = new Set([...repositories.values()].map((repository) => repository.repositoryId));
    if (repositoryIds.size !== 1 || (project.repositoryId && !repositoryIds.has(project.repositoryId))) {
      throw new ApiError(409, 'PROJECT_REPOSITORY_CHANGED', 'GitHub zwrócił inne repozytorium niż zapisane w projekcie.');
    }
    try {
      const team = await prisma.$transaction(async (tx) => {
        const locked = await tx.$queryRaw<{ id: string }[]>`
          SELECT "id" FROM "Project"
          WHERE "id" = ${project.id} AND "userId" = ${userId} AND "repository" = ${project.repository}
          FOR UPDATE
        `;
        if (locked.length !== 1) throw new ApiError(409, 'PROJECT_CHANGED', 'Projekt się zmienił. Odśwież formularz.');
        const created = await tx.team.create({
          data: { userId, projectId: project.id, name: input.name, description: input.description },
        });
        for (const member of input.members) {
          const definition = definitions.find((item) => item.id === member.definitionId);
          const repository = repositories.get(member.githubAccountId);
          if (!definition || !repository) throw new Error('Validated team member is missing.');
          const instance = await createInstance(tx, created.id, userId, definition, repository);
          instances.set(definition.id, instance.botId);
        }
        for (const task of input.tasks) {
          const botId = instances.get(task.definitionId);
          if (!botId) throw new Error('Validated task assignee is missing.');
          await tx.projectTask.create({
            data: {
              userId, projectId: project.id, teamId: created.id, botId,
              title: task.title, description: task.description, priority: task.priority,
            },
          });
        }
        await tx.auditEvent.create({
          data: {
            userId, action: 'TEAM_CREATED', targetType: 'Team', targetId: created.id,
            details: { projectId: project.id, memberCount: input.members.length },
          },
        });
        return created;
      });
      return reply.status(201).send({ team });
    } catch (error) {
      uniqueConflict(error, 'TEAM_NAME_EXISTS', 'Zespół o tej nazwie już istnieje.');
    }
  });

  app.patch('/api/workspace/teams/:id', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(teamDetailsSchema, request.body);
    try {
      await prisma.$transaction(async (tx) => {
        const result = await tx.team.updateMany({ where: { id, userId }, data: input });
        if (result.count !== 1) throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono zespołu.');
        await tx.auditEvent.create({
          data: { userId, action: 'TEAM_UPDATED', targetType: 'Team', targetId: id },
        });
      });
      return { ok: true };
    } catch (error) {
      uniqueConflict(error, 'TEAM_NAME_EXISTS', 'Zespół o tej nazwie już istnieje.');
    }
  });

  app.post('/api/workspace/teams/:id/members', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(memberSchema, request.body);
    const team = await prisma.team.findFirst({
      where: { id, userId }, include: { project: true },
    });
    if (!team) throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono zespołu.');
    const project = team.project;
    if (!project?.repository) throw new ApiError(409, 'PROJECT_REPOSITORY_REQUIRED', 'Projekt musi mieć repozytorium.');
    const definition = await prisma.botDefinition.findFirst({ where: { id: input.definitionId, userId } });
    if (!definition) throw new ApiError(404, 'BOT_DEFINITION_NOT_FOUND', 'Wybierz własną definicję bota.');
    const repository = await verifyRepository({
      userId, githubAccountId: input.githubAccountId, repository: project.repository,
    });
    if (project.repositoryId && repository.repositoryId !== project.repositoryId) {
      throw new ApiError(409, 'PROJECT_REPOSITORY_CHANGED', 'Repozytorium GitHub zmieniło się od utworzenia projektu.');
    }
    const member = await prisma.$transaction(async (tx) => {
      await lockTeam(tx, id, userId);
      const members = await tx.teamBot.findMany({
        where: { teamId: id }, select: { bot: { select: { definitionId: true } } },
      });
      if (members.length >= 20) throw new ApiError(409, 'TEAM_MEMBER_LIMIT', 'Zespół może mieć maksymalnie 20 botów.');
      if (members.some((member) => member.bot.definitionId === definition.id)) {
        throw new ApiError(409, 'BOT_ALREADY_IN_TEAM', 'Ta rola jest już w zespole.');
      }
      const created = await createInstance(tx, id, userId, definition, repository);
      await tx.team.update({ where: { id }, data: { updatedAt: new Date() } });
      await tx.auditEvent.create({
        data: { userId, action: 'TEAM_INSTANCE_CREATED', targetType: 'TeamBot', targetId: created.id },
      });
      return created;
    });
    return reply.status(201).send({ member });
  });

  app.delete('/api/workspace/teams/:id/members/:memberId', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id, memberId } = parseRequest(idSchema.extend({ memberId: z.string().cuid() }), request.params);
    await prisma.$transaction(async (tx) => {
      await lockTeam(tx, id, userId);
      const member = await tx.teamBot.findFirst({
        where: { id: memberId, teamId: id }, include: { bot: { select: { status: true } } },
      });
      if (!member) throw new ApiError(404, 'TEAM_BOT_NOT_FOUND', 'Nie znaleziono członka zespołu.');
      if (member.bot.status !== 'IDLE') throw new ApiError(409, 'BOT_NOT_IDLE', 'Najpierw zakończ sesję bota.');
      const taskCount = await tx.projectTask.count({ where: { teamId: id, botId: member.botId } });
      if (taskCount) throw new ApiError(409, 'BOT_HAS_TASKS', 'Najpierw przypisz zadania innemu botowi lub je usuń.');
      await tx.teamBot.updateMany({ where: { teamId: id, parentId: memberId }, data: { parentId: null } });
      await tx.teamBot.delete({ where: { id: memberId } });
      await tx.team.update({ where: { id }, data: { updatedAt: new Date() } });
      await tx.auditEvent.create({
        data: { userId, action: 'TEAM_INSTANCE_REMOVED', targetType: 'TeamBot', targetId: memberId },
      });
    });
    return reply.status(204).send();
  });

  app.patch('/api/workspace/teams/:id/hierarchy', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(hierarchySchema, request.body);
    validateHierarchy(input.members);
    await prisma.$transaction(async (tx) => {
      const team = await tx.team.findFirst({
        where: { id, userId },
        include: { bots: { select: { id: true } } },
      });
      if (!team) throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono zespołu.');
      const ids = new Set(input.members.map((member) => member.id));
      if (team.bots.length !== ids.size || team.bots.some((member) => !ids.has(member.id))) {
        throw new ApiError(409, 'TEAM_MEMBERS_CHANGED', 'Lista musi zawierać wszystkich aktualnych członków zespołu.');
      }
      const updated = await tx.team.updateMany({
        where: { id, userId, updatedAt: new Date(input.updatedAt) },
        data: { updatedAt: new Date() },
      });
      if (updated.count !== 1) throw new ApiError(409, 'TEAM_CHANGED', 'Zespół się zmienił. Odśwież widok.');
      for (const member of input.members) {
        await tx.teamBot.update({ where: { id: member.id }, data: { parentId: member.parentId } });
      }
      await tx.auditEvent.create({
        data: { userId, action: 'TEAM_HIERARCHY_UPDATED', targetType: 'Team', targetId: id },
      });
    });
    return { ok: true };
  });

  app.post('/api/workspace/teams/:id/tasks', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(taskSchema, request.body);
    const task = await prisma.$transaction(async (tx) => {
      await lockTeam(tx, id, userId);
      const team = await tx.team.findFirst({
        where: { id, userId },
        include: { bots: { select: { botId: true } } },
      });
      if (!team) throw new ApiError(404, 'TEAM_NOT_FOUND', 'Nie znaleziono zespołu.');
      const projectId = team.projectId;
      if (!projectId) throw new ApiError(409, 'TEAM_PROJECT_REQUIRED', 'Najpierw przypisz zespół do projektu.');
      if (!team.bots.some((member) => member.botId === input.botId)) {
        throw new ApiError(400, 'BOT_NOT_IN_TEAM', 'Przypisz zadanie botowi z tego zespołu.');
      }
      const created = await tx.projectTask.create({
        data: { userId, projectId, teamId: id, ...input },
      });
      await tx.auditEvent.create({
        data: { userId, action: 'TASK_CREATED', targetType: 'ProjectTask', targetId: created.id },
      });
      return created;
    });
    return reply.status(201).send({ task });
  });

  app.patch('/api/workspace/tasks/:id', async (request) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    const input = parseRequest(taskEditSchema, request.body);
    await prisma.$transaction(async (tx) => {
      const task = await tx.projectTask.findFirst({ where: { id, userId } });
      if (!task) throw new ApiError(404, 'TASK_NOT_FOUND', 'Nie znaleziono zadania.');
      if (task.teamId) await lockTeam(tx, task.teamId, userId);
      if (input.botId) {
        const membership = task.teamId && await tx.teamBot.findFirst({
          where: { teamId: task.teamId, botId: input.botId, bot: { userId } },
        });
        if (!membership) throw new ApiError(400, 'BOT_NOT_IN_TEAM', 'Przypisz zadanie botowi z tego zespołu.');
      }
      await tx.projectTask.update({ where: { id }, data: input });
      await tx.auditEvent.create({
        data: { userId, action: 'TASK_UPDATED', targetType: 'ProjectTask', targetId: id },
      });
    });
    return { ok: true };
  });

  app.delete('/api/workspace/tasks/:id', async (request, reply) => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(idSchema, request.params);
    await prisma.$transaction(async (tx) => {
      const rows = await tx.$queryRaw<{ id: string }[]>`
        SELECT "id" FROM "ProjectTask" WHERE "id" = ${id} AND "userId" = ${userId} FOR UPDATE
      `;
      if (rows.length !== 1) throw new ApiError(404, 'TASK_NOT_FOUND', 'Nie znaleziono zadania.');
      const dependents = await tx.taskDependency.count({ where: { dependsOnTaskId: id } });
      if (dependents) throw new ApiError(409, 'TASK_HAS_DEPENDENTS', 'Inne zadania zależą od tego zadania. Najpierw zmień ich zależności.');
      await tx.taskDependency.deleteMany({ where: { taskId: id } });
      await tx.projectTask.delete({ where: { id } });
      await tx.auditEvent.create({
        data: { userId, action: 'TASK_DELETED', targetType: 'ProjectTask', targetId: id },
      });
    });
    return reply.status(204).send();
  });
}
