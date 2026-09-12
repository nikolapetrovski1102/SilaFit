# SilaFit deployment

From-scratch deploy of the .NET API + SQL Server for a fresh Ubuntu server,
served at https://silafit.tappit.click.

## Layout expected on the server

```
/opt/silen/
  backend/     # app source (built into a Docker image)
  database/    # schema/, procedures/, seed/ .sql scripts
  deploy/
    deploy.sh                             # run this as root
    docker-compose.yml                    # db + api services
    nginx-silafit.tappit.click.conf
    well-known/assetlinks.json            # Android App Links verification (served statically)
    .env                                  # generated on first run — holds secrets
```

## Run

```bash
cd /opt/silen/deploy
sudo ./deploy.sh
```
Idempotent — safe to re-run, including after new files land in `database/schema`,
`database/procedures`, or `database/seed` (every script there is safe to re-apply).
To rebuild only the API after a code change:
```bash
cd /opt/silen/deploy && docker compose up -d --build silen-api
```

## What it does
1. Swap + Docker Engine + nginx + certbot (skipped if already present — safe to
   run alongside other sites on the same box)
2. SQL Server 2022 container, creates the `SilenDb` database, applies
   `database/schema`, `database/procedures`, then `database/seed`, in that order
3. Builds & runs the API on `127.0.0.1:5010`
4. nginx reverse proxy for `silafit.tappit.click`
5. Let's Encrypt HTTPS with auto HTTP->HTTPS redirect

## Notes
- DB engine is **Microsoft SQL Server** (all access goes through stored procedures,
  no ORM/LINQ-to-SQL — see `database/procedures`).
- `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` in `docker-compose.yml` is required —
  without it, `app.UseHttpsRedirection()` in `Program.cs` can't tell the request
  arrived over HTTPS (nginx talks plain HTTP to Kestrel) and redirects it back to
  HTTPS, which nginx re-terminates and forwards as HTTP again: a redirect loop.
- Ports 1433-range and 5010 are bound to `127.0.0.1` only; only 80/443 are public.
- This assumes the same Hetzner box already running Tappit (hence the shared
  `tappit.click` DNS zone) — every container/port/vhost name here is namespaced
  (`silen-*`, `5010`, `14340`) so it won't collide with Tappit's `tappit-*` stack.
  If SilaFit actually lives on a separate box, nothing else needs to change.
- `well-known/assetlinks.json` is what makes `https://silafit.tappit.click`
  Android App Links (`android:autoVerify="true"` in the app's
  `AndroidManifest.xml`) instead of just a browser link. `sha256_cert_fingerprints`
  must match the cert the release APK/AAB is actually signed with — see
  `deploy/certs/README.md`. Nginx serves this file statically (see the
  `location = /.well-known/assetlinks.json` block), so redeploying the API
  never affects it.
