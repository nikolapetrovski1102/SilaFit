# TODO — Push reminders

Status of the notification publish feature and the remaining setup needed to
make reminders actually reach devices.

The **backend/service/database is complete** and builds clean. What's left is
push transport credentials and the Flutter FCM client. Until the client registers
a token, `dbo.UserDeviceTokens` is empty and the publisher simply has no
candidates — nothing breaks, nothing is delivered.

---

## 1. Server — FCM service account (required)

The Firebase private key currently lives locally at
`deploy/secrets/fcm-service-account.json` (gitignored, mode `600`,
project id `silafit-9018c`). `deploy/.env` is root-owned, so it must be finished
on the server:

- [ ] Copy the key to the server (it does **not** travel via git):
  ```bash
  scp deploy/secrets/fcm-service-account.json \
      root@<server>:/opt/silen/deploy/secrets/fcm-service-account.json
  ssh root@<server> 'chmod 600 /opt/silen/deploy/secrets/fcm-service-account.json'
  ```
- [ ] Enable push in `deploy/.env`:
  ```bash
  ssh root@<server> 'echo "PUSH_ENABLED=true" >> /opt/silen/deploy/.env'
  ```
- [ ] Re-run deploy so the image pickup the new mount + cron:
  ```bash
  ssh root@<server> 'cd /opt/silen/deploy && ./deploy.sh'
  ```
- [ ] Confirm the publisher sees push as configured:
  ```bash
  cat /etc/cron.d/silen-notification-publish          # every 5 minutes
  tail -f /var/log/silen-notification-publish.log
  docker compose --profile tools run --rm silen-notification-publish -- --dry-run
  ```
  `PushConfigured: true` in the output means FCM is active. `false` means it fell
  back to the log-only sender.

Notes:
- `PUSH_PROJECT_ID` is optional — the project id is read from the JSON's own
  `project_id`. `PUSH_SERVICE_ACCOUNT_PATH` defaults to
  `/secrets/fcm-service-account.json`.
- The service account only needs the default Firebase Admin SDK role.
- `NOTIFICATION_RUN_IN_API` defaults to `false` in production (the cron tool runs
  the publisher). Set it to `true` to host the publisher inside the API instead.
  Do not run both — harmless because of dedupe keys, just redundant.

## 2. Flutter — FCM client (required; this is what turns reminders on)

The backend endpoint and `NotificationsRepository` are ready. The app has no
Firebase dependency yet.

- [ ] Add dependencies to `frontend/pubspec.yaml`:
  ```yaml
  firebase_core: ^3.x
  firebase_messaging: ^15.x
  ```
- [ ] **Android** — `frontend/android/app/build.gradle.kts`:
  - Add the Google Services plugin:
    ```kotlin
    plugins {
        id("com.google.gms.google-services")
    }
    ```
    (and add the classpath in the root `build.gradle.kts`)
  - Add `frontend/android/app/google-services.json`. This project uses a single
    product flavor named `silafit`; if Gradle can't resolve it, place it at
    `frontend/android/app/src/silafit/google-services.json` instead.
  - Create a notification channel with id **`silen_reminders`** at startup — the
    backend targets this `channel_id` in the FCM payload. If it doesn't exist,
    Android falls back to the default channel.
- [ ] **iOS** (target is named `SilaFit`, so paths are `ios/SilaFit/`):
  - Add `GoogleService-Info.plist`.
  - Enable **Push Notifications** capability and **Background Modes → Remote
    notifications**.
  - Upload the APNs auth key (`.p8`) in Firebase Project Settings → Cloud
    Messaging. Bundle id must match `APPLE_BUNDLE_ID`
    (`com.nikolapetrovski.silafit`).
- [ ] Initialize Firebase and register the token (e.g. in `main.dart` or the auth
      bootstrap), after permission is granted:
  ```dart
  final token = await FirebaseMessaging.instance.getToken();
  await context.read<NotificationsRepository>().registerDeviceToken(
        token: token,
        platform: devicePlatform(),
        timeZoneId: deviceTimeZoneId(),
        notificationsEnabled: true,
      );

  FirebaseMessaging.instance.onTokenRefresh.listen((t) =>
      context.read<NotificationsRepository>().registerDeviceToken(
            token: t, platform: devicePlatform()));
  ```
- [ ] Handle taps so the quiet-then-comeback backoff sees real engagement:
  ```dart
  FirebaseMessaging.onMessageOpenedApp.listen((m) =>
      context.read<NotificationsRepository>().recordInteraction(
            notificationId: m.data['notificationId'],
            timeZoneId: deviceTimeZoneId()));

  // cold start:
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  // ...same recordInteraction call, then route by m.data['screen']
  ```
  Each payload's `data` carries `notificationId`, `category`, and `screen`
  (`today` / `workout` / `meals` / `progress`).

## 3. Local dev (already wired — just start the DB)

- [ ] Start SQL Server and apply schema/procs, then run the API:
  ```bash
  docker compose up -d silen-sqlserver
  # apply database/schema/*.sql + database/procedures/*.sql (see repo README)
  docker compose up -d --build silen-api
  ```
- [ ] Or run the publisher directly (must run from its project dir so
      `appsettings.Development.json` loads):
  ```bash
  cd backend/src/Silen.Tools.NotificationPublish
  DOTNET_ENVIRONMENT=Development dotnet run -- --dry-run
  DOTNET_ENVIRONMENT=Development dotnet run -- --user=<your-guid> --dry-run
  ```
  Local dev config: root `.env` (`PUSH_ENABLED=true`,
  `NOTIFICATION_RUN_IN_API=true`), root `docker-compose.yml` mounts
  `./deploy/secrets:/secrets:ro`, and the Api/tool
  `appsettings.Development.json` files point at the key.

## 4. Optional tuning

Env overrides (form `NotificationPublish__<Key>`; defaults in
`backend/src/Silen.Api/appsettings.json`):

| Key | Default | Meaning |
| --- | --- | --- |
| `NotificationPublish__Enabled` | `true` | master off switch |
| `NotificationPublish__SendWindowMinutes` | `45` | window after a chosen local time |
| `NotificationPublish__MealReminderLocalTimes` | `["12:30","18:30"]` | meal nudge times |
| `NotificationPublish__SetNudgeAfterMinutes` | `20` | in-gym idle before "log your sets" |
| `NotificationPublish__SetNudgeCooldownMinutes` | `30` | min gap between set nudges |
| `NotificationPublish__InteractionSilenceHours` | `30` | normal reminders quiet down after this |
| `NotificationPublish__ComebackSilenceHours` | `48` | after this, send the comeback message |
| `NotificationPublish__ComebackCooldownDays` | `3` | min gap between comebacks |
| `NotificationPublish__MotivationMinGapDays` | `3` | min gap between motivation messages |
| `NotificationPublish__MaxNotificationsPerDay` | `6` | hard daily cap per user |
| `NotificationPublish__QuietHoursStart` / `End` | `7` / `22` | local hours with no sends |

Message copy lives in
`backend/src/Silen.Services/Helpers/NotificationMessageComposer.cs` — edit
templates there; no schema or scheduling changes needed.

## 5. Definition of done

- [ ] `PushConfigured: true` in a dry-run on the server.
- [ ] At least one row in `dbo.UserDeviceTokens` for a real device.
- [ ] A non-dry run logs `sent: 1` and the device receives the push.
- [ ] Tapping it writes `OpenedAtUtc` / `Status='Opened'` in
      `dbo.UserNotifications` and refreshes `LastInteractionAtUtc` in
      `dbo.UserNotificationStates`.
