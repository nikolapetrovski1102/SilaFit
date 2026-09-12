# Env files

Passed to Flutter at build/run time with `--dart-define-from-file`, which loads
every key in the JSON file as if it were `--dart-define=KEY=value`. `ApiConfig`
(`lib/core/api/api_config.dart`) reads `API_BASE_URL`, `GOOGLE_WEB_CLIENT_ID`, and
`GOOGLE_IOS_CLIENT_ID` from this at compile time.

```bash
flutter run --dart-define-from-file=env/dev.json
flutter build ios --dart-define-from-file=env/prod.json
```

Running `flutter run`/`flutter build` **without** one of these files gives you an
empty `API_BASE_URL`, which fails loudly with the app's normal "Cannot reach the
server" error - that's deliberate (see the comment in `api_config.dart`), so a
forgotten flag is obvious immediately instead of quietly hitting the wrong host.

## `dev.json`

Defaults to `http://localhost:5080/api`, for the macOS desktop / iOS simulator
inner loop against the locally-running stack from `docs/starting-the-stack.md`.
Swap the value for whichever local target you're actually running against:

| Target | `API_BASE_URL` |
|---|---|
| macOS desktop | `http://localhost:5080/api` |
| iOS simulator | `http://localhost:5080/api` |
| Physical device over LAN | `http://<mac's LAN IP>:5080/api` (`ipconfig getifaddr en0`) |
| Android emulator | `http://10.0.2.2:5080/api` |

The LAN IP changes when Wi-Fi reconnects or you switch networks - re-check it
and edit this file rather than passing an ad-hoc `--dart-define` override, so
the committed default stays what the team actually runs against.

## `prod.json`

Points at the real deployment - `https://silafit.tappit.click/api` (see
`deploy/README.md` and `deploy/nginx-silafit.tappit.click.conf`).

## `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID`

Both files currently ship placeholder values (`REPLACE_WITH_GOOGLE_...`) - Google
Sign-In is wired end-to-end (Flutter `GoogleSignIn`, backend `GoogleAuth:ClientIds`
validation) but needs real OAuth client IDs from a Google Cloud project before it'll
actually work. To create them:

1. In [Google Cloud Console](https://console.cloud.google.com/), create (or pick) a
   project, then go to **APIs & Services → Credentials → Create Credentials → OAuth
   client ID**.
2. Configure the **OAuth consent screen** first if prompted (External, app name
   "SilaFit", your email as support/developer contact - no special scopes needed
   beyond the default `email`/`profile`).
3. Create an **iOS** client:
   - Bundle ID: `com.nikolapetrovski.silafit`
   - Copy the generated client ID into `GOOGLE_IOS_CLIENT_ID` in both env files.
4. Create a **Web application** client (this is the one the backend validates
   Google ID tokens against - Google calls it the "server client ID" /
   `serverClientId` on the Flutter side, and it's also what an Android build's
   idToken is issued for):
   - No redirect URIs are needed for the native-app flow used here.
   - Copy the generated client ID into `GOOGLE_WEB_CLIENT_ID` in both env files,
     **and** into the repo-root `.env` file as `GOOGLE_WEB_CLIENT_ID=...` (picked up
     by `docker-compose.yml`'s `GoogleAuth__ClientIds__0` for the backend - see
     `.env` and `docker-compose.yml`).
5. If/when an Android OAuth client is added, it must be registered against the
   app's real `applicationId` + release/debug signing SHA-1 - `applicationId` is
   now `com.nikolapetrovski.silafit`, matching iOS.
