#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a
source .env
set +a

echo "[1/5] Ensure backups directory exists: ${BACKUP_DIR}"
sudo mkdir -p "${BACKUP_DIR}"
sudo chown -R "$USER:$USER" "$(dirname "${BACKUP_DIR}")"
sudo chmod -R 750 "$(dirname "${BACKUP_DIR}")"

echo "[2/5] Enable lingering so user systemd services run after logout/reboot"
loginctl enable-linger "$USER"

echo "[3/5] Install helper packages + rclone"
sudo apt-get update
sudo apt-get install -y busybox
curl -fsSL https://rclone.org/install.sh | sudo bash

echo "[4/5] Mark scripts executable"
chmod +x scripts/*.sh

echo "[5/5] Done. Next: set PODMAN_UID in .env, configure rclone, then ./scripts/up.sh"
