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

Aktualna dokumentacja GitHub REST API opisuje podglądowe (public preview)
endpointy uruchamiania i sprawdzania stanu zadań Copilot cloud agent.
`CopilotProvider` używa ich dla repozytorium i konta przypisanych do właściciela
bota. Uruchomienie wymaga planu Copilot Business lub Enterprise i autoryzacji
użytkownika z uprawnieniem repozytorium `Agent tasks: read and write`;
autoryzację tokenu trzeba potwierdzić dla każdego konta i repozytorium.
Tokeny instalacyjne GitHub App nie są obsługiwane. API nie udostępnia
wznawiania, wstrzymywania, anulowania ani odczytu logów; te capabilities
pozostają wyłączone. Status i powiadomienia synchronizują się po ręcznym
sprawdzeniu zadania, nie przez webhooki ani automatyczny polling.
Odpowiedź GitHub dotycząca planu lub uprawnień jest pokazywana jako błąd,
bez pozorowania, że zadanie zostało uruchomione.

Standardowe endpointy GitHub do operacji na PR nie zastępują endpointów
coding agent. Webhooki są weryfikowane, deduplikowane i przypisywane do konta.

## Dostępność i wdrożenie

Środowisko deweloperskie i staging nie otrzymuje dostępu do produkcyjnych sekretów ani danych. Wdrożenie na OVH pozostaje niedokończone do czasu potwierdzenia oddzielnych domen/DNS staging i produkcji oraz uprawnień GitHub OAuth dla Agent Tasks API.