#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a
source .env
set +a

TS="$(date -u +"%Y%m%dT%H%M%SZ")"
WORKDIR="${BACKUP_DIR}/work-${TS}"
BUNDLE="${BACKUP_DIR}/pikachu-n8n-${TS}.tar.gz"
ENCRYPTED="${BUNDLE}.gpg"

mkdir -p "${WORKDIR}"

echo "[1/7] Postgres dump (custom format)..."
podman exec -i pikachu-postgres pg_dump \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --format=custom \
  > "${WORKDIR}/postgres.dump"

echo "[2/7] Export n8n volume..."
podman volume export "${VOL_N8N}" > "${WORKDIR}/n8n-volume.tar"

echo "[3/7] Export redis volume..."
podman volume export "${VOL_REDIS}" > "${WORKDIR}/redis-volume.tar"

echo "[4/7] Export Traefik ACME volume (certs)..."
podman volume export "${VOL_TRAEFIK_ACME}" > "${WORKDIR}/traefik-acme-volume.tar"

echo "[5/7] Create bundle..."
tar -C "${WORKDIR}" -czf "${BUNDLE}" .

echo "[6/7] Encrypt bundle (GPG symmetric AES256)..."
printf "%s" "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
  --symmetric --cipher-algo AES256 \
  -o "${ENCRYPTED}" "${BUNDLE}"

rm -f "${BUNDLE}"
rm -rf "${WORKDIR}"

echo "[7/7] Upload to pCloud via rclone..."
rclone copy "${ENCRYPTED}" "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH}" --progress

echo "Backup complete: ${ENCRYPTED}"
