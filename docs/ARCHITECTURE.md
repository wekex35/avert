# Architecture

## Shape

Native **Swift** menu bar app for macOS 14+.

Not Flutter. CoreMotion and full-screen overlay windows are simpler and more reliable from AppKit/SwiftUI than through a Flutter shell.

```
┌─────────────────────────────────────────────┐
│  Menu bar / Settings (SwiftUI)              │
│  enable, calibrate, threshold, status       │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  HeadTracker                                │
│  CMHeadphoneMotionManager                   │
│  → relative yaw/pitch vs calibration        │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  PrivacyController                          │
│  thresholds, hysteresis, fade timing        │
│  → BlurSide: none | left | right | both?    │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│  OverlayManager                             │
│  borderless NSPanel(s) per display          │
│  NSVisualEffectView + animated mask/opacity │
└─────────────────────────────────────────────┘
```

## Modules

| Module | Responsibility |
|--------|----------------|
| `App` / `AppDelegate` | Lifecycle, menu bar, permissions prompt path |
| `HeadTracker` | Start/stop motion, connection delegate, calibration snapshot |
| `PoseMath` | Attitude relative to calibrated reference; expose yaw/pitch |
| `PrivacyController` | Map pose → blur intent with hysteresis |
| `OverlayManager` | Create/update/destroy overlay windows; animate blur region |
| `DisplayWatcher` | React to display connect/disconnect / arrangement changes |
| `SettingsStore` | UserDefaults: enabled, threshold, blur intensity, last calibration |

## Data flow

1. User enables Avert and calibrates while facing the screen.
2. `HeadTracker` stores reference `CMAttitude` (or quaternion).
3. Each motion update: `current.multiply(byInverseOf: reference)` → relative yaw.
4. `PrivacyController` compares yaw to ±threshold with dead zone.
5. `OverlayManager` sets left/right overlay opacity (0…1) with short animation.

## Overlay approach (App Store path)

Use **transparent, borderless, non-activating panels** above normal windows, filled with `NSVisualEffectView` (material that frosts content behind the panel).

- Obscures shoulder-readable text without capturing pixels
- No Screen Recording entitlement
- No Accessibility API for V1
- Avoid private CoreGraphics blur APIs

Directional effect: either

- **A.** Two half-width panels (left / right), opacity driven independently, or
- **B.** One full-screen panel with a gradient mask so only one side is opaque

Prefer **A** for simpler animation and hit-testing (`ignoresMouseEvents = true`).

## Window level

High enough to cover typical app windows; not so aggressive it fights system UI in a review-hostile way. Start with a floating / status-adjacent level and tune during implementation.

Overlays must:

- `ignoresMouseEvents = true` (clicks pass through)
- Not appear in Mission Control / Cmd-Tab as a normal app window if possible
- Hide from screen capture only if we later add an option (not V1)

## Permissions

| Permission | V1 |
|------------|----|
| Motion (`NSMotionUsageDescription`) | Required |
| Accessibility | Not used |
| Screen Recording | Not used |
| Camera | Not used |

## Threading

- Motion callbacks on a dedicated queue
- UI / overlay updates on main actor
- Debounce rapid pose chatter in `PrivacyController`, not in the overlay

## Failure modes (soft)

| Condition | Behavior |
|-----------|----------|
| No AirPods / motion unavailable | Status message; overlays off; no crash |
| Buds removed (ear detection) | Treat as disconnect; clear blur |
| App quit | Tear down overlays |
| Display unplugged | Recreate overlays for remaining displays |
