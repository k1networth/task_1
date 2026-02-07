#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${DB_STACK_PROJECT_DIR:-/srv/db_stack}"
BACKUP_DIR="${DB_STACK_BACKUP_DIR:-/srv/backups/postgres}"
ENV_FILE="${DB_STACK_ENV_FILE:-${PROJECT_DIR}/.env}"
COMPOSE_FILE="${DB_STACK_COMPOSE_FILE:-${PROJECT_DIR}/docker-compose.yml}"
PROJECT_NAME="${DB_STACK_PROJECT_NAME:-db_stack}"
RETENTION_DAYS="${DB_STACK_RETENTION_DAYS:-7}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: env file not found: ${ENV_FILE}" >&2
  exit 1
fi

# Load secrets to env (only on host)
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
  echo "ERROR: POSTGRES_PASSWORD is empty after sourcing ${ENV_FILE}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
chmod 0750 "${BACKUP_DIR}"

ts="$(date +%F)"
outfile="${BACKUP_DIR}/pgdump_${ts}.sql.gz"
tmpfile="${outfile}.tmp"

echo "[INFO] Starting backup: ${outfile}"

export PGPASSWORD="${POSTGRES_PASSWORD}"

# Ensure we run docker compose from a consistent directory
cd "${PROJECT_DIR}"

# Create a logical dump and compress
docker compose -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" exec -T postgres   pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --no-owner --no-privileges   | gzip -c > "${tmpfile}"

mv "${tmpfile}" "${outfile}"
chmod 0640 "${outfile}"

echo "[INFO] Backup completed: ${outfile}"

# Rotation: keep last N days (delete older files)
echo "[INFO] Rotating backups (retention: ${RETENTION_DAYS} days)"
find "${BACKUP_DIR}" -type f -name "pgdump_*.sql.gz" -mtime +"$((RETENTION_DAYS - 1))" -print -delete || true

echo "[INFO] Done."
