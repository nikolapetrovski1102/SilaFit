# SilaFit deployment

From-scratch deploy of the .NET API + SQL Server for a fresh Ubuntu server,
served at https://sila.fitness (with a dedicated https://api.sila.fitness vhost).

## Layout expected on the server

```
/opt/silen/
  backend/     # app source (built into a Docker image)
  database/    # schema/, procedures/, seed/ .sql scripts
  deploy/
    deploy.sh                             # run this as root
    docker-compose.yml                    # db + api services
    nginx-sila.fitness.conf
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
5. nginx reverse proxy for `sila.fitness` (+ `api.sila.fitness`, `admin.sila.fitness`)
6. Let's Encrypt HTTPS with auto HTTP->HTTPS redirect
7. Installs a cron entry for the monthly progress-email batch (see "Monthly
   progress emails" below)

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

The console is served at https://admin.sila.fitness/ (its own vhost in
`nginx-sila.fitness.conf`, which needs a DNS A record pointing at the server);
the old `sila.fitness/admin*.html` URLs 301 there. `website/admin.html` is
protected by nginx, not by anything inside the page. The admin vhost's
`location = /` block issues an `auth_request` subrequest to
`GET /api/admin/auth/session` and serves the console only on a 200; anything
else is redirected to `admin-login.html`. That single location is the whole gate — everything else under `website/` (css, js, assets)
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

To reprint an existing enrollment — e.g. to add a second device, or to recover the
secret when the original console output is lost — without rotating anything:

```bash
# --build because this mode adds the local QR renderer to the tool image, which
# deploy.sh does not rebuild for you.
docker compose --profile tools run --rm --build silen-admin-provision -- --show-totp
```

`--show-totp` is read-only: it decrypts the stored secret with
`ENCRYPTION_MASTER_KEY`, prints the secret, the `otpauth://` URI and the current
code, and renders the URI as a terminal QR code you can scan straight from an SSH
session. It never prompts for a password, never changes the password hash and never
signs any session out. It only works because the operator running it already holds
the master key that protects the secret; the API itself still refuses to hand the
secret back. The QR is drawn locally in the tool — the secret is never sent to a
third-party QR service.

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

## Monthly progress emails

Every active **ADVANCED** subscriber gets an AI-written monthly overview -
*what improved*, *what to improve*, and *how to continue next month* - generated
from their real training/bodyweight/nutrition history and emailed to them.

The batch lives in `Silen.Tools.MonthlyReview` and reuses the same
`AnalyticsService` / `dbo.AiPromptTemplates('MonthlyAnalytics')` pipeline the
in-app monthly analytics screen uses, so the narrative and the cached numbers
stay identical. `deploy.sh` installs a cron entry that runs it at **06:00 on the
1st of each month** for the **previous** calendar month:

```bash
cat /etc/cron.d/silen-monthly-review          # schedule + log path
tail -f /var/log/silen-monthly-review.log     # run output
```

Run it by hand (backfill a period, or test without email):

```bash
cd /opt/silen/deploy

# previous month, normal run
docker compose --profile tools run --rm --build silen-monthly-review

# a specific period, no email (reports are still generated + stored)
docker compose --profile tools run --rm silen-monthly-review -- --year=2026 --month=8 --dry-run

# only the paying subscribers, or only the non-paying teaser
docker compose --profile tools run --rm silen-monthly-review -- --audience=subscribers
docker compose --profile tools run --rm silen-monthly-review -- --audience=free
```

Exit codes: `0` clean run, `2` completed with per-user failures, `1` the run
itself failed. Safe to re-run — reports are cached per user+month (the AI is
never billed twice) and anyone already emailed for that period is skipped.

### Non-paying teaser (upgrade funnel)

The same cron run has a second pass for **non-paying users** (active accounts
with an email and no current PRO/ADVANCED entitlement). It emails their own
free-tier numbers for the month - sessions completed, tonnage, streak, nutrition
days logged - over a locked preview of the paid sections, with an "unlock your
review" button pointing at `MonthlyReview__UpgradeUrl`. It deliberately calls
only `usp_Analytics_GetMonthlySnapshot` (no OpenRouter call), so it costs nothing
per recipient and never gives away the paid narrative. A user with no logged
activity in the month is skipped, not emailed.

Delivery is idempotent **per audience** (`MonthlyReviewDeliveries.DeliveryKind` =
`Subscriber` / `Upsell`), so a free user who upgrades mid-period can still get
the full report, and re-running a period never double-emails either group.
Disable the teaser with `MONTHLY_REVIEW_SEND_UPSELL_EMAILS=false`; scope a manual
run with `--audience=subscribers` or `--audience=free`.

### Configuration (`.env`)

- `OPENROUTER_API_KEY` (required) / `OPENROUTER_MODEL` — generates the narrative.
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`,
  `SMTP_FROM_ADDRESS`, `SMTP_FROM_NAME` — delivery. **When `SMTP_HOST` is blank
  the batch still generates and stores every report but sends no email**
  (deliveries are recorded as `Generated`, so a later run with SMTP configured
  still reaches those users). The same settings power registration codes.
- `MONTHLY_REVIEW_PLAN_CODE` (default `ADVANCED`) and
  `MONTHLY_REVIEW_SEND_EMAILS` (default `true`).

### Where the state lives

- `dbo.MonthlyReviewRuns` / `dbo.MonthlyReviewDeliveries`
  (`database/schema/029_MonthlyReview.sql`) — one run row per execution and one
  delivery row per user considered (`Generated` / `Emailed` / `Skipped` /
  `Failed`, with the error message). The delivery table is what makes a re-run
  idempotent.
- `dbo.MonthlyAnalyticsReports` — the cached report itself, shared with the
  in-app analytics endpoint.
- All writes go through the stored procedures in
  `database/procedures/MonthlyReview.sql` and
  `database/procedures/Plans.sql` (`usp_Plans_GetActiveSubscribers`).

## Push reminders

Opted-in users get short, frequent, personality-forward push reminders, always
scheduled against **their own timezone** (stored at onboarding, never the
server's clock):

- a gym nudge around their chosen local reminder time on days they haven't trained;
- a "log your sets" nudge while a workout is open and idle (driven by the app's
  workout heartbeat);
- calorie / meal-idea nudges around configured local meal times;
- a motivational message when they've been consistent;
- after a couple of quiet days, a single comeback message ("you made a rest,
  let's get back to the gym") instead of all of the above;
- on the **1st of each month, non-paying users** get a single "unlock your
  monthly review" nudge (upgrade funnel) - paying users never see it.

The batch lives in `Silen.Tools.NotificationPublish` (service:
`NotificationPublishService` in `Silen.Services`). `deploy.sh` builds its image
once and installs a cron entry that runs it **every 5 minutes**:

```bash
cat /etc/cron.d/silen-notification-publish          # schedule + log path
tail -f /var/log/silen-notification-publish.log      # run output
```

Run it by hand (test one user without writing anything):

```bash
cd /opt/silen/deploy
docker compose --profile tools run --rm silen-notification-publish -- --dry-run
docker compose --profile tools run --rm silen-notification-publish -- --user=<user-guid> --dry-run
```

Exit codes: `0` clean run, `2` completed with per-user failures, `1` the run
itself failed. Safe to re-run: every reminder carries a dedupe key
(`userId` + category + local day/slot) enforced by a unique index, so overlapping
ticks never double-send.

### Pending flush

A normal run creates each notification and delivers it in the same pass, moving
the row to a terminal status (`Sent` / `Failed` / `Skipped`). If the process dies
mid-flight, or the transport fails before the row is updated, the row is left in
`Created`. The same cron tick therefore runs a **pending flush** right after the
publish pass: it re-reads notifications still in `Created` older than a grace
window (`PendingFlushGraceMinutes`, default 30) and delivers them, oldest first.

- `usp_NotificationPublish_GetPending` is the feed; `--no-flush` skips the pass
  when you only want the normal run.
- The grace window (milliseconds of real work vs. a 30-minute margin) is what
  keeps the flush from racing a run that is still mid-flight.
- Like the main pass, flushing is idempotent: delivery moves the row out of
  `Created`, so a row is never sent twice by overlapping ticks.

### Delivery (Firebase Cloud Messaging)

Delivery uses FCM HTTP v1. Enable it by copying your Firebase **service-account
JSON** to `deploy/secrets/fcm-service-account.json` on the server (the `./secrets`
dir is mounted read-only into the API and the tool, and is gitignored — it never
travels with the repo) and adding to `deploy/.env`:

```bash
PUSH_ENABLED=true
# PUSH_PROJECT_ID is optional: the project id is read from the JSON's own
# "project_id" field. Set it only to override that.
# PUSH_PROJECT_ID=silafit-9018c
# PUSH_SERVICE_ACCOUNT_PATH=/secrets/fcm-service-account.json
```

Then re-run `deploy.sh` (or `docker compose --profile tools run --rm --build
silen-notification-publish`) so the new image picks up the mount. The account
only needs the default Firebase Admin SDK role; no other Google Cloud setup is
required beyond having the Firebase project.

**When push is disabled the batch still composes and stores every notification**;
a log-only sender records what would have been delivered. That makes the whole
pipeline (scheduling, timezones, copy, dedupe) deployable and testable before
Firebase exists.

#### Client (Flutter app)

`PushMessagingService`
(`frontend/lib/features/notifications/push_messaging_service.dart`) is the device
half of the pipeline. When the user allows notifications on the final onboarding
screen it requests the FCM token and stores it, with the timezone/opt-in, in a
single `POST /api/notifications/device-token`. It also re-registers the token when
FCM rotates it, re-syncs it on cold start, and deactivates it on log-out /
account deletion. All of this is best-effort: if Firebase is not configured it
stores the opt-in with no token and logs "Push messaging unavailable" instead of
failing onboarding.

Firebase is wired for the `silafit-9018c` project:

- **Android** — `frontend/android/app/google-services.json` is in place and the
  `com.google.gms.google-services` plugin is applied in
  `android/settings.gradle.kts` (version, `apply false`) and
  `android/app/build.gradle.kts`. The plugin generates `google_app_id` /
  `gcm_defaultSenderId` at build time. The `silen_reminders` notification channel
  that the publisher targets is created in `MainActivity.ensureReminderChannel()`
  (Android 8+ silently drops a notification whose channel does not exist), with
  a `com.google.firebase.messaging.default_notification_channel_id` fallback in
  the manifest.
- **iOS** — `frontend/ios/SilaFit/GoogleService-Info.plist` is added to the
  `SilaFit` target's Copy Bundle Resources, `SilaFit/SilaFit.entitlements` carries
  `aps-environment`, and `Info.plist` declares the `remote-notification`
  background mode. Firebase is vendored through **CocoaPods**, which FlutterFire
  manages via `ios/Podfile` (`pod install` runs on `flutter build ios`); the
  Firebase console's Swift Package Manager snippet is not used and must not be
  added on top, or the SDK would be linked twice.

Two things can only be done in the Firebase/Apple consoles:

1. **iOS**: enable the **Push Notifications** capability for the App ID
   `com.nikolapetrovski.silafit` in the Apple Developer portal so the
   provisioning profile carries the `aps-environment` entitlement, and upload an
   **APNs authentication key** (`.p8`) under Firebase → Project settings → Cloud
   Messaging. Without the APNs key, iOS sends are rejected by FCM.
2. **Android/iOS**: nothing else — the client config files are matched to the
   bundle/package `com.nikolapetrovski.silafit`.

The two config files are client-side Firebase config, not server secrets; keep
them committed or add them to `.gitignore` per your release policy. Until the
console steps above are done, delivery stays off and no device token is stored —
the rest of the pipeline is unaffected.

### Configuration (`.env`)

- `PUSH_ENABLED`, `PUSH_PROJECT_ID`, `PUSH_SERVICE_ACCOUNT_PATH` — delivery.
- `NOTIFICATION_RUN_IN_API` (default `false`) — set `true` to host the publisher
  inside the API (`NotificationPublish:RunInApi`) instead of the cron entry; do
  not run both (harmless, just redundant).
- `NOTIFICATION_PUBLISH_ENABLED` (default `true`) — master switch.
- `NOTIFICATION_MONTHLY_UPSELL_ENABLED` (default `true`),
  `NOTIFICATION_MONTHLY_UPSELL_DAY` (default `1`),
  `NOTIFICATION_MONTHLY_UPSELL_TIME` (default `09:00`, local) — the monthly
  upgrade nudge for non-paying users. `usp_NotificationPublish_GetCandidates`
  returns `HasPaidSubscription`, and the publisher only composes the upsell for
  candidates where it is `0`, once per local month (`monthlyreview:{yyyy-MM}`
  dedupe key).
- `NotificationPublish__PendingFlushEnabled` (default `true`),
  `NotificationPublish__PendingFlushGraceMinutes` (default 30),
  `NotificationPublish__PendingFlushBatchSize` (default 200) — the outbox safety
  net; see "Pending flush" above.
- Cadence/thresholds (`SendWindowMinutes`, `MealReminderLocalTimes`,
  `SetNudgeAfterMinutes`, `InteractionSilenceHours`, `ComebackSilenceHours`,
  `MotivationMinGapDays`, `MaxNotificationsPerDay`, quiet hours, …) override the
  `NotificationPublish` section of `appsettings.json` via
  `NotificationPublish__<Key>` environment variables.

### Where the state lives

- `dbo.UserDeviceTokens` — active FCM tokens per user/device.
- `dbo.UserNotifications` — the outbox + delivery audit (`Created` / `Sent` /
  `Failed` / `Skipped` / `Opened`), with `UserId + DedupeKey` unique.
- `dbo.UserNotificationStates` — last interaction / last push / category
  cooldowns, which drive the quiet-then-comeback backoff.
- `dbo.WorkoutSessions.LastActivityAtUtc` — the workout heartbeat that makes the
  in-gym set nudge possible.
- Procedures: `database/procedures/NotificationPublish.sql` plus
  `usp_WorkoutSession_Heartbeat` in `database/procedures/WorkoutSession.sql`.

## Subscription sync

Purchases are verified server-side against the issuing store (App Store Server
API / Play Developer API) and activated from the store's own response, never
from a client-supplied plan id — see `ISubscriptionReceiptService` in
`Silen.Services`. Two paths keep entitlements current after the initial
purchase:

- **Webhooks** (`SubscriptionWebhooksController`, `POST /api/webhooks/apple`
  and `POST /api/webhooks/google`) apply renewals/cancellations/refunds the
  moment the store reports them. These need one-time setup in each console —
  see "App Store / Play Store review account" below and Phase 5 of the IAP
  rollout for the exact URLs to register.
- **`Silen.Tools.SubscriptionSync`** is the safety net for whatever a missed
  or late webhook wouldn't have caught: it re-verifies every active,
  auto-renewing `SubscriptionReceipts` row against its store. `deploy.sh`
  builds its image once and installs a cron entry that runs it **every 4
  hours**:

```bash
cat /etc/cron.d/silen-subscription-sync          # schedule + log path
tail -f /var/log/silen-subscription-sync.log     # run output
```

Run it by hand (test one user without writing anything):

```bash
cd /opt/silen/deploy
docker compose --profile tools run --rm silen-subscription-sync -- --dry-run
docker compose --profile tools run --rm silen-subscription-sync -- --user=<user-guid> --dry-run
```

Exit codes: `0` clean run, `2` completed with per-receipt failures, `1` the run
itself failed. Safe to re-run: activation is keyed on `(Store, TransactionId)`,
so overlapping runs or a webhook and a sync tick landing at the same time never
double-apply a change.

### Configuration (`.env`)

- `APP_STORE_SERVER_KEY_ID`, `APP_STORE_SERVER_ISSUER_ID`,
  `APP_STORE_SERVER_BUNDLE_ID` (default `com.nikolapetrovski.silafit`),
  `APP_STORE_SERVER_PRIVATE_KEY_PATH` (default
  `/secrets/appstore-server-key.p8`), `APP_STORE_SERVER_ENVIRONMENT` (default
  `Production`, set `Sandbox` while testing) — the App Store Server API key you
  generate in App Store Connect under Users and Access → Integrations →
  In-App Purchase. Drop the downloaded `.p8` at
  `deploy/secrets/appstore-server-key.p8` (the `./secrets` dir is mounted
  read-only into the API and the tool, and is gitignored — it never travels
  with the repo).
- `GOOGLE_PLAY_PACKAGE_NAME` (default `com.nikolapetrovski.silafit`),
  `GOOGLE_PLAY_SERVICE_ACCOUNT_PATH` (default
  `/secrets/play-service-account.json`) — a Play Console service account with
  "View financial data" + Play Developer API access. Drop its downloaded JSON
  key at `deploy/secrets/play-service-account.json`.

Both sets of credentials are shared between `silen-api` (verify-purchase
endpoint + webhooks) and `silen-subscription-sync`.

### Where the state lives

- `dbo.SubscriptionPlans.AppStoreProductId` / `PlayStoreProductId` — the store
  product ids a verified purchase resolves to a plan through.
- `dbo.SubscriptionReceipts` — append-only ledger of every verified receipt,
  unique on `(Store, TransactionId)`.
- `dbo.UserSubscriptions.LatestReceiptId` / `AutoRenewing` — the active
  entitlement, kept in sync from the latest applied receipt.
- Procedures: `database/procedures/SubscriptionReceipts.sql`.

## App Store / Play Store review account

`REVIEWER_BYPASS_EMAIL` / `REVIEWER_BYPASS_CODE` (`.env`) give app reviewers a
registration email that gets a fixed activation code instead of a random one
emailed out — so they can create and re-verify the demo account without inbox
access. Leave both blank outside of an active review; an unset/blank pair
disables the bypass entirely (`AuthService.IsReviewerBypassEmail`). To use it:

1. Set both vars in `deploy/.env` and redeploy the `silen-api` service.
2. In App Store Connect / Play Console review notes, give the reviewer the
   `REVIEWER_BYPASS_EMAIL` address, any password (min 8 chars, entered at
   sign-up), and the `REVIEWER_BYPASS_CODE` as the activation/verification code.
3. After the review, either blank both vars again or leave them set for the
   next re-review — the account itself is a normal registered user once created.

## Notes
- DB engine is **Microsoft SQL Server** (all access goes through stored procedures,
  no ORM/LINQ-to-SQL — see `database/procedures`).
- `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` in `docker-compose.yml` is required —
  without it, `app.UseHttpsRedirection()` in `Program.cs` can't tell the request
  arrived over HTTPS (nginx talks plain HTTP to Kestrel) and redirects it back to
  HTTPS, which nginx re-terminates and forwards as HTTP again: a redirect loop.
- Ports 1433-range and 5010 are bound to `127.0.0.1` only; only 80/443 are public.
- Every container/port/vhost name here is namespaced (`silen-*`, `5010`,
  `14340`), so `deploy.sh` is safe to run alongside other sites/stacks on the
  same box, not just on a dedicated one.
- `well-known/assetlinks.json` is what makes `https://sila.fitness`
  Android App Links (`android:autoVerify="true"` in the app's
  `AndroidManifest.xml`) instead of just a browser link. `sha256_cert_fingerprints`
  must match the cert the release APK/AAB is actually signed with — see
  `deploy/certs/README.md`. Nginx serves this file statically (see the
  `location = /.well-known/assetlinks.json` block), so redeploying the API
  never affects it.
