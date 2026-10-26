import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { PrismaClient } from '../generated/prisma/client.ts';
import type { VerifiedRepository } from '../github/repository-access.ts';
import { z } from 'zod';
import { ApiError, parseRequest } from '../http/errors.ts';

export const constructionRoles = [
  { name: 'BuildApp · Tech Lead', role: 'Architekt i koordynator', skills: ['Architecture', 'Planning', 'Review'],
    description: 'Plan produktu budowlanego, architektura web/mobile, podział pracy i przegląd zmian.',
    task: 'Zaprojektuj MVP: projekty budowlane, zadania ekip, kalkulator materiałów i raporty; przygotuj kontrakt API.',
    prompt: 'Koordynujesz pięcioosobowy zespół aplikacji dla ekip budowlanych. Opracuj architekturę web/mobile, kontrakty API, małe zadania i kryteria akceptacji. Nie zatwierdzaj własnych zmian ani nie scalaj PR. Wymagaj testów i dowodów dla tego samego SHA.' },
  { name: 'BuildApp · Web UX', role: 'Frontend web i UX', skills: ['TypeScript', 'React', 'Accessibility'],
    description: 'Responsywny panel ekip, listy zadań, formularze pomiarów i dostępność.',
    task: 'Przygotuj responsywne widoki projektów, zadań ekip i pomiarów wraz z testami UI.',
    prompt: 'Tworzysz frontend aplikacji budowlanej. Dbaj o prostą obsługę na budowie, kontrast, duże cele dotykowe i walidację jednostek. Uzgadniaj API z backendem, pokazuj błędy jawnie, nie podstawiaj danych demo za dane serwera. Dodawaj testy.' },
  { name: 'BuildApp · Mobile', role: 'Flutter i aplikacja mobilna', skills: ['Flutter', 'Dart', 'Offline'],
    description: 'Mobilne listy zadań, dokumentacja zdjęciowa i bezpieczna synchronizacja.',
    task: 'Przygotuj szkielet Flutter z projektami i zadaniami oraz projektem synchronizacji offline.',
    prompt: 'Tworzysz aplikację Flutter dla ekip budowlanych. Projektuj jawne stany offline/synchronizacji, uprawnienia zdjęć i dostępność. Zachowuj niezapisane dane, nie raportuj sukcesu niepotwierdzonego przez API. Testuj widgety i logikę.' },
  { name: 'BuildApp · Backend', role: 'Backend, dane i kalkulatory', skills: ['Node.js', 'PostgreSQL', 'API'],
    description: 'API projektów i ekip, uprawnienia, migracje oraz sprawdzalne kalkulatory materiałów.',
    task: 'Zaimplementuj API projektów i zadań z autoryzacją oraz testowany kalkulator ilości materiałów.',
    prompt: 'Tworzysz backend aplikacji budowlanej. Egzekwuj izolację użytkowników i ekip, walidację, migracje i logowanie błędów. Kalkulatory muszą mieć testy jednostek, tolerancji i zaokrągleń; nie przedstawiaj ich jako certyfikowanych obliczeń konstrukcyjnych. Uzgadniaj kontrakt z web/mobile.' },
  { name: 'BuildApp · QA DevOps', role: 'Testy, CI i wdrożenie', skills: ['Testing', 'Playwright', 'CI/CD'],
    description: 'Testy API/web/mobile, CI dla SHA oraz instrukcja wdrożenia i rollbacku.',
    task: 'Zdefiniuj scenariusze testów MVP, CI i kryteria akceptacji z dowodami dla commita.',
    prompt: 'Odpowiadasz za jakość i wdrożenie aplikacji budowlanej. Testuj API, izolację kont, web/mobile, błędy i offline. Zbieraj rzeczywiste wyniki testów przypięte do SHA. Brak testu nie oznacza sukcesu. Nie wdrażaj ani nie scalaj bez zgody właściciela.' },
] as const;

export function registerConstructionTemplate(app: FastifyInstance, options: {
  prisma: PrismaClient;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
  verifyRepository: (input: { userId: string; githubAccountId: string; repository: string }) => Promise<VerifiedRepository>;
}): void {
  app.post('/api/workspace/templates/construction', async (request, reply) => {
    const userId = await options.authenticate(request, true);
    const input = parseRequest(z.object({
      githubAccountId: z.string().cuid(), repository: z.string().regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/),
    }).strict(), request.body);
    const repository = await options.verifyRepository({ userId, ...input });
    const result = await createConstructionTeam(options.prisma, userId, repository);
    return reply.status(result.created ? 201 : 200).send(result);
  });
}

export async function createConstructionTeam(prisma: PrismaClient, userId: string, repository: VerifiedRepository) {
    return prisma.$transaction(async tx => {
      await tx.$queryRaw`SELECT "id" FROM "User" WHERE "id" = ${userId} FOR UPDATE`;
      const name = `BuildApp · ${repository.repository}`;
      const existing = await tx.team.findUnique({ where: { userId_name: { userId, name } } });
      if (existing) {
        const project = existing.projectId ? await tx.project.findUnique({ where: { id: existing.projectId } }) : null;
        const members = await tx.teamBot.findMany({ where: { teamId: existing.id }, include: { bot: true } });
        if (!project || project.repository !== repository.repository || members.length !== 5 ||
            members.some(member => member.bot.githubAccountId !== repository.githubAccountId)) {
          throw new ApiError(409, 'TEAM_TEMPLATE_CONFLICT', 'Istniejący zespół o tej nazwie ma inną konfigurację. Zmień jego nazwę przed dodaniem szablonu.');
        }
        return { teamId: existing.id, projectId: project.id, created: false };
      }
      const project = await tx.project.create({ data: {
        userId, name: 'Aplikacja dla budowlańców', repository: repository.repository,
        repositoryId: repository.repositoryId, defaultBranch: repository.defaultBranch,
        mainGithubAccountId: repository.githubAccountId,
        description: 'Web i mobile dla ekip budowlanych.',
        brief: 'MVP: projekty budowlane, zadania ekip, pomiary, kalkulator materiałów i raporty. Testy i ręczne review przed publikacją.',
      } });
      const team = await tx.team.create({ data: {
        userId, projectId: project.id, name,
        description: 'Pięć ról: architekt, web/UX, Flutter, backend i QA/DevOps. Utworzenie zespołu nie uruchamia agentów.',
      } });
      let leadId: string | undefined;
      const taskIds: string[] = [];
      for (const role of constructionRoles) {
        const definition = await tx.botDefinition.upsert({
          where: { userId_name: { userId, name: role.name } },
          create: { userId, name: role.name, role: role.role, description: role.description, systemPrompt: role.prompt, skills: [...role.skills] },
          update: {},
        });
        const bot = await tx.bot.create({ data: {
          userId, definitionId: definition.id, name: definition.name, systemPrompt: definition.systemPrompt, ...repository,
        } });
        const member = await tx.teamBot.create({ data: { teamId: team.id, botId: bot.id, parentId: leadId } });
        leadId ??= member.id;
        const task = await tx.projectTask.create({ data: {
          userId, projectId: project.id, teamId: team.id, botId: bot.id,
          title: role.task, description: role.description, priority: leadId === member.id ? 'HIGH' : 'NORMAL',
        } });
        taskIds.push(task.id);
        const prerequisites = taskIds.length === 5 ? taskIds.slice(0, -1) : taskIds.slice(0, 1).filter(id => id !== task.id);
        for (const dependsOnTaskId of prerequisites) {
          await tx.taskDependency.create({ data: { taskId: task.id, dependsOnTaskId } });
        }
      }
      await tx.auditEvent.create({ data: {
        userId, action: 'CONSTRUCTION_TEAM_CREATED', targetType: 'Team', targetId: team.id,
        details: { repository: repository.repository, bots: 5, executionStarted: false },
      } });
      return { teamId: team.id, projectId: project.id, created: true };
    });
}
