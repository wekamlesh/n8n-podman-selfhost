#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run this script with sudo; use the rootless user that owns the containers."
  exit 1
fi

set -a
source .env
set +a
REMOTE_PATH="${RCLONE_REMOTE_PATH%/}"

ensure_backup_dir() {
  if [[ ! -d "${BACKUP_DIR}" ]]; then
    mkdir -p "${BACKUP_DIR}" 2>/dev/null || sudo mkdir -p "${BACKUP_DIR}"
  fi
  sudo chown -R "${USER}:${USER}" "${BACKUP_DIR}" 2>/dev/null || true
  if [[ ! -w "${BACKUP_DIR}" ]]; then
    echo "ERROR: ${BACKUP_DIR} is not writable. Fix permissions or change BACKUP_DIR in .env."
    exit 1
  fi
}

# Trap errors and output failure message
trap 'echo "ERROR: Backup failed at step: $CURRENT_STEP"; echo "Error message: $BASH_COMMAND"; exit 1' ERR

ensure_backup_dir

N8N_VOL="${VOL_N8N:?Set VOL_N8N in .env}"
REDIS_VOL="${VOL_REDIS:?Set VOL_REDIS in .env}"
CERTS_VOL="${VOL_CADDY_DATA:?Set VOL_CADDY_DATA in .env}"

podman volume inspect "${N8N_VOL}" >/dev/null
podman volume inspect "${REDIS_VOL}" >/dev/null
podman volume inspect "${CERTS_VOL}" >/dev/null

TS="$(date +"%d-%m-%Y.%H:%M:%S")"
SAFE_TS="${TS//:/-}"
WORKDIR="${BACKUP_DIR}/work-${SAFE_TS}"
BUNDLE="${BACKUP_DIR}/n8n-${TS}.tar.gz"
ENCRYPTED="${BUNDLE}.gpg"
CERT_ARCHIVE="${WORKDIR}/caddy-certs-volume.tar"

mkdir -p "${WORKDIR}"

CURRENT_STEP="Postgres dump"
echo "[1/7] Postgres dump (custom format)..."
podman exec -i postgres pg_dump \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --format=custom \
  > "${WORKDIR}/postgres.dump"

CURRENT_STEP="Export n8n volume"
echo "[2/7] Export n8n volume..."
podman volume export "${N8N_VOL}" > "${WORKDIR}/n8n-volume.tar"

CURRENT_STEP="Export redis volume"
echo "[3/7] Export redis volume..."
podman volume export "${REDIS_VOL}" > "${WORKDIR}/redis-volume.tar"

CURRENT_STEP="Export Caddy certs volume"
echo "[4/7] Export Caddy certs volume..."
podman volume export "${CERTS_VOL}" > "${CERT_ARCHIVE}"

CURRENT_STEP="Create bundle"
echo "[5/7] Create bundle..."
tar -C "${WORKDIR}" -czf "${BUNDLE}" .

CURRENT_STEP="Encrypt bundle"
echo "[6/7] Encrypt bundle (GPG symmetric AES256)..."
printf "%s" "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
  --symmetric --cipher-algo AES256 \
  -o "${ENCRYPTED}" "${BUNDLE}"

rm -f "${BUNDLE}"
rm -rf "${WORKDIR}"

CURRENT_STEP="Upload to pCloud"
echo "[7/7] Upload to pCloud via rclone..."
rclone copy "${ENCRYPTED}" "${RCLONE_REMOTE}:${REMOTE_PATH}" --progress

CURRENT_STEP="Prune remote backups"
echo "[7b/7] Prune remote backups older than 7 days..."
rclone delete "${RCLONE_REMOTE}:${REMOTE_PATH}" --min-age 7d --progress

# Remove local encrypted artifact; staging data already removed
rm -f "${ENCRYPTED}"

echo "SUCCESS: Backup completed successfully at ${TS}"
echo "Encrypted backup uploaded to: ${RCLONE_REMOTE}:${REMOTE_PATH}/$(basename "${ENCRYPTED}")"