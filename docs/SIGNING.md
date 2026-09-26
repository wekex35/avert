# Signing & notarization (Gatekeeper-safe downloads)

Local folder `certs/` holds Apple signing material. **Never commit it** (see `.gitignore`).

## Why Gatekeeper blocks

| Build | Result |
|-------|--------|
| Unsigned / Development | Blocked |
| Apple Distribution only | Blocked for direct download |
| **Developer ID + notarized + stapled** | Opens cleanly |

Your current release `Avert-*-macos-signed.dmg` is **signed but not notarized** → “Apple could not verify…”. Product Hunt needs a **`macos-notarized.dmg`**.

---

## Complete process (one-time setup)

### 1. Create a Developer ID Application certificate

1. Open [Certificates](https://developer.apple.com/account/resources/certificates/add) (Account Holder / Admin).
2. Choose **Developer ID Application** → Continue.
3. Upload `certs/CertificateSigningRequest.certSigningRequest` (CN = Nirmal Mandal — private key already in your login Keychain).
4. Download `developerID_application.cer` → double-click to install into **login** Keychain.
5. Confirm:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You must see `Developer ID Application: … (9YCF9S8W2Y)`.

### 2. Export a new `.p12` for CI

Keychain Access → My Certificates → **Developer ID Application** → Export → `certs/Certificates.p12` (overwrite) with a strong password → save password in `certs/creds` (local only).

Include the private key when exporting.

### 3. App Store Connect API key (already present)

You have `certs/AuthKey_G59V94P49K.p8`. Put the **Issuer UUID** in `certs/issuer_id` (from [Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)).

Key needs **Developer** access (or Admin) so `notarytool` can submit.

### 4a. Local notarized build (fastest for PH)

```bash
export APPLE_API_ISSUER_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'   # or certs/issuer_id
./scripts/notarize-release.sh
```

Outputs:

- `dist/Avert-1.0.0-macos-notarized.dmg`
- `dist/Avert-1.0.0-macos-notarized.zip`

Verify:

```bash
spctl --assess --type execute -vv dist/Avert.app
# expected: accepted / source=Notarized Developer ID
```

Upload that DMG to a GitHub Release (not the `*-signed` one).

### 4b. CI path (ongoing)

Repo → **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|--------|
| `APPLE_P12_BASE64` | `base64 -i certs/Certificates.p12 \| pbcopy` |
| `APPLE_P12_PASSWORD` | `.p12` password |
| `APPLE_TEAM_ID` | `9YCF9S8W2Y` |
| `APPLE_API_KEY_ID` | `G59V94P49K` |
| `APPLE_API_ISSUER_ID` | Issuer UUID |
| `APPLE_API_KEY_BASE64` | `base64 -i certs/AuthKey_G59V94P49K.p8 \| pbcopy` |

Then:

```bash
git tag v1.0.0   # or bump
git push origin v1.0.0
```

CI will attach `Avert-*-macos-notarized.dmg` when the p12 contains Developer ID. Push to `main` only produces a `(dev)` build — use a **`v*` tag** for the Product Hunt link.

---

## Local material (keep private)

| File | Role |
|------|------|
| `Certificates.p12` | Must include **Developer ID Application** (+ key) |
| Password / `creds` | Local only — never commit |
| `AuthKey_….p8` | App Store Connect API key |
| `issuer_id` | Issuer UUID for notarytool |
| `CertificateSigningRequest.certSigningRequest` | Used to mint Developer ID |

Mac App Store uses a different cert/profile path — see `docs/APP_STORE.md`. That does **not** replace Developer ID notarization for GitHub DMG downloads.

## What CI publishes

| Job | When |
|-----|------|
| **Build (unsigned)** | Always |
| **Sign** | `main` / `v*` when `APPLE_P12_BASE64` is set |
| **Notarize** | Only if p12 has **Developer ID Application** + API key secrets |
| **GitHub Release** | Push to `main` or tag `v*` |

```bash
open Avert.xcodeproj
# Or: ./scripts/notarize-release.sh
# Or unsigned only: ./scripts/export-app.sh
```
