# Stan projektu

Ostatnia aktualizacja: 2026-10-26

## Wydanie `staging-agents-20261026-r2`

- Naprawiono czarne podpisy kafelków w ciemnym motywie i zwiększono kontrast
  podpisów/etykiet. Dodano regresję dla kolorów tekstu.
- Analiza AI zapisuje małe, szczegółowe zadania: kroki, kryteria, weryfikację
  i rzeczywiste zależności; kolejne zadania jednego bota są sekwencyjne.
- Podgląd botów pokazuje całą ekipę, etapy, postęp i stałe gałęzie; dialog
  agenta pokazuje metadane sesji, prompt i powiązany PR. Polling nie uruchamia zadań.
- Jedna gałąź na bota (`head_ref`); kolejny etap blokuje otwarty poprzedni PR.
  Historia powiązań PR nie jest przepisywana. API blokuje ręczne obejście review.
- Kontynuacja `@copilot` w tym samym PR wymaga jawnego wysłania. Publiczne API
  GitHuba nie zapewnia pełnej rozmowy ani automatycznego odpowiadania na pytania.
  Dostęp do samego wykonania zależy od planu/uprawnień konta, nie testowano
  rzeczywistych uruchomień użytkownika.
- Backend: 75/75 testów; PostgreSQL: 4/4 scenariusze na świeżej bazie,
  obejmujące szczegółowe zależności, brak duplikacji startu, blokadę otwartego
  PR oraz ponowne użycie tej samej gałęzi przez kolejny etap.
- Flutter: 31/31 celowanych testów panelu, aktywności botów, kosztów,
  zespołów i uwierzytelnienia. Analyze: 6 wcześniej istniejących informacji,
  bez błędów/ostrzeżeń. Release Web i oba obrazy Docker zbudowano poprawnie.
- Backup przed r2: `backups/staging/postgres-20261026T232411.349044094Z.dump`
  (zweryfikowane archiwum pg_restore). Brak nowej migracji względem r1.
- Wdrożono r2 pod `https://staging.copilotcontrolcenter.com/`.
  API/baza są zdrowe, 13 migracji zastosowanych. SHA-256 publicznego Web
  i lokalnego buildu: `e19c6902480bb6418732a34161eeb8191a02256f2cc65d7b8575fd74cea85215`.
  Chromium potwierdził panel, ustawienia, GitHub/PR, koszty i mobilny viewport
  bez błędów runtime. Konto smoke oraz tymczasowy swap buildowy usunięto.
- Oryginalny przykładowy zespół ma pięć botów IDLE i pięć zadań TODO
  w `kursap1906-lang/test`. Nie uruchomiono agentów ani płatnej analizy.
  Inne, utworzone przez użytkownika zespoły i zadania pozostawiono bez zmian.

## Wcześniejsze wydanie `staging-agents-20261026-r1`

- Przywrócono pulpit z kafelkami. Dodano rzeczywisty widok GitHub/PR:
  wybór konta/repozytorium, listę z paginacją, diff, CI dla SHA, komentarze,
  tworzenie draft PR oraz powiązanie PR z etapem i przejście do review.
- Dodano szablon BuildApp: pięć ról/instancji i pięć zadań z zależnościami
  dla aplikacji budowlanej web/mobile. Zapis jest atomowy i idempotentny.
- Boty zespołowe korzystają z GitHub Agent Tasks API, nie lokalnego SDK.
  Usunięto błędną blokadę startu ról. UI wymaga jawnego startu, odczytuje
  status i zachowuje historię; API sprawdza właściciela, zależności,
  harmonogram instancji oraz istniejące bramki etapów i kosztów.
  Nie uruchamiano rzeczywistych botów. GitHub wymaga planu Business/Enterprise
  i odpowiednich uprawnień użytkownika; dostęp konkretnego konta do płatnej
  usługi nie został potwierdzony testem wykonania.
- Koszty mają oddzielne pierścienie i paski każdego konta/pakietu.
  Ustawienia ponownie zawierają katalog integracji, kategorie, konta,
  serwer/MCP, automatyzacje i bezpieczeństwo. Niezaimplementowane adaptery
  są jawnie niedostępne, a ich klucze nie są zbierane.
- Dodano trzynastą migrację: powiązanie ProjectTask ze Stage.
  Backup przed migracją:
  `backups/staging/postgres-20261026T222708.033787360Z.dump`;
  odtworzenie sprawdzono w izolowanej bazie `ccc_restore_20261026222739`.
- Walidacja: 75/75 testów backendu, 4/4 integracyjne scenariusze na świeżej
  bazie z 13 migracjami, nowe testy widoków i regresje kosztów/logowania.
  Pełny wcześniejszy zestaw Fluttera 123/123 przeszedł przed końcowym
  dopięciem review; późniejsze testy celowane 19/19 przeszły.
  Flutter analyze: tylko 6 istniejących informacji; release Web zbudowany.
  Próba równoległej walidacji przekroczyła RAM hosta; TypeScript i testy
  PostgreSQL ponowiono osobno ze świeżą bazą i przeszły. Nie ukryto awarii
  przez zwiększanie timeoutów transakcji.
- Nie potwierdzono zgodności wizualnej 1:1 z obrazami 1–5.
  Nie wdrożono wszystkich adapterów z katalogu, lokalnego
  wykonawcy SDK, automatycznych harmonogramów ani izolowanego preview.

## Poprzedni stan stagingu — wydanie `staging-live-20261026-2050`

Ta sekcja zastępuje starsze opisy wdrożenia i ograniczeń poniżej; pozostałe
sekcje są historią prac, nie bieżącym raportem.

- Strona główna `https://staging.copilotcontrolcenter.com/` otwiera teraz
  uwierzytelniony panel `/workspace`, nie demo. Demo pozostało wyłącznie pod
  `/demo`. Potwierdzono w przeglądarce logowanie i panel danych z API.
- Wdrożono aktualne pliki z VPS: nowe UI, role/instancje botów, współdzielone
  projekty, zespoły, zadania, materiały/PDF, hierarchię, zapis harmonogramów,
  analizę OpenAI i koszty/metadane kont. Nie są to dane demonstracyjne.
- Kontenery API, PostgreSQL i sdk-metadata są zdrowe; publiczne
  `/health/ready` zwraca HTTP 200 z połączeniem bazy. SHA-256 publicznego
  `main.dart.js` jest identyczne z lokalnym nowym buildem.
- Świeży backup `backups/staging/postgres-20261026T204236.999569752Z.dump`
  sprawdzono przez odtworzenie do izolowanej bazy
  `ccc_restore_20261026204446` (11 migracji przed wdrożeniem).
  Następnie na stagingu zastosowano dwunastą migrację, z modelem TaskRun.
- Walidacja: 73/73 testy backendu, 10/10 testów SDK, 4/4 integracyjne
  scenariusze na jednorazowym PostgreSQL z kompletem 12 migracji oraz
  123/123 testy Fluttera. TypeScript obu pakietów i Prisma przechodzą.
  Flutter analyze zgłasza 6 istniejących informacji lint/deprecation
  (bez błędów i ostrzeżeń); analiza z `--no-fatal-infos` i release Web
  przechodzą. Nie deklarujemy całkowicie czystego lintowania.
- Publiczny smoke HTTPS potwierdził rejestrację, sesję, zapis własnej roli,
  jej trwałość po wylogowaniu/logowaniu i unieważnienie starej sesji.
  Konto testowe oraz jego dane usunięto. Nie wykonywano płatnej analizy.
- Model i API TaskRun są fundamentem, nie gotowym wykonawcą.
  `workspace.sdkExecution=false`; start zwraca jawne
  `503 SDK_EXECUTION_UNAVAILABLE` bez wpisu do nieobsługiwanej kolejki.
  Brakuje wykonawcy SDK, UI przeglądu uruchomienia, instalatora zależności,
  izolowanego CI/preview oraz testu „bot tworzy aplikację → testy → push/PR”.
  Harmonogramy nie sterują jeszcze automatycznie sesjami.
- Host ma 2 vCPU, 4 GB RAM i 38 GB dysku; nie nadaje się do pięciu
  równoległych buildów. Tymczasowy swap buildowy usunięto po wdrożeniu.
  Wybrane stare, nieaktywne tagi obrazów usunięto; bezpośrednio poprzednie
  wydanie `staging-sdk-costs-20261026-r2` zachowano do rollbacku.
  Zalecenia zasobów i kryteria pełnego E2E są w README.
- GitHub: próba zapisu bez interakcji jest blokowana brakiem poświadczeń Git.
  Samo połączenie konta GitHub w aplikacji nie konfiguruje autoryzacji Git
  użytkownika SSH. Produkcji nie zmieniano.

## Historia przyrostów

## Przyrost 2026-10-26 — projekty, skanowanie, zespoły i współpraca

- Dodano lokalną implementację projektów oraz wersjonowanych dokumentów PDF:
  dostęp właściciela, upload do 10 MiB, szyfrowanie AES-256-GCM, ekstrakcję
  tekstu przez `pdftotext`, pobieranie jako załącznik i miękkie usuwanie.
- Dodano „Skanuj postęp projektu”: analiza struktury i technologii repozytorium
  GitHub oraz markerów `[DONE]`, `[IN_PROGRESS]`, `[BLOCKED]`, `[TODO]` w
  dokumentacji postępu, zapisywana z SHA i wykrytym szacunkowym etapem.
- Do promptu Copilot trafia najnowszy skan dla repozytorium i aktualny stan
  etapów danego bota z bazy. Skan jest oznaczony jako snapshot/fakty, nie
  instrukcje; bez dokumentu postępu etap ma wartość „rozpoznanie”.
- Dodano interfejs tworzenia projektów, wgrywania i przeglądania wersji PDF oraz
  mobilny dolny pasek nawigacji z dostępem do wszystkich 15 sekcji.
- Dodano trwałe zespoły, przypisywanie botów należących do tego samego
  użytkownika oraz zadania projektowe z zależnościami. Backend odrzuca cykle
  i blokuje rozpoczęcie lub ukończenie zadania z niezakończonymi
  poprzednikami; UI pokazuje zespoły, boty i status zależności.
- Dodano projektowy dziennik wiadomości, prośby o pomoc z rozwiązywaniem oraz
  ręcznie zapisywane notatki checkpoint. Nie są to wiadomości wysyłane przez
  agenty ani checkpoint runtime'u i nie pozwalają wznowić zadania; GitHub
  Agent Tasks API nie udostępnia takiego sterowania.
- Backend: `npm test` 48/48, `tsc --noEmit`, walidacja schematu Prisma i
  `git diff --check` przechodzą. Flutter: `flutter test` 11/11 i
  `flutter analyze` bez uwag. Najnowszy release build Web został przerwany
  przez system (`dart2js` exit -9) przy ograniczonej pamięci hosta; build
  produkcyjny po zmianach UI nie jest jeszcze zweryfikowany.
- Migracja nie została zastosowana na stagingu, a staging nie zawiera tego
  przyrostu. Przed wdrożeniem wymagane są świeży backup i test odtworzenia.
  Produkcja nie była zmieniana. Świeży backup stagingu został wykonany i
  zweryfikowany testem odtworzenia do izolowanej bazy:
  `backups/staging/postgres-20261026T111644.201227208Z.dump`. Dodano lokalnie
  (migracja `20261026120000_schedules_costs_evidence`, jeszcze nie na stagingu):
  harmonogram okien pracy blokujący start etapu, import kosztów z CSV z limitem
  zużycia oraz zatwierdzanie etapu po zweryfikowanym przez serwer CI (GitHub
  check-runs dla aktualnego SHA) i zaliczonym teście manualnym przypiętym do SHA.
  Brak: izolowane preview (nie jest wymuszane), automatyczne rozliczenia,
  współpraca agent-agent i checkpointy runtime. Budowa obrazu
  Docker jest zablokowana brakiem dostępu użytkownika do `/var/run/docker.sock`.
- Zmiany pozostają niezacommitowane. Nie wykonano push; pełna zgodność z PDF
  nie jest jeszcze osiągnięta.

## Wynik

- Punkt wyjścia: repozytorium zawierało tylko krótki `README.md` i początkowy commit.
- Narzędzia na VPS: Node.js 24.22.0 i Flutter 3.47.7 zainstalowane w katalogu użytkownika; Docker Engine 29.1.3 i Compose 2.40.3 z oficjalnych pakietów Ubuntu.
- Flutter 3.47.7 / Dart 3.13.5 zweryfikowano z oficjalnego manifestu; release build Web został wykonany na serwerze.
- Na OVH potwierdzono Ubuntu 26.04, użytkownika `ubuntu`, SSH na porcie 22, wolne porty 80/443 i nieaktywny UFW. Docker Engine został zainstalowany po backupie konfiguracji systemowej; dostęp SSH zachowano.
- Na serwerze działa staging: API, PostgreSQL z nazwanym wolumenem, Caddy i izolowany edytor. Produkcji nie wdrażano; reguł firewalla nie zmieniano, dostęp SSH zachowano.
- Repozytorium sprawdzono na commicie `29963081e95c4e6e7ed4c1a412aea2c4ea0d4e4f` z `main`; poprawki funkcjonalne rozwijane są na branchu `feature/github-agent-tasks`.
- Dokumentacja GitHub z 2026-10-19 opisuje public preview Agent Tasks API: start i odczyt stanu/sesji. Wymaga planu Copilot Business/Enterprise; akceptuje user-to-server tokeny, nie tokeny instalacyjne GitHub App. Tokeny fine-grained wymagają repozytoryjnego `Agent tasks`; prawdziwe OAuth/API nie było testowane.

## Ukończone i weryfikacja

- Analiza początkowego repozytorium, narzędzi, skonfigurowanego aliasu SSH i publicznego zakresu REST GitHuba.
- Backend TypeScript/Fastify: `npm exec -- tsc --noEmit`, bez błędów; pierwotny baseline miał 37/37 testów. Przyrost projektów/PDF i skanowania zwiększył zestaw do 43/43, zespołów i DAG zadań do 46/46, a współpracy projektowej do 48/48.
- Flutter: aktualny zestaw 11/11 testów zaliczony i `flutter analyze` bez uwag. Poprzedni release build Web przeszedł przed ostatnim przyrostem zespołów, zadań i współpracy; ponowny build po tych zmianach został przerwany przez limit pamięci hosta.
- Nawigacja ma wszystkie 15 pozycji z PDF. Projekty/PDF, skan postępu, zespoły, zadania z zależnościami oraz dziennik/prośby o pomoc/ręczne notatki checkpoint mają lokalne API/UI. Współpraca agent-agent, CI/CD/preview, harmonogramy i rozliczenia nadal są brakami.
- Zatwierdzenie etapu jest dozwolone tylko, gdy serwer potwierdzi zielone CI dla aktualnego SHA PR i zaliczony test manualny przypięty do tego SHA. Preview i osobne uprawnienia recenzenta nie są jeszcze wymuszane (właściciel bota jest jedynym recenzentem).
- Commit `1857a47` wdrożono na istniejącym hostingu staging. Strona i `/health/ready` zwracają HTTP 200; kontenery API, PostgreSQL i Caddy są zdrowe. Edytor code-server działa na prywatnej sieci; jego upstream zwraca HTTP 200, a publiczny URL bez sesji HTTP 401. Caddy poprawnie uzyskał certyfikat TLS dla domeny edytora.
- Logowanie akceptuje istniejące hasła krótsze niż minimalne 12 znaków wymagane przy rejestracji; poprawka wdrożona na stagingu jako `c112795`.
- Backup stagingu `backups/staging/postgres-20261023T075448.114430245Z.dump` zweryfikowano i odtworzono do osobnej bazy `ccc_restore_20261023075822` (3 migracje); istniejąca baza nie była nadpisywana.
- Push na GitHub jest jeszcze zablokowany przez brak uwierzytelnienia Git w środowisku. Produkcja nie była zmieniana.
- Schemat Prisma poprawnie zwalidowany, klient wygenerowany, 3 lokalne migracje zastosowane w bazie z nazwanym wolumenem i 16 tabel potwierdzonych przez PostgreSQL.
- Lokalne health-checki API zwracają HTTP 200, baza jest gotowa, preflight CORS dla portu UI zwraca 204.
- Flutter Web i bootstrap asset zwracają HTTP 200; aplikacja została otwarta w domyślnej przeglądarce. Sprawdzenie po restarcie: UI `4173` HTTP 200, API `3000/` HTTP 302 do UI, `/health/ready` HTTP 200 z połączeniem PostgreSQL.
- Naprawiono biały ekran Flutter Web: locale przeglądarki `en-US@posix` było normalizowane do prawidłowego BCP 47 przed bootstrapem; web nie uruchamia niezainicjalizowanego Firebase przed `runApp`. Chromium potwierdził ekran logowania na desktopie `1440×900` i telefonie `390×844`, bez błędów JavaScript. Gateway nie cache'uje stabilnych nazw plików startowych, a autostart wykrywa zmiany `mobile/web`.
- Skrypt `scripts/dev-up.sh` uruchomiono ponownie po naprawie dziedziczenia locka; migracje pozostały aktualne, ponowny start był idempotentny i nie pozostawił procesów oczekujących.
- Browser E2E rejestracji na prawdziwym PostgreSQL: rejestracja `201`, automatyczna sesja `200`, dashboard widoczny i czysta konsola. Tymczasowe konto, sesję i wpis audytu posprzątano.
- Backend uruchamia zadania przez GitHub Agent Tasks API, zachowując izolację kont, identyfikatory zadań, audyt i powiadomienia przy ręcznej synchronizacji statusu.
- Browser i native OAuth używają PKCE, stanu `state` i krótkotrwałej, jednorazowej wymiany bearer session; testy weryfikują odrzucenie nieprawidłowego `state`.
- Bez prawdziwego GitHub OAuth clienta autoryzacja zwraca HTTP 503; konta, boty i PR wymagają skonfigurowania OAuth i logowania.
- `npm audit --omit=dev` zgłasza zero podatności; produkcyjny obraz Docker został zbudowany z OpenSSL dla Prisma i bundla Flutter Web. Izolowany test HTTP potwierdził stronę Flutter, health liveness i 404 API; test nie opublikował portów na hoście.
- Compose staging, production i proxy przechodzą walidację; wszystkie trzy Caddyfile są poprawne. Staging i production mają osobne sieci edge oraz sieci PostgreSQL bez publicznego portu. `Caddyfile` udostępnia tylko staging; preproduction odpowiada `503` na domenie production do czasu weryfikacji TLS; dopiero `Caddyfile.production` kieruje tam ruch.
- Dodano jednorazowy migrator, skrypty backupu i odtworzenia na nowej, osobnej bazie staging oraz generator plików środowiskowych, który wymaga terminala, ukrywa OAuth Client ID/Secret, generuje odrębne sekrety, ustawia tryb `0600` i odmawia nadpisywania plików.
- Dodatkowy izolowany smoke test użył tymczasowej PostgreSQL bez mapowania portów i trwałego wolumenu: migracje, gotowość API, Flutter Web/API, rejestracja, sesja, logout/unieważnienie i ponowne logowanie zakończyły się oczekiwanymi wynikami; tymczasowe zasoby testu usunięto.
- Backup przed instalacją Dockera zachowano w `/home/ubuntu/.copilot-backups/pre-docker-20261019/`.
- Faza 1 zapisana commitem `ddbd45e`.
- GitHub OAuth, Firebase, trwałe środowisko deweloperskie, pozostałe backendy z PDF i buildy platform pozostają nieukończone.

## Następne kroki

1. Aby aktywować logowanie, utworzyć GitHub OAuth App i skonfigurować `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, adres callback oraz stabilny `APP_ENCRYPTION_KEY`.
2. Skonfigurować Firebase przed testami dostarczania push i przeglądarkowe uprawnienia połączenia z GitHub.
3. Skonfigurować i zweryfikować OAuth oraz uprawnienia GitHub Agent Tasks na stagingu; bez tego logowanie i funkcje konta nie są aktywne.
4. Po teście logowania i wymaganych integracji przygotować raport, backup i plan rollbacku przed ewentualną decyzją o wdrożeniu produkcji.
5. Android wymaga SDK i konfiguracji podpisu, Windows wymaga Windows runnera, iOS wymaga macOS/Xcode i konta Apple Developer; obecnie nie zbudowano tych binariów.