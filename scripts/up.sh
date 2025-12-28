#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
podman-compose --env-file .env --env-file .env.secrets up -d
