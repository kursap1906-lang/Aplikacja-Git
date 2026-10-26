# Copilot Control Center

Aplikacja Flutter do zarządzania kontami GitHub, botami, repozytoriami i etapami
projektu z jawną akceptacją. API Fastify przechowuje dane w PostgreSQL.

## Aktualne wydanie staging

`staging-live-20261026-2050` działa pod
`https://staging.copilotcontrolcenter.com/`. Root otwiera rzeczywisty panel
API; demonstracja jest dostępna wyłącznie pod `/demo`. Szczegółowy bieżący
status oraz jawne braki są na początku `PROJECT_STATUS.md`.

Po zapisaniu zmian w lokalnym commicie publikacja odbywa się na istniejącą
gałąź, bez wymuszania nadpisania historii:

```bash
cd /home/ubuntu/copilot-control-center
git push -u origin feature/github-agent-tasks
```

Jeżeli Git w terminalu SSH nie może zapytać o poświadczenia:

```bash
GIT_ASKPASS= SSH_ASKPASS= GIT_TERMINAL_PROMPT=1 \
  git -c core.askPass= push -u origin feature/github-agent-tasks
```

Dla zdalnego HTTPS podaj login GitHub, a jako hasło token z dostępem do
tego repozytorium i prawem zapisu kodu (nie hasło konta GitHub).
Nie wpisuj tokenu do URL, kodu, plików śledzonych ani rozmowy.
Alternatywą jest skonfigurowany klucz SSH z prawem zapisu.
Autoryzacja konta w aplikacji nie nadaje uprawnień programowi Git na VPS.
Push publikuje kod; staging wdrażany jest osobno, nie automatycznie przez Git.

## Zasoby VPS i pięć botów

Poniższe wartości są szacunkiem do planowania, nie wynikiem testu obciążenia
pięciu wykonawców. Modele Copilot/OpenAI działają u dostawców, a VPS utrzymuje
panel, bazę, procesy SDK, checkouty, zależności oraz kompilacje/testy.

| Scenariusz | CPU | RAM | Dysk SSD/NVMe |
| --- | --- | --- | --- |
| 5 skonfigurowanych botów, praca pojedynczo w kolejce | 4 vCPU | 8 GB | 100 GB |
| 5 równoległych lekkich zadań Node/Python/Go/static | 8 vCPU | 32 GB | 250 GB |
| 5 równoległych zadań z Flutter Web, przeglądarką, CI/preview | 16 vCPU | 64 GB | 500 GB |

Zalecane są stabilne CPU bez agresywnego współdzielenia, Linux x86_64, Docker
Engine i Compose, łącze 1 Gb/s oraz kopie zapasowe poza VPS. Rezerwuj co
najmniej 20% wolnego dysku, limituj logi/cache i rotuj obrazy. Swap 4–8 GB
może chronić przed krótkimi skokami pamięci, ale nie zastępuje RAM ani nie
gwarantuje ukończenia buildów. Buildy warto przenieść na osobnego runnera.

Punkt startowy dla lekkiego zadania: sandbox 1 vCPU i 2–3 GB RAM, osobny
checkout/wolumen, limity czasu/procesów/dysku; dla Fluttera lub przeglądarki
zwykle potrzeba 4–8 GB i 2 vCPU na aktywne zadanie. Wymagania zależą od
repozytorium i testów. Współbieżność musi być kontrolowana przez kolejkę;
sama zmiana parametrów VPS nie uruchomi pięciu sesji w aplikacji.

Obecny host ma 2 vCPU, około 4 GB RAM i 38 GB dysku. Służy do stagingu;
nie jest przeznaczony do pięciu równoległych buildów. Wykonawca zadań SDK
i wielobotowy test obciążenia nie są jeszcze gotowe.

Warunkiem pełnego testu end-to-end, oprócz zasobów, są: wdrożony wykonawca
SDK i sandboxy dla wybranych technologii, kontrolowana instalacja zależności,
autoryzowane konta GitHub z dostępem do repozytorium i uprawnieniami Copilot
wymaganymi przez SDK, poprawny OAuth callback, dostęp do usług dostawców,
CI/preview oraz jawne zatwierdzenie zmian przed pushem/PR. Test powinien
objąć zadanie z przeglądarki, rzeczywistą edycję i testy w sandboxie, zapis
logów/diffu, odrzucenie lub zatwierdzenie, push, PR, CI dla tego samego SHA,
izolację pięciu botów oraz zachowanie po timeout/restart/anulowaniu.
Większy VPS nie gwarantuje przejścia tych scenariuszy bez implementacji
i weryfikacji brakujących elementów. Android wymaga dodatkowo Android SDK;
buildy iOS wymagają runnera macOS i podpisywania Apple.

## Podłączanie nowego UI do backendu

Publiczne `/` otwiera panel `/workspace`. Tylko `/demo` pokazuje lokalny prototyp
opisany w `mobile/README.md`.
Panel `/workspace` używa tego samego motywu i układu, ale wymaga zweryfikowanej
sesji i pokazuje wyłącznie własne dane API. Nie oznacza to jeszcze gotowej
obsługi sesji botów. Analiza OpenAI jest osobną, jawnie włączaną funkcją.

Osobny ekran `/connect` podłącza rzeczywiste logowanie/rejestrację i autoryzację
konta GitHub. Callback `/auth/complete` wraca do tego ekranu, a nie do starego
dashboardu. Nie uruchamia agentów ani nie pokazuje przykładowych botów.
Główny interfejs korzysta z API; połączenie konta nie oznacza zakończenia
integracji wszystkich zakładek. Ekran `/workspace` podłącza:

- własne definicje botów, jawne szablony i łączenie ról;
- projekty, wspólny opis/kontekst, wszystkie zadania projektu (również starsze
  zadania bez zespołu), wersjonowane PDF oraz dowolne załączniki;
- rzeczywiste konta i repozytoria GitHub, wraz ze stronicowaniem i blokadą
  repozytoriów tylko do odczytu;
- tworzenie zespołów z wyborem konta dla każdego bota i planem tasków,
  dodawanie/odłączanie instancji, przypisania, priorytety i statusy zadań;
- edytowalny graf współpracy w podglądzie zespołu, z jawnym zapisem i kontrolą
  konfliktu wersji;
- koszty własnych analiz OpenAI, zapisywaną politykę dopłat SDK i rzeczywisty
  odczyt limitów podłączonych kont GitHub, bez uruchamiania botów;
- kalendarz rzeczywistych instancji z zapisem strefy IANA, dni ISO 1–7
  i godzin na serwerze. Widok tygodnia pokazuje wyłącznie zapisane harmonogramy,
  a nie niewysłane zmiany formularza. Nie ma jeszcze automatycznego start/stop SDK.

W kreatorze niezapisane pliki pozostają wybrane po zmianie kroku, a zapis
zespołu wymaga ich wysłania lub usunięcia z planu. Błąd odświeżenia zachowuje
ostatnie dane i otwarty formularz, pokazując jawny komunikat.
Pozostałe ekrany panelu API są oznaczone jako niepodłączone, bez danych demo.
Żaden z powyższych zapisów nie uruchamia SDK, nie wykonuje pusha ani PR.
Model i trasy `TaskRun` są przygotowane do następnego przyrostu. Do czasu
wdrożenia wykonawcy start zwraca jawne `503 SDK_EXECUTION_UNAVAILABLE`, bez
dodawania zadania do nieobsługiwanej kolejki; `workspace.sdkExecution=false`.

- Jeden projekt może mieć wiele zespołów. Repozytorium, opis zadania, kontekst
  i materiały są współdzielone przez zespoły projektu.
- `BotDefinition` przechowuje własną rolę i prompt. Dodanie roli do zespołu
  tworzy osobną instancję `Bot` z wybranym kontem GitHub. Edycja definicji nie
  zmienia promptu istniejącej instancji.
- `GET /api/workspace` zwraca własne definicje, projekty, zespoły, instancje,
  zadania z przypisaniem i priorytetem, pliki oraz harmonogramy. Nie zwraca
  tokenów GitHub ani zaszyfrowanej zawartości plików.
- `POST /api/bot-definitions` i `PATCH /api/bot-definitions/:id` zapisują role.
  Projekty tworzy się przez `POST /api/workspace/projects`, a ich opis,
  brief i kontekst edytuje przez `PATCH /api/workspace/projects/:id`.
- `POST /api/workspace/teams` tworzy zespół, jego instancje oraz opcjonalną listę
  planowanych zadań atomowo. Uprawnienia każdego konta do repozytorium są
  weryfikowane na GitHubie; nie jest to jeszcze weryfikacja dostępu do Copilot.
  Repozytorium projektu z zespołami nie może być zmienione starym endpointem.
- Członków dodaje/usuwa się przez `/api/workspace/teams/:id/members`.
  Usunięcie wymaga bezczynnego bota i wcześniejszego przepisania/usunięcia jego
  zadań. Historia instancji pozostaje w bazie. Stare API przypinania globalnych
  botów nie może współdzielić tych instancji między zespołami.
- Hierarchia używa identyfikatorów członkostw i wymaga kompletnej listy członków
  oraz aktualnego `updatedAt`. Cykle, obcy członkowie i nieaktualne wersje są
  odrzucane.
- Dowolne pliki przesyła się jako `application/octet-stream` z query
  `filename` na `/api/workspace/projects/:id/files`,
  `/api/workspace/messages/:id/files` lub `/api/workspace/revisions/:id/files`.
  Obowiązuje 10 MB na plik i 30 MB na kolekcję. Limity kolekcji są sprawdzane pod
  blokadą rodzica, również przy równoległym uploadzie. Treść jest szyfrowana
  AES-256-GCM, a pobieranie sprawdza rozmiar i SHA-256.
- Rozmowy pod `/api/workspace/bots/:id/messages` są na razie zapisanymi szkicami
  `DRAFT`: nie są wysyłane do modelu i nie produkują sztucznych odpowiedzi.
  Każda instancja ma osobną historię. Harmonogram
  `/api/workspace/bots/:id/schedule` używa strefy IANA oraz dni ISO 1–7
  (poniedziałek–niedziela); zapis nie uruchamia automatycznie bota.
- „Do poprawek” wymaga tekstowych instrukcji. Odpowiedź zawiera `transitionId`
  do dodania plików; po wznowieniu etapu nie można zmieniać tych załączników.
  Instancje z definicji są blokowane w starym endpointcie uruchamiania Agent
  Tasks API — nie wolno przedstawiać go jako wykonania przez Copilot SDK.

Migracja `20261026130000_workspace_bot_instances` jest addytywna: stare
zespoły/boty bez powiązania z projektem/definicją nadal są obsługiwane.
Przed zastosowaniem na stagingu należy wykonać zweryfikowany backup.

`npm test` obejmuje regresje API i walidację hierarchii. Oddzielny
`npm run test:workspace` wymaga zależności obu pakietów (`npm ci --ignore-scripts`
oraz `npm --prefix sdk-worker ci --ignore-scripts`), `WORKSPACE_TEST_DATABASE_URL`, wykonanych migracji
i jednorazowego PostgreSQL dostępnego wewnątrz izolowanej sieci Docker jako
`workspace-db`, z bazą `workspace_integration`. Test odmawia pracy pod innym
adresem. Używa fikcyjnych odpowiedzi GitHub, nie uruchamia agentów i sprawdza
rzeczywisty zapis, restart backendu, izolację kont, limity plików, rozmowy,
poprawki oraz harmonogramy. Testy AI korzystają wyłącznie z syntetycznych
materiałów i fikcyjnego dostawcy, bez płatnych wywołań.

### Analiza materiałów przez OpenAI

`OPENAI_ANALYSIS_ENABLED=true` oraz prywatnie ustawiony `OPENAI_API_KEY`
włączają analizę w zadaniach zapisanego zespołu. Klucz nie trafia do Fluttera,
logów ani repozytorium. Domyślnie funkcja jest wyłączona.

- `POST /api/workspace/teams/:id/analyses` wymaga sesji, CSRF i `requestKey`
  (UUID). Zwraca 202 z trwałym zadaniem; powtórzenie tego samego żądania
  zwraca istniejącą analizę, również po zmianie danych wywołanej jej wynikiem.
- Historia zespołu: `GET /api/workspace/teams/:id/analyses`. Status:
  `GET /api/workspace/analyses/:id`. Inny użytkownik nie ma do nich dostępu.
- Wykonawca obsługuje jeden job globalnie, z dzierżawą i bez ponawiania modelu.
  Jeden użytkownik może mieć jedną analizę w kolejce/wykonaniu.
- Model jest przypięty do `gpt-5.4-mini-2026-03-17`, bez automatycznego
  przełączania na droższy model. Dokładne liczenie tokenów używa tego samego
  kontekstu i schematu co generowanie. Odpowiedzi mają `store:false`.
- Przed wywołaniem baza rezerwuje do 1 USD; wydatki i pozostałe rezerwacje
  nie mogą przekroczyć 10 USD globalnie w miesiącu UTC rozpoczęcia wywołania.
  Kolejka przekraczająca granicę miesiąca przenosi rezerwację przed zapłatą.
  Limit dotyczy wyłącznie wywołań tej aplikacji, nie innych użyć tego klucza.
  Wartości są całkowitymi mikro-USD, nie zmiennoprzecinkowym saldem.
- Znane tokeny są rozliczane także po odrzuceniu wyniku. Timeout/zerwane
  połączenie lub restart po rozpoczęciu wywołania daje `UNKNOWN` i pozostawia
  rezerwację; nie wolno przedstawiać go jako kosztu zerowego ani samoczynnie
  zwalniać rezerwacji. Jest to estymacja według standardowych cen tokenów,
  nie faktura OpenAI (np. podatki nie są tu obliczane).
- Analiza obejmuje brief, kontekst, role, istniejące taski, załączniki projektu
  oraz aktualne wersje niezarchiwizowanych PDF. Obsługuje tekst/kod UTF-8,
  PDF, PNG/JPG/WebP i dokumenty Office. Nieobsługiwany format jest jawnym
  błędem, nie pominiętym załącznikiem. Przed odczytem zaszyfrowanych danych
  sprawdzane są limity: 100 materiałów, 30 MB i 1000 istniejących tasków.
- Wynik jest ściśle walidowany, może dodać do 100 tasków tylko botom tego
  zespołu. Nie usuwa/zastępuje zadań, nie zmienia ukończonych prac i nie
  uruchamia SDK. Zmiana materiałów, składu lub zadań w trakcie analizy
  blokuje zapis planu. Skanowanie repozytorium przez AI nadal jest osobnym,
  niewdrożonym zadaniem.

Migracja `20261026190000_openai_budget_queue` jest addytywna i wymaga backupu
przed wdrożeniem. Testy `npm run test:workspace` obejmują prawdziwe blokady,
równoległe limity, idempotencję, zmianę miesiąca, restart wykonawcy i rozliczenie
odrzuconych wyników w jednorazowej bazie PostgreSQL.

Administracyjny `src/ai/diagnostic.ts` wymaga istniejącego
`AI_DIAGNOSTIC_USER_ID` i jawnego
`AI_DIAGNOSTIC_CONFIRMATION=synthetic-only-up-to-1-usd`.
Przesyła wyłącznie stały syntetyczny opis, bez kodu aplikacji, repozytoriów
i prywatnych dokumentów. Powtórne uruchomienie odczytuje istniejący test zamiast
zlecać następne płatne wywołanie. `AI_DIAGNOSTIC_RUN_ONCE=true` pozwala wykonać
wyłącznie ten diagnostyczny job bez uruchamiania ogólnej kolejki.

### Koszty i kredyty

Panel `/workspace` udostępnia rzeczywistą historię własnych analiz OpenAI,
zajęte rezerwacje i nierozstrzygnięte koszty, niezależnie od kredytów GitHub.
Nie pokazuje salda klucza OpenAI ani fikcyjnego zużycia SDK.

- `GET /api/workspace/costs` zwraca wyłącznie dane zalogowanego właściciela.
- `POST /api/workspace/costs/sdk-policy` zapisuje miesięczną zgodę na dopłaty
  w całkowitych centach USD (`monthlyExtraLimitMinor`, zakres 0–1000000).
  Wymaga CSRF i `updatedAt` poprzedniej wersji (przy pierwszym zapisie `null`).
  Konflikt wersji daje 409, bez nadpisania formularza. Zero oznacza brak zgody
  na dopłaty; brak zapisanej polityki nie jest saldem zero.
- Zapis dotyczy polityki aplikacji, **nie zmienia limitów ani rozliczeń GitHub**.
  Egzekwowanie podczas wykonywania SDK pozostaje częścią niewłączonego
  wykonawcy. Wszystkie przyszłe sesje mają używać natywnego `model: "auto"`
  i subskrypcji konta przypisanego do konkretnego bota, bez fallbacku BYOK.
- `POST /api/workspace/github-accounts/:id/sdk-metadata` kolejkuje odczyt
  modeli i limitów własnego aktywnego konta. Wymaga CSRF oraz
  `SDK_METADATA_ENABLED=true`. Trwające żądanie jest ponownie wykorzystywane.
  Sam odczyt nie tworzy sesji, nie wysyła promptu ani kodu repozytorium.
- Raport `account.getQuota` dotyczy całego konta GitHub, również użycia poza
  aplikacją. Zachowuje nazwy i jednostki dostawcy. Nieznane dane nie stają się
  zerem ani nie są przeliczane na USD. Ostatni udany odczyt pozostaje widoczny
  z czasem pobrania, również gdy późniejsze odświeżenie się nie powiedzie.

Addytywna migracja `20261026203000_sdk_cost_policy` wymaga backupu przed
wdrożeniem. Opcjonalny broker metadanych działa osobno, bez socketu Dockera,
hostowych montowań, klucza OpenAI i uprawnień wykonawcy:

```bash
sudo env APP_ENV_FILE=.env.staging docker compose -p ccc-staging --env-file .env.staging --profile sdk build sdk-metadata
sudo env APP_ENV_FILE=.env.staging docker compose -p ccc-staging --env-file .env.staging --profile sdk up -d --no-build sdk-metadata
```

Broker wymaga aktualnego obrazu aplikacji/migratora, bazy i
`APP_ENCRYPTION_KEY`. API należy włączyć dopiero po sprawdzeniu zdrowia brokera.
Dzierżawa jest globalnie pojedyncza; przerwane odczyty jawnie kończą się błędem
i nie powtarzają się automatycznie. `npm run test:workspace` sprawdza zapis,
konflikty, restart, CSRF, własność, wygasanie dzierżaw i zachowanie poprzedniego
raportu w jednorazowej bazie PostgreSQL, z syntetycznym dostawcą bez inferencji.

Administracyjny `sdk-worker/src/list-models.ts` odczytuje rzeczywistą listę modeli,
jednostki cen i limity wybranego aktywnego konta (`CCC_SDK_MODELS_ACCOUNT_ID`, jawne
`CCC_SDK_MODELS_READ_ONLY=true`). Nie tworzy sesji ani nie wysyła promptów.
W `mode: empty` wywołania metadanych przekazują tożsamość jawnie przez
typowane RPC `models.list` / `models.listTokenPriceUnits` / `account.getQuota`; globalny „current
account” nie jest dowodem autoryzacji tego konta. Brak ceny pozostaje brakiem
danych, a nie darmowym modelem. Broker wymaga systemowego magazynu certyfikatów
CA (obraz runtime go zawiera; obraz migratora nie). Nie wolno wyłączać
weryfikacji TLS. Rozliczenia GitHub/Copilot są odrębne od limitu OpenAI.

### Diagnostyka prawdziwego SDK

Oddzielny pakiet `sdk-worker` przypina `@github/copilot-sdk` 1.0.26.
Zod jest jawnie przypięty do 4.6.7 i współdzielony z zależnością SDK przez
`overrides`: wbudowane przypięcie SDK do 4.3.6 obejmuje ostrzeżenie
GHSA-mrhx-c7xc-m3w5 (nadmierne zużycie pamięci podczas walidacji kolekcji).
Nie obniżaj wersji SDK w ramach automatycznej naprawy audytu npm.
Administracyjny test jest ograniczony do jawnie zatwierdzonego
`kursap1906-lang/test`. Pobiera i przypina commit repozytorium, sprawdza prawo
zapisu wybranego konta i uruchamia prawdziwą sesję SDK z jego tokenem OAuth.
Nie zapisuje tokena w argumentach poleceń, plikach repozytorium ani raporcie.

SDK działa w trybie `empty`, z oddzielnym prywatnym katalogiem, bez odziedziczonego
logowania i bez wbudowanych narzędzi/MCP. Jedno jawnie udostępnione narzędzie
tworzy diagnostyczny JSON i sprawdza go asercjami Node w oddzielnym kontenerze.
Kontener wykonawczy ma przypięty obraz, nie ma sieci, hostowych montowań,
socketu Docker, sekretów ani kodu aplikacji. Działa bez roota, z read-only rootfs,
ograniczeniami pamięci/CPU/PID i wyłącznie tymczasowym checkoutem.
Po teście sesja i kontener są zamykane, a katalog SDK usuwany.
Test nie wykonuje commita, pusha ani PR.

Po rzeczywistym wykonaniu raport zawiera identyfikator sesji, SHA commita,
liczbę wywołań narzędzia i hash zweryfikowanego pliku. Osobny skrypt `record.ts`
waliduje raport i zapisuje wynik w audycie właściwego konta; sam tekst odpowiedzi
modelu nie wystarcza do sukcesu. To test techniczny, nie gotowa usługa wykonywania
zadań: kolejka, trwałe sesje instancji i przyciski głównego UI pozostają do
podłączenia. Brak automatycznego startu lub ogólnego endpointu diagnostycznego.

```bash
cd sdk-worker
npm ci --ignore-scripts
npm run check
npm test
```

`credentials.ts` uruchamia się wyłącznie jako zaufaną operację administracyjną
z dostępem do konfiguracji backendu i sieci GitHub. Wymaga
`CCC_APPROVED_SMOKE_TEST=kursap1906-lang/test`. Wynik musi płynąć bezpośrednio
przez stdin do `smoke.ts`, nigdy do terminala ani logu. Kontener migracyjny
ma domyślnie tylko wewnętrzną sieć bazy, dlatego sam nie ma dostępu do GitHub.
Nie należy przekazywać jego środowiska do wykonawcy kodu repozytorium.

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

Ekran „Projekty i PDF” pozwala utworzyć projekt, przechowywać wersje PDF,
szyfrować pliki, wyodrębniać tekst przez `pdftotext`, przeglądać tekst i pobierać
wersje jako załączniki. Upload jest ograniczony do 10 MiB. Wymaga trwałej bazy
PostgreSQL, skonfigurowanego `APP_ENCRYPTION_KEY` i `pdftotext` (jest w obrazie
Docker). „Skanuj postęp projektu” analizuje wskazane repozytorium GitHub na
konkretnym SHA, wykrywa strukturę, technologie i markery statusu w dokumentach
postępu, zapisuje raport i dołącza najnowszy wynik do zadań Copilot tego samego
repozytorium. Etap jest szacunkiem opartym na jawnych dowodach (np. `[DONE]`,
`[IN_PROGRESS]`, `[BLOCKED]`, `[TODO]`), nie swobodną deklaracją AI; brak
dokumentów postępu daje etap „rozpoznanie”. Treści z repozytorium są przekazywane
botom wyłącznie jako niezaufane fakty, nie jako instrukcje. Skan repozytorium
jest osobną funkcją od odczytu PDF. Migracja i test end-to-end na stagingu są
jeszcze do wykonania.

Zespoły i przypisywanie botów, projektowe zadania z zależnościami oraz
projektowy dziennik/prośby o pomoc/ręczne checkpointy mają lokalną
implementację API/UI; migracje stagingowe i smoke testy są jeszcze wymagane.
Wiadomości nie są dostarczane agentom, a ręczne notatki checkpoint nie zapisują
stanu runtime ani nie wznawiają zadań. Izolowane runner-y CI/CD, preview PR,
automatyczne rozliczenia nadal wymagają implementacji. Harmonogram okien pracy
i limit zużycia z importu CSV są sprawdzane po stronie serwera przy starcie
etapu. Interfejs nie pokazuje fikcyjnych kosztów i nie udaje, że uruchomił
preview.

Zatwierdzenie etapu wymaga po stronie API zielonego CI (GitHub check-runs)
dla aktualnego commit SHA otwartego PR oraz zaliczonego testu manualnego
zapisanego dla tego samego SHA (`POST /api/pull-requests/:id/evidence`,
`GET /api/stages/:id/approval-readiness`). Preview nie jest jeszcze
wymuszane, a recenzentem jest właściciel bota. Sam status etapu lub kliknięcie
w przeglądarce nie stanowią dowodu akceptacji. Zmiany kodu nadal
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
każdym żądaniu do edytora. Caddy usuwa prefiks `/editor` przed przekazaniem
żądania do code-server. Nie wystawiaj jego portu bezpośrednio ani nie zmieniaj
`--auth none` bez utrzymania kontroli dostępu Caddy.

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