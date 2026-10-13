#!/usr/bin/env bash
###############################################################################
# SilaFit — from-scratch deploy for a fresh Ubuntu server (or an existing
# Hetzner box already running other sites — every step here is idempotent and
# scoped to its own container/port/vhost names, so it won't touch them).
#
# Provisions:
#   - Swap (memory safety on small boxes)
#   - Docker Engine + compose plugin
#   - PostgreSQL 18 (Docker) + silendb database + migrations/functions/seed
#   - Silen.Api (.NET 8, Docker) on 127.0.0.1:5010
#   - nginx reverse proxy for sila.fitness (+ api.sila.fitness, admin.sila.fitness)
#   - Let's Encrypt HTTPS (certbot)
#   - Host hardening: key-only SSH, fail2ban, ufw (80/443 from Cloudflare only),
#     nginx real-client-IP from Cloudflare, nightly encrypted pg_dump backups
#
# Idempotent: safe to re-run. Secrets are generated once and cached in ./.env.
#
# Usage (as root, from this directory):
#   ./deploy.sh
###############################################################################
set -euo pipefail

# ---- config -----------------------------------------------------------------
DOMAIN="sila.fitness"
API_DOMAIN="api.$DOMAIN"
IMAGES_DOMAIN="images.$DOMAIN"
ADMIN_DOMAIN="admin.$DOMAIN"
LE_EMAIL="nikpetrovski007@gmail.com"
DB_NAME="silendb"
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

# PostgreSQL superuser password (postgres). Only deploy-time tooling and the
# one-off seed tool use it; the API and cron tools log in as silen_app. Hex only,
# so it is safe unquoted in .env, YAML and connection strings.
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD" >> "$ENV_FILE"
  ok "Generated new PostgreSQL superuser password -> $ENV_FILE (chmod 600)"
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

# Password for silen_app, the least-privilege database role the API and the
# scheduled tools connect as (step 7) - EXECUTE on the dbo functions only.
if [ -z "${APP_DB_PASSWORD:-}" ]; then
  APP_DB_PASSWORD="Sa$(openssl rand -hex 18)#P4q"
  printf 'APP_DB_PASSWORD=%s\n' "$APP_DB_PASSWORD" >> "$ENV_FILE"
  ok "Generated new app DB login password -> $ENV_FILE (chmod 600)"
fi

export POSTGRES_PASSWORD JWT_SIGNING_KEY ENCRYPTION_MASTER_KEY APP_DB_PASSWORD
export GOOGLE_WEB_CLIENT_ID="${GOOGLE_WEB_CLIENT_ID:-}"
export APPLE_BUNDLE_ID="${APPLE_BUNDLE_ID:-com.nikolapetrovski.silafit}"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
export OPENROUTER_MODEL="${OPENROUTER_MODEL:-openai/gpt-4.1}"
# Push reminders. PUSH_ENABLED + a Firebase service-account JSON dropped at
# deploy/secrets/fcm-service-account.json turn on real FCM delivery; with
# PUSH_ENABLED unset the publisher still composes + records notifications, so
# the pipeline is safe to deploy before Firebase is wired.
export NOTIFICATION_PUBLISH_ENABLED="${NOTIFICATION_PUBLISH_ENABLED:-true}"
export NOTIFICATION_RUN_IN_API="${NOTIFICATION_RUN_IN_API:-false}"
export PUSH_ENABLED="${PUSH_ENABLED:-false}"
export PUSH_PROJECT_ID="${PUSH_PROJECT_ID:-}"
export PUSH_SERVICE_ACCOUNT_PATH="${PUSH_SERVICE_ACCOUNT_PATH:-/secrets/fcm-service-account.json}"

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
# Wait (up to 10 min) for the dpkg lock instead of failing outright: Ubuntu's
# apt-daily / unattended-upgrades timers hold it for minutes at a time.
echo 'DPkg::Lock::Timeout "600";' > /etc/apt/apt.conf.d/90silen-lock-timeout
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

# ---- 5. host hardening -------------------------------------------------------
# 5a. SSH: keys only. A 00- drop-in wins over everything else in sshd_config.d
# (first value read is the one sshd keeps), including cloud-init's 50- file.
log "Hardening SSH (key-only)"
cat > /etc/ssh/sshd_config.d/00-silen-hardening.conf <<'SSHD'
# Installed by deploy.sh - see deploy/README.md "Server hardening".
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
X11Forwarding no
SSHD
chmod 644 /etc/ssh/sshd_config.d/00-silen-hardening.conf
if sshd -t; then
  systemctl reload ssh 2>/dev/null || systemctl restart ssh
  ok "sshd: password login off, root key-only, X11 forwarding off"
else
  rm -f /etc/ssh/sshd_config.d/00-silen-hardening.conf
  warn "sshd -t rejected the hardening drop-in — removed it, SSH left unchanged"
fi

# 5b. fail2ban for SSH brute force.
log "Installing fail2ban"
apt-get install -y -qq fail2ban >/dev/null
cat > /etc/fail2ban/jail.d/silen-sshd.local <<'JAIL'
# Installed by deploy.sh
[sshd]
enabled  = true
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
JAIL
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
ok "fail2ban active (sshd jail)"

# 5c. Cloudflare ranges. sila.fitness and every subdomain are proxied through
# Cloudflare, so the origin should only ever be reached from Cloudflare's edge:
# the same list drives both the firewall (5d) and nginx's real-client-IP (5e).
# Cached so a failed fetch on a later run reuses the last good list.
CF_CACHE=/etc/silen/cloudflare-ips.txt
mkdir -p /etc/silen
log "Fetching Cloudflare IP ranges"
CF_RANGES=""
if cf_v4="$(curl -fsS --max-time 15 https://www.cloudflare.com/ips-v4)" && \
   cf_v6="$(curl -fsS --max-time 15 https://www.cloudflare.com/ips-v6)"; then
  CF_RANGES="$(printf '%s\n%s\n' "$cf_v4" "$cf_v6" | grep -E '^[0-9a-fA-F:.]+/[0-9]+$' || true)"
fi
if [ "$(printf '%s' "$CF_RANGES" | grep -c /)" -ge 10 ]; then
  printf '%s\n' "$CF_RANGES" > "$CF_CACHE"
  ok "$(wc -l < "$CF_CACHE") Cloudflare ranges"
elif [ -s "$CF_CACHE" ]; then
  CF_RANGES="$(cat "$CF_CACHE")"
  warn "could not fetch Cloudflare ranges — reusing cached list ($CF_CACHE)"
else
  CF_RANGES=""
  warn "could not fetch Cloudflare ranges and no cache exists — firewall/real-IP steps skipped"
fi

# 5d. Firewall. Default deny inbound; SSH open (or limited to SSH_ALLOWED_IPS from
# .env, space-separated); 80/443 only from Cloudflare. Docker's published ports are
# bound to 127.0.0.1 in docker-compose.yml, so ufw never needs to cover them.
# ORIGIN_ALLOW_ALL=true in .env opens 80/443 to everyone (e.g. with the Cloudflare
# proxy switched off).
log "Configuring firewall (ufw)"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
if [ -n "${SSH_ALLOWED_IPS:-}" ]; then
  for ip in $SSH_ALLOWED_IPS; do
    ufw allow proto tcp from "$ip" to any port 22 comment 'silen-ssh' >/dev/null
  done
  ufw delete allow 22/tcp >/dev/null 2>&1 || true
  ufw delete allow OpenSSH >/dev/null 2>&1 || true
  ok "SSH allowed from: $SSH_ALLOWED_IPS"
else
  ufw allow 22/tcp comment 'silen-ssh' >/dev/null
  ok "SSH allowed from anywhere (set SSH_ALLOWED_IPS in $ENV_FILE to restrict)"
fi
if [ "${ORIGIN_ALLOW_ALL:-false}" = "true" ]; then
  ufw allow 80,443/tcp comment 'silen-web' >/dev/null
  warn "ORIGIN_ALLOW_ALL=true — 80/443 open to everyone, not just Cloudflare"
elif [ -n "$CF_RANGES" ]; then
  for range in $CF_RANGES; do
    ufw allow proto tcp from "$range" to any port 80,443 comment 'cloudflare' >/dev/null
  done
  ufw delete allow 80,443/tcp >/dev/null 2>&1 || true
  ufw delete allow 'Nginx Full' >/dev/null 2>&1 || true
  ufw delete allow 'Nginx HTTP' >/dev/null 2>&1 || true
  ufw delete allow 'Nginx HTTPS' >/dev/null 2>&1 || true
  ok "80/443 allowed from Cloudflare only"
else
  ufw allow 80,443/tcp comment 'silen-web' >/dev/null
  warn "no Cloudflare list — 80/443 left open to everyone"
fi
ufw --force enable >/dev/null
ok "ufw active"

# 5e. nginx: real client IP from Cloudflare (otherwise every request appears to
# come from a Cloudflare edge address, and the API's per-IP rate limits throttle
# whole regions together), and no version number in the Server header.
log "Configuring nginx real-IP + server_tokens"
if [ -n "$CF_RANGES" ]; then
  {
    echo "# Generated by deploy.sh from https://www.cloudflare.com/ips - do not edit."
    for range in $CF_RANGES; do echo "set_real_ip_from $range;"; done
    echo "real_ip_header CF-Connecting-IP;"
  } > /etc/nginx/conf.d/silen-cloudflare-realip.conf
  ok "real client IP taken from CF-Connecting-IP"
fi
if grep -qE '^\s*server_tokens\s' /etc/nginx/nginx.conf; then
  sed -i -E 's/^(\s*)server_tokens\s+[a-z]+;.*/\1server_tokens off;/' /etc/nginx/nginx.conf
else
  echo "server_tokens off;" > /etc/nginx/conf.d/silen-server-tokens.conf
fi
ok "server_tokens off"

# ---- 6. start PostgreSQL -----------------------------------------------------
# A server that still runs its data on SQL Server must move it with
# migrate-to-postgres.sh first: applying the schema here would leave the API on
# an empty database, and the data copy only loads into empty tables.
pg_value() { docker exec -i silen-postgres psql -U postgres -d "$DB_NAME" -X -q -At -v ON_ERROR_STOP=1 -c "$1"; }
if docker ps -a --format '{{.Names}}' | grep -qx silen-sqlserver; then
  migrated=""
  if docker ps --format '{{.Names}}' | grep -qx silen-postgres; then
    migrated="$(pg_value "SELECT to_regclass('public.schema_migrations') IS NOT NULL AND EXISTS (SELECT 1 FROM public.schema_migrations)" 2>/dev/null || true)"
  fi
  if [ "$migrated" != "t" ]; then
    echo "This server still has its data in SQL Server (silen-sqlserver). Run ./migrate-to-postgres.sh cutover instead (see deploy/README.md \"PostgreSQL migration\")."
    exit 1
  fi
fi

log "Starting PostgreSQL container"
docker compose up -d silen-postgres
ok "waiting for PostgreSQL to become healthy..."
for i in $(seq 1 40); do
  status="$(docker inspect -f '{{.State.Health.Status}}' silen-postgres 2>/dev/null || echo starting)"
  [ "$status" = "healthy" ] && break
  sleep 3
done
[ "$status" = "healthy" ] || { echo "PostgreSQL did not become healthy"; docker logs --tail 40 silen-postgres; exit 1; }
ok "PostgreSQL healthy"

# ---- 6b. push secrets dir ---------------------------------------------------
# The API/tool containers mount ./secrets read-only for the Firebase service
# account. Creating it here (owned by root, 700) keeps `docker compose` from
# creating it lazily as a root-owned directory mid-run.
# Owned by UID 1654 - the non-root "app" user silen-api runs as (backend/Dockerfile).
# The tool containers still run as root, which can read it regardless.
API_UID=1654
mkdir -p "$SCRIPT_DIR/secrets"
chown -R "$API_UID:$API_UID" "$SCRIPT_DIR/secrets"
chmod 700 "$SCRIPT_DIR/secrets"
find "$SCRIPT_DIR/secrets" -type f -exec chmod 600 {} +
if [ ! -s "$SCRIPT_DIR/secrets/fcm-service-account.json" ]; then
  warn "No deploy/secrets/fcm-service-account.json yet — push reminders will be composed but not delivered (log-only sender). Drop the Firebase service account there and set PUSH_ENABLED=true in $ENV_FILE to enable delivery."
fi

# ---- 6c. uploaded-image storage ---------------------------------------------
# Bind-mounted into silen-api at /app/uploads (see docker-compose.yml) and read
# straight off disk by nginx's images.sila.fitness vhost - owned by the API
# container's non-root UID so it can write, world-readable so the nginx worker
# (www-data) can serve what it writes.
mkdir -p "$SCRIPT_DIR/uploads"
chown -R "$API_UID:$API_UID" "$SCRIPT_DIR/uploads"
chmod 755 "$SCRIPT_DIR/uploads"

# ---- 7. migrations, functions, seed + app role -------------------------------
# database/apply.sh applies each new migration once, reloads every function, and
# seeds reference data on a brand-new database only. It also (re)creates the
# silen_owner / silen_app roles: silen_app can call the SECURITY DEFINER
# functions in dbo and nothing else. Re-running resets its password to .env's.
log "Applying database/ to $DB_NAME"
PSQL="docker exec -i silen-postgres psql -U postgres -d $DB_NAME" "$REPO_ROOT/database/apply.sh"
echo "ALTER ROLE silen_app WITH LOGIN PASSWORD :'pw';" \
  | docker exec -i silen-postgres psql -U postgres -d "$DB_NAME" -X -q -v ON_ERROR_STOP=1 -v pw="$APP_DB_PASSWORD"
ok "silen_app: EXECUTE on dbo functions only"
ok "tables in $DB_NAME: $(pg_value "SELECT count(*) FROM pg_tables WHERE schemaname = 'dbo'")"

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
log "Configuring nginx site for $DOMAIN and $API_DOMAIN"

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

mkdir -p /etc/nginx/snippets
cp "$SCRIPT_DIR/nginx-security-headers.conf" /etc/nginx/snippets/silen-security-headers.conf
cp "$SCRIPT_DIR/nginx-admin-headers.conf" /etc/nginx/snippets/silen-admin-headers.conf
cp "$SCRIPT_DIR/nginx-sila.fitness.conf" /etc/nginx/sites-available/$DOMAIN.conf
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
log "Ensuring HTTPS + nginx TLS block for $DOMAIN and $API_DOMAIN"
# Step 9 above always re-copies nginx-$DOMAIN.conf from the repo, which only has
# the plain :80 blocks - so any 443 block certbot appended on a previous run gets
# wiped on every redeploy. Always re-running the --nginx installer here (instead
# of skipping whenever a cert already exists) is what re-adds that 443 block;
# certbot itself decides whether the cert actually needs reissuing, so this
# doesn't cost an extra ACME issuance/rate-limit hit once the cert is valid.
# Best-effort: DNS for $DOMAIN/$API_DOMAIN might not point at this box yet (or
# might have moved on, e.g. after a server migration), in which case ACME
# validation fails by design. Treating that as fatal used to abort the script
# here, before the monthly-review / notification-publish / subscription-sync /
# weekly-plan-generation cron steps, leaving
# them stale. certbot rolls its nginx edits back on failure, so it is safe to
# warn and continue.
if certbot --nginx -d "$DOMAIN" -d "$API_DOMAIN" --non-interactive --agree-tos -m "$LE_EMAIL" --redirect; then
  ok "HTTPS certificate + nginx TLS block ensured"
else
  warn "certbot could not (re)issue a certificate for $DOMAIN/$API_DOMAIN — continuing; verify DNS points at this server and TLS is set up correctly."
fi

# Issued separately from $DOMAIN/$API_DOMAIN on purpose: certbot's multi-SAN
# issuance is all-or-nothing, so if images.sila.fitness's DNS record isn't
# created yet (or hasn't propagated), bundling it into the call above would
# fail the *whole* request and take down the already-working sila.fitness/
# api.sila.fitness cert along with it. Keeping it independent means a not-yet-
# ready images subdomain only warns here, never touches the other two.
if certbot --nginx -d "$IMAGES_DOMAIN" --non-interactive --agree-tos -m "$LE_EMAIL" --redirect; then
  ok "HTTPS certificate + nginx TLS block ensured for $IMAGES_DOMAIN"
else
  warn "certbot could not (re)issue a certificate for $IMAGES_DOMAIN — continuing; add a DNS A record for $IMAGES_DOMAIN pointing at this server, then re-run deploy.sh."
fi
# Same reasoning as $IMAGES_DOMAIN: its own certificate, so a missing DNS record for
# the admin host never takes the public site's cert down with it.
if certbot --nginx -d "$ADMIN_DOMAIN" --non-interactive --agree-tos -m "$LE_EMAIL" --redirect; then
  ok "HTTPS certificate + nginx TLS block ensured for $ADMIN_DOMAIN"
else
  warn "certbot could not (re)issue a certificate for $ADMIN_DOMAIN — continuing; add a DNS A record for $ADMIN_DOMAIN pointing at this server, then re-run deploy.sh."
fi
systemctl reload nginx

# ---- 10b. verify the console gate actually refuses anonymous access --------
# The console (https://$ADMIN_DOMAIN/) must never answer 200 to a request with no
# session cookie. Checked over HTTPS (certbot just configured it); best-effort,
# since DNS/TLS can need a moment on a first-ever deploy.
log "Checking the admin console gate"
console_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://$ADMIN_DOMAIN/" 2>/dev/null || true)"
case "${console_code:-000}" in
  302|303) ok "anonymous request to https://$ADMIN_DOMAIN/ is redirected to the sign-in page (HTTP $console_code)" ;;
  401|403) ok "anonymous request to https://$ADMIN_DOMAIN/ is refused (HTTP $console_code)" ;;
  200)    warn "SERVED THE CONSOLE WITHOUT A SESSION — the gate is not enforcing. Check the auth_request block and that the API answers /api/admin/auth/session with 401." ;;
  000)    warn "could not reach https://$ADMIN_DOMAIN yet (DNS/TLS may still be settling) — re-check the gate by hand with: curl -skI https://$ADMIN_DOMAIN/" ;;
  *)      warn "unexpected HTTP $console_code from https://$ADMIN_DOMAIN/" ;;
esac

# ---- 11. monthly review cron ------------------------------------------------
# Generates + emails the monthly AI progress overview for every active ADVANCED
# subscriber (see the silen-monthly-review compose service). A system cron entry
# fits better than a long-running container: it is a short, once-a-month batch.
# Re-running deploy.sh just rewrites the same two files.
log "Installing monthly review cron (06:00 on the 1st)"
cat > "$SCRIPT_DIR/run-monthly-review.sh" <<'WRAPPER'
#!/usr/bin/env bash
# Installed by deploy.sh - runs the monthly review batch for the previous month.
# Output is captured to /var/log/silen-monthly-review.log by the cron entry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec docker compose --profile tools run --rm --build silen-monthly-review
WRAPPER
chmod 750 "$SCRIPT_DIR/run-monthly-review.sh"

cat > /etc/cron.d/silen-monthly-review <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# m h dom mon dow user command
0 6 1 * * root $SCRIPT_DIR/run-monthly-review.sh >> /var/log/silen-monthly-review.log 2>&1
CRON
chmod 644 /etc/cron.d/silen-monthly-review
ok "cron installed: /etc/cron.d/silen-monthly-review -> $SCRIPT_DIR/run-monthly-review.sh"

# ---- 12. notification publish cron ------------------------------------------
# Frequent reminder batch (Silen.Tools.NotificationPublish). Built once here -
# not with --build in the wrapper - because it runs every five minutes and a
# per-tick image rebuild would be wasteful. Dedupe keys in dbo.UserNotifications
# make overlapping ticks harmless.
log "Building notification publisher image"
docker compose --profile tools build silen-notification-publish >/dev/null
ok "silen-notification-publish image built"

log "Installing notification publish cron (every 5 minutes)"
cat > "$SCRIPT_DIR/run-notification-publish.sh" <<'WRAPPER'
#!/usr/bin/env bash
# Installed by deploy.sh - runs the notification publish batch once.
# Output is captured to /var/log/silen-notification-publish.log by the cron entry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec docker compose --profile tools run --rm silen-notification-publish
WRAPPER
chmod 750 "$SCRIPT_DIR/run-notification-publish.sh"

cat > /etc/cron.d/silen-notification-publish <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# m h dom mon dow user command
*/5 * * * * root $SCRIPT_DIR/run-notification-publish.sh >> /var/log/silen-notification-publish.log 2>&1
CRON
chmod 644 /etc/cron.d/silen-notification-publish
ok "cron installed: /etc/cron.d/silen-notification-publish -> $SCRIPT_DIR/run-notification-publish.sh"

# ---- 12b. subscription reconciliation cron ----------------------------------
# Safety net for App Store/Play Store renewals, cancellations, refunds and
# expirations that SubscriptionWebhooksController's push notifications missed
# or arrived late for (Silen.Tools.SubscriptionSync). Built once here, not
# with --build in the wrapper, same reasoning as notification-publish above.
# Idempotent: activation is keyed on (Store, TransactionId).
log "Building subscription sync image"
docker compose --profile tools build silen-subscription-sync >/dev/null
ok "silen-subscription-sync image built"

log "Installing subscription sync cron (every 4 hours)"
cat > "$SCRIPT_DIR/run-subscription-sync.sh" <<'WRAPPER'
#!/usr/bin/env bash
# Installed by deploy.sh - runs the subscription reconciliation batch once.
# Output is captured to /var/log/silen-subscription-sync.log by the cron entry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec docker compose --profile tools run --rm silen-subscription-sync
WRAPPER
chmod 750 "$SCRIPT_DIR/run-subscription-sync.sh"

cat > /etc/cron.d/silen-subscription-sync <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# m h dom mon dow user command
0 */4 * * * root $SCRIPT_DIR/run-subscription-sync.sh >> /var/log/silen-subscription-sync.log 2>&1
CRON
chmod 644 /etc/cron.d/silen-subscription-sync
ok "cron installed: /etc/cron.d/silen-subscription-sync -> $SCRIPT_DIR/run-subscription-sync.sh"

# ---- 13. weekly AI plan generation cron -------------------------------------
# Generates + delivers a fresh custom split + diet plan for every active
# ADVANCED subscriber (see the silen-weekly-plan-generation compose service).
# The generated diet plan becomes active automatically; a new split remains a
# recommendation. Runs Sunday morning so the
# week it summarizes (Mon-Sun) has just closed. Re-running deploy.sh just
# rewrites the same two files; WeeklyAiPlanDeliveries dedupes any overlap.
log "Installing weekly AI plan generation cron (06:00 on Sundays)"
cat > "$SCRIPT_DIR/run-weekly-plan-generation.sh" <<'WRAPPER'
#!/usr/bin/env bash
# Installed by deploy.sh - runs the weekly AI plan generation batch for the week that just ended.
# Output is captured to /var/log/silen-weekly-plan-generation.log by the cron entry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec docker compose --profile tools run --rm --build silen-weekly-plan-generation
WRAPPER
chmod 750 "$SCRIPT_DIR/run-weekly-plan-generation.sh"

cat > /etc/cron.d/silen-weekly-plan-generation <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# m h dom mon dow user command
0 6 * * 0 root $SCRIPT_DIR/run-weekly-plan-generation.sh >> /var/log/silen-weekly-plan-generation.log 2>&1
CRON
chmod 644 /etc/cron.d/silen-weekly-plan-generation
ok "cron installed: /etc/cron.d/silen-weekly-plan-generation -> $SCRIPT_DIR/run-weekly-plan-generation.sh"

# ---- 14. nightly database backup --------------------------------------------
# Full pg_dump (custom format, zstd) of $DB_NAME every night, encrypted with age
# as it is written to $BACKUP_DIR (outside deploy/, so publish.sh's rsync --delete
# never touches it) and kept for BACKUP_RETENTION_DAYS (default 3 - the disk is
# small). With BACKUP_REMOTE set in .env (e.g.
# u123456@u123456.your-storagebox.de:silen-backups) each run also mirrors the
# directory off the box over SSH (port BACKUP_REMOTE_PORT, default 23 for a
# Hetzner Storage Box) with the key below; the Storage Box's own snapshots
# provide longer history.
#
# Dumps are encrypted to the public half of an age key generated here once
# (/etc/silen/backup-age.key). Restoring one needs that key's private half: copy
# it off the server to a password manager - a backup is useless without it, and
# anyone holding it plus a dump can read the database. See README.md "Backups".
BACKUP_DIR=/opt/silen/backups
BACKUP_KEY=/root/.ssh/silen_backup_ed25519
AGE_KEY=/etc/silen/backup-age.key
log "Installing nightly database backup cron (03:30)"
mkdir -p "$BACKUP_DIR" /etc/silen
chmod 700 "$BACKUP_DIR" /etc/silen
command -v age >/dev/null || apt-get install -y -qq age
if [ ! -s "$AGE_KEY" ]; then
  age-keygen -o "$AGE_KEY" 2>/dev/null
  chmod 600 "$AGE_KEY"
  warn "New backup encryption key $AGE_KEY - COPY IT OFF THIS SERVER NOW (password manager). Without it no backup can be restored:"
  warn "  scp root@<server>:$AGE_KEY ~/silen-backup-age.key"
fi
age-keygen -y "$AGE_KEY" > /etc/silen/backup-age.pub
if [ ! -f "$BACKUP_KEY" ]; then
  ssh-keygen -q -t ed25519 -N "" -C "silen-backup@$(hostname)" -f "$BACKUP_KEY"
fi

# Google Drive target: /etc/silen/rclone.conf holds a [silen-gdrive] remote (an
# OAuth token limited to the drive.file scope - it only sees files it uploaded),
# created on a laptop with `rclone config create` and piped here; see README.md.
GDRIVE_CONF=/etc/silen/rclone.conf
if [ -f "$GDRIVE_CONF" ]; then
  chown root:root "$GDRIVE_CONF"
  chmod 600 "$GDRIVE_CONF"
  command -v rclone >/dev/null || apt-get install -y -qq rclone
  rclone --config "$GDRIVE_CONF" lsd silen-gdrive: >/dev/null \
    || { echo "rclone cannot reach Google Drive with $GDRIVE_CONF (token revoked? re-create it, see README.md)"; exit 1; }
  ok "Google Drive reachable (backups go to My Drive/${BACKUP_GDRIVE_FOLDER:-silen-backups})"
fi

cat > "$SCRIPT_DIR/run-db-backup.sh" <<'WRAPPER'
#!/usr/bin/env bash
# Installed by deploy.sh - nightly full backup of silendb, see deploy.sh step 14.
# Output is captured to /var/log/silen-db-backup.log by the cron entry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
set -a; source ./.env; set +a

DB=silendb
BACKUP_DIR=/opt/silen/backups
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-3}"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
FILE="${DB}_${STAMP}.dump.age"

echo "[$(date -u +%FT%TZ)] backup $FILE"
# Streamed straight into age, so no unencrypted copy ever touches the disk.
# pipefail turns a pg_dump failure into a failed run instead of a short file.
docker exec silen-postgres pg_dump -U postgres -d "$DB" -Fc -Z zstd:6 \
  | age -R /etc/silen/backup-age.pub -o "$BACKUP_DIR/$FILE.partial"
mv "$BACKUP_DIR/$FILE.partial" "$BACKUP_DIR/$FILE"
chmod 600 "$BACKUP_DIR/$FILE"
echo "  saved $(du -h "$BACKUP_DIR/$FILE" | cut -f1) -> $BACKUP_DIR/$FILE"

rm -f "$BACKUP_DIR"/*.partial
# SilenDb_*.bak: the SQL Server backups from before the PostgreSQL move age out the same way.
find "$BACKUP_DIR" \( -name "${DB}_*.dump.age" -o -name "SilenDb_*.bak" \) -type f -mtime +"$RETENTION_DAYS" -print -delete

if [ -n "${BACKUP_REMOTE:-}" ]; then
  rsync -a --delete -e "ssh -p ${BACKUP_REMOTE_PORT:-23} -i /root/.ssh/silen_backup_ed25519 -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
    "$BACKUP_DIR/" "$BACKUP_REMOTE/"
  echo "  synced to $BACKUP_REMOTE"
fi

GDRIVE_CONF=/etc/silen/rclone.conf
if [ -f "$GDRIVE_CONF" ]; then
  GDRIVE="silen-gdrive:${BACKUP_GDRIVE_FOLDER:-silen-backups}"
  rclone --config "$GDRIVE_CONF" copy "$BACKUP_DIR/$FILE" "$GDRIVE" --retries 5
  echo "  uploaded to Google Drive ($GDRIVE)"
  # Delete permanently: trashed files still count against the account's 15 GB.
  rclone --config "$GDRIVE_CONF" delete "$GDRIVE" --include "${DB}_*.dump.age" --include "SilenDb_*.bak" \
    --min-age "${BACKUP_GDRIVE_RETENTION_DAYS:-7}d" --drive-use-trash=false
fi

if [ -z "${BACKUP_REMOTE:-}" ] && [ ! -f "$GDRIVE_CONF" ]; then
  echo "  WARNING: no BACKUP_REMOTE or Google Drive configured - this backup exists only on this server"
fi

used="$(df --output=pcent / | tail -1 | tr -dc 0-9)"
[ "$used" -lt 90 ] || echo "  WARNING: root filesystem ${used}% full"
WRAPPER
chmod 750 "$SCRIPT_DIR/run-db-backup.sh"

cat > /etc/cron.d/silen-db-backup <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# m h dom mon dow user command
30 3 * * * root $SCRIPT_DIR/run-db-backup.sh >> /var/log/silen-db-backup.log 2>&1
CRON
chmod 644 /etc/cron.d/silen-db-backup
ok "cron installed: /etc/cron.d/silen-db-backup -> $SCRIPT_DIR/run-db-backup.sh"
if [ -z "${BACKUP_REMOTE:-}" ] && [ ! -f "$GDRIVE_CONF" ]; then
  warn "No BACKUP_REMOTE or Google Drive configured — backups stay on this server only (see deploy/README.md \"Backups\"). Public key to authorize on the backup target:"
  cat "$BACKUP_KEY.pub"
fi

log "DONE"
echo "  DB      : PostgreSQL 18 (container silen-postgres), database $DB_NAME"
echo "  API     : container silen-api on 127.0.0.1:5010"
echo "  Public  : https://$DOMAIN"
echo "  Secrets : $ENV_FILE"
