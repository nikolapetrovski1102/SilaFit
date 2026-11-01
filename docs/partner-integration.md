# Partner integration: provisioning SilaFit PRO for website leads

The partner website signs a lead up (Apple, Google or email). When the lead reaches the
"use the app" screen, the partner's **server** calls SilaFit to create the lead's account
with PRO. PRO stays active, with no expiry, until the partner calls cancel, which ends it
immediately.

Never call these endpoints from a browser or mobile client. The credentials and the
payload key must stay on the partner's server.

## Endpoints

| Purpose   | Method and path                  | Request AAD purpose | Response AAD purpose |
|-----------|----------------------------------|---------------------|----------------------|
| Provision | `POST /api/partner/leads`        | `provision`         | `provision-response` |
| Cancel    | `POST /api/partner/leads/cancel` | `cancel`            | `cancel-response`    |

Both endpoints take `Content-Type: application/json` and the body `{ "payload": "<encrypted>" }`.

Rate limit: 60 requests per minute per client IP. Requests over the limit get `429`.

## Authentication: HTTP Basic

```
Authorization: Basic base64(username + ":" + password)
```

SilaFit issues the username and password. A missing or wrong header gets `401` with
`WWW-Authenticate: Basic realm="SilaFit Partner"`.

## Payload encryption: AES-256-GCM

- **Key:** 32 random bytes, shared out of band as base64.
- **Nonce:** 12 random bytes, new for every request. Never reuse a nonce with the same key.
- **Associated data (AAD):** the UTF-8 string `silafit-partner:` + purpose. Requests use `provision`
  or `cancel`; SilaFit seals its successful responses with `provision-response` or `cancel-response`.
  A payload sealed for one endpoint or direction will not decrypt anywhere else.
- **Tag:** 16 bytes.
- **Wire format:** `base64url( nonce ‖ ciphertext ‖ tag )`. Standard base64 is accepted too.

The plaintext is UTF-8 JSON.

### Provision payload

```json
{
  "partnerUserId": "your-stable-lead-id",
  "email": "lead@example.com",
  "displayName": "Ana",
  "provider": "Google",
  "issuedAtUtc": "2026-10-22T10:15:30.123Z",
  "profile": {
    "gender": "Female",
    "ageYears": 29,
    "heightCm": 168,
    "weightKg": 64,
    "goal": "LoseFat",
    "trainingDaysPerWeek": 4,
    "trainingExperience": "Beginner",
    "equipmentAccess": "Dumbbells",
    "dailyActivityLevel": "LightlyActive"
  }
}
```

| Field           | Rules                                                                                     |
|-----------------|-------------------------------------------------------------------------------------------|
| `partnerUserId` | Required, at most 100 characters. Your own stable id for the lead; cancel uses the same id. |
| `email`         | Required and valid. This is how the lead's app sign-in finds the account (see below).     |
| `displayName`   | Optional. Trimmed and cut to 100 characters.                                              |
| `provider`      | `Apple`, `Google` or `Email`: how the lead signed up with you.                            |
| `issuedAtUtc`   | Required, ISO 8601. Set it to the current time when you build the request.                |
| `profile`       | Optional. The lead's answers to the app's onboarding questions. See [Onboarding profile](#onboarding-profile). |

### Cancel payload

```json
{ "partnerUserId": "your-stable-lead-id", "issuedAtUtc": "2026-10-22T11:00:00.000Z" }
```

### Freshness and replay

- `issuedAtUtc` must be within **5 minutes** of SilaFit's clock, or the request is rejected with `401`.
- SilaFit stores the newest `issuedAtUtc` it has applied for each lead. A request older than
  that one is rejected with `409`, so a delayed provision can never undo a later cancel.
- Retrying is safe, but build a new payload with a new `issuedAtUtc` for each retry.

### Node.js example

```js
import crypto from "node:crypto";

const key = Buffer.from(process.env.SILAFIT_PAYLOAD_KEY, "base64"); // 32 bytes
const auth = "Basic " + Buffer.from(`${process.env.SILAFIT_USER}:${process.env.SILAFIT_PASS}`).toString("base64");

function encrypt(obj, purpose) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(`silafit-partner:${purpose}`, "utf8"));
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(obj), "utf8"), cipher.final()]);
  return Buffer.concat([nonce, ciphertext, cipher.getAuthTag()]).toString("base64url");
}

function decrypt(payload, purpose) {
  const bytes = Buffer.from(payload, "base64url");
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, bytes.subarray(0, 12));
  decipher.setAAD(Buffer.from(`silafit-partner:${purpose}`, "utf8"));
  decipher.setAuthTag(bytes.subarray(bytes.length - 16));
  return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(12, bytes.length - 16)), decipher.final()]).toString("utf8"));
}

async function call(path, purpose, body) {
  const issuedAtUtc = new Date().toISOString();
  const res = await fetch(`https://api.sila.fitness/api/partner/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: auth },
    body: JSON.stringify({ payload: encrypt({ ...body, issuedAtUtc }, purpose) }),
  });
  const envelope = await res.json();
  if (!res.ok) return { status: res.status, error: envelope.message }; // errors are not encrypted

  const result = decrypt(envelope.data.payload, `${purpose}-response`);
  if (new Date(result.requestIssuedAtUtc).getTime() !== new Date(issuedAtUtc).getTime())
    throw new Error("Response does not belong to this request");
  return { status: res.status, result };
}

await call("leads", "provision", { partnerUserId: "lead-123", email: "ana@example.com", displayName: "Ana", provider: "Google" });
await call("leads/cancel", "cancel", { partnerUserId: "lead-123" });
```

## Onboarding profile

### How onboarding works in the app

On first launch the app shows two intro slides, then nine questions, one per screen, then a
notification permission screen. The answers are saved together at the end as the user's
profile. SilaFit uses the profile to recommend a workout split, pick exercises and work out
daily calorie and macro targets.

| # | Screen in the app                         | Profile field          |
|---|-------------------------------------------|------------------------|
| 1 | What's your gender?                       | `gender`               |
| 2 | What is your age?                         | `ageYears`             |
| 3 | What's your height? (cm or ft)            | `heightCm`             |
| 4 | What's your current weight? (kg or lb)    | `weightKg`             |
| 5 | What's your main goal?                    | `goal`                 |
| 6 | Training days per week?                   | `trainingDaysPerWeek`  |
| 7 | How would you rate your fitness level?    | `trainingExperience`   |
| 8 | What equipment can you use?               | `equipmentAccess`      |
| 9 | How active is your day?                   | `dailyActivityLevel`   |

The app does not ask for session length. It saves 45 minutes, and the user can change it later
in Settings.

When a lead signs in to an account that has no complete profile, the app shows the same nine
questions, filled in with any answers it already has. If you send `profile` with every field,
the lead goes straight into the app with a plan that fits them. If you send only some fields,
the app asks again, with your answers already selected.

### Profile fields

Send the values exactly as listed. Choices are matched without regard to case and come back
in the casing shown. Height is always in centimetres and weight in kilograms, so convert ft/in
and lb on your side.

| Field                    | Required        | Type    | Allowed values and rules                                                                  |
|--------------------------|-----------------|---------|-------------------------------------------------------------------------------------------|
| `gender`                 | Yes             | string  | `Male`, `Female`, `Other`                                                                 |
| `ageYears`               | Yes             | integer | 13 to 100                                                                                 |
| `heightCm`               | Yes             | number  | 100 to 250. Stored to one decimal place.                                                  |
| `weightKg`               | Yes             | number  | 30 to 300. Stored to one decimal place.                                                   |
| `goal`                   | Yes             | string  | `BuildMuscle` (Build muscle), `LoseFat` (Lose fat), `MaintainActive` (Stay active)        |
| `trainingDaysPerWeek`    | No              | integer | 1 to 7. The app offers 1–2 days (`2`), 3–4 days (`4`), 5 days (`5`) and 6+ days (`6`).    |
| `trainingExperience`     | No              | string  | `Beginner` (Getting started), `Intermediate` (Somewhat athletic), `Advanced` (Very athletic) |
| `equipmentAccess`        | No              | string  | `FullGym` (Full gym), `Dumbbells` (Dumbbells), `Bodyweight` (Bodyweight only)             |
| `dailyActivityLevel`     | No              | string  | `Sedentary` (Mostly sitting), `LightlyActive` (Some walking), `Active` (Mostly on my feet), `VeryActive` (Physical work) |
| `sessionDurationMinutes` | No (default 45) | integer | 15 to 180                                                                                 |

The text in brackets is what the app shows for each value. Use the same wording in your own
questionnaire so the lead's answers mean the same thing on both sides.

### Rules

- Once you send `profile`, `gender`, `ageYears`, `heightCm`, `weightKg` and `goal` are
  required. Leave out `profile` entirely if you don't have them.
- An optional field that is missing or `null` is left empty, and the app asks for it.
- An invalid value rejects the whole request with `400` before anything is saved. `message`
  names the field, for example `profile.goal must be one of BuildMuscle, LoseFat, MaintainActive (required).`
- The profile only fills in an account that has no answers yet. It never overwrites answers
  already on the account, whether the user gave them in the app or an earlier provision sent
  them. The response's `profileSaved` tells you whether yours was used.
- The profile is stored encrypted, like every SilaFit profile.

## Responses

Every response uses the SilaFit envelope. On success, `data.payload` is the result sealed
with the shared key under the response purpose:

```json
{ "success": true, "message": null, "data": { "payload": "<encrypted>" } }
```

Decrypted, the payload is:

```json
{
  "partnerUserId": "lead-123",
  "userId": "0286906e-097f-49aa-85d0-cf76b2d49398",
  "status": "Active",
  "isNewAccount": true,
  "proGranted": true,
  "profileSaved": true,
  "requestIssuedAtUtc": "2026-10-22T10:15:30.123Z"
}
```

- `requestIssuedAtUtc` echoes your request's `issuedAtUtc` (to the millisecond). Check it, so a
  response replayed from an earlier call is rejected.
- Errors (`success: false`) are **not** encrypted, so you can still read them when your key or
  format is wrong. They hold only a generic `message` and never any lead data.

- `status` is `Active` after a provision and `Cancelled` after a cancel.
- `isNewAccount` is `false` when the email already had a SilaFit account; the lead is attached to it.
- `proGranted` is `false` when that account already has its own live paid plan (an App Store or
  Play subscription). That plan is left untouched and keeps the user on PRO. Cancelling the lead
  never ends a plan the user pays for themselves.
- `profileSaved` is `true` when your `profile` was saved to the account. It is `false` when you
  sent no profile, or the account already had onboarding answers, which are kept. Cancel
  always returns `false`.

| Status | Meaning                                                                                                                   |
|--------|---------------------------------------------------------------------------------------------------------------------------|
| 200    | Applied. Provisioning the same lead again is idempotent, and provisioning after a cancel re-activates PRO.                |
| 400    | The payload decrypted, but the JSON or a field is invalid. `message` says which.                                          |
| 401    | Wrong Basic credentials, payload that won't decrypt (wrong key, AAD or format), or `issuedAtUtc` outside the 5-minute window. |
| 404    | Cancel for a `partnerUserId` that was never provisioned.                                                                  |
| 409    | Stale request (older than one already applied), the email belongs to another lead, or the account is deactivated.        |
| 429    | Rate limited.                                                                                                             |

## How the lead lands on the account in the app

The account is found by **email**, so send the same email the lead will use in the app.

Tell the lead to tap **Log in** on the app's first screen. That skips the onboarding questions
and goes straight to sign-in. Once they sign in, the app uses the profile you sent. Answers a
lead gives before signing in belong to a temporary guest session and are not moved to the
provisioned account.

- **Google:** signing in to the app with the same Google account links to the provisioned account.
- **Apple:** the same, as long as Apple gives SilaFit the same email. If the lead chose
  *Hide My Email*, the relay address Apple gives the partner differs from the one it gives
  SilaFit unless both apps are in the same Apple developer team. In that case, ask for the real
  email or send the lead through email registration.
- **Email:** the lead chooses "Register with email" in the app with the same address. They get a
  verification code, and the password they set is attached to the provisioned account.
