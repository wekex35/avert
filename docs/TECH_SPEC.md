# Technical specification

## Platform

- **OS:** macOS 14.0+
- **Language:** Swift 5.9+
- **UI:** SwiftUI for menu/settings; AppKit for overlay windows
- **Frameworks:** AppKit, SwiftUI, CoreMotion

## AirPods motion

### API

`CMHeadphoneMotionManager`

Preconditions before starting updates:

1. Info.plist contains `NSMotionUsageDescription`
2. `isDeviceMotionAvailable == true`
3. Prefer checking authorization status when available; handle denial gracefully

### Lifecycle

```
startConnectionStatusUpdates()   // optional but useful for UI
startDeviceMotionUpdates(to:queue) { motion, error in ... }
stopDeviceMotionUpdates()        // on disable / quit
```

Adopt `CMHeadphoneMotionManagerDelegate` for connect/disconnect (including Automatic Ear Detection remove/insert).

### Compatible hardware (expected)

AirPods with dynamic head tracking / spatial audio motion (commonly AirPods Pro, AirPods Max, AirPods 3rd gen+). Exact support is gated by `isDeviceMotionAvailable` at runtime — always trust the API over a hardcoded model list in UI copy.

## Calibration

1. User faces the laptop and taps **Calibrate**.
2. Capture current `motion.attitude` as `referenceAttitude`.
3. For each sample thereafter:

```text
relative = currentAttitude.copy()
relative.multiply(byInverseOf: referenceAttitude)
yaw = relative.yaw      // radians; confirm axis in device coords during bring-up
pitch = relative.pitch
```

4. Recalibrate after seating position changes, or expose “Recalibrate” in menu.

Store reference in memory for V1; optionally persist last good calibration (may drift — document as soft).

## Privacy mapping (defaults — tunables in Settings)

| Parameter | Default | Notes |
|-----------|---------|-------|
| Yaw threshold | ~20–25° | Beyond this, blur intensifies |
| Dead zone / hysteresis | ~5° | Prevents flicker at the edge |
| Fade duration | 150–250 ms | Ease in/out |
| Max blur opacity | 0.85–1.0 | Side fully unreadable |
| Side selection | Sign of yaw | Negative → one side, positive → other (confirm with hardware) |

V1 maps **yaw only**. Pitch reserved for future (e.g. look-down dim).

### State machine (conceptual)

```
Idle (disabled)
  → Enabled, awaiting calibration
  → TrackingClear (yaw inside dead zone)
  → TrackingBlurLeft / TrackingBlurRight
  → MotionUnavailable
```

Transitions must be hysteresis-aware.

## Overlay windows

Per connected display (V1: at least main display; ideally all active displays):

- Borderless `NSPanel`
- Full display frame in screen coordinates
- `NSVisualEffectView` as content (material: something strong enough to obscure text — tune on Retina)
- Left and right child regions OR two panels
- `ignoresMouseEvents = true`
- Collection behavior: can join all spaces if we want coverage on every Space (decide in implementation; document outcome in DECISIONS)

## Info.plist keys

```xml
<key>NSMotionUsageDescription</key>
<string>Avert uses AirPods motion to detect when you look away from the screen so it can blur private content.</string>
```

LS ID, category (Utilities), menu bar–friendly app chrome (accessory / prohibited dock policy — decide: LSUIElement vs regular app with menu bar extra).

**Recommendation:** `LSUIElement = true` (agent app) so it lives in the menu bar without a Dock icon.

## Settings (UserDefaults)

| Key | Type | Purpose |
|-----|------|---------|
| `enabled` | Bool | Master toggle |
| `yawThresholdDegrees` | Double | Sensitivity |
| `blurIntensity` | Double | 0…1 max opacity |
| `fadeMilliseconds` | Int | Animation |
| `calibratedOnce` | Bool | Onboarding gate |

## Logging / privacy

- No screen contents logged
- No motion data uploaded
- Local-only diagnostics optional behind a debug flag

## Testing plan (manual V1)

1. AirPods connected, head tracking on → motion available
2. Calibrate → turn left → left blur; turn right → right blur
3. Small head movements → no flicker
4. Remove AirPods → blur clears, status updates
5. Disable toggle → overlays gone
6. Quit app → overlays gone
7. External display connected → behavior documented (cover all vs main only)

## Open implementation questions

Record resolutions in [DECISIONS.md](DECISIONS.md):

1. Exact yaw sign → left/right mapping on MacBook lid coordinates
2. Cover all Spaces or current Space only
3. Single display vs all displays for V1
4. Swift Package vs Xcode app project layout
