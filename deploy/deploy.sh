#!/usr/bin/env bash
###############################################################################
# SilaFit — from-scratch deploy for a fresh Ubuntu server (or an existing
# Hetzner box already running other sites — every step here is idempotent and
# scoped to its own container/port/vhost names, so it won't touch them).
#
# Provisions:
#   - Swap (memory safety on small boxes)
#   - Docker Engine + compose plugin
#   - SQL Server 2022 (Docker) + SilenDb database + schema/procedures/seed
#   - Silen.Api (.NET 8, Docker) on 127.0.0.1:5010
#   - nginx reverse proxy for silafit.tappit.click
#   - Let's Encrypt HTTPS (certbot)
#
# Idempotent: safe to re-run. Secrets are generated once and cached in ./.env.
#
# Usage (as root, from this directory):
#   ./deploy.sh
###############################################################################
set -euo pipefail

# ---- config -----------------------------------------------------------------
DOMAIN="silafit.tappit.click"
LE_EMAIL="nikpetrovski007@gmail.com"
DB_NAME="SilenDb"
SWAP_GB=4

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
cd "$SCRIPT_DIR"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }

# ---- 1. secrets -------------------------------------------------------------
log "Loading / generating secrets"
umask 077
touch "$ENV_FILE"
if [ -s "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  ok ".env found — reusing existing secrets"
fi

# SA password — SQL Server complexity: upper + lower + digit + special. Avoid shell/YAML-hostile chars.
if [ -z "${SA_PASSWORD:-}" ]; then
  SA_PASSWORD="Sf$(openssl rand -hex 18)#K7m"
  printf 'SA_PASSWORD=%s\n' "$SA_PASSWORD" >> "$ENV_FILE"
  ok "Generated new SA password -> $ENV_FILE (chmod 600)"
fi

# JWT signing secret — used to sign/verify auth tokens (Jwt__SigningKey env override).
if [ -z "${JWT_SIGNING_KEY:-}" ]; then
  JWT_SIGNING_KEY="$(openssl rand -hex 32)"
  printf 'JWT_SIGNING_KEY=%s\n' "$JWT_SIGNING_KEY" >> "$ENV_FILE"
  ok "Generated new JWT signing key -> $ENV_FILE (chmod 600)"
fi

export SA_PASSWORD JWT_SIGNING_KEY
export GOOGLE_WEB_CLIENT_ID="${GOOGLE_WEB_CLIENT_ID:-}"
export APPLE_BUNDLE_ID="${APPLE_BUNDLE_ID:-com.nikolapetrovski.silafit}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-openai/gpt-4.1}"

# ---- 2. swap ----------------------------------------------------------------
log "Ensuring ${SWAP_GB}GB swap"
if ! swapon --show | grep -q '/swapfile'; then
  fallocate -l "${SWAP_GB}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((SWAP_GB*1024))
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "Swap enabled"
else
  ok "Swap already present"
fi

# ---- 3. base packages + docker ----------------------------------------------
log "Installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release ufw >/dev/null
# Some fresh Ubuntu images register curl in dpkg but ship without the binary — repair it.
if ! command -v curl >/dev/null 2>&1; then
  warn "curl binary missing despite package — reinstalling"
  apt-get install --reinstall -y -qq curl >/dev/null
fi
command -v curl >/dev/null 2>&1 || { echo "curl unavailable after reinstall"; exit 1; }
ok "base packages"

if ! command -v docker >/dev/null 2>&1; then
  # Prefer Ubuntu's own packages (most reliable on a brand-new release).
  log "Installing Docker Engine (Ubuntu repo)"
  if apt-get install -y -qq docker.io docker-compose-v2 docker-buildx >/dev/null 2>&1 && \
     docker compose version >/dev/null 2>&1; then
    ok "Docker installed from Ubuntu repo"
  else
    warn "distro docker packages unavailable/incomplete — using Docker's official repo"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
    gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg /tmp/docker.asc
    chmod a+r /etc/apt/keyrings/docker.gpg
    UBU_CODENAME="$(. /etc/os-release; echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBU_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq || true
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  ok "Docker installed"
else
  ok "Docker already installed"
fi
docker --version
docker compose version >/dev/null 2>&1 || { echo "docker compose plugin missing"; exit 1; }

# ---- 4. nginx + certbot -----------------------------------------------------
log "Installing nginx + certbot"
apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null
systemctl enable --now nginx >/dev/null 2>&1 || true
ok "nginx + certbot"

# ---- 5. firewall ------------------------------------------------------------
log "Configuring firewall (ufw)"
if ufw status | grep -q "Status: active"; then
  ufw allow OpenSSH >/dev/null 2>&1 || true
  ufw allow 'Nginx Full' >/dev/null 2>&1 || true
  ok "ufw rules ensured (active)"
else
  warn "ufw inactive — leaving it disabled (Hetzner default). Ports 80/443/22 open."
fi

# ---- 6. start SQL Server -----------------------------------------------------
log "Starting SQL Server container"
docker compose up -d silen-sqlserver
ok "waiting for SQL Server to become healthy..."
for i in $(seq 1 40); do
  status="$(docker inspect -f '{{.State.Health.Status}}' silen-sqlserver 2>/dev/null || echo starting)"
  [ "$status" = "healthy" ] && break
  sleep 5
done
[ "$status" = "healthy" ] || { echo "SQL Server did not become healthy"; docker logs --tail 40 silen-sqlserver; exit 1; }
ok "SQL Server healthy"

# sqlcmd helpers (tools path differs across image versions; env vars avoid quoting issues)
run_sql() {   # run_sql <db> <query>
  docker exec -e SAPW="$SA_PASSWORD" -e DBN="$1" -e QRY="$2" silen-sqlserver /bin/bash -c '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then BIN=/opt/mssql-tools18/bin/sqlcmd; C=-C;
    else BIN=/opt/mssql-tools/bin/sqlcmd; C=; fi
    "$BIN" -S localhost -U sa -P "$SAPW" $C -b -d "$DBN" -Q "$QRY"'
}
run_sql_file() {  # run_sql_file <db> <container_path>
  docker exec -e SAPW="$SA_PASSWORD" -e DBN="$1" -e FIL="$2" silen-sqlserver /bin/bash -c '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then BIN=/opt/mssql-tools18/bin/sqlcmd; C=-C;
    else BIN=/opt/mssql-tools/bin/sqlcmd; C=; fi
    "$BIN" -S localhost -U sa -P "$SAPW" $C -b -d "$DBN" -i "$FIL"'
}

# ---- 7. create database + apply schema/procedures/seed ----------------------
# Same three directories, same order, as database/scripts/deploy.sh (local dev) —
# every file is a plain idempotent .sql script (CREATE ... IF NOT EXISTS, or
# CREATE OR ALTER for procedures), so re-running this after new migrations land
# only applies what's new.
log "Creating database [$DB_NAME]"
run_sql master "IF DB_ID('$DB_NAME') IS NULL CREATE DATABASE [$DB_NAME];"
ok "database ensured"

for stage in schema procedures seed; do
  log "Applying database/$stage"
  for f in "$REPO_ROOT/database/$stage"/*.sql; do
    docker cp "$f" "silen-sqlserver:/tmp/$(basename "$f")"
    run_sql_file "$DB_NAME" "/tmp/$(basename "$f")" >/dev/null
    ok "$(basename "$f")"
  done
done
tbl_count="$(run_sql "$DB_NAME" "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables;" | tr -d '[:space:]')"
ok "tables in $DB_NAME: $tbl_count"

# ---- 8. build + start API ---------------------------------------------------
log "Building + starting API container (this compiles the .NET app — may take a few minutes)"
docker compose up -d --build silen-api
ok "waiting for API to answer on 127.0.0.1:5010..."
api_ok=""
for i in $(seq 1 40); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:5010/api/plans 2>/dev/null || true)"
  [ -z "$code" ] && code=000
  # any real HTTP status (not 000) means Kestrel is serving; /api/plans needs no auth.
  if [ "$code" != "000" ]; then api_ok="$code"; break; fi
  sleep 5
done
[ -n "$api_ok" ] || { echo "API did not respond"; docker logs --tail 60 silen-api; exit 1; }
ok "API responding (HTTP $api_ok on /api/plans)"

# ---- 9. nginx site ----------------------------------------------------------
log "Configuring nginx site for $DOMAIN"
cp "$SCRIPT_DIR/nginx-silafit.tappit.click.conf" /etc/nginx/sites-available/$DOMAIN.conf
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf
nginx -t
systemctl reload nginx
ok "nginx reloaded (HTTP proxy live)"

# ---- 10. HTTPS via Let's Encrypt --------------------------------------------
log "Ensuring HTTPS + nginx TLS block for $DOMAIN"
# Step 9 above always re-copies nginx-$DOMAIN.conf from the repo, which only has
# the plain :80 block - so any 443 block certbot appended on a previous run gets
# wiped on every redeploy. Always re-running the --nginx installer here (instead
# of skipping whenever a cert already exists) is what re-adds that 443 block;
# certbot itself decides whether the cert actually needs reissuing, so this
# doesn't cost an extra ACME issuance/rate-limit hit once the cert is valid.
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$LE_EMAIL" --redirect
ok "HTTPS certificate + nginx TLS block ensured"
systemctl reload nginx

log "DONE"
echo "  DB      : SQL Server 2022 (container silen-sqlserver), database $DB_NAME"
echo "  API     : container silen-api on 127.0.0.1:5010"
echo "  Public  : https://$DOMAIN"
echo "  Secrets : $ENV_FILE"
