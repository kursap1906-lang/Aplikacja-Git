# Stan projektu

Ostatnia aktualizacja: 2026-10-19

## Wynik

- Punkt wyjścia: repozytorium zawierało tylko krótki `README.md` i początkowy commit.
- Narzędzia na VPS: Node.js 24.22.0 i Flutter 3.47.7 zainstalowane w katalogu użytkownika; Docker Engine 29.1.3 i Compose 2.40.3 z oficjalnych pakietów Ubuntu.
- Flutter 3.47.7 / Dart 3.13.5 zweryfikowano z oficjalnego manifestu; release build Web został wykonany na serwerze.
- Na OVH potwierdzono Ubuntu 26.04, użytkownika `ubuntu`, SSH na porcie 22, wolne porty 80/443 i nieaktywny UFW. Docker Engine został zainstalowany po backupie konfiguracji systemowej; dostęp SSH zachowano.
- Żaden stack staging/production, Caddy, kontener PostgreSQL ani wolumen wdrożeniowy nie został uruchomiony/utworzony. Aplikacja nie zajmuje portów 80/443, firewall pozostał bez zmian.
- Repozytorium sprawdzono na commicie `29963081e95c4e6e7ed4c1a412aea2c4ea0d4e4f` z `main`; poprawki funkcjonalne rozwijane są na branchu `feature/github-agent-tasks`.
- Dokumentacja GitHub z 2026-10-19 opisuje public preview Agent Tasks API: start i odczyt stanu/sesji. Wymaga planu Copilot Business/Enterprise; akceptuje user-to-server tokeny, nie tokeny instalacyjne GitHub App. Tokeny fine-grained wymagają repozytoryjnego `Agent tasks`; prawdziwe OAuth/API nie było testowane.

## Ukończone i weryfikacja

- Analiza początkowego repozytorium, narzędzi, skonfigurowanego aliasu SSH i publicznego zakresu REST GitHuba.
- Backend TypeScript/Fastify: `npm exec -- tsc --noEmit`, bez błędów; `npm test`, 32/32 testy zaliczone, w tym preflight Codespaces, rejestracja, Origin/CSRF i odrzucenie obcego hosta.
- Flutter: `flutter test`, 4/4 testy zaliczone; `flutter analyze`, bez uwag.
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
- Backup przed instalacją Dockera zachowano w `/home/ubuntu/.copilot-backups/pre-docker-20261019/`; stagingowe backup/restore nie mogły być uruchomione bez stacku i plików konfiguracyjnych.
- Faza 1 zapisana commitem `ddbd45e`.
- GitHub OAuth, Firebase, trwałe środowisko deweloperskie, buildy platform i wdrożenie pozostają nieukończone.

## Następne kroki

1. Aby aktywować logowanie, utworzyć GitHub OAuth App i skonfigurować `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, adres callback oraz stabilny `APP_ENCRYPTION_KEY`.
2. Skonfigurować Firebase przed testami dostarczania push i przeglądarkowe uprawnienia połączenia z GitHub.
3. Potwierdzić dwa osobne hosty i DNS oraz uprawnienia OAuth/Agent tasks przed stagingiem i wystawieniem certyfikatów.
4. Po potwierdzeniu DNS i OAuth uruchomić staging, przetestować HTTPS, API/UI/rejestrację i backup/restore; dopiero potem przygotować raport/rollback produkcji.
5. Android wymaga SDK i konfiguracji podpisu, Windows wymaga Windows runnera, iOS wymaga macOS/Xcode i konta Apple Developer; obecnie nie zbudowano tych binariów.