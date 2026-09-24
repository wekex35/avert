# Mac App Store

Goal: ship Avert on the **Mac App Store** with a sandboxed, public-API build.

## Allowed approach (target)

| Piece | Approach |
|-------|----------|
| Head tracking | `CMHeadphoneMotionManager` (public) |
| Blur | Overlay `NSPanel` + `NSVisualEffectView` |
| Permissions | Motion usage description only |
| Sandbox | App Sandbox enabled |
| Private APIs | **None** |

This obscures content by frosting what’s *behind* the transparent overlay. It does not capture the screen.

## Rejected / high-risk approaches

| Approach | Why avoid |
|----------|-----------|
| Private CoreGraphics desktop blur APIs | Private API → rejection / removal |
| Screen Recording to snapshot + blur | Heavy permission, review friction, surplus for V1 |
| Accessibility to inject into other apps | Wrong tool; looks invasive |
| Undocumented window levels / SPI | Fragile + review risk |

Direct distribution (Developer ID + notarization) can stay as a **backup** channel if a future advanced mode needs entitlements the Store won’t allow — not required for V1.

## Review narrative

App Review should understand in one sentence:

> Avert uses AirPods motion sensors to detect when you look away from your Mac and temporarily blurs part of the screen to reduce shoulder surfing.

Demo video tips:

- Show calibration
- Show look-away → blur → look-back → clear
- Show Settings: threshold / intensity
- Show graceful “AirPods required” empty state

## Guidelines to watch

- Accurate privacy claims (shoulder-surf reduction, not absolute secrecy)
- Permission strings match actual use
- No misleading system UI spoofing
- Don’t require unnecessary entitlements

## Entitlements (expected V1)

- App Sandbox: on
- No `com.apple.security.device.camera`
- No Accessibility-related temporary exceptions
- Hardened Runtime as required for notarization / Store tooling

Confirm final entitlements file during Xcode project setup.

## Age rating / category

- Category: **Utilities** (or Productivity — pick one before submission)
- No user-generated content, no account system in V1 → simpler questionnaire

## Localization

English-first for Store listing and motion usage string. Additional languages later.
