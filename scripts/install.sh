#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

set -a
source .env
set +a

echo "[1/6] Ensure backups directory exists: ${BACKUP_DIR}"
sudo mkdir -p "${BACKUP_DIR}"
sudo chown -R "$USER:$USER" "$(dirname "${BACKUP_DIR}")"
sudo chmod -R 750 "$(dirname "${BACKUP_DIR}")"

echo "[2/6] Enable lingering so user systemd services run after logout/reboot"
loginctl enable-linger "$USER"

echo "[3/6] Install helper packages + rclone"
sudo apt-get update -y && sudo apt-get upgrade -y && \
sudo apt-get install -y busybox curl wget git podman podman-compose python3 python3-pip && \
curl -fsSL https://rclone.org/install.sh | sudo bash

echo "[4/6] Mark scripts executable"
chmod +x scripts/*.sh

echo "[5/6] Configure systemd rootless Podman services"
systemctl --user enable --now podman.socket
systemctl --user enable --now podman-auto-update.timer

echo "[6/6] Done. Next: set PODMAN_UID in .env, configure rclone, then ./scripts/up.sh"
