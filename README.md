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

Wdrożeniowy obraz i migracje zweryfikowano również z jednorazową PostgreSQL w
izolowanej sieci Docker, bez host-portów i trwałego wolumenu. Test nie zastępuje
stagingu, HTTPS ani weryfikacji OAuth na prawdziwym koncie.

## Zakres funkcji i warunki zatwierdzania

Nawigacja strony zawiera 15 ekranów zdefiniowanych w specyfikacji. Ekrany botów,
repozytoriów, etapów, pull requestów, Review Center, kont GitHub, powiadomień
i Code Center korzystają z istniejących danych API. Konto GitHub musi być
połączone, a edytor otwiera osobny, autoryzowany workspace na obecnym hostingu.

Zespoły, trwałe projekty/PDF, współpraca agentów, izolowane runner-y CI/CD,
preview PR, harmonogramy i koszty wymagają dodatkowych modeli lub usług.
Interfejs informuje o ich braku; nie zapisuje pozornie formularzy, nie pokazuje
fikcyjnych kosztów i nie udaje, że uruchomił preview.

Zatwierdzenie etapu jest zablokowane również po stronie API do czasu, aż serwer
będzie przechowywał i weryfikował zielone CI, aktualny deployment przypięty do
commit SHA, testy manualne oraz uprawnienia recenzenta. Sam status etapu lub
kliknięcie w przeglądarce nie stanowią dowodu akceptacji. Zmiany kodu nadal
publikujemy do repozytorium GitHub, a aplikacja pozostaje na obecnym hostingu.

## GitHub Copilot coding agent

GitHub udostępnia publicznie podglądowe (public preview) REST API do
uruchamiania i sprawdzania stanu zadań cloud agent:
`POST /agents/repos/{owner}/{repo}/tasks` oraz
`GET /agents/repos/{owner}/{repo}/tasks/{task_id}`. Uruchomienie wymaga planu
Copilot Business lub Enterprise oraz tokenu użytkownika. Dokumentacja dopuszcza personal access token,
OAuth App token i GitHub App user-to-server token; GitHub App installation
access token nie jest obsługiwany. Dla fine-grained PAT i GitHub App user
token wymagane jest repozytoryjne `Agent tasks: read and write` (przy samym
odczycie stanu: `read`). OAuth App i uprawnienia konkretnego konta/repozytorium
oraz reguły organizacji muszą być zweryfikowane na prawdziwym koncie; aplikacja
nie udaje sukcesu przy odpowiedzi odmownej API.

Źródła: [uruchamianie cloud agent przez API](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-via-the-api)
i [REST API agent tasks](https://docs.github.com/en/rest/agent-tasks/agent-tasks).
API jest public preview i wymaga Copilot Business lub Enterprise. Pozwala
uruchomić zadanie i odczytać jego stan/sesje, ale nie udostępnia endpointu
wznawiania, pauzowania, anulowania ani logów wykonania. W aplikacji te funkcje
nie są symulowane. Status odświeża się na żądanie użytkownika; powiadomienia
aplikacyjne zapisują się przy synchronizacji, ale push wymaga Firebase.

Do logowania potrzebne są poświadczenia GitHub i osobna zgoda na każdy
podłączany account. Nie wkładaj tokenów ani sekretów do repozytorium. Jeśli
GitHub odrzuci żądanie z powodu planu, zakresu tokenu lub reguł organizacji,
aplikacja pokazuje błąd zamiast udawać uruchomienie.

Powiadomienia push wymagają konfiguracji Firebase. iOS wymaga macOS,
certyfikatów i konta Apple Developer.

## Topologia Compose dla stagingu i produkcji

Flutter Web jest kompilowany do `mobile/build/web`, a obraz API serwuje ten
bundle razem z `/api/*` i health-checkami. Zewnętrzny, wspólny projekt Caddy
łączy się z osobnymi sieciami brzegowymi staging i production; PostgreSQL
pozostaje bez `ports` w prywatnej sieci danego projektu. Named volumes i nazwy
projektów są oddzielne. Jednorazowy kontener migracyjny wdraża zatwierdzone
migracje PostgreSQL przed uruchomieniem API. Edytor VS Code działa jako
osobny kontener i osobny checkout repozytorium; nie ma dostępu do sieci
aplikacyjnej ani poświadczeń API lub bazy danych.

Utwórz osobną GitHub OAuth App dla każdego środowiska. Ustaw:

- Production Homepage URL: `https://<PRODUCTION_DOMAIN>`
- Production Authorization callback URL: `https://<PRODUCTION_DOMAIN>/api/auth/github/callback`
- Staging Homepage URL: `https://staging.copilotcontrolcenter.com`
- Staging Authorization callback URL: `https://staging.copilotcontrolcenter.com/api/auth/github/callback`

Po zatwierdzeniu zmian kodu uruchom `python3 scripts/create-deployment-env.py`
w chronionym terminalu. Skrypt pyta o domeny i ukrywa oba OAuth Client ID/Secret
podczas wpisywania, generuje odrębne losowe hasła PostgreSQL, klucze szyfrowania
i sekrety webhooków, a następnie tworzy trzy pliki z prawami `0600`. Obecne
pliki nigdy nie są nadpisywane; skrypt odmawia pracy przy brudnym drzewie Git.
Wygenerowane pliki nie są śledzone przez Git. Skrypt nie sprawdza DNS i nie
uruchamia kontenerów. Właściciel musi dodać rekordy A/AAAA dla domeny staging
i `editor.<domena-staging>` przed uruchomieniem Caddy.
Jeśli chronione pliki `.env.staging` lub `.env.proxy` zostały utworzone przed
dodaniem edytora, dopisz do nich odpowiednio
`EDITOR_URL=https://editor.<domena-staging>/editor/` i
`EDITOR_DOMAIN=editor.<domena-staging>`. Nie umieszczaj tych plików w Git.

W plikach staging/production zachowaj różne `APP_PROXY_ALIAS`, bazy,
użytkowników, edge networks i losowe sekrety. `APP_IMAGE_TAG` jest ustawiany na
commit SHA źródła. `.env.proxy` zawiera nazwy domen i ścieżkę do aktywnego
Caddyfile. Utwórz sieci dopiero po wykonaniu backupu wymaganej konfiguracji
serwera i sprawdzeniu, że zachowano SSH.

Najpierw zbuduj Web i uruchom wyłącznie staging:

```bash
(cd mobile && flutter build web --release)
sudo docker network create ccc-staging-edge
sudo docker network create ccc-production-edge
sudo docker network create ccc-editor-edge
sudo env APP_ENV_FILE=.env.staging docker compose -p ccc-staging --env-file .env.staging up -d --build
sudo docker compose -f docker-compose.editor.yml -p ccc-staging-editor --env-file .env.staging up -d --build
```

Edytor klonuje publiczną gałąź `main` do osobnego wolumenu i tworzy lokalną
gałąź `phone-editor`. Wolumen `editor_workspace` zachowuje zmiany po odtworzeniu
kontenera; repozytorium nie jest automatycznie synchronizowane zdalnie.
Zaloguj się do Control Center i otwórz **Ustawienia → Edytor kodu**. Backend
wystawia wtedy na cztery godziny ciasteczko HttpOnly; proxy sprawdza je przy
każdym żądaniu do edytora. Nie wystawiaj portu code-server bezpośrednio ani nie
zmieniaj `--auth none` bez utrzymania kontroli dostępu Caddy.

Po dodaniu rekordów DNS dla stagingu i `editor.staging.copilotcontrolcenter.com`
uruchom Caddy z domyślnym `Caddyfile`, który kieruje staging i edytor wyłącznie
do stagingu. Sprawdź HTTPS, API, UI, rejestrację/logowanie oraz backup i restore
na osobnej bazie staging:

```bash
sudo env PROXY_ENV_FILE=.env.proxy docker compose -f docker-compose.proxy.yml -p ccc-proxy --env-file .env.proxy up -d
bash scripts/backup-postgres.sh staging
bash scripts/restore-staging-backup-test.sh backups/staging/<backup>.dump
```

Po akceptacji raportu stagingu, backupu i rollbacku uruchom prywatny produkcyjny
stack API:

```bash
sudo env APP_ENV_FILE=.env.production docker compose -p ccc-production --env-file .env.production up -d --build
```

Zmień `CADDYFILE` w `.env.proxy` na `./Caddyfile.preproduction` i odtwórz tylko
kontener proxy; konfiguracja ta obsługuje staging, ale zwraca `503` dla
production podczas uzyskiwania i weryfikacji certyfikatu:

```bash
sudo env PROXY_ENV_FILE=.env.proxy docker compose -f docker-compose.proxy.yml -p ccc-proxy --env-file .env.proxy up -d --force-recreate caddy
```

Dopiero po sprawdzeniu certyfikatu przełącz `CADDYFILE` na
`./Caddyfile.production` i ponownie odtwórz Caddy. Tylko końcowy plik routuje
ruch production do API. Nie zmieniaj firewalla bez backupowania konfiguracji
i zachowania dostępu SSH.

Po utworzeniu aplikacyjnego stacku twórz i sprawdzaj backup PostgreSQL na stagingu
poleceniami `bash scripts/backup-postgres.sh staging` i
`bash scripts/restore-staging-backup-test.sh backups/staging/<backup>.dump`.
Restore tworzy osobną bazę testową i nigdy nie nadpisuje ani nie usuwa
istniejącej bazy. Lokalne backupy trzeba skopiować do zatwierdzonego przez
właściciela, szyfrowanego storage poza VPS przed produkcją.

W każdym wdrożeniu ustaw `APP_IMAGE_TAG` na niezmienny identyfikator commita
i zachowaj poprzednie obrazy pod ich tagami. Rollback wymaga przywrócenia
poprzedniego `APP_IMAGE_TAG` w `.env.production`, a następnie:

```bash
sudo env APP_ENV_FILE=.env.production docker compose -p ccc-production --env-file .env.production up -d --no-build
```

Wolumen bazy nie jest usuwany. Rollback jest bezpieczny tylko wtedy, gdy
poprzedni kod jest zgodny z już wdrożonymi migracjami. Nie cofaj migracji przez
kasowanie lub nadpisywanie bazy. Przed każdą zmianą produkcyjną wymagane są
zweryfikowany backup i sprawdzona procedura odtworzenia.

## Architektura i stan

Przeczytaj [ARCHITECTURE.md](ARCHITECTURE.md), [TASKS.md](TASKS.md) i
[PROJECT_STATUS.md](PROJECT_STATUS.md) przed wdrożeniem lub konfiguracją
zewnętrznych usług.