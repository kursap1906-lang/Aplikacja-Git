#!/usr/bin/env bash
set -euo pipefail
umask 077

backup_file="${1:-}"
if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
  printf 'Usage: %s /path/to/0600-postgres-backup.dump\n' "$0" >&2
  exit 2
fi
backup_mode="$(stat -c '%a' -- "$backup_file")"
if [[ "$backup_mode" != 600 ]]; then
  printf 'Refusing to restore: the backup must have mode 0600.\n' >&2
  exit 1
fi

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
env_file=".env.staging"
if [[ ! -f "$env_file" ]]; then
  printf 'Refusing to restore: %s must exist with mode 0600.\n' "$env_file" >&2
  exit 1
fi
env_mode="$(stat -c '%a' -- "$env_file")"
if [[ "$env_mode" != 600 ]]; then
  printf 'Refusing to restore: %s must exist with mode 0600.\n' "$env_file" >&2
  exit 1
fi

restore_db="ccc_restore_$(date -u '+%Y%m%d%H%M%S')"
compose=(sudo -n env APP_ENV_FILE="$env_file" docker compose -p ccc-staging --env-file "$env_file" exec -T)

if ! "${compose[@]}" -e RESTORE_DB="$restore_db" database \
  sh -ec 'createdb --username="$POSTGRES_USER" --owner="$POSTGRES_USER" "$RESTORE_DB"'; then
  printf 'Could not create a new isolated staging restore database; existing databases were left unchanged.\n' >&2
  exit 1
fi

if ! "${compose[@]}" -e RESTORE_DB="$restore_db" database \
  sh -ec 'pg_restore --exit-on-error --no-owner --no-acl --username="$POSTGRES_USER" --dbname="$RESTORE_DB"' \
  < "$backup_file"; then
  printf 'Restore failed. The new test database %s was preserved for inspection; no existing database was overwritten.\n' "$restore_db" >&2
  exit 1
fi

migrations="$("${compose[@]}" -e RESTORE_DB="$restore_db" \
  -e MIGRATION_CHECK_SQL='SELECT count(*) FROM "_prisma_migrations" WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL' \
  database sh -ec 'psql --username="$POSTGRES_USER" --dbname="$RESTORE_DB" --no-psqlrc --tuples-only --no-align --command="$MIGRATION_CHECK_SQL"')"
if [[ ! "$migrations" =~ ^[0-9]+$ || "$migrations" -lt 1 ]]; then
  printf 'Restore completed, but the migration-table verification failed for %s.\n' "$restore_db" >&2
  exit 1
fi

printf 'Verified backup restored to isolated staging database %s (%s applied migrations). The database was preserved.\n' \
  "$restore_db" "$migrations"
