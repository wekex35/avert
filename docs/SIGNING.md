# Signing & CI

Local folder `certs/` holds Apple signing material. **Never commit it** (see `.gitignore`).

## Local material (keep private)

| File | Role |
|------|------|
| `Certificates.p12` | Signing identity (private key + cert) |
| Password file for the `.p12` | Local only — never commit |
| `AuthKey_….p8` | App Store Connect API key (notarization) |
| Mac provisioning profiles | Only if they match `com.avert.app` |

Profiles for other apps are useless here. For public downloads you need a **Developer ID Application** cert + notarization. For Mac App Store, use a matching Mac distribution profile.

## GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|--------|
| `APPLE_P12_BASE64` | `base64 -i certs/Certificates.p12 \| pbcopy` |
| `APPLE_P12_PASSWORD` | `.p12` password |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `APPLE_API_KEY_ID` | Key id from `AuthKey_<ID>.p8` |
| `APPLE_API_ISSUER_ID` | Issuer UUID from App Store Connect |
| `APPLE_API_KEY_BASE64` | `base64 -i certs/AuthKey_….p8 \| pbcopy` |

## What CI publishes

| Job | When |
|-----|------|
| **Build (unsigned)** | Always — `.app` zip + `.dmg` |
| **Sign** | `main` / `v*` when `APPLE_P12_BASE64` is set |
| **GitHub Release** | Push to `main` or tag `v*` — attaches zip + dmg to **Releases** |

- Push to `main` → release `Avert 1.0.0+<run> (dev)` (shown as **Latest** in the sidebar)  
- `git tag v1.0.0 && git push --tags` → tagged release  

Notarized outside-App-Store builds need a **Developer ID Application** identity in the `.p12`. Development/Distribution alone can archive on CI but cannot notarize for Gatekeeper.

```bash
open Avert.xcodeproj
# Signing & Capabilities → Team = your Apple team
# Product → Archive → Distribute App → Developer ID → Notarize
```

Or unsigned local export: `./scripts/export-app.sh` then `./scripts/make-dmg.sh dist/Avert.app`.
