# Zadania projektu

Statusy: `DONE`, `IN_PROGRESS`, `BLOCKED`, `TODO`. Zadania oznaczamy jako wykonane wyłącznie po przeprowadzeniu opisanej weryfikacji.

## Faza 1 — Analiza wymagań i repozytorium

- [DONE] Sprawdzić strukturę, historię, stan Git i lokalnie dostępne narzędzia.
- [DONE] Zapisać architekturę początkową oraz ujawnić niezweryfikowane założenia o Copilocie i VPS.
- [DONE] Zbudować i przetestować reguły etapów blokujące przejścia poza wymaganymi statusami.
- [DONE] Sprawdzić publiczną specyfikację REST GitHuba pod kątem endpointu uruchamiania coding agent; nie został znaleziony.

## Faza 2 — Architektura i baza danych

- [DONE] Model Prisma dla użytkowników, bezpiecznych sesji i OAuth, kont GitHub, botów, etapów, PR, zadań, webhooków, powiadomień i audytu.
- [DONE] Migracje PostgreSQL zwalidowane i zastosowane w lokalnej bazie z nazwanym wolumenem; potwierdzono 16 tabel.
- [TODO] Testy integracyjne trwałości przejść stanów na PostgreSQL.

## Faza 3 — Backend i autoryzacja

- [DONE] API Fastify z walidacją Zod, limitowaniem żądań, kontrolą uprawnień i health checks.
- [IN_PROGRESS] OAuth z PKCE, CSRF, przechowywaniem sesji i szyfrowaniem tokenów; do rzeczywistego logowania potrzebny GitHub OAuth client.
- [DONE] Testy API/OAuth/CSRF/Codespaces Origin, test TypeScript i testy jednostkowe: 24/24 zaliczone; `GET /` przekierowuje do UI.
- [DONE] Pełne E2E rejestracji w Chromium i PostgreSQL: `201` rejestracja, `200` sesja i widoczny dashboard; konto testowe posprzątano.

## Faza 4 — Integracja GitHub i Copilot

- [DONE] Zweryfikować oficjalne publiczne OpenAPI: endpointów uruchamiania/wznawiania/monitorowania zadań coding agent nie znaleziono.
- [BLOCKED] Pozostaje potwierdzić udokumentowany oficjalny alternatywny mechanizm uruchamiania agenta; API ustawień uprawnień nie steruje zadaniami.
- [TODO] Implementować tylko obsługiwane operacje, webhooki z weryfikacją podpisu i deduplikacją.
- [TODO] Test integracyjny wymaga prawdziwej autoryzacji GitHub i repozytorium testowego.

## Faza 5 — System botów i etapów

- [DONE] API tworzenia botów z wieloma etapami oraz weryfikacją uprawnień, repozytorium i konta GitHub.
- [IN_PROGRESS] Historia audytu, PR, etapy i jawne zatwierdzanie są zapisane w PostgreSQL; trwałe retry/wznowienie pracy workerów wymaga backendu zadaniowego.
- [DONE] Zatwierdzanie etapu jest osobne od scalania PR; kolejne etapy pozostają blokowane do zatwierdzenia poprzedniego.

## Faza 6 — Flutter UI/UX

- [DONE] Flutter Web uruchomiony, dashboard z nawigacją desktop/mobile, Material 3, Riverpod i GoRouter; testy 3/3 przechodzą, analizator bez błędów.
- [DONE] Usunięto biały ekran wywołany nieprawidłowym browser locale i inicjalizacją Firebase; screenshoty Chromium potwierdziły render loginu na desktopie/mobile bez błędów konsoli.
- [DONE] Codespaces ma jeden automatyczny start przy uruchomieniu kontenera i właściwe przekierowanie root API do portu UI.
- [DONE] Fingerprintowy start/restart zachowuje jeden proces API/gateway i wolumen PostgreSQL, nie wymaga ręcznego zabijania portów.
- [IN_PROGRESS] Widoki kont GitHub, botów, etapów, PR, zdarzeń i ustawień są połączone z API; produkcyjne logowanie czeka na OAuth client.
- [TODO] Potwierdzić eksport buildu Android/Windows; iOS wymaga macOS i podpisu Apple Developer.

## Faza 7 — Powiadomienia

- [TODO] Historia zdarzeń aplikacji i rejestracja urządzeń.
- [TODO] FCM wymaga konfiguracji projektu Firebase i platformowych poświadczeń.

## Faza 8 — Testy i bezpieczeństwo

- [TODO] Testy domenowe, API, retry, webhooków i autoryzacji; przegląd bezpieczeństwa.
- [TODO] Nie deklarować testów produkcyjnych bez rzeczywistych poświadczeń i potwierdzonego środowiska.

## Faza 9 — Wdrożenie VPS

- [TODO] Docker Compose, Caddy, PostgreSQL tylko w sieci prywatnej, health checks, backup i restore.
- [BLOCKED] Przed dostępem do OVH potrzebny jest poprawny alias/hostname SSH z użytkownikiem `ubuntu` i kluczem operatora.
- [TODO] Sprawdzić system, zasoby i istniejące usługi przed jakąkolwiek zmianą; bez destrukcyjnych działań.

## Faza 10 — Kompilacja i wydanie

- [TODO] GitHub Actions dla Android APK/AAB i Windows ZIP z binariami Flutter.
- [BLOCKED] iOS IPA wymaga macOS, podpisywania i konfiguracji konta Apple Developer.

## Jawne braki

Nie znaleziono oficjalnego endpointu uruchamiania zadań coding agent. Brakuje OAuth client GitHub, konfiguracji Firebase, produkcyjnej trwałej bazy i artefaktów buildów Android/Windows/iOS. VPS jest celowo nietknięty, aby umożliwić ręczne przeniesienie projektu.

## Podgląd lokalny

- Flutter Web: `https://legendary-space-guacamole-p79p5g9j9qw6f6rvq-4173.app.github.dev/`
- Backend: port `3000`; health checks `/health/live` i `/health/ready` zweryfikowane.
- Lokalny PostgreSQL: `127.0.0.1:55433`, kontener z nazwanym wolumenem `ccc-dev-pgdata`; nie zastępuje kopii zapasowej ani bazy produkcyjnej.
- Codespaces automatycznie uruchamia `scripts/dev-up.sh` po starcie; port `4173` to UI, a `3000` to API z przekierowaniem `GET /` do UI.