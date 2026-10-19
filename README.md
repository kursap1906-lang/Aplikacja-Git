# Copilot Control Center

Aplikacja Flutter do zarządzania kontami GitHub, botami, repozytoriami i etapami
projektu z jawną akceptacją. API Fastify przechowuje dane w PostgreSQL.

## Codespaces

Po uruchomieniu Codespace projekt automatycznie startuje backend, lokalną bazę
PostgreSQL, migracje i Flutter Web. Interfejs jest na porcie `4173`, a API na
porcie `3000`. Otwieraj oznaczony `Control Center (UI + API)` URL z portu `4173`;
otwarcie portu API `3000` przekierowuje do interfejsu.

```bash
bash scripts/dev-up.sh       # bezpieczny, idempotentny start
bash scripts/dev-restart.sh  # sprawdza zmiany i restartuje tylko własne, nieaktualne procesy
```

Flutter Web wywołuje API względnie na bieżącym originie, a API przekazuje
rejestrację wyłącznie dla skonfigurowanego originu aplikacji lub same-origin.
Obcy origin nadal jest odrzucany. Skrypt startowy zapisuje niejawne fingerprinty
kodu i konfiguracji; jeśli port zajmuje proces spoza projektu, nie zabija go ani
nie wymaga `kill-port`, tylko zgłasza konflikt.

Diagnostyka startu: `.run-start.log`, `.run/api.log` i `.run/gateway.log`.
Automatyczny start jest skonfigurowany przez `postStartCommand` w
`.devcontainer/devcontainer.json`; VS Code zawiera również ręczne zadania startu
i restartu.

Kontener PostgreSQL używa nazwanego wolumenu Docker `ccc-dev-pgdata`. Jest to
lokalne środowisko deweloperskie, nie kopia zapasowa ani baza produkcyjna.

## Logowanie GitHub

Aby aktywować OAuth, utwórz GitHub OAuth App z callbackiem
`<URL-Codespaces-4173>/api/auth/github/callback`, a następnie dodaj
`GITHUB_CLIENT_ID` i `GITHUB_CLIENT_SECRET` do lokalnego `.env`. Zachowaj
wygenerowany przez start klucz `APP_ENCRYPTION_KEY` przy restartach; bez tych
poświadczeń logowanie poprawnie zwraca informację, że wymaga konfiguracji.
Nie umieszczaj sekretów w repozytorium.

## Lokalna weryfikacja

Wymagane: Node.js 22 lub nowszy, Docker z działającym daemonem oraz Flutter SDK
3.47.7 (w Codespaces instalowany poza repozytorium przez skrypt startowy).

```bash
npm ci
npm test
npm exec -- tsc --noEmit
(cd mobile && flutter test && flutter analyze)
```

E2E rejestracji zostało zweryfikowane w Chromium z lokalnym PostgreSQL:
`201` dla utworzenia konta, `200` dla nowej sesji i widoczny dashboard.
Testowe konto, sesje i wpisy audytu usunięto po teście.

## Ograniczenia

Sprawdzona oficjalna specyfikacja GitHub REST API nie zawiera endpointu
uruchamiania zadań Copilot coding agent. Aplikacja nie symuluje tej funkcji;
przedstawia ją jako niedostępną. Faktyczne logowanie wymaga skonfigurowanych
sekretów OAuth GitHub. Powiadomienia push wymagają Firebase. iOS wymaga macOS,
certyfikatów i konta Apple Developer.

## Architektura i stan

Przeczytaj [ARCHITECTURE.md](ARCHITECTURE.md), [TASKS.md](TASKS.md) i
[PROJECT_STATUS.md](PROJECT_STATUS.md) przed wdrożeniem lub konfiguracją
zewnętrznych usług.