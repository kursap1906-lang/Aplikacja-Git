# Architektura

## Stan początkowy

Repozytorium startuje od pojedynczego README, bez aplikacji, testów ani konfiguracji wdrożenia. Node.js, npm i Docker Compose są dostępne lokalnie; Flutter nie jest zainstalowany.

## Docelowy kształt

- Klient: Flutter, Material 3, Riverpod i GoRouter; obsługiwane platformy mobilne i desktopowe.
- API: Node.js LTS, TypeScript i Fastify, z walidacją wejścia przez Zod.
- Dane: PostgreSQL przez Prisma; sekrety GitHub szyfrowane po stronie serwera.
- Praca asynchroniczna: trwałe zadania i zdarzenia w PostgreSQL, wznowienie przez worker po restarcie.
- Integracje: OAuth GitHub oraz tylko publicznie udokumentowane API. Operacje coding agent są osobną, wymienną implementacją; brak publicznego API oznacza funkcję niedostępną, nie symulację.
- Wdrożenie: Docker Compose, prywatna sieć PostgreSQL, Caddy, health checks i kopie zapasowe.

## Granice funkcjonalne

Stan etapów jest domeną aplikacji, a akceptacja etapu jest osobnym zdarzeniem od scalenia PR. Zmiana etapu na RUNNING jest odrzucana, jeśli poprzedni etap nie ma statusu APPROVED. Automatyczne scalanie do głównej gałęzi jest wykluczone.

OAuth, repozytoria i zadania muszą być zawsze przypisane do właściwego konta GitHub. Tokeny, klucze i hasła nie są przechowywane w repozytorium.

## Interfejsy integracyjne

Sprawdzono publiczny [GitHub REST API OpenAPI](https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.json) z odczytem bez autoryzacji. Dokumentuje uprawnienia coding agenta organizacji i endpoint konfiguracji cloud agenta repozytorium, ale nie zawiera endpointu do uruchamiania, wznawiania ani monitorowania jego zadania. Integracja nie może zgłaszać tych operacji jako obsługiwanych ani symulować odpowiedzi. Przed ich wdrożeniem należy potwierdzić inny oficjalny, udokumentowany mechanizm.

`CopilotProvider` powinien jawnie raportować obsługiwane możliwości; brak obsługi tworzenia zadania lub pobierania jego logów jest zwracany jako błąd capability, nie fikcyjny wynik. Standardowe endpointy GitHub do operacji na PR nie oznaczają dostępności API sterującego agentem. Webhooki są weryfikowane, deduplikowane i przypisywane do konta.

## Dostępność i wdrożenie

Środowisko deweloperskie i staging nie otrzymuje dostępu do produkcyjnych sekretów ani danych. Stan serwera OVH nie został sprawdzony: dostępny alias SSH `ovh` wskazuje na użytkownika `codespace` i host `ovh`, a nie potwierdzony serwer i użytkownika `ubuntu`. Połączenie nie zostało nawiązane.