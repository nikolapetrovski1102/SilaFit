# SilaFit

A fitness-tracking app: today's workout, split library, AI-narrated progress analytics, and
subscription plans. Guests are usable instantly via a per-device identity; creating an
account (email, Google, or Apple) is required only to link progress across devices, buy a
plan, or otherwise persist anything long-term.

- **Backend** — ASP.NET Core Web API, SQL Server via stored procedures only (no ORM/LINQ-to-SQL).
- **Frontend** — Flutter (single codebase, iOS + Android + web-capable).
- **Database** — SQL Server 2022, schema + procedures + seed data as plain `.sql` scripts.

## Repo layout

```
backend/    ASP.NET Core API (Silen.Api, Silen.Services, Silen.Common, ...)
database/   schema/, procedures/, seed/ .sql scripts + deploy.sh
frontend/   Flutter app
deploy/     production deploy to Hetzner (sila.fitness) — see deploy/README.md
docs/       (reserved for design/architecture notes)
docker-compose.yml   SQL Server + API, wired together for local dev
```

## Running the backend + database

1. Start SQL Server and the API:
   ```bash
   docker compose up -d
   ```
2. Apply schema, stored procedures, and seed data (safe to re-run):
   ```bash
   ./database/scripts/deploy.sh
   ```
3. The API is now reachable at `http://localhost:5080`.

To run the API outside Docker instead (e.g. for debugging in an IDE), start only the
database service (`docker compose up -d silen-sqlserver`) then:
```bash
cd backend/src/Silen.Api
dotnet run
```
It picks up `appsettings.Development.json`, which already points at the Dockerized SQL
Server on `localhost,14330`.

**Before going anywhere near production:** the committed `Jwt:SigningKey` and SQL `sa`
password are dev-only placeholders checked in for convenience — replace both, and fill in
`GoogleAuth:ClientIds` / `AppleAuth:ClientIds` with real OAuth client IDs, before this leaves
a local machine.

## Running the frontend

The Flutter project here is hand-authored source only — `flutter create` has not been run
against it, so there is **no generated `android/`, `ios/`, `macos/`, `linux/`, `windows/`, or
`web/` folder yet**, and nothing in it has been compiled or run (no Flutter SDK was available
in the environment that built it). Before it will run:

```bash
cd frontend
flutter create .          # generates the native platform folders in place, without touching lib/
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:5080
```

Notes:
- `API_BASE_URL` must be reachable from wherever the app runs — `http://localhost:5080` works
  for a desktop/web target hitting the Dockerized API on the same machine, but an Android
  emulator needs `http://10.0.2.2:5080`, and a physical device needs your machine's LAN IP.
- Google Sign-In and Sign in with Apple are wired up in code (`google_sign_in`,
  `sign_in_with_apple`) but both need real native configuration that only you can provide:
  a Google OAuth client (`google-services.json` / URL scheme) and an Apple Sign-In
  entitlement + Services ID. Until those are added, tapping those buttons will fail — email
  registration/login and the device-id guest flow work with no extra setup.
- Every screen talks to the real backend endpoints (Today, Splits, Progress, Plans); there is
  no mock data layer to swap out.

## Architecture notes

The local database can also host a merged, searchable catalog of food macros
from USDA, CNF, CoFID, and Open Food Facts. See
[`docs/food-nutrition-import.md`](docs/food-nutrition-import.md) for the import
and refresh workflow.

- **Backend**: controllers are thin (DI'd interfaces only, no private helper methods), all
  responses share one envelope shape, and every unhandled/unsupported error surfaces to the
  client as a single generic "Something went wrong" message while the real detail is logged
  server-side. All SQL access goes through stored procedures via a shared dynamic execution
  helper — no inline/injected SQL, no LINQ-to-SQL.
- **Frontend**: mirrors the same "one generic message" contract in `ApiException`, and uses a
  shared `ResourceState<T>` + `ResourceBuilder<T>` pair everywhere a screen loads data, so the
  loading/error/retry UI is written once and reused across Today/Splits/Progress/Plans rather
  than duplicated per screen. `AccountGate.ensure()` is the single choke point that enforces
  "guest is fine to browse, but progress tracking and purchases require a linked account" —
  it's called from the Progress tab switch and from the plan-purchase action, matching what
  the backend already enforces server-side via its `RequireLinkedAccount` policy.
- Progress analytics are rule-based on real logged data (streaks, compliance, hydration/weight
  trends) — there is no external LLM call, and the narrative text is a template filled with
  those real numbers, not fabricated content.
- Push reminders are delivered by `NotificationPublishService`, driven by a frequent
  (`Silen.Tools.NotificationPublish`, every 5 minutes on the server) batch. Scheduling is
  done in each user's own stored timezone, never the server's — the timezone is captured at
  onboarding and refreshed on every app open. Messages are short, varied and personality-led
  (gym time, log-your-sets, calories/meal ideas, motivation), with a quiet-then-comeback
  backoff when a user stops engaging. Delivery uses FCM HTTP v1 when configured and falls back
  to a log-only sender otherwise, so the pipeline works before Firebase is wired. See
  `deploy/README.md` ("Push reminders").
