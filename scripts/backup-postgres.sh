#!/usr/bin/env bash
set -euo pipefail
umask 077

deployment="${1:-}"
case "$deployment" in
  staging)
    compose_project="ccc-staging"
    env_file=".env.staging"
    ;;
  production)
    compose_project="ccc-production"
    env_file=".env.production"
    ;;
  *)
    printf 'Usage: %s staging|production\n' "$0" >&2
    exit 2
    ;;
esac

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

if [[ ! -f "$env_file" ]]; then
  printf 'Refusing to back up: %s must exist with mode 0600.\n' "$env_file" >&2
  exit 1
fi
env_mode="$(stat -c '%a' -- "$env_file")"
if [[ "$env_mode" != 600 ]]; then
  printf 'Refusing to back up: %s must exist with mode 0600.\n' "$env_file" >&2
  exit 1
fi

backup_dir="$project_root/backups/$deployment"
install -d -m 700 "$backup_dir"
timestamp="$(date -u '+%Y%m%dT%H%M%S.%NZ')"
temporary_file="$(mktemp "$backup_dir/.${timestamp}.XXXXXX")"
backup_file="$backup_dir/postgres-${timestamp}.dump"
trap 'rm -f -- "$temporary_file"' EXIT

if ! sudo -n env APP_ENV_FILE="$env_file" docker compose \
  -p "$compose_project" --env-file "$env_file" exec -T database \
  sh -ec 'pg_dump --format=custom --no-owner --no-acl --username="$POSTGRES_USER" "$POSTGRES_DB"' \
  > "$temporary_file"; then
  printf 'PostgreSQL backup failed; no backup was published.\n' >&2
  exit 1
fi

if ! sudo -n env APP_ENV_FILE="$env_file" docker compose \
  -p "$compose_project" --env-file "$env_file" exec -T database \
  pg_restore --list < "$temporary_file" > /dev/null; then
  printf 'PostgreSQL backup verification failed; no backup was published.\n' >&2
  exit 1
fi

chmod 600 "$temporary_file"
ln -- "$temporary_file" "$backup_file"
rm -- "$temporary_file"
trap - EXIT
printf 'Verified PostgreSQL backup created: %s\n' "$backup_file"
