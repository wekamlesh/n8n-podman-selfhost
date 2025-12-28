#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a
source .env
set +a

TS="${1:-}"
if [[ -z "$TS" ]]; then
  echo "ERROR: Provide backup timestamp."
  echo "Example: ./scripts/restore.sh 20251228T060000Z"
  exit 1
fi

ENCRYPTED_NAME="pikachu-n8n-${TS}.tar.gz.gpg"
LOCAL_ENC="${BACKUP_DIR}/${ENCRYPTED_NAME}"
WORKDIR="${BACKUP_DIR}/restore-work-${TS}"

mkdir -p "${WORKDIR}"

echo "[1/9] Download from pCloud..."
rclone copy "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH}/${ENCRYPTED_NAME}" "${BACKUP_DIR}" --progress

echo "[2/9] Decrypt..."
DECRYPTED="${WORKDIR}/bundle.tar.gz"
printf "%s" "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
  -o "${DECRYPTED}" --decrypt "${LOCAL_ENC}"

echo "[3/9] Extract..."
tar -C "${WORKDIR}" -xzf "${DECRYPTED}"

echo "[4/9] Stop stack..."
podman-compose --env-file .env down

echo "[5/9] Recreate volumes (wipe old data safely)..."
podman volume rm -f "${VOL_N8N}" "${VOL_REDIS}" "${VOL_POSTGRES}" "${VOL_TRAEFIK_ACME}" || true
podman volume create "${VOL_N8N}"
podman volume create "${VOL_REDIS}"
podman volume create "${VOL_POSTGRES}"
podman volume create "${VOL_TRAEFIK_ACME}"

echo "[6/9] Import volumes..."
podman volume import "${VOL_N8N}" "${WORKDIR}/n8n-volume.tar"
podman volume import "${VOL_REDIS}" "${WORKDIR}/redis-volume.tar"
podman volume import "${VOL_TRAEFIK_ACME}" "${WORKDIR}/traefik-acme-volume.tar"

echo "[7/9] Start postgres only..."
podman-compose --env-file .env up -d postgres
sleep 10

echo "[8/9] Restore Postgres dump..."
podman exec -i pikachu-postgres psql -U "${POSTGRES_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${POSTGRES_DB}';" || true
podman exec -i pikachu-postgres psql -U "${POSTGRES_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
podman exec -i pikachu-postgres psql -U "${POSTGRES_USER}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB};"

podman exec -i pikachu-postgres pg_restore \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --clean --if-exists \
  < "${WORKDIR}/postgres.dump"

echo "[9/9] Start full stack..."
podman-compose --env-file .env up -d

echo "Restore complete. Run: ./scripts/verify.sh"
