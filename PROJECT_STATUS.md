# Stan projektu

Ostatnia aktualizacja: 2026-10-19

## Wynik

- Punkt wyjścia: repozytorium zawierało tylko krótki `README.md` i początkowy commit.
- Dostępne lokalnie: Node.js 24.21.0, npm 11.19.0, Docker 29.8.0, Docker Compose 5.5.1 i GitHub CLI 2.100.0.
- Oficjalny Flutter 3.47.7 / Dart 3.13.5 zainstalowano poza repozytorium i użyto do uruchomienia klienta Web.
- PostgreSQL 17 działa w kontenerze `ccc-dev-db` na `127.0.0.1:55433`; dane są w lokalnym nazwanym wolumenie `ccc-dev-pgdata`.
- API Fastify działa pod portem `3000`; Flutter Web działa pod `4173`.
- Codespaces uruchamia `scripts/dev-up.sh` przez `postStartCommand`; jedynym automatycznym wyzwalaczem startu jest hook Codespaces. Zadania VS Code start/restart są ręczne.
- Port UI `4173` auto-otwiera przeglądarkę; port API `3000` ma opis API, a `GET /` przekierowuje do interfejsu.
- API i gateway nie dziedziczą deskryptora blokady startowej, więc kolejne uruchomienia nie zawieszają się na `flock`.
- `dev-up.sh` porównuje niejawny fingerprint kodu/konfiguracji i restartuje wyłącznie procesy zapisane przez aplikację; obcych usług nie zabija. Ponowny start nie wymaga `kill-port` i pozostawia po jednym API oraz gateway.
- Flutter Web kieruje API na bieżący origin. Same-origin na różnych portach działa, a obce originy nadal są blokowane.
- Repozytorium zawiera zmiany implementacyjne; końcowy stan Git nie został jeszcze zacommitowany.
- Alias SSH `ovh` wskazuje na użytkownika `codespace` i host `ovh`. VPS nie był sprawdzany ani modyfikowany, zgodnie z poleceniem przeniesienia aplikacji ręcznie.
- Oficjalna specyfikacja REST potwierdza endpointy ustawień uprawnień coding agenta i konfiguracji cloud agent, ale nie udostępnia endpointu uruchamiania, wznawiania ani monitorowania zadań.

## Ukończone i weryfikacja

- Analiza początkowego repozytorium, narzędzi, skonfigurowanego aliasu SSH i publicznego zakresu REST GitHuba.
- Backend TypeScript/Fastify: `npm exec -- tsc --noEmit`, bez błędów; `npm test`, 24/24 testy zaliczone, w tym preflight Codespaces, rejestracja, Origin/CSRF i odrzucenie obcego hosta.
- Flutter: `flutter test`, 4/4 testy zaliczone; `flutter analyze`, bez uwag.
- Schemat Prisma poprawnie zwalidowany, klient wygenerowany, 3 lokalne migracje zastosowane w bazie z nazwanym wolumenem i 16 tabel potwierdzonych przez PostgreSQL.
- Lokalne health-checki API zwracają HTTP 200, baza jest gotowa, preflight CORS dla portu UI zwraca 204.
- Flutter Web i bootstrap asset zwracają HTTP 200; aplikacja została otwarta w domyślnej przeglądarce. Sprawdzenie po restarcie: UI `4173` HTTP 200, API `3000/` HTTP 302 do UI, `/health/ready` HTTP 200 z połączeniem PostgreSQL.
- Naprawiono biały ekran Flutter Web: locale przeglądarki `en-US@posix` było normalizowane do prawidłowego BCP 47 przed bootstrapem; web nie uruchamia niezainicjalizowanego Firebase przed `runApp`. Chromium potwierdził ekran logowania na desktopie `1440×900` i telefonie `390×844`, bez błędów JavaScript. Gateway nie cache'uje stabilnych nazw plików startowych, a autostart wykrywa zmiany `mobile/web`.
- Skrypt `scripts/dev-up.sh` uruchomiono ponownie po naprawie dziedziczenia locka; migracje pozostały aktualne, ponowny start był idempotentny i nie pozostawił procesów oczekujących.
- Browser E2E rejestracji na prawdziwym PostgreSQL: rejestracja `201`, automatyczna sesja `200`, dashboard widoczny i czysta konsola. Tymczasowe konto, sesję i wpis audytu posprzątano.
- GitHub REST API nie udostępnia w sprawdzonej specyfikacji uruchamiania zadań Copilot coding agent; aplikacja wyłącza tę funkcję jawnie, bez atrap.
- Browser i native OAuth używają PKCE, stanu `state` i krótkotrwałej, jednorazowej wymiany bearer session; testy weryfikują odrzucenie nieprawidłowego `state`.
- Bez prawdziwego GitHub OAuth clienta autoryzacja zwraca HTTP 503; konta, boty i PR wymagają skonfigurowania OAuth i logowania.
- Faza 1 zapisana commitem `ddbd45e`.
- GitHub OAuth, Firebase, trwałe środowisko deweloperskie, buildy platform i wdrożenie pozostają nieukończone.

## Następne kroki

1. Aby aktywować logowanie, utworzyć GitHub OAuth App i skonfigurować `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, adres callback oraz stabilny `APP_ENCRYPTION_KEY`.
2. Skonfigurować Firebase przed testami dostarczania push i przeglądarkowe uprawnienia połączenia z GitHub.
3. Rozstrzygnąć wspierany przez GitHub sposób uruchamiania coding agenta; do tego czasu UI/API poprawnie pokazują tę funkcję jako niedostępną.
4. Po przeniesieniu na serwer skonfigurować kopie bezpieczeństwa, HTTPS i produkcyjne sekrety; lokalny wolumen deweloperski nie zastępuje kopii zapasowej.