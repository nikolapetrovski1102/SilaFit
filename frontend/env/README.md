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

Defaults to the production API, `https://api.sila.fitness/api`, so debug builds
exercise the same authenticated data as release builds. To work against a
locally-running backend instead, change the value for the target you use:

| Target | `API_BASE_URL` |
|---|---|
| macOS desktop | `http://localhost:5080/api` |
| iOS simulator | `http://localhost:5080/api` |
| Physical device over LAN | `http://<mac's LAN IP>:5080/api` (`ipconfig getifaddr en0`) |
| Android emulator | `http://10.0.2.2:5080/api` |

The LAN IP changes when Wi-Fi reconnects or you switch networks, so re-check it
before temporarily pointing the file at a physical-device development server.

## `prod.json`

Points at the real deployment - `https://api.sila.fitness/api` (see
`deploy/migration/README.md` and `deploy/migration/nginx-silen.conf`).

## `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID`

Google Sign-In is wired end-to-end (Flutter `GoogleSignIn`, backend
`GoogleAuth:ClientIds` validation) with real OAuth client IDs from the `silafit`
Google Cloud project, all three registered against `applicationId`/bundle id
`com.nikolapetrovski.silafit`:

- **iOS** client → `GOOGLE_IOS_CLIENT_ID` in both env files, and the matching
  `REVERSED_CLIENT_ID` URL scheme in `ios/SilaFit/Info.plist`
  (`CFBundleURLTypes`) so the sign-in redirect lands back in the app.
- **Android** client → registered against the app's package name + debug/release
  signing SHA-1 in Google Cloud Console. Nothing to configure app-side: the
  `google_sign_in` plugin picks it up automatically from the app's signature,
  not from a client ID passed in code.
- **Web application** client → the one the backend actually validates ID tokens
  against (Google calls it the "server client ID" / `serverClientId` on the
  Flutter side, and it's also what an Android build's idToken is issued for).
  Lives in `GOOGLE_WEB_CLIENT_ID` in both env files, and in the repo-root `.env`
  file (picked up by `docker-compose.yml`'s `GoogleAuth__ClientIds__0` for the
  backend). It needs no redirect URIs or JS origins - it only serves as a token
  audience, never an actual web flow.

Rotating or adding a client (e.g. a new signing key's SHA-1, or a new bundle id)
means creating/updating it in [Google Cloud Console](https://console.cloud.google.com/)
under **APIs & Services → Credentials**, project `silafit`.

Production (`deploy/.env` on the server, separate from this repo) needs its own
`GOOGLE_WEB_CLIENT_ID` set the same way - see `deploy/.env.example`.
