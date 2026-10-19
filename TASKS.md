# Zadania projektu

Statusy: `DONE`, `IN_PROGRESS`, `BLOCKED`, `TODO`. Zadania oznaczamy jako wykonane wyłącznie po przeprowadzeniu opisanej weryfikacji.

## Faza 1 — Analiza wymagań i repozytorium

- [DONE] Sprawdzić strukturę, historię, stan Git i lokalnie dostępne narzędzia.
- [DONE] Zapisać architekturę początkową oraz ujawnić niezweryfikowane założenia o Copilocie i VPS.
- [DONE] Zbudować i przetestować reguły etapów blokujące przejścia poza wymaganymi statusami.
- [DONE] Zweryfikować aktualną dokumentację GitHub REST Agent Tasks API, wymagane uprawnienia i ograniczenia public preview.

## Faza 2 — Architektura i baza danych

- [DONE] Model Prisma dla użytkowników, bezpiecznych sesji i OAuth, kont GitHub, botów, etapów, PR, zadań, webhooków, powiadomień i audytu.
- [DONE] Migracje PostgreSQL zwalidowane i zastosowane w lokalnej bazie z nazwanym wolumenem; potwierdzono 16 tabel.
- [TODO] Testy integracyjne trwałości przejść stanów botów na PostgreSQL.
- [DONE] Migracje Prisma i przepływ użytkownika zweryfikowane na jednorazowym PostgreSQL bez host-portów ani trwałego wolumenu; test obejmuje rejestrację, sesję, logout/unieważnienie i ponowne logowanie.

## Faza 3 — Backend i autoryzacja

- [DONE] API Fastify z walidacją Zod, limitowaniem żądań, kontrolą uprawnień i health checks.
- [DONE] OAuth z PKCE, CSRF, przechowywaniem sesji i szyfrowaniem tokenów; rzeczywiste logowanie czeka na poświadczenia właściciela.
- [DONE] Testy API/OAuth/CSRF/Codespaces Origin, TypeScript i testy jednostkowe: 32/32 zaliczone; `GET /` przekierowuje do UI.
- [DONE] Pełne E2E rejestracji w Chromium i PostgreSQL: `201` rejestracja, `200` sesja i widoczny dashboard; konto testowe posprzątano.

## Faza 4 — Integracja GitHub i Copilot

- [DONE] Zaimplementować uruchamianie zadań i pobieranie ich statusu przez GitHub Agent Tasks REST API (public preview).
- [DONE] Wiązać uruchamianie z repozytorium i kontem GitHub wybranym dla bota, zapisywać identyfikator zadania i powiadomienia oraz chronić przed duplikowaniem po niejednoznacznym timeoutie.
- [IN_PROGRESS] Prawdziwy test GitHub wymaga zgody OAuth, uprawnienia Agent tasks i planu Copilot Business/Enterprise.
- [DONE] Status jest synchronizowany na żądanie. Aktualne REST API nie udostępnia endpointów wznawiania, logów, pauzowania ani anulowania zadań.
- [TODO] Synchronizacja artefaktu PR z Agent Task do lokalnego modelu widoku PR; aktualnie aplikacja zapisuje ID i URL zadania.

## Faza 5 — System botów i etapów

- [DONE] API tworzenia botów z wieloma etapami oraz weryfikacją uprawnień, repozytorium i konta GitHub.
- [IN_PROGRESS] Historia audytu, PR, etapy i jawne zatwierdzanie są zapisane w PostgreSQL; trwałe retry/wznowienie pracy workerów wymaga backendu zadaniowego.
- [DONE] Zatwierdzanie etapu jest osobne od scalania PR; kolejne etapy pozostają blokowane do zatwierdzenia poprzedniego.

## Faza 6 — Flutter UI/UX

- [DONE] Flutter Web, dashboard z nawigacją desktop/mobile, Material 3, Riverpod i GoRouter; testy 4/4 przechodzą, analizator bez błędów, release bundle zbudowany.
- [DONE] Usunięto biały ekran wywołany nieprawidłowym browser locale i inicjalizacją Firebase; screenshoty Chromium potwierdziły render loginu na desktopie/mobile bez błędów konsoli.
- [DONE] Codespaces ma jeden automatyczny start przy uruchomieniu kontenera i właściwe przekierowanie root API do portu UI.
- [DONE] Fingerprintowy start/restart zachowuje jeden proces API/gateway i wolumen PostgreSQL, nie wymaga ręcznego zabijania portów.
- [IN_PROGRESS] Widoki kont GitHub, botów, etapów, PR, zdarzeń i ustawień są połączone z API; prawdziwy przepływ OAuth wymaga poświadczeń i weryfikacji uprawnień.
- [TODO] Potwierdzić eksport buildu Android/Windows; iOS wymaga macOS i podpisu Apple Developer.

## Faza 7 — Powiadomienia

- [IN_PROGRESS] Powiadomienia aplikacyjne zapisują się przy synchronizacji statusu zadania; automatyczny polling nie jest skonfigurowany.
- [BLOCKED] Push FCM wymaga konfiguracji projektu Firebase i platformowych poświadczeń.

## Faza 8 — Testy i bezpieczeństwo

- [DONE] Backend: 32/32 testy; TypeScript, Prisma schema, Flutter testy/analyze/build Web, `npm audit --omit=dev` i diff checks przechodzą.
- [TODO] Dodatkowe testy integracyjne z prawdziwym GitHub OAuth/Agent Tasks i PostgreSQL staging.
- [TODO] Nie deklarować testów produkcyjnych bez rzeczywistych poświadczeń i potwierdzonego środowiska.

## Faza 9 — Wdrożenie VPS

- [DONE] Docker/Compose z oficjalnych pakietów Ubuntu po backupie konfiguracji; PostgreSQL prywatny, osobne stacki, health checks, rotacja logów, migracje przed API oraz skrypty backupu i bezpiecznego test restore.
- [DONE] Wykonać tylko odczytowy preflight OVH: użytkownik `ubuntu`, Ubuntu 26.04, zasoby, usługi, porty i firewall.
- [DONE] Compose i Caddy rozdzielają staging/production, izolują PostgreSQL i kierują Flutter Web/API przez wspólny HTTPS origin; obraz aplikacji zbudowany i przetestowany lokalnie bez otwierania portów.
- [BLOCKED] Publiczny staging/HTTPS wymaga domeny staging i potwierdzonego DNS; test OAuth wymaga poświadczeń właściciela. Backup/restore staging można wykonać dopiero po uruchomieniu stacku staging. Nie uruchamiać Caddy ani nie zmieniać firewalla przed wymaganymi potwierdzeniami.

## Faza 10 — Kompilacja i wydanie

- [BLOCKED] Android APK/AAB wymaga Android SDK i konfiguracji podpisu; Windows ZIP wymaga Windows runnera/MSVC.
- [BLOCKED] iOS IPA wymaga macOS, podpisywania i konfiguracji konta Apple Developer.

## Jawne braki

Agent Tasks API jest w public preview; wymaga Copilot Business/Enterprise i tokenu użytkownika z właściwym dostępem. Wdrożenie staging/production blokują domeny/DNS, OAuth App credentials i weryfikacja uprawnień na prawdziwym koncie. Staging nie został uruchomiony, a Caddy/firewall nie zostały zmienione. Brakuje Firebase/push oraz artefaktów kompilacji Android/Windows/iOS.

## Podgląd lokalny

- Flutter Web: `https://legendary-space-guacamole-p79p5g9j9qw6f6rvq-4173.app.github.dev/`
- Backend: port `3000`; health checks `/health/live` i `/health/ready` zweryfikowane.
- Lokalny PostgreSQL: `127.0.0.1:55433`, kontener z nazwanym wolumenem `ccc-dev-pgdata`; nie zastępuje kopii zapasowej ani bazy produkcyjnej.
- Codespaces automatycznie uruchamia `scripts/dev-up.sh` po starcie; port `4173` to UI, a `3000` to API z przekierowaniem `GET /` do UI.