# SilaFit — App Encryption / Export Compliance Documentation

This document is the export-compliance (encryption) statement for the SilaFit iOS
app. It is the information App Store Connect asks for under **App Encryption
Documentation / Export Compliance** when a build is submitted for review, and it
answers the review questions Apple sends when a build is flagged with
"Missing Export Compliance Information".

- **App name:** SilaFit
- **iOS bundle identifier:** `com.nikolapetrovski.silafit`
- **Live Activity extension bundle id:** `com.nikolapetrovski.silafit.LiveActivity`
- **Marketing version:** 1.0 (`MARKETING_VERSION`)
- **Platform:** iOS (single Flutter codebase; Android/web builds are not part of the
  App Store submission)
- **Backend:** `https://api.sila.fitness/api`

> This document describes the app as built from this repository. It is a factual
> engineering statement, not legal advice. Confirm the final classification with
> counsel or your export-compliance contact if App Review requests a formal filing.

---

## 1. Bottom line / declaration

**Does SilaFit use encryption?** Yes.
**Does it implement any proprietary or non-standard cryptographic algorithm?** No.
**Does it require an export license or a CCATS?** No.

SilaFit uses only standard, publicly available encryption that is either provided
by Apple's operating system or by the standard TLS stack in the Flutter/Dart
runtime, and only for (a) securing network transport and (b) protecting
credentials on the device. It contains **no custom or proprietary cryptography**,
no user-facing "encryption product" functionality (e.g. no arbitrary file
encryption, no VPN, no secure messaging, no encrypted storage product, no
cryptographic key management exposed to the user).

**App Store Connect answer:** the app qualifies for the standard encryption
exemptions and can be submitted as:

> **"Yes, my app uses encryption" → "It uses only exempt encryption"**
> and App Store Connect's **`ITSAppUsesNonExemptEncryption` = `NO`**.

If App Review asks for a self-classification report (rather than the simple
exempt check-box), use the summary in §6. It classifies under **ECCN 5D002,
License Exception ENC, §740.17(b)(1) (mass market)** — the same position Apple's
"Complying with Encryption Export Regulations" guide describes for apps whose
only cryptography is standard OS/networking encryption.

---

## 2. Encryption actually present in the app binary

| # | Use | Where | Technology | Exempt? |
|---|-----|-------|-----------|---------|
| 1 | Network transport | All API calls (`lib/core/api/api_client.dart`) | HTTPS / TLS 1.2+ using standard cipher suites (Dart `dart:io` HTTP client, bundled BoringSSL) | Yes — standard, non-proprietary |
| 2 | On-device credential storage | `lib/core/session/session_store.dart` via `flutter_secure_storage` | iOS **Keychain** (hardware-backed, Apple-provided). Stores auth token, device id, email, display name. | Yes — OS-provided |
| 3 | OS data protection | App sandbox / `NSFileProtection` defaults, App Group container | Apple-provided | Yes — OS-provided |
| 4 | Sign in with Apple | `sign_in_with_apple` → `ASAuthorization` | Apple-provided authentication | Yes — authentication |
| 5 | Google Sign-In | `google_sign_in` → OAuth 2.0 / OIDC ID tokens | Standard TLS + Google infrastructure | Yes — authentication |
| 6 | Session authentication | Backend-issued **JWT signed with HMAC-SHA256** (verified server-side) | Standard, server-side | Yes — authentication |
| 7 | Email verification codes | Backend **TOTP / HMAC-SHA1** | Standard, server-side | Yes — authentication |

### Explicitly not present in the app

- No proprietary or custom cipher implementation.
- No AES/RSA/ECC key generation or key management performed by the app itself.
- No certificate pinning or custom trust store.
- No VPN, proxy, or tunneling functionality.
- No encrypted-messaging or encrypted-file-storage product feature.
- No use of non-standard "cryptographic" libraries; the app does not import any
  third-party crypto package at runtime (see note below).

### Note on the declared `crypto` dependency

`frontend/pubspec.yaml` declares `crypto: ^3.0.5`, but **no Dart source imports
`package:crypto`** (verified: no `package:crypto` references under `frontend/lib`
or `frontend/test`). It is dead weight from an earlier iteration and is removed
from a release build by Dart's tree-shaking, so it contributes no cryptography to
the shipped app. It should be dropped from `pubspec.yaml` before submission so the
dependency manifest matches the binary (see §8).

### On-device storage split (by design)

- **Sensitive** values (auth token, device id, email, display name) → Keychain via
  `flutter_secure_storage`, with `AndroidOptions(encryptedSharedPreferences: true)`
  on the Android side (Keystore-backed AES). The iOS Keychain item is not
  iCloud-synchronized, so it does not leave the device through iCloud Keychain.
- **Non-sensitive** values (onboarding-complete flag, cached appearance mode,
  in-progress-workout draft, exercise memory) → plain `SharedPreferences`/local
  storage, unencrypted by design because they contain no personal data.

---

## 3. Backend encryption (context — not part of the distributed app)

The iOS binary does not contain any of the following; it only talks to the
backend over TLS. This is provided so reviewers / counsel can see the full data
path. The backend is hosted infrastructure, not software distributed through the
App Store.

| Use | Implementation |
|-----|----------------|
| Transport to clients | HTTPS terminated at nginx with a Let's Encrypt (certbot) certificate; HTTP redirected to HTTPS |
| Sensitive columns at rest | **AES-256-GCM** field-level encryption, random 12-byte nonce + 16-byte tag per value, 256-bit master key from environment (`Silen.Common/Helpers/FieldCipher.cs`) |
| Password storage | **PBKDF2-HMAC-SHA256** with per-user salt (`Silen.Common/Helpers/PasswordHasher.cs`) |
| TOTP verification codes | **HMAC-SHA1** (`Silen.Common/Helpers/TotpHelper.cs`) |
| JWT session/admin tokens | **HMAC-SHA256** signing (`Silen.Common/Helpers/JwtTokenFactory.cs`) |
| Log redaction | **SHA-256** (`Silen.Common/Helpers/LogRedaction.cs`) |

All of the above are standard, publicly specified algorithms
(AES, SHA-2, PBKDF2, HMAC).

---

## 4. Classification

- **ECCN:** 5D002 (encryption software) — mass-market qualification under
  **License Exception ENC, 15 CFR §740.17(b)(1)** and **Note 4 to Category 5,
  Part 2**.
- **License required:** No.
- **CCATS required:** No, because the app meets the mass-market criteria: it is
  available to the general public via the App Store, its cryptography is standard
  and not user-modifiable, and it is not designed for government/enterprise
  cryptographic use.
- **Self-classification report:** recommended (see §6); no annual report is
  required for a pure mass-market app, but filing one avoids repeated App Review
  questions and satisfies BIS reporting expectations.
- **France:** if distributing on the French App Store, a declaration to ANSSI may
  be requested by Apple. SilaFit's use of encryption is limited to standard
  transport/authentication and it qualifies as a mass-market app, so the standard
  notification path applies. No France-specific code changes are needed.

---

## 5. App Store Connect questionnaire — suggested answers

1. **Does your app use encryption?** Yes.
2. **Does your app qualify for any of the exemptions provided in Category 5,
   Part 2 of the U.S. Export Administration Regulations?** Yes.
3. **Which exemption?** Encryption is limited to:
   - standard HTTPS/TLS networking for data in transit, and
   - authentication (Apple/Google sign-in, JWT/TOTP verification), and
   - OS-provided secure storage (iOS Keychain).
4. **Does your app implement proprietary or non-standard encryption?** No.
5. **`ITSAppUsesNonExemptEncryption` value:** `false` (i.e. no non-exempt
   encryption, no export documentation required).

App Store Connect may instead offer a shorter flow: *"Your app uses encryption
but only as required by the operating system / only standard encryption"* →
choose the exempt option.

---

## 6. Self-classification report summary (if requested)

```
Product:            SilaFit (iOS)
Bundle identifier:  com.nikolapetrovski.silafit
Version:            1.0 (build 1)
Manufacturer:       <developer legal entity>
ECCN:               5D002
License Exception:  ENC, 15 CFR 740.17(b)(1) — mass market
Algorithms:         AES-128/256, SHA-256, HMAC-SHA1/SHA-256, PBKDF2-HMAC-SHA256,
                    TLS 1.2+ standard cipher suites
Implementations:    Apple iOS Keychain; Apple ASAuthorization (Sign in with Apple);
                    OAuth 2.0/OIDC (Google); Dart/Flutter runtime TLS (BoringSSL);
                    server-side ASP.NET Core Cryptography (AES-GCM, PBKDF2, HMAC)
Purpose:            Data-in-transit protection (HTTPS), on-device credential
                    protection (Keychain), user authentication
Non-standard crypto: None
User-modifiable:    No
Source:             Standard, publicly available algorithms only
```

Self-classification reports are emailed to `enc@bis.doc.gov` and
`crypt@bis.doc.gov` (see BIS guidance), and a copy is kept for five years. Apple
also accepts the self-classification summary through the App Store Connect
Export Compliance flow.

---

## 7. Recommended change: declare the flag in `Info.plist`

`frontend/ios/SilaFit/Info.plist` currently does **not** contain
`ITSAppUsesNonExemptEncryption`. Adding it prevents App Store Connect from
prompting on every subsequent build. Because the app qualifies for an exemption,
the correct value is:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

(Set it to `false` *only* while the §2 inventory stays true. If a custom
encryption feature is ever added, change it to `true` and provide a CCATS or
self-classification report instead.)

---

## 8. Pre-submission checklist

- [ ] Add `ITSAppUsesNonExemptEncryption = false` to
      `frontend/ios/SilaFit/Info.plist` (§7).
- [ ] Remove the unused `crypto: ^3.0.5` dependency from
      `frontend/pubspec.yaml` so the manifest matches the shipped binary (§2).
- [ ] **Tighten App Transport Security.** `Info.plist` currently sets
      `NSAllowsArbitraryLoads = true` (ATS fully disabled), which was needed for
      the plain-HTTP local dev API. Production traffic is HTTPS
      (`https://api.sila.fitness/api`), so the release build should drop the
      global ATS exception — ideally to nothing, or at most a scoped
      `NSExceptionDomains` entry — so the app enforces TLS as the documentation
      states. App Review can reject or question a released app that disables ATS
      wholesale.
- [ ] Confirm the production `API_BASE_URL` is HTTPS (it is in
      `frontend/env/prod.json`) and that the certificate is valid/auto-renewing.
- [ ] Confirm no new crypto dependency or custom cipher was introduced after this
      document was written; re-run the `package:crypto` / `AES|RSA|encrypt` search
      if in doubt.
- [ ] Keep this document with the release record for the build submitted.

---

## 9. References

- Apple — *Complying with Encryption Export Regulations*:
  https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- Apple — *Export Compliance* overview (App Store Connect Help):
  https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- U.S. BIS — License Exception ENC, 15 CFR §740.17:
  https://www.bis.doc.gov/index.php/policy-guidance/encryption
- U.S. BIS — self-classification reporting instructions:
  https://www.bis.doc.gov/index.php/policy-guidance/encryption/2-uncategorized/1497-enc
- Flutter — security/networking notes (TLS via `dart:io`):
  https://docs.flutter.dev/data-and-backend/networking
