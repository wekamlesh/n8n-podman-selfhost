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

N8N_VOL="${VOL_N8N:?Set VOL_N8N in .env}"
REDIS_VOL="${VOL_REDIS:?Set VOL_REDIS in .env}"
POSTGRES_VOL="${VOL_POSTGRES:?Set VOL_POSTGRES in .env}"
CERTS_VOL="${VOL_CADDY_DATA:?Set VOL_CADDY_DATA in .env}"
BACKUP_DIR="${BACKUP_DIR:?Set BACKUP_DIR in .env}"
REMOTE_PATH="${RCLONE_REMOTE_PATH%/}"

BASENAME="${1:-}"
if [[ -z "$BASENAME" ]]; then
  echo "ERROR: Provide backup timestamp."
  echo "Example: ./scripts/restore.sh 28-01-2025.14:30:22"
  echo "Or full filename: ./scripts/restore.sh n8n-28-01-2025.14:30:22.tar.gz.gpg"
  exit 1
fi
# Allow passing full filename; strip leading path and expected prefix/suffix
BASENAME="${BASENAME##*/}"
if [[ "${BASENAME}" =~ ^n8n-(.*)\.tar\.gz\.gpg$ ]]; then
  TS="${BASH_REMATCH[1]}"
elif [[ "${BASENAME}" == n8n-* ]]; then
  TS="${BASENAME#n8n-}"
else
  TS="${BASENAME}"
fi

ENCRYPTED_NAME="n8n-${TS}.tar.gz.gpg"
LOCAL_ENC="${BACKUP_DIR}/${ENCRYPTED_NAME}"
SAFE_TS="${TS//:/-}"
WORKDIR="${BACKUP_DIR}/restore-work-${SAFE_TS}"

mkdir -p "${WORKDIR}"
if [[ ! -w "${WORKDIR}" ]]; then
  echo "ERROR: Cannot write to ${WORKDIR}. Fix permissions on BACKUP_DIR or change it in .env."
  exit 1
fi

echo "[1/9] Download from pCloud..."
rclone copy "${RCLONE_REMOTE}:${REMOTE_PATH}/${ENCRYPTED_NAME}" "${BACKUP_DIR}" --progress

echo "[2/9] Decrypt..."
DECRYPTED="${WORKDIR}/bundle.tar.gz"
printf "%s" "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
  -o "${DECRYPTED}" --decrypt "${LOCAL_ENC}"

echo "[3/9] Extract..."
tar -C "${WORKDIR}" -xzf "${DECRYPTED}"

CERT_ARCHIVE="${WORKDIR}/caddy-certs-volume.tar"
if [[ ! -f "${CERT_ARCHIVE}" ]]; then
  echo "ERROR: No certs archive found (expected ${CERT_ARCHIVE})."
  exit 1
fi

echo "[4/9] Stop stack..."
podman-compose down

echo "[5/9] Recreate volumes (wipe old data safely)..."
podman volume rm -f "${N8N_VOL}" "${REDIS_VOL}" "${POSTGRES_VOL}" "${CERTS_VOL}" || true
podman volume create "${N8N_VOL}"
podman volume create "${REDIS_VOL}"
podman volume create "${POSTGRES_VOL}"
podman volume create "${CERTS_VOL}"

echo "[6/9] Import volumes..."
podman volume import "${N8N_VOL}" "${WORKDIR}/n8n-volume.tar"
podman volume import "${REDIS_VOL}" "${WORKDIR}/redis-volume.tar"
podman volume import "${CERTS_VOL}" "${CERT_ARCHIVE}"

echo "[7/9] Start postgres only..."
podman-compose up -d postgres
sleep 10

echo "[8/9] Restore Postgres dump..."
podman exec -i postgres psql -U "${POSTGRES_USER}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${POSTGRES_DB}';" || true
podman exec -i postgres psql -U "${POSTGRES_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
podman exec -i postgres psql -U "${POSTGRES_USER}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB};"

podman exec -i postgres pg_restore \
  -U "${POSTGRES_USER}" \
  -d "${POSTGRES_DB}" \
  --clean --if-exists \
  < "${WORKDIR}/postgres.dump"

echo "[9/9] Start full stack..."
podman-compose up -d

echo "Restore complete. Run: ./scripts/verify.sh"
