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

# Application-level column encryption master key (Encryption__MasterKeyBase64,
# Silen.Common.Helpers.FieldCipher — AES-256-GCM). Must decode to exactly 32
# raw bytes, hence base64 (not hex, unlike JWT_SIGNING_KEY above).
if [ -z "${ENCRYPTION_MASTER_KEY:-}" ]; then
  ENCRYPTION_MASTER_KEY="$(openssl rand -base64 32)"
  printf 'ENCRYPTION_MASTER_KEY=%s\n' "$ENCRYPTION_MASTER_KEY" >> "$ENV_FILE"
  ok "Generated new column-encryption master key -> $ENV_FILE (chmod 600)"
fi

# TDE master key password — protects the server-level (master db) master key
# used to hold the TDE certificate. SQL Server complexity rules, same shape as SA_PASSWORD.
if [ -z "${TDE_MASTER_KEY_PASSWORD:-}" ]; then
  TDE_MASTER_KEY_PASSWORD="Sf$(openssl rand -hex 18)#K7m"
  printf 'TDE_MASTER_KEY_PASSWORD=%s\n' "$TDE_MASTER_KEY_PASSWORD" >> "$ENV_FILE"
  ok "Generated new TDE master key password -> $ENV_FILE (chmod 600)"
fi

# TDE certificate private-key backup password — protects the .pvk file backed
# up to deploy/tde-cert-backup/ (see step 7b below).
if [ -z "${TDE_CERT_BACKUP_PASSWORD:-}" ]; then
  TDE_CERT_BACKUP_PASSWORD="Sf$(openssl rand -hex 18)#K7m"
  printf 'TDE_CERT_BACKUP_PASSWORD=%s\n' "$TDE_CERT_BACKUP_PASSWORD" >> "$ENV_FILE"
  ok "Generated new TDE certificate backup password -> $ENV_FILE (chmod 600)"
fi

export SA_PASSWORD JWT_SIGNING_KEY ENCRYPTION_MASTER_KEY TDE_MASTER_KEY_PASSWORD TDE_CERT_BACKUP_PASSWORD
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
run_sql() {   # run_sql <db> <query> — headers off (-h -1) since callers often
              # compare the trimmed result numerically (e.g. is_encrypted below)
  docker exec -e SAPW="$SA_PASSWORD" -e DBN="$1" -e QRY="$2" silen-sqlserver /bin/bash -c '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then BIN=/opt/mssql-tools18/bin/sqlcmd; C=-C;
    else BIN=/opt/mssql-tools/bin/sqlcmd; C=; fi
    "$BIN" -S localhost -U sa -P "$SAPW" $C -b -h -1 -d "$DBN" -Q "$QRY"'
}
run_sql_file() {  # run_sql_file <db> <container_path>
  docker exec -e SAPW="$SA_PASSWORD" -e DBN="$1" -e FIL="$2" silen-sqlserver /bin/bash -c '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then BIN=/opt/mssql-tools18/bin/sqlcmd; C=-C;
    else BIN=/opt/mssql-tools/bin/sqlcmd; C=; fi
    "$BIN" -S localhost -U sa -P "$SAPW" $C -b -d "$DBN" -i "$FIL"'
}

# One-time backfill for the column-encryption rollout (see step 7's hook
# below) — builds and runs Silen.Tools.EncryptExistingData in a throwaway
# container on the compose network, resumable/idempotent by design (only
# rows whose *Enc column is still NULL get processed).
run_encryption_backfill() {
  log "Backfilling AES-256-GCM ciphertext into *Enc columns before cutover"
  # --build: `run` alone reuses an already-built image even when the Dockerfile
  # changed on disk (bit us once - fixed image, stale container, same crash).
  docker compose --profile tools run --build --rm silen-encrypt-backfill
  ok "backfill complete"
}

# ---- 7. create database + apply schema/procedures/seed ----------------------
# Same three directories, same order, as database/scripts/deploy.sh (local dev) —
# every file is a plain idempotent .sql script (CREATE ... IF NOT EXISTS, or
# CREATE OR ALTER for procedures), so re-running this after new migrations land
# only applies what's new.
log "Creating database [$DB_NAME]"
run_sql master "IF DB_ID('$DB_NAME') IS NULL CREATE DATABASE [$DB_NAME];"
ok "database ensured"

# database/manual-migrations/ is intentionally NOT one of these directories —
# it holds migrations (e.g. 026_ColumnEncryptionCleanup.sql) that must only
# ever run when a human explicitly invokes them, never swept up here.
for stage in schema procedures seed; do
  log "Applying database/$stage"
  for f in "$REPO_ROOT/database/$stage"/*.sql; do
    fname="$(basename "$f")"

    # The column-encryption rollout (024/025) needs real data encrypted into
    # the new *Enc columns BEFORE 025 renames them into place — otherwise the
    # cutover promotes empty/NULL ciphertext columns over live plaintext data.
    # Run the backfill tool here, once, right before 025 is applied.
    if [ "$fname" = "025_ColumnEncryptionCutover.sql" ]; then
      run_encryption_backfill
    fi

    docker cp "$f" "silen-sqlserver:/tmp/$fname"
    run_sql_file "$DB_NAME" "/tmp/$fname" >/dev/null
    ok "$fname"
  done
done
tbl_count="$(run_sql "$DB_NAME" "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables;" | tr -d '[:space:]')"
ok "tables in $DB_NAME: $tbl_count"

# ---- 7b. Transparent Data Encryption (TDE) ----------------------------------
log "Ensuring Transparent Data Encryption (TDE) for [$DB_NAME]"
is_encrypted="$(run_sql master "SET NOCOUNT ON; SELECT ISNULL(DATABASEPROPERTYEX('$DB_NAME','IsEncrypted'),0);" | tr -d '[:space:]')"
if [ "$is_encrypted" = "1" ]; then
  ok "TDE already enabled"
else
  cert_exists="$(run_sql master "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.certificates WHERE name = 'SilenTdeCert';" | tr -d '[:space:]')"
  if [ "$cert_exists" = "0" ]; then
    log "Creating TDE certificate (one-time)"
    run_sql master "IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##') CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$TDE_MASTER_KEY_PASSWORD';"
    run_sql master "CREATE CERTIFICATE SilenTdeCert WITH SUBJECT = N'SilenDb TDE certificate';"
    docker exec silen-sqlserver mkdir -p /var/opt/mssql/tde-backup
    run_sql master "BACKUP CERTIFICATE SilenTdeCert TO FILE = N'/var/opt/mssql/tde-backup/SilenTdeCert.cer' WITH PRIVATE KEY (FILE = N'/var/opt/mssql/tde-backup/SilenTdeCert.pvk', ENCRYPTION BY PASSWORD = N'$TDE_CERT_BACKUP_PASSWORD');"

    # Copy the certificate + private key OUT of the container/volume onto the
    # host immediately - they otherwise live only inside silen-sqldata, so a
    # lost/corrupted volume would take the only copy down with it.
    mkdir -p "$SCRIPT_DIR/tde-cert-backup"
    docker cp "silen-sqlserver:/var/opt/mssql/tde-backup/SilenTdeCert.cer" "$SCRIPT_DIR/tde-cert-backup/SilenTdeCert.cer"
    docker cp "silen-sqlserver:/var/opt/mssql/tde-backup/SilenTdeCert.pvk" "$SCRIPT_DIR/tde-cert-backup/SilenTdeCert.pvk"
    chmod 600 "$SCRIPT_DIR/tde-cert-backup/"*
    warn "TDE certificate backed up to $SCRIPT_DIR/tde-cert-backup/ — MOVE THIS TO SEPARATE SECURE STORAGE NOW. Losing it permanently locks the encrypted database (see deploy/README.md)."
  else
    ok "SilenTdeCert already exists — reusing"
  fi

  run_sql "$DB_NAME" "IF NOT EXISTS (SELECT 1 FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID()) CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256 ENCRYPTION BY SERVER CERTIFICATE SilenTdeCert;"
  run_sql "$DB_NAME" "ALTER DATABASE [$DB_NAME] SET ENCRYPTION ON;"
  ok "TDE enabled on $DB_NAME"
fi

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

# The vhost now serves the static site out of $REPO_ROOT/website (publish.sh uploads
# it) and gates admin.html behind an auth_request to the API. Both need the directory
# to exist and be readable by the nginx worker, or every page 404s.
mkdir -p "$REPO_ROOT/website"
chmod -R a+rX "$REPO_ROOT/website"
if [ -f "$REPO_ROOT/website/index.html" ]; then
  ok "website/ present on the server"
else
  warn "website/ has no index.html yet — run deploy/publish.sh from your machine to upload the site"
fi

cp "$SCRIPT_DIR/nginx-silafit.tappit.click.conf" /etc/nginx/sites-available/$DOMAIN.conf
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf
nginx -t
systemctl reload nginx
ok "nginx reloaded (static site + /api proxy live)"

# Fail here rather than discover in production that the console gate silently
# isn't enforcing. Ubuntu's nginx ships auth_request, but the module can be absent
# on a custom build — and without it `nginx -t` still passes while the whole
# single-choke-point design quietly stops existing.
if nginx -V 2>&1 | grep -q 'with-http_auth_request_module'; then
  ok "auth_request module available (admin console gate is enforceable)"
else
  warn "nginx has no auth_request module — admin.html cannot be gated by this vhost. Install Ubuntu's nginx package or compile the module in."
fi

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

# ---- 10b. verify the console gate actually refuses anonymous access --------
# admin.html must never answer 200 to a request with no session cookie. Checked
# over HTTPS (certbot just configured it); best-effort, since DNS/TLS can need a
# moment on a first-ever deploy.
log "Checking the admin console gate"
console_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://$DOMAIN/admin.html" 2>/dev/null || true)"
case "${console_code:-000}" in
  302|303) ok "anonymous request to /admin.html is redirected to the sign-in page (HTTP $console_code)" ;;
  401|403) ok "anonymous request to /admin.html is refused (HTTP $console_code)" ;;
  200)    warn "SERVER /admin.html WITHOUT A SESSION — the gate is not enforcing. Check the auth_request block and that the API answers /api/admin/auth/session with 401." ;;
  000)    warn "could not reach https://$DOMAIN yet (DNS/TLS may still be settling) — re-check the gate by hand with: curl -skI https://$DOMAIN/admin.html" ;;
  *)      warn "unexpected HTTP $console_code from /admin.html" ;;
esac

log "DONE"
echo "  DB      : SQL Server 2022 (container silen-sqlserver), database $DB_NAME"
echo "  API     : container silen-api on 127.0.0.1:5010"
echo "  Public  : https://$DOMAIN"
echo "  Secrets : $ENV_FILE"
