#!/usr/bin/env bash
###############################################################################
# SilaFit — publish from your Mac to the Hetzner server.
#
# deploy.sh only works on the actual Ubuntu box (apt-get, systemctl, ufw,
# swapon/fallocate, docker.io — none of which exist on macOS), so it can't be
# run locally. This script is the local-Mac side: it uploads backend/,
# database/, and deploy/ (everything deploy.sh needs) to the server over SSH,
# then runs deploy.sh there as root.
#
# deploy.sh is idempotent, so this one command covers both the first-ever
# provisioning run (Docker, SQL Server, nginx, TLS — takes a few minutes) and
# every later "ship a code/schema change" redeploy.
#
# Usage (from anywhere, on your Mac):
#   ./deploy/publish.sh
#
# Overridable via env vars:
#   SILEN_SSH    SSH target      (default: root@silafit.tappit.click)
#   REMOTE_DIR   path on server  (default: /opt/silen)
#   DOMAIN       public host     (default: silafit.tappit.click)
###############################################################################
set -euo pipefail

# ---- config -----------------------------------------------------------------
SILEN_SSH="${SILEN_SSH:-root@silafit.tappit.click}"
REMOTE_DIR="${REMOTE_DIR:-/opt/silen}"
DOMAIN="${DOMAIN:-silafit.tappit.click}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m    ✗ %s\033[0m\n' "$*" >&2; exit 1; }

command -v ssh   >/dev/null 2>&1 || die "ssh not found on this machine"
command -v rsync >/dev/null 2>&1 || die "rsync not found on this machine"

# ---- 0. sanity: can we reach the server? ------------------------------------
log "Checking SSH access to $SILEN_SSH"
ssh -o ConnectTimeout=10 "$SILEN_SSH" 'echo ok' >/dev/null 2>&1 \
  || die "cannot SSH to $SILEN_SSH (check the host / your SSH key / ~/.ssh/config)"
ok "connected"

ssh "$SILEN_SSH" "mkdir -p '$REMOTE_DIR/backend' '$REMOTE_DIR/database' '$REMOTE_DIR/deploy'"

# ---- 1. sync API source ------------------------------------------------------
log "Uploading backend/ -> $SILEN_SSH:$REMOTE_DIR/backend"
rsync -az --delete \
  --exclude 'bin' --exclude 'obj' --exclude '.vs' --exclude '*.user' \
  --exclude 'appsettings.Development.json' --exclude '.DS_Store' --exclude '._*' \
  "$REPO_ROOT/backend/" "$SILEN_SSH:$REMOTE_DIR/backend/"
ok "backend uploaded"

# ---- 2. sync schema/procedures/seed -----------------------------------------
log "Uploading database/ -> $SILEN_SSH:$REMOTE_DIR/database"
rsync -az --delete --exclude '.DS_Store' --exclude '._*' \
  "$REPO_ROOT/database/" "$SILEN_SSH:$REMOTE_DIR/database/"
ok "database uploaded"

# ---- 3. sync deploy assets (never touches the server's own .env) -----------
log "Uploading deploy/ -> $SILEN_SSH:$REMOTE_DIR/deploy"
rsync -az --delete \
  --exclude '.env' --exclude 'publish.sh' --exclude '.DS_Store' --exclude '._*' \
  "$SCRIPT_DIR/" "$SILEN_SSH:$REMOTE_DIR/deploy/"
ssh "$SILEN_SSH" "chmod +x '$REMOTE_DIR/deploy/deploy.sh'"
ok "deploy assets uploaded"

# ---- 4. run deploy.sh on the server ------------------------------------------
log "Running deploy.sh on the server (idempotent — safe on both a first deploy and a redeploy)"
ssh -t "$SILEN_SSH" "cd '$REMOTE_DIR/deploy' && ./deploy.sh"

# ---- 5. external health check (best-effort, non-fatal) -----------------------
log "Checking https://$DOMAIN externally"
code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://$DOMAIN/api/plans" 2>/dev/null || echo 000)"
if [ "$code" != "000" ]; then
  ok "public endpoint responded (HTTP $code)"
else
  warn "public https://$DOMAIN did not respond — if this is the first deploy, DNS/TLS may need a minute; otherwise SSH in and check: docker logs silen-api"
fi

log "DONE — published to https://$DOMAIN"
