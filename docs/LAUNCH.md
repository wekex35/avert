# Launch checklist

Use this before shipping a build to yourself, friends, or TestFlight-style / notarized distribution.

## Build

- [ ] Open `Avert.xcodeproj`
- [ ] Scheme **Avert** → **Release**
- [ ] Product → Archive (or `scripts/export-app.sh`)
- [ ] Version shows **1.0.0** in General → About

## Branding

- [ ] Dock / Finder icon is the Avert logo (not a placeholder)
- [ ] Menu bar shows BrandLogo
- [ ] Main window sidebar shows logo + “Avert”

## Core privacy (AirPods in, motion allowed)

- [ ] Enable → first-time calibrate flow
- [ ] Look left / right → that side veils; look center → clears
- [ ] Look down → soft dim (Privacy → lower threshold or Invert if needed)
- [ ] Look up → sticky cover; ⌘⇧B clears
- [ ] Quit app → overlays gone; relaunch → auto-recenter without forced sheet (after first calibrate)

## Resilience

- [ ] Phone call / switch audio to iPhone → status shows busy; Bring AirPods to Mac resumes
- [ ] Disable → overlays clear
- [ ] Panic stays until cleared even if you look down

## Neck

- [ ] Status → Start exercise → one full set (images + timer + voice stay in sync)
- [ ] 2h reminder toggle schedules (Notifications allowed)

## Store / notarize (when ready)

- [ ] Privacy policy URL public (see `docs/PRIVACY.md`)
- [ ] Screenshots: calibrate, look-away blur, settings, empty “AirPods required”
- [ ] App Review notes quote from `docs/APP_STORE.md`
- [ ] Category: Utilities
