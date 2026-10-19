#!/usr/bin/env bash
# Idempotentny start środowiska deweloperskiego: PostgreSQL, migracje, API i UI Flutter Web.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
RUN_DIR="$ROOT/.run"
umask 077
mkdir -p "$RUN_DIR"
exec 9>"$RUN_DIR/lock"
flock 9

GATEWAY_PORT="${GATEWAY_PORT:-4173}"
API_PORT="${API_PORT:-3000}"
DB_PORT="${DB_PORT:-55433}"
DB_CONTAINER="ccc-dev-db"
FLUTTER_VERSION="3.47.7"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"

log() { printf '[dev-up] %s\n' "$*"; }

process_is_owned() {
  local pid="$1" command_hint="$2" command working_directory
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
  command="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
  working_directory="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
  [[ "$working_directory" == "$ROOT" && "$command" == *"$command_hint"* ]]
}

stop_owned_process() {
  local name="$1" pidfile="$2" command_hint="$3" pid
  [[ -f "$pidfile" ]] || return 0
  pid="$(tr -cd '0-9' <"$pidfile")"
  if ! process_is_owned "$pid" "$command_hint"; then
    rm -f "$pidfile"
    return 0
  fi

  log "Restartuję nieaktualny proces $name (PID $pid)"
  kill -TERM "$pid"
  for _ in $(seq 1 20); do
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$pidfile"
      return 0
    fi
    sleep 0.25
  done
  if process_is_owned "$pid" "$command_hint"; then
    kill -KILL "$pid"
  fi
  rm -f "$pidfile"
}

port_is_listening() {
  ss -H -ltn "sport = :$1" | grep -q .
}

if [[ -n "${CODESPACE_NAME:-}" ]]; then
  PUBLIC_URL="https://${CODESPACE_NAME}-${GATEWAY_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
else
  PUBLIC_URL="http://127.0.0.1:${GATEWAY_PORT}"
fi

# Sekrety lokalne trafiają tylko do .env (ignorowanego przez Git); istniejących wartości nie nadpisujemy.
touch .env
chmod 600 .env
ensure_env() {
  grep -q "^$1=." .env || printf '%s=%s\n' "$1" "$2" >>.env
}
ensure_env DEV_DB_PASSWORD "$(openssl rand -hex 16)"
ensure_env APP_ENCRYPTION_KEY "$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"
ensure_env GITHUB_WEBHOOK_SECRET "$(openssl rand -hex 32)"
set -a
# shellcheck disable=SC1091
source .env
set +a

# --- PostgreSQL (trwały wolumen, tylko loopback) ---
if ! docker inspect "$DB_CONTAINER" >/dev/null 2>&1; then
  log "Tworzę kontener PostgreSQL $DB_CONTAINER"
  docker run -d --name "$DB_CONTAINER" --restart unless-stopped \
    -e POSTGRES_DB=control_center -e POSTGRES_USER=control_center -e POSTGRES_PASSWORD="$DEV_DB_PASSWORD" \
    -p "127.0.0.1:${DB_PORT}:5432" -v ccc-dev-pgdata:/var/lib/postgresql/data postgres:17-alpine >/dev/null
elif [[ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER")" != "true" ]]; then
  log "Uruchamiam kontener $DB_CONTAINER"
  docker start "$DB_CONTAINER" >/dev/null
fi
for _ in $(seq 1 40); do
  docker exec "$DB_CONTAINER" pg_isready -U control_center -d control_center >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$DB_CONTAINER" pg_isready -U control_center -d control_center >/dev/null

export DATABASE_URL="postgresql://control_center:${DEV_DB_PASSWORD}@127.0.0.1:${DB_PORT}/control_center?schema=public"
export NODE_ENV=development HOST=127.0.0.1 PORT="$API_PORT"
export APP_ORIGIN="$PUBLIC_URL" PUBLIC_API_URL="$PUBLIC_URL"

# --- Zależności, klient Prisma, migracje ---
if [[ ! -d node_modules || package-lock.json -nt node_modules/.package-lock.json ]]; then
  log "npm ci"
  npm ci --no-audit --no-fund
fi
npx prisma generate >/dev/null
npx prisma migrate deploy

# --- API ---
API_FINGERPRINT_FILE="$RUN_DIR/api.fingerprint"
API_FINGERPRINT="$({
  find src -type f -name '*.ts' -print0 | sort -z | xargs -0 sha256sum
  sha256sum package.json package-lock.json prisma/schema.prisma prisma.config.ts
  printf '%s\0' "$APP_ORIGIN" "$PUBLIC_API_URL" "$API_PORT" "$DATABASE_URL" \
    "${GITHUB_CLIENT_ID:-}" "${GITHUB_CLIENT_SECRET:-}" "${GITHUB_WEBHOOK_SECRET:-}" "${APP_ENCRYPTION_KEY:-}"
} | sha256sum | awk '{print $1}')"
API_PID_FILE="$RUN_DIR/api.pid"
API_COMMAND='src/server.ts'
API_READY=false
API_OWNED=false
if curl -fs "http://127.0.0.1:${API_PORT}/health/ready" >/dev/null 2>&1; then
  API_READY=true
fi
if [[ -f "$API_PID_FILE" ]] && process_is_owned "$(tr -cd '0-9' <"$API_PID_FILE")" "$API_COMMAND"; then
  API_OWNED=true
fi

if [[ "$API_READY" == true && "$API_OWNED" == true \
  && "$(cat "$API_FINGERPRINT_FILE" 2>/dev/null || true)" == "$API_FINGERPRINT" ]]; then
  log "API działa z aktualnym kodem i konfiguracją"
else
  if [[ "$API_OWNED" == true ]]; then
    stop_owned_process "API" "$API_PID_FILE" "$API_COMMAND"
  elif [[ "$API_READY" == true ]] || port_is_listening "$API_PORT"; then
    log "Port API $API_PORT zajmuje proces nieuruchomiony przez projekt; nie zatrzymuję obcej usługi."
    exit 1
  fi

  log "Startuję API na porcie $API_PORT"
  nohup node --experimental-strip-types src/server.ts >"$RUN_DIR/api.log" 2>&1 9>&- &
  API_PID=$!
  printf '%s\n' "$API_PID" >"$API_PID_FILE"
  for _ in $(seq 1 30); do
    curl -fs "http://127.0.0.1:${API_PORT}/health/ready" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fs "http://127.0.0.1:${API_PORT}/health/ready" >/dev/null || { tail -n 30 "$RUN_DIR/api.log"; exit 1; }
  printf '%s\n' "$API_FINGERPRINT" >"$API_FINGERPRINT_FILE"
fi

# --- Flutter Web ---
if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  log "Instaluję Flutter $FLUTTER_VERSION w $FLUTTER_DIR"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
WEB_BUILD="$ROOT/mobile/build/web"
STAMP="$RUN_DIR/web-build.stamp"
if [[ ! -f "$WEB_BUILD/index.html" || "$(cat "$STAMP" 2>/dev/null)" != "$PUBLIC_URL" \
  || -n "$(find mobile/lib mobile/web mobile/pubspec.yaml -newer "$WEB_BUILD/index.html" -print -quit 2>/dev/null)" ]]; then
  log "Buduję Flutter Web (API: ${PUBLIC_URL}/api)"
  (cd mobile && flutter config --no-analytics >/dev/null 2>&1 || true
   flutter pub get && flutter build web --release --dart-define=API_BASE_URL="${PUBLIC_URL}/api")
  echo "$PUBLIC_URL" >"$STAMP"
fi

# --- Bramka UI + proxy /api ---
GATEWAY_FINGERPRINT_FILE="$RUN_DIR/gateway.fingerprint"
GATEWAY_FINGERPRINT="$({
  sha256sum scripts/gateway.mjs
  printf '%s\0' "$WEB_BUILD" "$GATEWAY_PORT" "$API_PORT"
} | sha256sum | awk '{print $1}')"
GATEWAY_PID_FILE="$RUN_DIR/gateway.pid"
GATEWAY_COMMAND='scripts/gateway.mjs'
GATEWAY_READY=false
GATEWAY_OWNED=false
if curl -fs "http://127.0.0.1:${GATEWAY_PORT}/__control-center/health" | grep -q 'copilot-control-center-gateway'; then
  GATEWAY_READY=true
fi
if [[ -f "$GATEWAY_PID_FILE" ]] && process_is_owned "$(tr -cd '0-9' <"$GATEWAY_PID_FILE")" "$GATEWAY_COMMAND"; then
  GATEWAY_OWNED=true
fi

if [[ "$GATEWAY_READY" == true && "$GATEWAY_OWNED" == true \
  && "$(cat "$GATEWAY_FINGERPRINT_FILE" 2>/dev/null || true)" == "$GATEWAY_FINGERPRINT" ]]; then
  log "Gateway działa z aktualnym kodem"
else
  if [[ "$GATEWAY_OWNED" == true ]]; then
    stop_owned_process "gateway" "$GATEWAY_PID_FILE" "$GATEWAY_COMMAND"
  elif [[ "$GATEWAY_READY" == true ]] || port_is_listening "$GATEWAY_PORT"; then
    log "Port UI $GATEWAY_PORT zajmuje proces nieuruchomiony przez projekt; nie zatrzymuję obcej usługi."
    exit 1
  fi

  log "Startuję UI na porcie $GATEWAY_PORT"
  WEB_ROOT="$WEB_BUILD" GATEWAY_PORT="$GATEWAY_PORT" PORT="$API_PORT" nohup node scripts/gateway.mjs >"$RUN_DIR/gateway.log" 2>&1 9>&- &
  GATEWAY_PID=$!
  printf '%s\n' "$GATEWAY_PID" >"$GATEWAY_PID_FILE"
  for _ in $(seq 1 30); do
    curl -fs "http://127.0.0.1:${GATEWAY_PORT}/__control-center/health" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fs "http://127.0.0.1:${GATEWAY_PORT}/__control-center/health" | grep -q 'copilot-control-center-gateway'
  printf '%s\n' "$GATEWAY_FINGERPRINT" >"$GATEWAY_FINGERPRINT_FILE"
fi

log "Aplikacja działa: $PUBLIC_URL"
if [[ -z "${GITHUB_CLIENT_ID:-}" || -z "${GITHUB_CLIENT_SECRET:-}" ]]; then
  log "Logowanie GitHub wymaga OAuth App: callback ${PUBLIC_URL}/api/auth/github/callback;"
  log "wpisz GITHUB_CLIENT_ID i GITHUB_CLIENT_SECRET do .env i uruchom: bash scripts/dev-restart.sh"
fi
