# Signing & CI

Local folder `certs/` holds Apple signing material for Avert CI/release.  
**It must never be committed** (see `.gitignore`).

## What’s typically in `certs/`

| File | Role |
|------|------|
| `Certificates.p12` | Exported signing identity (private key + cert) |
| `creds` | Password for the `.p12` (local only) |
| `AuthKey_….p8` | App Store Connect API key (notarization / ASC) |
| `development.cer` / `distribution.cer` | Public certs (optional if inside the `.p12`) |
| `*.mobileprovision` | **iOS/Mac App Store profiles** — only useful if it matches `com.avert.app` |

A profile named like `Japa_App_Store` is almost certainly for **another app**. Avert (`com.avert.app`) needs either:

- **Developer ID Application** (direct download + notarize), or  
- **Mac App Store** distribution cert + matching Mac provisioning profile  

## Wire GitHub Actions (signed job)

Repo → **Settings → Secrets and variables → Actions** → add:

| Secret | Value |
|--------|--------|
| `APPLE_P12_BASE64` | `base64 -i certs/Certificates.p12 \| pbcopy` |
| `APPLE_P12_PASSWORD` | contents of `certs/creds` |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_API_KEY_ID` | key id from filename (`AuthKey_XXXX.p8` → `XXXX`) |
| `APPLE_API_ISSUER_ID` | issuer UUID from App Store Connect → Users and Access → Keys |
| `APPLE_API_KEY_BASE64` | `base64 -i certs/AuthKey_….p8 \| pbcopy` |

The **Build (unsigned)** job always runs.  
The **Sign (Developer ID)** job runs on `main` only when `APPLE_P12_BASE64` is set.

## Local `certs/` note

Current `Certificates.p12` contains **Apple Development** / **Apple Distribution** (team `9YCF9S8W2Y`).  
That is enough to **archive** on CI. **Notarized outside-App-Store builds** need a **Developer ID Application** cert added to the same `.p12` (or a new export).

`Japa_App_Store.mobileprovision` is for another app — not used by Avert.

```bash
open Avert.xcodeproj
# Signing & Capabilities → Team = your Apple team
# Product → Archive → Distribute App → Developer ID → Notarize
```

Or: `./scripts/export-app.sh` (unsigned CI-style). For signed local export use Xcode Organizer.
