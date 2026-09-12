# Signing certificates (reference only)

Public X.509 certificates only — **no private key material**. Safe to commit;
they exist so the SHA-256 fingerprint in `deploy/well-known/assetlinks.json`
can be traced back to the cert that produced it.

| File | SHA-256 fingerprint | Used in assetlinks.json? |
|---|---|---|
| `deployment_cert.der` | `0C:85:94:EB:03:A0:9C:C9:0E:DA:C9:BA:49:CC:5C:98:3B:AB:BE:CD:A7:05:07:69:BB:10:8C:2D:09:A7:26:29` | Yes — current release signing cert |
| `hybrid_classical_cert.der` | `07:D9:1A:D3:50:1D:24:A0:8A:03:04:F3:85:C6:0C:4D:EF:7F:21:1E:5C:7C:05:D4:26:F8:CA:C9:07:F8:FD:3E` | No — kept for reference |
| `hybrid_pqc_cert.der` | `48:14:A9:5B:68:CB:5F:5A:A6:EB:52:99:CF:BC:37:47:F8:75:9B:D3:C0:78:03:E3:D1:99:76:87:49:D9:88:E0` | No — kept for reference |

To re-derive a fingerprint: `openssl x509 -inform der -in <file> -noout -fingerprint -sha256`.

Note: `frontend/android/app` still signs release builds with the debug key
(see the `TODO` in `build.gradle.kts`). None of these `.der` files can be used
as a Gradle `signingConfig` on their own — that needs the actual keystore
(`.jks`/`.p12`) with its private key, which isn't in this repo.
