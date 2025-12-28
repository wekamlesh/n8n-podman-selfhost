#!/usr/bin/env bash
set -euo pipefail

echo "[1/4] Containers:"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo "[2/4] Postgres ready?"
podman exec -i pikachu-postgres pg_isready -U n8n -d n8n || true

echo "[3/4] Redis ping:"
podman exec -i pikachu-redis redis-cli PING || true

echo "[4/4] n8n logs tail:"
podman logs --tail=80 pikachu-n8n