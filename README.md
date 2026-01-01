# n8n Production Stack (Podman, rootless) + Postgres + Redis + Caddy (Let's Encrypt)
Production-grade n8n automation platform running on rootless Podman with automatic SSL certificates, encrypted backups, and simple Caddy reverse-proxying.

---

## 🎯 Quick Start

### 1. Set Your User ID
```bash
id -u
cp .env.example .env
nano .env
```

**Example `.env` snippet:**
```bash
PODMAN_UID=1000
N8N_ENCRYPTION_KEY=generate-a-long-random-secret
POSTGRES_PASSWORD=strong-db-password
BACKUP_PASSPHRASE=strong-backup-passphrase
RCLONE_REMOTE=your-cloud-crypt
RCLONE_REMOTE_PATH=your-backup-folder
BACKUP_DIR=/path/to/backups
VOL_CADDY_DATA=caddy_data
VOL_CADDY_CONFIG=caddy_config
N8N_HOST=your-domain.com
```

### 2. Protect Your .env
```bash
chmod 600 .env
```

> ⚠️ Ensure `N8N_ENCRYPTION_KEY` is long, random, and stored safely forever.

### 3. Install Dependencies
```bash
cd /path/to/project
chmod +x scripts/*.sh
./scripts/install.sh
```

### 4. Allow rootless Caddy to bind 80/443 (once per host)
```bash
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
echo 'net.ipv4.ip_unprivileged_port_start=0' | sudo tee /etc/sysctl.d/99-rootless-ports.conf
sudo sysctl --system
```

### 5. Ensure the shared network exists (once per host)
```bash
podman network create --driver bridge --label dns.podman=1 shared-network || true
```

### 6. Configure Encrypted Cloud Backup (Optional)
```bash
rclone config
```

- Create cloud remote (OAuth)
- Create crypt layer remote

### 7. Start the Stack
```bash
./scripts/up.sh
./scripts/verify.sh
```

### 8. Access Your Services
- **n8n Automation:** https://${N8N_HOST}

---

## 💾 Backup & Restore

### Manual Backup
```bash
./scripts/backup.sh
```

**Output:**
- ✓ SUCCESS: Backup completed successfully (in green)
- File: n8n-DD-MM-YYYY.HH-MM-SS.tar.gz.gpg
- Time: Xm Ys

Backs up:
- Postgres dump
- n8n data
- Redis files
- Caddy certs

Encrypted and uploaded to cloud storage. Local file removed.

### Restore Backup
```bash
rclone ls your-cloud-crypt:your-backup-folder
./scripts/restore.sh <TIMESTAMP>
./scripts/verify.sh
```

> ⚠️ Restoration overwrites current data.

---

## 🔄 Automatic Container Updates

```bash
systemctl --user enable --now podman-auto-update.timer
systemctl --user list-timers | grep podman-auto-update
podman auto-update
```

- Uses `io.containers.autoupdate=image`
- Conservative tag policy (e.g., `stable`)

---

## 📋 Setup Checklist

```bash
cd /path/to/project
id -u
cp .env.example .env
nano .env
chmod 600 .env
chmod +x scripts/*.sh
./scripts/install.sh
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
echo 'net.ipv4.ip_unprivileged_port_start=0' | sudo tee /etc/sysctl.d/99-rootless-ports.conf
sudo sysctl --system
podman network create --driver bridge --label dns.podman=1 shared-network || true
rclone config
./scripts/up.sh
./scripts/verify.sh
systemctl --user enable --now podman-auto-update.timer
./scripts/backup.sh
echo "Visit: https://your-domain.com"
```

---

## 📁 Project Structure

```
project-root/
├── README.md
├── .env.example
├── .env
├── podman-compose.yml
├── Caddyfile
├── scripts/
│   ├── install-rootless.sh
│   ├── up.sh
│   ├── down.sh
│   ├── verify.sh
│   ├── backup.sh
│   └── restore.sh
├── data/
│   ├── n8n/
│   ├── postgres/
│   └── redis/
└── backups/
```

---

## 🔧 Troubleshooting

### Containers Won't Start
```bash
podman logs n8n
podman logs postgres
podman logs caddy
ss -tulpn | grep -E ':(80|443|5432|6379)'
podman pod ps
```

### Database/Redis `EHOSTUNREACH` inside n8n
- Refresh DNS records on the shared network:
```bash
podman network reload shared-network
podman-compose down
podman-compose up -d
podman exec n8n getent hosts postgres redis
```
- If stale entries remain, recreate the network:
```bash
podman-compose down
podman network rm shared-network
podman network create --driver bridge --label dns.podman=1 shared-network
podman-compose up -d
```

### SSL Issues
```bash
podman logs caddy
dig your-domain.com
curl -I http://your-domain.com
```

### Database Errors
```bash
podman exec -it postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"
grep POSTGRES_PASSWORD .env
```

### Permission Denied
```bash
ls -la data/
podman unshare chown -R $(id -u):$(id -g) data/
```

### Backup Failures
```bash
rclone ls your-cloud-crypt:
grep N8N_ENCRYPTION_KEY .env
df -h
```

---

## 🛡️ Security Considerations

- Rootless Podman for enhanced isolation
- Encrypted backups with GPG AES256
- Secrets stored in `.env` (never committed)
- HTTPS via Caddy with automatic Let's Encrypt certificates
- Isolated Podman network
- Password-protected backup archives
- Automatic old backup pruning (7 days retention)

---

## 📚 Resources

- [n8n Docs](https://docs.n8n.io/)
- [Podman Docs](https://docs.podman.io/)
- [Caddy Docs](https://caddyserver.com/docs/)
- [rclone Docs](https://rclone.org/docs/)

---

## 📝 License

Provided as-is for personal and commercial use.

---

## 🤝 Support

- Check troubleshooting section  
- Review logs: `podman logs <container-name>`  
- Run: `./scripts/verify.sh`
- Check backup status: `./scripts/backup.sh` (shows colored success/failure)

---

## 🔐 Important Notes

- Never commit `.env` file to version control
- Store `N8N_ENCRYPTION_KEY` and `BACKUP_PASSPHRASE` securely
- Test restore process regularly
- Monitor backup success notifications
- Keep rclone config secure
```
