# Starting the SilaFit stack

Quick one-liners for spinning everything up from a cold machine (nothing running yet).
Run these from the repo root (`/Users/nikolapetrovski/Developer/Silen`) unless noted.

## 1. Database + Backend API

Starts SQL Server and the API containers, then applies schema/procedures/seed data
(the deploy script is safe to re-run any time, e.g. after a schema change):

```bash
docker compose up -d && ./database/scripts/deploy.sh
```

Check it's up:

```bash
docker compose ps
```

API is reachable at `http://localhost:5080` (from an Android emulator use `http://10.0.2.2:5080`;
from a physical device use your Mac's LAN IP, e.g. `http://192.168.1.242:5080`).

**Stop it:**

```bash
docker compose down
```

### Backend outside Docker (for IDE debugging)

Only start the DB container, then run the API from source:

```bash
docker compose up -d silen-sqlserver && (cd backend/src/Silen.Api && dotnet run)
```

## 2. Frontend (Flutter)

The API base URL comes from a checked-in env file (`frontend/env/`, see its README) via
`--dart-define-from-file`, not an inline `--dart-define`. Edit `frontend/env/dev.json` if the
target below doesn't match your current setup.

### macOS desktop (fastest inner loop, no code signing needed)

```bash
cd frontend && flutter run -d macos --dart-define-from-file=env/dev.json
```

`env/dev.json` defaults to `http://localhost:5080/api`, which works as-is for this target.

### Physical iPhone (wired via USB)

Needs your Xcode dev-team signing already configured, and uses the Mac's LAN IP
(a physical device can't reach `localhost` on your Mac):

```bash
cd frontend && flutter run -d "Nikola's iPhone" --dart-define-from-file=env/dev.json
flutter run -d 00008150-001005D91404401C --dart-define-from-file=env/dev.json
```

> LAN IP can change (Wi-Fi reconnects, different network). If the app can't reach the API,
> re-check it with `ipconfig getifaddr en0` and update `API_BASE_URL` in `frontend/env/dev.json`.

### Fresh install (clean rebuild of dependencies/native folders)

Use this after pulling changes to `pubspec.yaml`, switching Flutter/Xcode versions, or if
the build is behaving strangely:

```bash
cd frontend && flutter clean && flutter pub get
```

Then run one of the `flutter run` commands above as usual.

## Known gotcha: macOS sandbox network entitlement

The `flutter create .`-generated macOS target is sandboxed and by default only allows
*incoming* connections (`network.server`), not outgoing ones — so `google_fonts` (fetched at
runtime) and all calls to the backend API fail with `SocketException: Operation not permitted`
the first time you run on macOS. This is already fixed in this repo by adding
`com.apple.security.network.client` to `frontend/macos/Runner/DebugProfile.entitlements` and
`Release.entitlements`. If it ever regresses (e.g. after `flutter create .` is re-run), add it
back to both files inside the `<dict>`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

## Known gotcha: Sign In with Apple needs a portal capability enabled

The app's `CODE_SIGN_ENTITLEMENTS` (`frontend/ios/SilaFit/SilaFit.entitlements`) and Xcode project
wiring are already in place, but Apple also requires the **App ID** itself to have the "Sign In
with Apple" capability turned on before a real device build will show the native sign-in sheet
instead of failing immediately. This is a one-time manual step, not a secret or code change:

1. [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. Select (or create, if this is a fresh App ID post-rename) the `com.nikolapetrovski.silafit` App ID.
3. Enable the **Sign In with Apple** capability, save.
4. Re-download/regenerate the provisioning profile if Xcode doesn't pick the change up
   automatically (Xcode → Signing & Capabilities → re-toggle automatic signing).

Google Sign-In has an equivalent one-time manual step - see `frontend/env/README.md` for
creating the real OAuth client IDs the app currently ships as placeholders for.

## Known gotcha: physical iPhone gets killed right after launch

If `flutter run -d "Nikola's iPhone"` installs and launches fine, then immediately shows
`Lost connection to device.` with a `signal SIGKILL` stack trace, iOS itself killed the app -
this happens when the phone's screen is locked (or locks) right as the debugger attaches.
Unlock the phone and keep it awake/on the home screen or in the app during launch, then re-run
the same command.

## Everything at once

```bash
docker compose up -d && ./database/scripts/deploy.sh && (cd frontend && flutter run -d macos --dart-define-from-file=env/dev.json)
```
