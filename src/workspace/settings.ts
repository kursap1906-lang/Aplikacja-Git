import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { PrismaClient } from '../generated/prisma/client.ts';
import type { AppConfig } from '../config.ts';
import { ApiError, parseRequest } from '../http/errors.ts';
import { decryptSecret } from '../security/secrets.ts';

const catalog = [
  ['github', 'GitHub', 'AI i GitHub', 'Konta, repozytoria, komentarze i Pull Requests'],
  ['agents', 'GitHub Agents', 'AI i GitHub', 'Zdalna praca botów w repozytorium GitHub, bez lokalnego wykonawcy'],
  ['copilot', 'Copilot SDK', 'AI i GitHub', 'Metadane kont i natywny Auto; wykonawca zadań nie jest jeszcze dostępny'],
  ['openai', 'OpenAI API', 'AI i GitHub', 'Analiza materiałów i planowanie zadań'],
  ['postgres', 'PostgreSQL', 'Bazy i storage', 'Trwałe dane aplikacji i sesji'],
  ['redis', 'Redis', 'Bazy i storage', 'Kolejki i cache'],
  ['storage', 'S3 Storage', 'Bazy i storage', 'Zewnętrzny magazyn artefaktów'],
  ['docker', 'Docker', 'Serwer i CLI', 'Izolacja środowisk agentów'],
  ['node', 'Node.js', 'Serwer i CLI', 'Runtime API aplikacji; nie jest sandboxem bota'],
  ['python', 'Python', 'Serwer i CLI', 'Skrypty i obliczenia'],
  ['flutter', 'Flutter SDK', 'Serwer i CLI', 'Budowanie aplikacji web i mobile'],
  ['blender', 'Blender', 'CAD i grafika', 'Modelowanie 3D i eksport GLB'],
  ['freecad', 'FreeCAD', 'CAD i grafika', 'Modele i geometria CAD'],
  ['inkscape', 'Inkscape', 'CAD i grafika', 'SVG i ilustracje'],
  ['figma', 'Figma', 'CAD i grafika', 'Projekty UI/UX'],
  ['imagemagick', 'ImageMagick', 'CAD i grafika', 'Konwersje i miniatury'],
  ['ffmpeg', 'FFmpeg', 'CAD i grafika', 'Wideo i animacje'],
  ['playwright', 'Playwright MCP', 'MCP i Skills', 'Testy przeglądarkowe'],
  ['filesystem', 'Filesystem MCP', 'MCP i Skills', 'Ograniczony dostęp do katalogów roboczych'],
  ['context7', 'Context7 MCP', 'MCP i Skills', 'Dokumentacja bibliotek'],
  ['githubmcp', 'GitHub MCP', 'MCP i Skills', 'Narzędzia repozytoriów dla agentów'],
  ['security', 'Security Skills', 'MCP i Skills', 'Przegląd bezpieczeństwa kodu'],
  ['actions', 'GitHub Actions', 'DevOps', 'Odczyt check-runs i statusów CI w szczegółach PR'],
  ['sentry', 'Sentry', 'DevOps', 'Monitoring błędów'],
  ['cloudflare', 'Cloudflare', 'DevOps', 'DNS i wdrożenia'],
  ['slack', 'Slack', 'Powiadomienia', 'Alerty i raporty'],
  ['discord', 'Discord', 'Powiadomienia', 'Alerty zespołowe'],
  ['telegram', 'Telegram', 'Powiadomienia', 'Powiadomienia mobilne'],
  ['smtp', 'SMTP / Email', 'Powiadomienia', 'Wiadomości i raporty'],
  ['webhooks', 'Webhooki wychodzące', 'Powiadomienia', 'Własne zdarzenia HTTP'],
] as const;
const supported = new Set(['github', 'agents', 'copilot', 'openai', 'postgres', 'node', 'actions']);

export function registerWorkspaceSettings(app: FastifyInstance, options: {
  prisma: PrismaClient; config: AppConfig; encryptionKey: () => string;
  fetcher: typeof fetch;
  authenticate: (request: FastifyRequest, mutation: boolean) => Promise<string>;
}): void {
  const { prisma, config, authenticate } = options;
  app.get('/api/workspace/settings', async request => {
    const userId = await authenticate(request, false);
    const accounts = await prisma.gitHubAccount.findMany({
      where: { userId }, select: { id: true, login: true, status: true },
    });
    const active = accounts.filter(account => account.status === 'ACTIVE').length;
    return {
      integrations: catalog.map(([id, name, category, description]) => ({
        id, name, category, description, supported: supported.has(id),
        status: id === 'node' ? 'AVAILABLE'
          : id === 'postgres' ? 'CONFIGURED'
          : id === 'openai' ? (config.OPENAI_ANALYSIS_ENABLED ? 'CONFIGURED' : 'NOT_CONFIGURED')
          : id === 'github' || id === 'actions' || id === 'agents' ? (active > 0 ? 'CONFIGURED' : 'NOT_CONFIGURED')
          : id === 'copilot' ? (config.SDK_METADATA_ENABLED ? 'METADATA_ONLY' : 'NOT_CONFIGURED')
          : 'UNAVAILABLE',
        configuration: id === 'agents' ? 'Uruchamianie ręczne: Zespoły AI → zadanie → Agent GitHub. GitHub sprawdza plan Copilot i uprawnienia Agent tasks. Sprawdzenie konta nie potwierdza dostępności płatnej usługi. Kod i PR powstają na GitHub; lokalny SDK nie wykonuje zadań.'
          : id === 'github' || id === 'actions' ? 'OAuth konta użytkownika; nie wklejaj tokenów do formularzy.'
          : id === 'openai' ? 'OPENAI_ANALYSIS_ENABLED i prywatny OPENAI_API_KEY na serwerze. Limit: 1 USD/analizę i 10 USD/miesiąc globalnie.'
          : id === 'postgres' ? 'DATABASE_URL jest zarządzany przez wdrożenie. Pliki są szyfrowane w bazie; zewnętrzny S3 nie jest używany.'
          : id === 'node' ? `Wersja serwera: ${process.version}. Środowiska agentów są osobnym mechanizmem.`
          : id === 'copilot' ? 'SDK_METADATA_ENABLED włącza odczyt pakietów. Wykonywanie zadań i dostęp agentów do narzędzi nie są jeszcze gotowe.'
          : 'Adapter wykonawczy nie jest wdrożony. Nie można zapisać klucza ani udostępnić tej usługi botom. Obecność narzędzia na hoście nie oznacza integracji z agentem.',
      })),
      accounts,
      security: {
        csrf: true, encryptedSecrets: true, ownerIsolation: true,
        manualApproval: true, ciPinnedToSha: true, manualTestsPinnedToSha: true,
        previewRequired: false, agentToolAccessAvailable: false, agentExecution: 'GITHUB_HOSTED',
      },
      automation: { automaticSdkStart: false, automaticMerge: false, schedulePersistence: true },
    };
  });
  app.post('/api/workspace/settings/integrations/:id/test', async request => {
    const userId = await authenticate(request, true);
    const { id } = parseRequest(z.object({ id: z.enum(['github', 'agents', 'postgres', 'node', 'openai', 'copilot', 'actions']) }).strict(), request.params);
    let message: string;
    if (id === 'postgres') {
      await prisma.$queryRaw`SELECT 1`;
      message = 'Połączenie PostgreSQL działa.';
    } else if (id === 'node') {
      message = `Runtime API działa: ${process.version}. Nie sprawdza to wykonawcy bota.`;
    } else if (id === 'github' || id === 'actions' || id === 'agents') {
      const { accountId } = parseRequest(z.object({ accountId: z.string().cuid() }).strict(), request.body);
      const account = await prisma.gitHubAccount.findFirst({ where: { id: accountId, userId, status: 'ACTIVE' } });
      if (!account) throw new ApiError(404, 'GITHUB_ACCOUNT_NOT_AVAILABLE', 'Wybierz własne aktywne konto.');
      if (account.tokenExpiresAt && account.tokenExpiresAt <= new Date()) {
        throw new ApiError(401, 'GITHUB_REAUTH_REQUIRED', 'Token konta wygasł. Połącz konto ponownie.');
      }
      let response: Response;
      try {
        response = await options.fetcher('https://api.github.com/user', {
          headers: { accept: 'application/vnd.github+json', authorization: `Bearer ${decryptSecret(account.encryptedAccessToken, options.encryptionKey())}` },
          redirect: 'error', signal: AbortSignal.timeout(10_000),
        });
      } catch (error) {
        if (!(error instanceof TypeError) && !(error instanceof DOMException)) throw error;
        throw new ApiError(502, 'GITHUB_UNAVAILABLE', 'Nie udało się połączyć z GitHub.');
      }
      if (!response.ok) throw new ApiError(502, 'GITHUB_CONNECTION_FAILED', `GitHub zwrócił HTTP ${response.status}.`);
      const identity = z.object({ id: z.number().int(), login: z.string() }).safeParse(await response.json());
      if (!identity.success || String(identity.data.id) !== account.githubUserId) {
        throw new ApiError(502, 'GITHUB_IDENTITY_MISMATCH', 'GitHub nie potwierdził tożsamości wybranego konta.');
      }
      message = `GitHub potwierdził konto @${identity.data.login}. Dostęp do PR i CI jest sprawdzany osobno dla repozytorium.`;
    } else {
      const configured = id === 'openai' ? config.OPENAI_ANALYSIS_ENABLED : config.SDK_METADATA_ENABLED;
      if (!configured) throw new ApiError(409, 'INTEGRATION_NOT_CONFIGURED', 'Usługa jest wyłączona w konfiguracji serwera.');
      message = id === 'openai'
        ? 'Konfiguracja analizy OpenAI jest włączona. Nie wykonano płatnego wywołania ani weryfikacji salda dostawcy.'
        : 'Odczyt metadanych SDK jest włączony. Pakiet konkretnego konta sprawdzisz w Koszty i kredyty. Wykonawca zadań nie jest dostępny.';
    }
    await prisma.auditEvent.create({ data: {
      userId, action: 'INTEGRATION_CHECKED', targetType: 'Integration', targetId: id,
    } });
    return { message, checkedAt: new Date().toISOString() };
  });
}
