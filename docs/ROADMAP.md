# Roadmap

## Phase 0 — Docs

- [x] Repo stub + product / architecture / tech / App Store docs
- [x] Privacy statement (`docs/PRIVACY.md`)
- [x] Launch checklist (`docs/LAUNCH.md`)
- [ ] Lock remaining commercial decisions in DECISIONS.md as we choose them

## Phase 1 — Vertical slice (Mac)

Goal: one person can wear AirPods, calibrate, and see directional blur.

1. [x] Xcode macOS app (menu bar / `LSUIElement`)
2. [x] Motion permission + `CMHeadphoneMotionManager` smoke test
3. [x] Calibration + relative yaw
4. [x] Full-display overlay with `NSVisualEffectView`
5. [x] Left/right opacity driven by yaw + hysteresis
6. [x] Menu: Enable, Calibrate, Quit + basic status
7. [x] Manual test checklist (`docs/LAUNCH.md`)

## Phase 2 — Productize

- [x] Settings window (sidebar): status, privacy, neck, schedule, general
- [x] Threshold / intensity / fade sliders
- [x] Multi-display coverage toggle (all vs main)
- [x] Launch at login + remembered enable state
- [x] Panic hotkey ⌘⇧B
- [x] Schedule / outside work hours
- [x] Drift recalibrate prompt
- [x] Demo stillness (2 min)
- [x] Icon + menu bar brand mark
- [x] Overlay teardown on quit / terminate
- [x] Look-down dim + look-up sticky panic
- [x] Neck exercises + voice coach
- [x] Auto-recenter for returning users

## Phase 3 — Distribute (next)

- [x] App Sandbox + usage strings
- [ ] Notarized direct download (Developer ID)
- [ ] Screenshots / preview video
- [ ] Mac App Store submission
- [ ] Public privacy-policy URL

## Phase 4 — Explore (optional)

| Idea | Constraint |
|------|------------|
| Camera / Vision face yaw fallback | Optional; Camera permission |
| Per-app rules (never blur Xcode) | May need Accessibility — Store risk |
| iOS companion | In-app only; no system-wide overlay |

## Explicit non-roadmap (for now)

- Android / Windows
- Cloud accounts
- Bundling into DiskViper
