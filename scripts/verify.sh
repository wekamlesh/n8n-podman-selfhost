#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a
source .env
set +a

echo "[1/4] Containers:"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "[2/4] Postgres ready?"
podman exec -i postgres pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" || true

echo "[3/4] Redis ping:"
podman exec -i redis redis-cli PING || true

echo "[4/4] n8n logs tail:"
podman logs --tail=80 n8n
