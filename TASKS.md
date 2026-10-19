# Zadania projektu

Statusy: `DONE`, `IN_PROGRESS`, `BLOCKED`, `TODO`. Zadania oznaczamy jako wykonane wyłącznie po przeprowadzeniu opisanej weryfikacji.

## Faza 1 — Analiza wymagań i repozytorium

- [DONE] Sprawdzić strukturę, historię, stan Git i lokalnie dostępne narzędzia.
- [DONE] Zapisać architekturę początkową oraz ujawnić niezweryfikowane założenia o Copilocie i VPS.
- [DONE] Zbudować i przetestować reguły etapów blokujące przejścia poza wymaganymi statusami.
- [DONE] Sprawdzić publiczną specyfikację REST GitHuba pod kątem endpointu uruchamiania coding agent; nie został znaleziony.

## Faza 2 — Architektura i baza danych

- [TODO] Model Prisma dla użytkowników, kont GitHub, botów, etapów, zdarzeń, PR, zadań i urządzeń powiadomień.
- [TODO] Migracje PostgreSQL i testy trwałości przejść między statusami.

## Faza 3 — Backend i autoryzacja

- [TODO] API Fastify z walidacją, limitowaniem żądań, uprawnieniami i health checks.
- [TODO] Bezpieczny przepływ OAuth GitHub, CSRF, ponowna autoryzacja i szyfrowanie tokenów.
- [TODO] Testy tras, autoryzacji i API.

## Faza 4 — Integracja GitHub i Copilot

- [DONE] Zweryfikować oficjalne publiczne OpenAPI: endpointów uruchamiania/wznawiania/monitorowania zadań coding agent nie znaleziono.
- [BLOCKED] Pozostaje potwierdzić udokumentowany oficjalny alternatywny mechanizm uruchamiania agenta; API ustawień uprawnień nie steruje zadaniami.
- [TODO] Implementować tylko obsługiwane operacje, webhooki z weryfikacją podpisu i deduplikacją.
- [TODO] Test integracyjny wymaga prawdziwej autoryzacji GitHub i repozytorium testowego.

## Faza 5 — System botów i etapów

- [TODO] CRUD botów, repozytoriów, promptów i uporządkowanych etapów.
- [TODO] Historia audytu, retry i trwałe wznowienie zadań po restarcie.
- [TODO] Akceptacja etapu nie scala PR i nie uruchamia następnego etapu bez jawnej akcji.

## Faza 6 — Flutter UI/UX

- [TODO] Flutter, Material 3, Riverpod i GoRouter; panel desktopowy i nawigacja mobilna po polsku.
- [TODO] Widoki kont GitHub, botów, etapów, PR, zdarzeń, diagnostyki i ustawień.
- [BLOCKED] Lokalny build Flutter wymaga zainstalowanego Flutter SDK; iOS wymaga macOS.

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

Nie potwierdzono oficjalnego endpointu publicznego dla wszystkich operacji GitHub Copilot coding agent. Nie utworzono aplikacji GitHub, OAuth client, projektu Firebase ani konta Apple. Nie sprawdzono VPS. Nie powstały artefakty buildów ani wdrożenie.