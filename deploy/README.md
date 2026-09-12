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
   (see "Column-encryption rollout" below for a caveat specific to that step)
3. Enables Transparent Data Encryption (TDE) on `SilenDb` if not already on
4. Builds & runs the API on `127.0.0.1:5010`
5. nginx reverse proxy for `silafit.tappit.click`
6. Let's Encrypt HTTPS with auto HTTP->HTTPS redirect

## ⚠️ TDE certificate backup — read this before your first deploy

Step 3 above generates a certificate (`SilenTdeCert`) that SQL Server needs to
read the encrypted database at all. `deploy.sh` copies it (plus its private
key) to `deploy/tde-cert-backup/` on the VPS the moment it's created — but
**that is not a safe final resting place**: it's still on the same box as the
database it protects. Move `deploy/tde-cert-backup/` to separate, offline
secure storage (a password manager, an encrypted USB drive, a different
machine) immediately after the first deploy that creates it, then delete it
from the VPS.

**Losing this certificate permanently locks the entire encrypted database —
including every backup taken after TDE was enabled. There is no recovery.**
`deploy/tde-cert-backup/` is `.gitignore`d — it is never meant to reach the repo.

## Column-encryption rollout (`database/schema/024`–`025`, app-level AES-256-GCM)

Several sensitive columns (bodyweight, age/height/gender/goal, meal titles +
macros, nutrition targets) are additionally encrypted at the application
layer (`Silen.Common.Helpers.FieldCipher`, keyed by `ENCRYPTION_MASTER_KEY` /
`Encryption__MasterKeyBase64`) on top of TDE, independent of it. Because
production already holds real rows, this shipped as a safe multi-step
migration instead of an in-place column-type change:

1. `024_ColumnEncryptionAdd.sql` — additive, nullable `*Enc` sibling columns.
2. `deploy.sh` automatically runs `Silen.Tools.EncryptExistingData` (via
   `docker compose --profile tools run --rm silen-encrypt-backfill`) right
   before applying `025`, encrypting every existing plaintext row into its
   `*Enc` column. Resumable/idempotent — safe to interrupt and re-run.
3. `025_ColumnEncryptionCutover.sql` — renames the old plaintext columns to
   `*_Legacy` (kept, not dropped — a rollback path) and promotes `*Enc` to
   the real column names. The backend deployed in step 4 above reads/writes
   those real names, so 024 → backfill → 025 → new API build must all land
   together, in that order — `deploy.sh` already sequences this correctly.
4. `database/manual-migrations/026_ColumnEncryptionCleanup.sql` drops the
   `*_Legacy` columns for good. **This is deliberately never run
   automatically** — it lives outside `database/schema/` specifically so
   `deploy.sh`'s apply-everything loop can't reach it. Run it by hand (see
   the instructions in that file) only after the new build has been healthy
   in production for a few days.

If you ever need to roll back after a cutover but before running 026, the
`*_Legacy` columns still hold the original plaintext — no data is lost.

## Admin console (two-factor sign-in)

`website/admin.html` is protected by nginx, not by anything inside the page. The
`location = /admin.html` block in `nginx-silafit.tappit.click.conf` issues an
`auth_request` subrequest to `GET /api/admin/auth/session` and serves the console
only on a 200; anything else is redirected to `admin-login.html`. That single
location is the whole gate — everything else under `website/` (css, js, assets)
is shared with the public site and stays public, and the login page is
deliberately ungated because it is what hands out the cookie in the first place.
The gate **fails closed**: if the API is unreachable nginx answers 500 rather
than serving the console on an unproven session.

Sign-in needs both factors, and passing the first grants nothing on its own:

1. username + password, checked against `dbo.AdminUsers` with the same PBKDF2
   hasher the app uses (`Silen.Common.Helpers.PasswordHasher`). Success returns a
   5-minute *challenge* token, not a session.
2. a 6-digit RFC 6238 TOTP code (`Silen.Common.Helpers.TotpHelper`). Success sets
   the `silafit_admin_session` HttpOnly + SameSite=Strict cookie; the raw token is
   never echoed into a response body.

Wrong password and wrong code count against the same lockout, so neither factor
can be brute-forced independently.

### Creating / rotating an operator

Accounts are created only by the provisioning tool or direct SQL — there is no
self-service sign-up. The same command both creates and rotates:

```bash
cd /opt/silen/deploy
docker compose --profile tools run --rm silen-admin-provision
```

It prompts for the username and password, then prints the TOTP secret and an
`otpauth://` URI to enroll in Google Authenticator / Authy / 1Password, plus the
code valid at that moment. **Store the secret in a password manager — it is the
only copy.** For an unattended run, set `SILEN_ADMIN_USERNAME` and
`SILEN_ADMIN_PASSWORD` in `.env` instead of prompting.

Rotating an existing operator's password issues a new TOTP secret by default and
drops every live session for that account (so a leaked password can be shut out
immediately). Pass `--keep-totp` to rotate the password only and keep the existing
enrollment:

```bash
docker compose --profile tools run --rm silen-admin-provision -- --keep-totp
```

### Where the state lives

- `dbo.AdminUsers` (`database/schema/027_AdminAccounts.sql`) — password hash +
  salt, the failed-attempt counter and lockout window, and the TOTP secret
  encrypted with `ENCRYPTION_MASTER_KEY` (`AdminTotpSecretCipher`), so a database
  dump alone does not let anyone generate codes.
- `dbo.AdminSessions` — session **token hashes**, never the tokens themselves,
  with both an idle (`AdminAuth__SessionIdleMinutes`) and an absolute
  (`AdminAuth__SessionAbsoluteMinutes`) deadline. "Revoke all sessions" in the
  console deletes every row for that operator.
- All access goes through the stored procedures in `database/procedures/Admin.sql`
  (idempotent `CREATE OR ALTER`), applied by `deploy.sh` like the rest.

### Tunables

Overridable in `.env` (see `.env.example`): `ADMIN_SESSION_IDLE_MINUTES`,
`ADMIN_LOCKOUT_THRESHOLD`, `ADMIN_LOCKOUT_MINUTES`. `AdminAuth__CookieSecure`
must stay `true` in production — a `Secure` cookie is never sent over plain HTTP,
and the only path that turns it off is local development.

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
