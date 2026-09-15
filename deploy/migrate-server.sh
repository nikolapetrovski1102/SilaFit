#!/usr/bin/env bash
# Run on the Mac. Transfers the deployed release, not uncommitted local changes.
set -euo pipefail
SOURCE=${SOURCE:-root@silafit.tappit.click}
TARGET=${TARGET:-root@46.224.235.167}
KEY=${KEY:-$HOME/.ssh/silafit_ed25519}
HERE=$(cd "$(dirname "$0")" && pwd)
old() { ssh -o BatchMode=yes "$SOURCE" "set -e; $*"; }
new() { ssh -o BatchMode=yes -i "$KEY" "$TARGET" "set -e; $*"; }
case ${1:-help} in
prepare)
  new 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; apt-get install -y -qq docker.io docker-compose-v2 nginx certbot python3-certbot-nginx rsync dnsutils; systemctl enable --now docker nginx; install -d -m 700 /opt/silen-migration'
  # Retain secrets, deployment certificates, source, website and job wrappers.
  old 'tar -C /opt -czf - silen' | new 'umask 077; cat > /opt/silen-migration/release.tar.gz; tar -C /opt -xzf /opt/silen-migration/release.tar.gz'
  # Preserve the exact running SQL binary so system databases match.
  digest=$(old 'docker image inspect mcr.microsoft.com/mssql/server:2022-latest --format "{{index .RepoDigests 0}}"')
  [[ $digest =~ ^mcr.microsoft.com/mssql/server@sha256:[a-f0-9]{64}$ ]]
  new "docker pull '$digest'; docker tag '$digest' mcr.microsoft.com/mssql/server:2022-latest"
  old 'docker image ls --format "{{.Repository}}:{{.Tag}}" | awk "/^silenfit-/" | xargs docker save | gzip -1' | new 'gunzip | docker load'
  # Carry the old HTTPS identity to keep installed mobile clients operational.
  old 'tar -C / -czhf - etc/letsencrypt/live/silafit.tappit.click' | new 'tar -C / -xzf -'
  old 'cat /etc/nginx/sites-enabled/silafit.tappit.click.conf' | new 'cat > /etc/nginx/sites-available/silafit.tappit.click.conf'
  old 'tar -C /etc/cron.d -czf - silen-monthly-review silen-notification-publish' | new 'cat > /opt/silen-migration/cron.tar.gz'
  new 'test -f /etc/letsencrypt/options-ssl-nginx.conf || cp /usr/lib/python3/dist-packages/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf /etc/letsencrypt/options-ssl-nginx.conf'
  old 'cat /etc/letsencrypt/ssl-dhparams.pem' | new 'cat > /etc/letsencrypt/ssl-dhparams.pem'
  cat "$HERE/migration/nginx-silen.conf" | new 'cat > /etc/nginx/sites-available/sila.fitness.conf'
  cat "$HERE/migration/compose.override.yaml" | new 'cat > /opt/silen/deploy/compose.override.yaml'
  new 'ln -sf /etc/nginx/sites-available/sila.fitness.conf /etc/nginx/sites-enabled/; ln -sf /etc/nginx/sites-available/silafit.tappit.click.conf /etc/nginx/sites-enabled/; chmod -R a+rX /opt/silen/website; nginx -t; systemctl reload nginx'
  ;;
copy-db)
  # The target must not already have a live DB. Never overwrite a migrated DB.
  new 'test ! -e /opt/silen-migration/database-copied; ! docker inspect silen-sqlserver >/dev/null 2>&1'
  old 'install -d -m 700 /opt/silen-migration; cp /etc/cron.d/silen-* /opt/silen-migration/; rm /etc/cron.d/silen-monthly-review /etc/cron.d/silen-notification-publish; docker stop -t 60 silen-api; for c in silenfit-silen-notification-publish-run silenfit-silen-monthly-review-run; do docker ps --filter name="$c" -q | xargs -r docker stop -t 60; done; docker stop -t 120 silen-sqlserver'
  # Keep all system databases, TDE certificates and machine encryption secrets.
  # Source remains stopped on error: do not create two writable databases.
  old 'tar --numeric-owner -C /var/lib/docker/volumes/silenfit_silen-sqldata/_data -czf - .' | new 'umask 077; cat > /opt/silen-migration/database.tar.gz; gzip -t /opt/silen-migration/database.tar.gz; docker volume create silenfit_silen-sqldata; tar --numeric-owner -C /var/lib/docker/volumes/silenfit_silen-sqldata/_data -xzf /opt/silen-migration/database.tar.gz; touch /opt/silen-migration/database-copied'
  new 'cd /opt/silen/deploy; docker compose up -d --no-build silen-sqlserver silen-api'
  ;;
activate)
  new 'curl -fsS http://127.0.0.1:5010/health/ready; test -e /opt/silen-migration/database-copied'
  # Never reactivate the old DB after this point: the new DB accepts writes.
  old 'python3 -' <<'PY'
from pathlib import Path
p=Path('/etc/nginx/sites-available/silafit.tappit.click.conf')
s=p.read_text()
backup=Path('/opt/silen-migration/nginx-before-cutover.conf')
if not backup.exists():
    backup.write_text(s)
if 'proxy_pass http://127.0.0.1:5010' in s:
    s=s.replace('proxy_pass http://127.0.0.1:5010', 'proxy_pass https://46.224.235.167')
    s=s.replace('proxy_set_header Host $host;', '''proxy_ssl_server_name on;
        proxy_ssl_name silafit.tappit.click;
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 3;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        proxy_set_header Host $host;''')
    p.write_text(s)
PY
  old 'nginx -t && systemctl reload nginx; docker update --restart=no silen-api silen-sqlserver'
  new 'tar -C /etc/cron.d -xzf /opt/silen-migration/cron.tar.gz; chmod 644 /etc/cron.d/silen-*; touch /opt/silen-migration/activated'
  ;;
tls)
  new 'set -e; for domain in sila.fitness api.sila.fitness; do dig +short A "$domain" @1.1.1.1 | grep -qx 46.224.235.167 || { echo "DNS not ready: $domain"; exit 1; }; done; certbot --nginx --non-interactive --agree-tos --email nikpetrovski007@gmail.com --redirect -d sila.fitness -d api.sila.fitness; systemctl enable --now certbot.timer; nginx -t'
  ;;
*) echo 'Usage: deploy/migrate-server.sh prepare|copy-db|activate|tls'; exit 2 ;;
esac
